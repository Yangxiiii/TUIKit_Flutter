import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/controls/single_call_controls.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/float/call_scene.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/hint/call_hint_messages.dart';

/// 纯本地预览入口：不进入业务启动流程，不登录、请求接口或创建腾讯通话状态。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final path = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  final scene = _Scene.values.where((s) => s.path == path).firstOrNull;
  runApp(ProviderScope(
      child: MaterialApp(
    debugShowCheckedModeBanner: false,
    initialRoute: '/',
    navigatorObservers: [AppDialog.observer],
    builder: AppDialog.init(),
    theme:
        AppThemeFactory.create(const AppNormalColorScheme(), Brightness.light),
    home: scene == null ? const _Menu() : _CallPreview(scene: scene),
  )));
}

/// 预览路由与固定状态一一对应，只在当前测试入口中存在。
enum _Scene {
  voiceConnecting('/voice-connecting', '语音接入中', false, false, false),
  voiceWaiting('/voice-waiting', '语音主叫等待', false, false, false),
  voiceIncoming('/voice-incoming', '语音来电', false, false, true),
  voiceConnected('/voice-connected', '语音通话中', false, true, false),
  videoConnecting('/video-connecting', '视频接入中', true, false, false,
      localCamera: true),
  videoWaiting('/video-waiting', '视频主叫等待', true, false, false),
  videoIncoming('/video-incoming', '视频来电', true, false, true),
  videoConnected('/video-connected', '视频双方摄像头关闭', true, true, false),
  videoLocal('/video-local', '视频仅本端摄像头开启', true, true, false,
      localCamera: true),
  videoRemote('/video-remote', '视频仅对端摄像头开启', true, true, false,
      remoteCamera: true),
  videoBoth('/video-both', '视频双方摄像头开启', true, true, false,
      localCamera: true, remoteCamera: true),
  videoNetwork('/video-network', '视频双方网络不佳', true, true, false,
      remoteCamera: true);

  const _Scene(this.path, this.label, this.video, this.accepted, this.incoming,
      {this.localCamera = false, this.remoteCamera = false});
  final String path;
  final String label;
  final bool video;
  final bool accepted;
  final bool incoming;
  final bool localCamera;
  final bool remoteCamera;
}

/// 从单独入口选择固定场景，公共弹窗直接复用生产 API。
class _Menu extends AppBasePage {
  const _Menu();
  @override
  String get title => '通话与基础弹窗预览';
  @override
  Widget buildBody(BuildContext context, WidgetRef ref, Locale locale) =>
      ListView(children: [
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('纯本地资料，不连接业务接口或腾讯服务。视频区域为本地色块，用于验证有/无画面与控件布局。')),
        for (final scene in _Scene.values)
          Semantics(
              identifier: 'preview${scene.path.replaceAll('-', '.')}',
              child: ListTile(
                  title: Text(scene.label),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => _CallPreview(scene: scene))))),
        for (final (kind, title, body, reference) in [
          ('title-body', '弹窗标题', '内容内容内容内容内容内容', false),
          ('body', '', '内容内容内容内容内容内容', false),
          ('reference', '弹窗标题', '', true),
          ('title', '弹窗标题', '', false),
        ])
          for (final cancel in [false, true])
            Semantics(
                identifier: 'preview.dialog.$kind.${cancel ? 'two' : 'one'}',
                child: ListTile(
                    title: Text('弹窗 $kind · ${cancel ? '双按钮' : '单按钮'}'),
                    onTap: () => AppDialog.showAlert(
                        title: title,
                        content: body,
                        referenceContent: reference ? '你好，很高兴认识你！' : null,
                        referenceMeta:
                            reference ? '杨洋阳(一只羊)发送于 2026-8-28 14:13' : null,
                        cancelText: '取消',
                        confirmText: '确定',
                        showCancelButton: cancel,
                        theme: Theme.of(context)))),
      ]);
}

/// 只保存预览开关；生产布局和控件均直接复用，不复制布局树。
class _CallPreview extends AppBaseStatefulPage {
  const _CallPreview({required this.scene});

  /// 当前预览的固定媒体、角色和连接状态。
  final _Scene scene;
  @override
  ConsumerState<_CallPreview> createState() => _CallPreviewState();
}

/// 固定资料下允许操作设备开关和画面互换，方便覆盖四种摄像头组合。
class _CallPreviewState extends AppBaseStatefulPageState<_CallPreview> {
  /// 只影响本地预览的麦克风状态。
  bool _microphone = true;

  /// 只影响本地预览的路由状态。
  late bool _speaker = widget.scene.video;

  /// 本地色块画面开关，不调用真实摄像头。
  late bool _localCamera = widget.scene.localCamera;

  /// 对端色块画面开关，不订阅网络流。
  late final bool _remoteCamera = widget.scene.remoteCamera;

  /// 预览中的主次位置，互换不改变参与者身份。
  bool _localInMain = false;

  /// 点击接听后进入本地连接布局，不发起 SDK 调用。
  late bool _accepted = widget.scene.accepted;
  @override
  SystemUiOverlayStyle systemOverlayStyleOf(BuildContext context) =>
      SystemUiOverlayStyle.light;
  @override
  bool get showAppBar => false;
  @override
  bool get safeAreaTop => false;
  @override
  bool get safeAreaBottom => false;
  @override
  Widget buildBody(BuildContext context, WidgetRef ref, Locale locale) =>
      Stack(children: [
        CallScene(
          self: (
            id: 'local',
            name: '本地用户',
            avatarUrl: '',
            subtitle: '',
            cameraOn: _localCamera
          ),
          remote: (
            id: 'peer',
            name: '杨阳洋 (一只羊)',
            avatarUrl: '',
            subtitle: '众德家族-众森磊-再遇欢 I 主播',
            cameraOn: _remoteCamera
          ),
          video: widget.scene.video,
          accepted: _accepted,
          localInMainView: _localInMain,
          onSwap: () => setState(() => _localInMain = !_localInMain),
          videoBuilder: (id) => ColoredBox(
              color: id == 'local'
                  ? context.appColors.primaryContainer
                  : context.appColors.referenceBackground),
          hint: CallHintMessages(
              waiting: !_accepted,
              messages: widget.scene == _Scene.videoNetwork
                  ? const ['当前通话你的网络不佳', '当前通话对方网络不佳']
                  : _accepted
                      ? const []
                      : [
                          widget.scene.incoming
                              ? '邀请你${widget.scene.video ? '视频' : '语音'}通话...'
                              : [_Scene.voiceConnecting, _Scene.videoConnecting]
                                      .contains(widget.scene)
                                  ? '正在接入中...'
                                  : '正在呼叫...'
                        ]),
          timer: Text(_accepted ? '02:09' : '',
              style: TextStyle(
                  fontSize: 16,
                  height: 1.25,
                  color: context.appColors.onScrim)),
          controls: SingleCallControls(
            video: widget.scene.video,
            incoming: widget.scene.incoming && !_accepted,
            accepted: _accepted,
            microphoneOn: _microphone,
            speakerOn: _speaker,
            cameraOn: _localCamera,
            onEnd: () => Navigator.of(context).maybePop(),
            onAccept: () => setState(() => _accepted = true),
            onMicrophone: () => setState(() => _microphone = !_microphone),
            onSpeaker: () => setState(() => _speaker = !_speaker),
            onCamera: () => setState(() => _localCamera = !_localCamera),
            onFlip: () {},
          ),
        ),
        Positioned(
          left: 12,
          top: 52,
          width: 40,
          height: 40,
          child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Semantics(
                  identifier: 'preview.back',
                  label: '返回预览菜单',
                  child: Icon(AppIcons.copy,
                      size: 24, color: context.appColors.onScrim))),
        ),
      ]);
}
