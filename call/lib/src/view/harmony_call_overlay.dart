import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:tuikit_atomic_x/atomicx.dart' show LoginStore;

import '../control/harmony_group_control_media.dart';
import '../manager/call_duration_limit.dart';
import '../manager/group_control_lifecycle.dart';
import '../state/global_state.dart';
import '../state/group_control_state.dart';
import '../tui_call_kit.dart';
import '../tui_call_kit_impl.dart';

import 'call_presentation_theme.dart';
import 'callview/public/controls/single_call_controls.dart';
import 'callview/public/float/call_compact_widget.dart';
import 'callview/public/float/call_minimize_button.dart';
import 'callview/public/float/call_scene.dart';
import 'callview/public/hint/call_hint_messages.dart';
import 'callview/public/hint/timer_widget.dart';
import 'callview/public/multi/group_call_header_actions.dart';
import 'callview/public/multi/group_device_open_dialog.dart';
import 'callview/public/participant/call_participant_pane.dart';
import 'component/incoming_banner/incoming_banner_widget.dart';
import 'harmony_group_call_view.dart';

/// 在鸿蒙宿主上用共享 Flutter 组件呈现单聊和多人通话，原生插件持有通话状态。
class HarmonyCallOverlay extends StatefulWidget {
  const HarmonyCallOverlay({super.key, required this.child});

  /// OA 的导航和聊天页面保留在全屏、横幅及小窗下面。
  final Widget child;

  @override
  State<HarmonyCallOverlay> createState() => _HarmonyCallOverlayState();
}

/// 管理与原生 SDK 的展示订阅及当前会话的 Flutter 小窗位置。
class _HarmonyCallOverlayState extends State<HarmonyCallOverlay>
    with WidgetsBindingObserver {
  // 独立通道避免腾讯 Flutter CallKit 后续初始化时覆盖鸿蒙事件监听。
  static const _channel = MethodChannel(
    'tencent_calls_uikit/harmony_presentation',
  );

  /// 无法显示 Flutter 纹理的构建可以切回原生视频窗口。
  static const _useNativeVideo = bool.fromEnvironment(
    'OA_HARMONY_NATIVE_VIDEO',
  );

  /// 最新原生快照。会话标识变化时重置小窗状态。
  _HarmonyCallSnapshot? _call;

  /// SDK 只有开始和结束事件，通话期间轮询设备、资料和网络状态。
  Timer? _poll;

  /// 路由变化递增代次，过期请求结果不能恢复已结束通话。
  int _generation = 0;
  bool _reading = false;

  /// 当前通话内的展示形态与拖动偏移，由 Flutter 本地管理。
  bool _compact = false;
  Offset _drag = Offset.zero;

  /// 单聊与多人布局均按场次和用户复用纹理，避免切换宫格时重新订阅。
  final Map<String, GlobalKey> _videoKeys = {};

  /// 接通后只在用户主动点击时交换主次画面。
  bool _localInMainView = false;

  /// 按展示会话和动作防重，手动挂断与到期挂断共用同一个标记。
  final Set<String> _pending = {};

  /// 使用原生接通时长与可信群截止点，到期后同一展示会话只挂断一次。
  late final _durationLimit = CallDurationLimit(onLimit: _endAtDurationLimit);

  /// 共享会控只在鸿蒙宿主注册，测试展示层无需初始化其他平台的通话引擎。
  GroupControlLifecycle? _groupControl;

  /// 当前展示代次和 SDK 信令标识共同绑定本机设备适配。
  HarmonyGroupControlMedia? _groupMedia;

  /// 当前通话中仅显示一个开启确认，超时或换场自动拒绝。
  ({GroupControlDevice device, Completer<bool> response})? _deviceRequest;

  @override
  void initState() {
    super.initState();
    if (TUICallKit.usesNativeHarmonyCallKit) {
      _groupControl = TUICallKitImpl.instance.harmonyGroupControl;
    }
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onNativeEvent);
    unawaited(_read(ready: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    _poll?.cancel();
    _clearGroupControl();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_read(ready: true));
  }

  /// 开始时立即取一帧，结束时先隐藏旧 UI，再作废在途读操作。
  Future<Object?> _onNativeEvent(MethodCall event) async {
    if (event.method != 'harmonyPresentationChanged') {
      throw MissingPluginException(event.method);
    }
    if (event.arguments == true) {
      // 新路由通知优先于正在返回的旧快照，防止旧空快照撤掉新页面。
      _generation++;
      _startPolling();
      unawaited(_read());
    } else {
      _clearCall();
    }
    return null;
  }

  /// 通话已结束时立即撤掉页面并作废在途快照，避免残留不可操作的按钮。
  void _clearCall() {
    _generation++;
    _poll?.cancel();
    _poll = null;
    _clearGroupControl();
    if (mounted && _call != null) {
      setState(() {
        _call = null;
      });
    }
  }

  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(_read());
    });
  }

  /// 通道串行读取，避免前一通电话的结果覆盖新会话。
  Future<void> _read({bool ready = false}) async {
    if (_reading) return;
    _reading = true;
    final generation = _generation;
    try {
      final data = await _channel.invokeMapMethod<String, Object?>(
        ready ? 'harmonyPresentationReady' : 'harmonyPresentationSnapshot',
        ready ? {'nativeVideo': _useNativeVideo} : null,
      );
      if (!mounted || generation != _generation) return;
      if (data == null) {
        // 即使原生结束事件未送达，也用只读快照确认通话已经消失。
        if (_call != null) _clearCall();
        return;
      }
      final next = _HarmonyCallSnapshotCodec.fromMap(data, _call?.group);
      _startPolling();
      _syncGroupControl(next);
      if (next != _call) {
        setState(() {
          if (_call?.id != next.id) {
            _compact = false;
            _drag = Offset.zero;
            _localInMainView = false;
            _videoKeys.clear();
          } else if (_compact &&
              (!next.video || next.group != null) &&
              next.incoming &&
              _call?.accepted == false &&
              next.accepted) {
            // 被叫接听成功后才展开，权限拒绝时保留待接听浮窗。
            _compact = false;
          }
          _call = next;
        });
      }
      // 快照无变化时也要复核群截止点，挂断失败可在下一次轮询重试。
      _checkDurationLimit(next);
    } on PlatformException catch (error) {
      debugPrint('Harmony call state: ${error.code}');
    } on MissingPluginException {
      debugPrint('Harmony call state: presentation channel unavailable');
    } finally {
      _reading = false;
    }
  }

  /// 仅本次接通可触发到期挂断，已开始手动结束时等待原请求结果。
  void _checkDurationLimit(_HarmonyCallSnapshot call) {
    if (!call.accepted || _pending.contains('${call.id}:end')) return;
    final control = _groupControl?.controller?.value;
    unawaited(
      _durationLimit
          .update(
            callId: call.sdkCallId.isEmpty
                ? 'presentation:${call.id}'
                : '${call.self.id}:${call.sdkCallId}',
            sessionId: call.id,
            seconds: call.duration,
            connected: call.accepted,
            deadlineMs: control?.callId == call.sdkCallId
                ? control?.deadlineMs
                : null,
          )
          .catchError((Object error) {
            debugPrint('鸿蒙通话到期挂断失败：$error');
          }),
    );
  }

  /// 与手动结束共用操作标记，原生确认成功后才提示，结束事件先回也能显示。
  Future<void> _endAtDurationLimit() async {
    final id = _call!.id;
    final pendingKey = '$id:end';
    _pending.add(pendingKey);
    try {
      await _channel.invokeMethod<void>('harmonyPresentationAction', {
        'id': id,
        'action': 'endAtDurationLimit',
      });
      if (mounted && (_call?.id ?? id) == id) {
        showCallDurationLimitToast(context);
      }
    } finally {
      _pending.remove(pendingKey);
    }
  }

  /// 只用与当前 IM 登录一致的已接通快照注册会控，通话结束立即撤销。
  void _syncGroupControl(_HarmonyCallSnapshot call) {
    final lifecycle = _groupControl;
    if (lifecycle == null) return;
    final group = call.group;
    if (group == null ||
        !call.accepted ||
        call.sdkCallId.isEmpty ||
        LoginStore.shared.loginState.loginUserInfo?.userID != call.self.id) {
      _clearGroupControl();
      return;
    }
    var media = _groupMedia;
    if (media == null ||
        media.presentationId != call.id ||
        media.callId != call.sdkCallId) {
      _clearGroupControl();
      _groupMedia = media = HarmonyGroupControlMedia(
        presentationId: call.id,
        callId: call.sdkCallId,
        channel: _channel,
      );
    }
    media.update(microphone: call.microphone, camera: call.self.cameraOn);
    lifecycle.updateHarmony(
      callId: call.sdkCallId,
      selfId: call.self.id,
      inviterId: group.inviterId,
      groupId: call.groupId,
      video: call.video,
      connectedAtMs: call.connectedAtMs,
      joinedIds: [
        call.self.id,
        for (final member in group.members)
          if (member.joined && member.id != call.self.id) member.id,
      ],
      media: media,
      confirm: _confirmDeviceOpen,
    );
  }

  /// 先废弃控制器和同意，再释放媒体观察，迟到回包无法作用于新通话。
  void _clearGroupControl() {
    if (_groupControl?.controller != null) _groupControl!.clear();
    _groupMedia?.dispose();
    _groupMedia = null;
    final response = _deviceRequest?.response;
    if (response != null && !response.isCompleted) response.complete(false);
  }

  /// 只在当前多人全屏或小窗询问本人；小窗收到请求时恢复通话页。
  Future<bool> _confirmDeviceOpen(
    GroupControlDevice device,
    Duration remaining,
  ) async {
    if (!mounted || _call?.accepted != true || _deviceRequest != null) {
      return false;
    }
    final response = Completer<bool>();
    setState(() {
      _compact = false;
      _deviceRequest = (device: device, response: response);
    });
    try {
      return await response.future.timeout(remaining, onTimeout: () => false);
    } finally {
      if (mounted) setState(() => _deviceRequest = null);
    }
  }

  /// 宿主导航在通话浮层下方，确认层需遮挡通话本身才能只响应确认和拒绝。
  Widget _buildDeviceRequest(
    BuildContext context,
    GroupControlDevice device,
    Completer<bool> response,
  ) => Positioned.fill(
    child: BlockSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ModalBarrier(dismissible: false, color: context.appColors.scrim),
          buildGroupDeviceOpenDialog(context, device, (agreed) {
            if (!response.isCompleted) response.complete(agreed);
          }),
        ],
      ),
    ),
  );

  /// 多人本人操作与远端命令共用权限、原生执行及实际结果。
  Future<void> _groupAction(String action) async {
    final controller = _groupControl?.controller;
    if (controller == null || (action != 'microphone' && action != 'camera')) {
      await _act(action);
      return;
    }
    final media = _groupMedia!;
    final microphone = action == 'microphone';
    await controller.setSelfDevice(
      microphone ? GroupControlDevice.microphone : GroupControlDevice.camera,
      microphone ? !media.microphoneOn : !media.cameraOn,
    );
  }

  /// 操作携带原生展示会话标识，界面从回读的真实结果更新。
  Future<void> _act(String action) async {
    final id = _call?.id;
    if (id == null || !_pending.add('$id:$action')) return;
    try {
      await _channel.invokeMethod<void>('harmonyPresentationAction', {
        'id': id,
        'action': action,
      });
      if (mounted) await _read();
    } on PlatformException catch (error) {
      debugPrint('Harmony call action $action: ${error.code}');
      if (mounted) await _read();
    } on MissingPluginException {
      debugPrint(
        'Harmony call action $action: presentation channel unavailable',
      );
    } finally {
      _pending.remove('$id:$action');
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    // 浮层顺序与安卓一致，横幅和小窗保留底层聊天的交互区域。
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // 仅在通话层固定配色，底层页面继续继承全局外观。
        if (call != null)
          CallPresentationTheme(
            builder: (context) => _buildPresentation(context, call),
          ),
      ],
    );
  }

  /// 按当前通话状态选择横幅、小窗或全屏，设备确认在最上层显示。
  Widget _buildPresentation(BuildContext context, _HarmonyCallSnapshot call) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 横幅仅占状态栏下方的固定区域，小窗及全屏复用各自的布局。
        if (call.banner)
          Positioned(
            left: IncomingBannerContent.horizontalInset,
            right: IncomingBannerContent.horizontalInset,
            top:
                MediaQuery.viewPaddingOf(context).top +
                IncomingBannerContent.topGap,
            child: IncomingBannerContent(
              userId: call.peer.id,
              name: AppUserAvatarScope.personName(
                context,
                call.peer.id,
                fallback: call.peer.name,
              ),
              avatarUrl: call.peer.avatarUrl,
              video: call.video,
              multi: call.group != null,
              onShowCalling: () => _act('expand'),
              onReject: () => _act('end'),
              onAccept: () => _act('accept'),
            ),
          )
        else if (_compact)
          _buildCompact(context, call)
        else
          _buildFull(context, call),
        // 设备确认显示时阻挡通话层上的其他操作。
        if (_deviceRequest case final request?)
          _buildDeviceRequest(context, request.device, request.response),
      ],
    );
  }

  /// 共享全屏布局仅注入原生状态和腾讯视频层。
  Widget _buildFull(BuildContext context, _HarmonyCallSnapshot call) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: context.appColors.scrim,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 多人继续使用宫格、主画面和共享按钮，媒体由鸿蒙纹理提供。
            if (call.group case final group?)
              ListenableBuilder(
                listenable: GlobalState.instance.groupControl,
                builder: (context, _) {
                  final control = GlobalState.instance.groupControl.value;
                  return HarmonyGroupCallView(
                    groupId: call.groupId,
                    key: ValueKey(call.id),
                    group: group,
                    selfId: call.self.id,
                    duration: call.duration,
                    incoming: call.incoming,
                    accepted: call.accepted,
                    video: call.video,
                    microphone: call.microphone,
                    speaker: call.speaker,
                    camera: call.self.cameraOn,
                    videoBuilder: (id) => _participantVideo(call, id),
                    onAction: _groupAction,
                    control: control?.callId == call.sdkCallId ? control : null,
                  );
                },
              )
            else
              CallScene(
                key: ValueKey(call.id),
                self: call.self,
                remote: call.peer,
                video: call.video,
                accepted: call.accepted,
                localInMainView: _localInMainView,
                onSwap: () =>
                    setState(() => _localInMainView = !_localInMainView),
                videoBuilder: (id) => _participantVideo(call, id),
                controls: SingleCallControls(
                  video: call.video,
                  incoming: call.incoming,
                  accepted: call.accepted,
                  microphoneOn: call.microphone,
                  speakerOn: call.speaker,
                  cameraOn: call.self.cameraOn,
                  onEnd: () => _act('end'),
                  onAccept: () => _act('accept'),
                  onMicrophone: () => _act('microphone'),
                  onSpeaker: () => _act('speaker'),
                  onCamera: () => _act('camera'),
                  onFlip: () => _act('flip'),
                ),
                hint: _buildHint(context, call),
                timer: call.accepted
                    ? Text(
                        const TimerWidget().formatDuration(call.duration),
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.onScrim,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            if (call.group != null)
              GroupCallHeaderActions(
                incoming: call.incoming,
                showMinimize: true,
                showInvite: false,
                inviteEnabled: false,
                onMinimize: () => setState(() => _compact = true),
              )
            else
              CallMinimizeButton(
                onPressed: () => setState(() => _compact = true),
              ),
          ],
        ),
      ),
    );
  }

  /// 小窗仅改变展示区域，拖动限制在系统安全区内。
  Widget _buildCompact(BuildContext context, _HarmonyCallSnapshot call) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    // 多人和其他 Flutter 端一样用状态小卡，恢复全屏后显示多人视频。
    final compactVideo = call.video && call.group == null;
    final width = compactVideo ? 98.0 : CallCompactAudioContent.dimension;
    final height = compactVideo ? 211.0 : CallCompactAudioContent.dimension;
    final topGap = compactVideo ? 62.0 : CallCompactAudioContent.topGap;
    final maxLeft = (size.width - width).clamp(0.0, size.width);
    final maxTop = (size.height - padding.bottom - height).clamp(
      padding.top,
      size.height,
    );
    final left = (size.width - width - 8 + _drag.dx).clamp(0.0, maxLeft);
    final top = (padding.top + topGap + _drag.dy).clamp(padding.top, maxTop);
    void restore() => setState(() => _compact = false);
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Semantics(
        identifier: 'call.restore',
        button: true,
        label: AppLocalization.of(
          context,
        ).resolve('chat.uikit.callRestore', '返回通话'),
        onTap: restore,
        child: GestureDetector(
          // 原生画面只负责渲染，小窗整块区域都由 Flutter 接收点击和拖动。
          behavior: HitTestBehavior.opaque,
          onTap: restore,
          onPanUpdate: (details) => setState(() {
            _drag =
                Offset(
                  left - size.width + width + 8,
                  top - padding.top - topGap,
                ) +
                details.delta;
          }),
          // 视频需要裁剪纹理，语音浮窗的阴影绘制在卡片边界之外。
          child: compactVideo
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildCompactVideo(call),
                )
              : CallCompactAudioSurface(
                  child: CallCompactAudioContent(
                    id: call.peer.id,
                    name: AppUserAvatarScope.personName(
                      context,
                      call.peer.id,
                      fallback: call.peer.name,
                    ),
                    avatarUrl: call.peer.avatarUrl,
                    incoming: call.incoming,
                    duration: call.accepted ? call.duration : null,
                    onWaitingAction: () {
                      // 卡片更新前的旧手势不能影响新通话或已接通的通话。
                      if (_call?.id == call.id && _call?.accepted == false) {
                        unawaited(_act(call.incoming ? 'accept' : 'end'));
                      }
                    },
                  ),
                ),
        ),
      ),
    );
  }

  /// 等待接听时只显示本机，接通后保留当前主次画面顺序。
  Widget _buildCompactVideo(_HarmonyCallSnapshot call) {
    if (!_usesVideoPreview(call)) {
      return CallCompactVideoContent(
        main: _compactPane(call, _localInMainView ? call.self : call.peer),
        small: _compactPane(call, _localInMainView ? call.peer : call.self),
      );
    }
    return _participantVideo(call, call.self.id);
  }

  /// 接通前仅显示本机预览，接通后沿用同一纹理并补上对端。
  Widget _participantVideo(_HarmonyCallSnapshot call, String id) {
    if (!call.video || id.isEmpty || (!call.accepted && id != call.self.id)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: _HarmonyVideo(
        key: _videoKeys.putIfAbsent(id, GlobalKey.new),
        userId: id,
      ),
    );
  }

  Widget _compactPane(_HarmonyCallSnapshot call, CallSceneUser user) =>
      CallParticipantPane(
        userId: user.id,
        name: user.name,
        avatarUrl: user.avatarUrl,
        hasVideo: call.accepted && user.id.isNotEmpty && user.cameraOn,
        video: _participantVideo(call, user.id),
        isMainView: false,
      );

  bool _usesVideoPreview(_HarmonyCallSnapshot call) =>
      call.video && !call.accepted && call.self.cameraOn;

  Widget _buildHint(BuildContext context, _HarmonyCallSnapshot call) {
    final text = AppLocalization.of(context);
    return CallHintMessages(
      waiting: !call.accepted,
      messages: call.accepted
          ? [
              if (call.duration < 3) text.callConnected,
              if (call.selfPoor) text.callSelfNetworkLowQuality,
              if (call.peerPoor) text.callOtherPartyNetworkLowQuality,
            ]
          : [
              if (!call.incoming)
                text.callWaitingForInvitationAcceptance
              else if (call.video)
                text.callInvitedToVideoCall
              else
                text.callInvitedToAudioCall,
            ],
    );
  }
}

/// Flutter OHOS 的纹理平台视图通道与 AndroidView 使用相同的创建、尺寸及释放协议。
class _HarmonyVideo extends StatelessWidget {
  const _HarmonyVideo({super.key, required this.userId});

  /// 与当前竖屏通话输出一致的纹理像素尺寸，主小画面互换时保持此尺寸。
  static const _portraitPixels = Size(720, 1280);

  /// 指定鸿蒙纹理要绑定的单路视频。
  final String userId;

  @override
  Widget build(BuildContext context) {
    final viewport = _portraitPixels / MediaQuery.devicePixelRatioOf(context);
    // Flutter 负责等比裁剪，原生纹理不跟随卡片尺寸变化，避免旧帧被拉伸。
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox.fromSize(
        size: viewport,
        child: AndroidView(
          key: ValueKey(userId),
          viewType: 'oa.harmony.call.video',
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          creationParams: userId,
          creationParamsCodec: const StandardMessageCodec(),
        ),
      ),
    );
  }
}

/// 原生只读快照使用值类型，相同状态的轮询结果不重建视频或头像。
typedef _HarmonyCallSnapshot = ({
  String id,
  String sdkCallId,
  String groupId,
  int connectedAtMs,
  bool banner,
  bool video,
  bool accepted,
  bool incoming,
  bool microphone,
  bool speaker,
  int duration,
  bool selfPoor,
  bool peerPoor,
  CallSceneUser self,
  CallSceneUser peer,
  HarmonyGroupCall? group,
});

extension _HarmonyCallSnapshotCodec on _HarmonyCallSnapshot {
  /// 平台通道只传输基本值，转换后交给共享界面。
  static _HarmonyCallSnapshot fromMap(
    Map<String, Object?> map,
    HarmonyGroupCall? previousGroup,
  ) => (
    id: map['id'] as String,
    sdkCallId: map['callId'] as String? ?? '',
    groupId: map['groupId'] as String? ?? '',
    connectedAtMs: (map['connectedAtMs'] as num?)?.toInt() ?? 0,
    banner: map['banner'] == true,
    video: map['video'] == true,
    accepted: map['accepted'] == true,
    incoming: map['incoming'] == true,
    microphone: map['microphone'] == true,
    speaker: map['speaker'] == true,
    duration: (map['duration'] as num).toInt(),
    selfPoor: map['selfPoor'] == true,
    peerPoor: map['peerPoor'] == true,
    self: _user(map['self'] as Map<Object?, Object?>),
    peer: _user(map['peer'] as Map<Object?, Object?>),
    group: decodeHarmonyGroup(map, previousGroup),
  );

  static CallSceneUser _user(Map<Object?, Object?> map) => (
    id: map['id'] as String,
    name: map['name'] as String,
    avatarUrl: map['avatar'] as String,
    subtitle: '',
    cameraOn: map['camera'] == true,
  );
}
