import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import 'callview/public/controls/single_call_controls.dart';
import 'callview/public/float/call_compact_widget.dart';
import 'callview/public/float/call_minimize_button.dart';
import 'callview/public/float/call_scene.dart';
import 'callview/public/hint/call_hint_messages.dart';
import 'callview/public/hint/timer_widget.dart';
import 'callview/public/participant/call_participant_pane.dart';
import 'component/incoming_banner/incoming_banner_widget.dart';

/// 在鸿蒙宿主上用与安卓相同的 Flutter 组件呈现单聊，原生插件拥有通话状态。
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
  static const _channel =
      MethodChannel('tencent_calls_uikit/harmony_presentation');

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

  /// 全屏和悬浮窗分别复用本端与对端纹理。等待预览使用单独的组合视图。
  GlobalKey _combinedVideoKey = GlobalKey();
  GlobalKey _localVideoKey = GlobalKey();
  GlobalKey _remoteVideoKey = GlobalKey();

  /// 接通后只在用户主动点击时交换主次画面。
  bool _localInMainView = false;

  /// 同一通话的一次设备操作完成前，不重复弹权限或发送动作。
  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onNativeEvent);
    unawaited(_read(ready: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    _poll?.cancel();
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
      );
      if (!mounted || generation != _generation) return;
      if (data == null) {
        // 即使原生结束事件未送达，也用只读快照确认通话已经消失。
        if (_call != null) _clearCall();
        return;
      }
      final next = _HarmonyCallSnapshotCodec.fromMap(data);
      _startPolling();
      if (next == _call) return;
      setState(() {
        if (_call?.id != next.id) {
          _compact = false;
          _drag = Offset.zero;
          _localInMainView = false;
          _combinedVideoKey = GlobalKey();
          _localVideoKey = GlobalKey();
          _remoteVideoKey = GlobalKey();
        }
        _call = next;
      });
    } on PlatformException catch (error) {
      debugPrint('Harmony call state: ${error.code}');
    } on MissingPluginException {
      debugPrint('Harmony call state: presentation channel unavailable');
    } finally {
      _reading = false;
    }
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
          'Harmony call action $action: presentation channel unavailable');
    } finally {
      _pending.remove('$id:$action');
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    // 浮层顺序与安卓一致，横幅和小窗保留底层聊天的交互区域。
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (call != null && call.banner)
        Positioned(
          left: IncomingBannerContent.horizontalInset,
          right: IncomingBannerContent.horizontalInset,
          top: MediaQuery.viewPaddingOf(context).top +
              IncomingBannerContent.topGap,
          child: IncomingBannerContent(
            userId: call.peer.id,
            name: call.peer.name,
            avatarUrl: call.peer.avatarUrl,
            video: call.video,
            onShowCalling: () => _act('expand'),
            onReject: () => _act('end'),
            onAccept: () => _act('accept'),
          ),
        )
      else if (call != null && _compact)
        _buildCompact(context, call)
      else if (call != null)
        _buildFull(context, call),
    ]);
  }

  /// 共享全屏布局仅注入原生状态和腾讯视频层。
  Widget _buildFull(BuildContext context, _HarmonyCallSnapshot call) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: context.appColors.scrim,
        child: Stack(fit: StackFit.expand, children: [
          CallScene(
            key: ValueKey(call.id),
            self: call.self,
            remote: call.peer,
            video: call.video,
            accepted: call.accepted,
            localInMainView: _localInMainView,
            onSwap: () => setState(() => _localInMainView = !_localInMainView),
            videoBuilder: (id) => _participantVideo(call, id),
            combinedVideo: _usesVideoPreview(call)
                ? _HarmonyVideo(key: _combinedVideoKey)
                : null,
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
                        color: context.appColors.onScrim),
                  )
                : const SizedBox.shrink(),
          ),
          CallMinimizeButton(onPressed: () => setState(() => _compact = true)),
        ]),
      ),
    );
  }

  /// 小窗仅改变展示区域，拖动限制在系统安全区内。
  Widget _buildCompact(BuildContext context, _HarmonyCallSnapshot call) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final width = call.video ? 98.0 : 80.0;
    final height = call.video ? 211.0 : 80.0;
    final maxLeft = (size.width - width).clamp(0.0, size.width);
    final maxTop =
        (size.height - padding.bottom - height).clamp(padding.top, size.height);
    final left = (size.width - width - 8 + _drag.dx).clamp(0.0, maxLeft);
    final top = (padding.top + 62 + _drag.dy).clamp(padding.top, maxTop);
    void restore() => setState(() => _compact = false);
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Semantics(
        identifier: 'call.restore',
        button: true,
        label: AppLocalization.of(context)
            .resolve('chat.uikit.callRestore', '返回通话'),
        onTap: restore,
        child: GestureDetector(
          // 原生画面只负责渲染，小窗整块区域都由 Flutter 接收点击和拖动。
          behavior: HitTestBehavior.opaque,
          onTap: restore,
          onPanUpdate: (details) => setState(() {
            _drag =
                Offset(left - size.width + width + 8, top - padding.top - 62) +
                    details.delta;
          }),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: call.video
                ? _buildCompactVideo(size, call)
                : CallCompactAudioContent(
                    id: call.peer.id,
                    name: call.peer.name,
                    avatarUrl: call.peer.avatarUrl,
                    duration: call.accepted ? call.duration : null,
                  ),
          ),
        ),
      ),
    );
  }

  /// 保持主次画面顺序，等待接听时单独缩放腾讯本机预览。
  Widget _buildCompactVideo(Size size, _HarmonyCallSnapshot call) {
    if (!_usesVideoPreview(call)) {
      return CallCompactVideoContent(
        main: _compactPane(call, _localInMainView ? call.self : call.peer),
        small: _compactPane(call, _localInMainView ? call.peer : call.self),
      );
    }
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.topRight,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: _HarmonyVideo(key: _combinedVideoKey),
        ),
      ),
    );
  }

  /// 接通后按用户保留原生纹理，摄像头关闭时由画面组件隐藏纹理。
  Widget _participantVideo(_HarmonyCallSnapshot call, String id) {
    if (!call.accepted || id.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: _HarmonyVideo(
        key: id == call.self.id ? _localVideoKey : _remoteVideoKey,
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
  const _HarmonyVideo({super.key, this.userId});

  /// 指定单路视频，空值由鸿蒙端使用腾讯组合视图。
  final String? userId;

  @override
  Widget build(BuildContext context) => AndroidView(
        key: ValueKey(userId),
        viewType: 'oa.harmony.call.video',
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        creationParams: userId,
        creationParamsCodec: const StandardMessageCodec(),
      );
}

/// 原生只读快照使用值类型，相同状态的轮询结果不重建视频或头像。
typedef _HarmonyCallSnapshot = ({
  String id,
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
});

extension _HarmonyCallSnapshotCodec on _HarmonyCallSnapshot {
  /// 平台通道只传输基本值，转换后交给共享界面。
  static _HarmonyCallSnapshot fromMap(Map<String, Object?> map) => (
        id: map['id'] as String,
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
      );

  static CallSceneUser _user(Map<Object?, Object?> map) => (
        id: map['id'] as String,
        name: map['name'] as String,
        avatarUrl: map['avatar'] as String,
        subtitle: '',
        cameraOn: map['camera'] == true,
      );
}
