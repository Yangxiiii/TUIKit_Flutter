import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_controls.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_header_actions.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_member.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_scene.dart';
import 'package:tencent_calls_uikit/src/view/component/incoming_banner/incoming_banner_widget.dart';

import 'group_call_control_preview_panel.dart';

/// 离线预览只启动生产展示组件，不登录腾讯、不创建呼叫，也不下载头像。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const GroupCallPreviewApp());
}

/// Android 审阅入口，所有场景使用生产布局和按钮。
class GroupCallPreviewApp extends StatelessWidget {
  const GroupCallPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorObservers: [AppDialog.observer],
        builder: AppDialog.init(
            builder: (_, child) => AnnotatedRegion<SystemUiOverlayStyle>(
                value: const SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.light,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: Brightness.light,
                ),
                child: child!)),
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        home: const _PreviewPage(),
      );
}

/// 视觉样本类型与生产状态区分，不把预览数据写入 SDK Store。
enum _Preview {
  nineWaiting,
  nineTimeout,
  three,
  two,
  focus,
  focusTwo,
  incoming,
  banner,
  members
}

/// 在相同生产布局中切换固定样本，方便真机审阅不同人数与邀请结果。
class _PreviewPage extends StatefulWidget {
  const _PreviewPage();

  @override
  State<_PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<_PreviewPage> {
  /// 仅控制离线展示，默认九人等待场景。
  _Preview _preview = _Preview.nineWaiting;
  bool _microphoneOn = true;
  bool _cameraOn = false;

  /// 仅模拟音频路由，离线预览无需启动腾讯音频设备。
  bool _speakerOn = true;

  /// 每次预览启动只记录一次设备指标，避免动画帧产生重复日志。
  bool _metricsPrinted = false;

  static const _labels = [
    '九格呼叫',
    '九格超时',
    '三人通话',
    '双人通话',
    '大画面',
    '双人大画面',
    '来电待接听',
    '来电横幅',
    '管理成员'
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_metricsPrinted) return;
    final media = MediaQuery.of(context);
    // 原生窗口首帧可能尚无尺寸，等待真实指标后再保留验收日志。
    if (media.size.isEmpty) return;
    _metricsPrinted = true;
    debugPrint('group-call-preview metrics: size=${media.size}, '
        'padding=${media.padding}, viewPadding=${media.viewPadding}, '
        'DPR=${media.devicePixelRatio}');
  }

  @override
  Widget build(BuildContext context) {
    if (_preview == _Preview.banner) return _bannerPreview();
    final incoming = _preview == _Preview.incoming;
    final ended = _preview == _Preview.nineTimeout;
    final connected = !incoming && !ended && _preview != _Preview.nineWaiting;
    final focused = _preview == _Preview.focus || _preview == _Preview.focusTwo;
    final count = _preview == _Preview.two || _preview == _Preview.focusTwo
        ? 2
        : _preview == _Preview.three
            ? 3
            : 9;
    final members = _members(count, connected: connected, ended: ended);
    return Scaffold(
        body: Stack(children: [
      GroupCallScene(
          key: ValueKey(_preview),
          title: '研发协作群',
          status: Text(
              connected
                  ? '10:00'
                  : ended
                      ? '呼叫超时，无人接听'
                      : '正在呼叫…',
              style: TextStyle(
                  fontSize: 12, color: context.appColors.onScrimSecondary)),
          members: members,
          inviterId: incoming ? 'user1' : 'self',
          selfId: 'self',
          incoming: incoming,
          showMemberOrganizations: _preview == _Preview.nineWaiting,
          video: !incoming,
          initialFocusedId: focused ? 'self' : null,
          videoBuilder: (id) => _offlineVideo(members, id),
          onRetry: ended ? null : (_) => _notice('离线预览：重新邀请'),
          onManage: () => _showMembers(members),
          controls: GroupCallControls(
              incoming: incoming,
              connected: connected,
              ended: ended,
              retryable: ended,
              microphoneOn: _microphoneOn,
              cameraOn: _cameraOn,
              speakerOn: _speakerOn,
              canFlip: connected && _cameraOn,
              onEnd: () => _notice('离线预览：结束操作'),
              onAccept: () => setState(() => _preview = _Preview.three),
              onMicrophone: () =>
                  setState(() => _microphoneOn = !_microphoneOn),
              onCamera: () => setState(() => _cameraOn = !_cameraOn),
              onSpeaker: () => setState(() => _speakerOn = !_speakerOn),
              // 离线预览没有真实摄像头，仅展示按钮位置。
              onFlip: null,
              onRetry: () => setState(() => _preview = _Preview.nineWaiting))),
      Positioned.fill(
          child: GroupCallHeaderActions(
              incoming: incoming,
              showMinimize: true,
              showInvite: !incoming,
              inviteEnabled: true,
              onMinimize: () => _notice('离线预览：最小化通话'),
              onInvite: () => _notice('离线预览：添加成员'))),
      _sceneMenu(),
    ]));
  }

  /// 离线工具独立于生产头部，切换时只重置展示夹具。
  Widget _sceneMenu() => Positioned(
      bottom: MediaQuery.paddingOf(context).bottom,
      left: 8,
      child: Semantics(
          identifier: 'call.preview.scene',
          child: PopupMenuButton<_Preview>(
              tooltip: '离线预览场景',
              child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text('离线预览 · 切换场景',
                      style: TextStyle(
                          fontSize: 10,
                          color: _preview == _Preview.banner
                              ? context.appColors.textSecondary
                              : context.appColors.onScrimSecondary))),
              itemBuilder: (_) => [
                    for (final value in _Preview.values)
                      PopupMenuItem(
                          value: value, child: Text(_labels[value.index]))
                  ],
              onSelected: (value) {
                setState(() {
                  _preview = value;
                  // 大画面样本同时验证本端开摄像头与静音状态，不调用设备。
                  _cameraOn =
                      value == _Preview.focus || value == _Preview.focusTwo;
                  _microphoneOn = !_cameraOn;
                });
                if (value == _Preview.members) {
                  _showMembers(_members(9, connected: true, ended: false));
                }
              })));

  List<GroupCallMember> _members(int count,
          {required bool connected, required bool ended}) =>
      List.generate(
          count,
          (index) => GroupCallMember(
              id: index == 0 ? 'self' : 'user$index',
              name: index == 0 ? '我' : '测试成员$index',
              subtitle: '开发部',
              status: index == 0 || connected && index < 3
                  ? GroupCallMemberStatus.joined
                  : ended || index == 4
                      ? GroupCallMemberStatus.noResponse
                      : index == 5
                          ? GroupCallMemberStatus.rejected
                          : GroupCallMemberStatus.waiting,
              microphoneOn: index == 0 ? _microphoneOn : index.isEven,
              cameraOn: index == 0 && _cameraOn && !ended,
              volume: connected && index == 2 ? 65 : 0));

  /// 用同源头像标记离线视频占位，不创建原生纹理或宣称摄像头正在采集。
  Widget _offlineVideo(List<GroupCallMember> members, String id) {
    final member = members.firstWhere((member) => member.id == id);
    return Semantics(
        label: '离线视频占位，不采集摄像头',
        child: LayoutBuilder(
            builder: (_, constraints) => AppUserAvatar(
                userId: id,
                name: member.name,
                url: '',
                size: constraints.maxWidth,
                borderRadius: BorderRadius.zero)));
  }

  /// G21 仅比较横幅组件，中性背景不代表宿主应用的完整消息页面。
  Widget _bannerPreview() => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent),
      child: Scaffold(
          backgroundColor: context.appColors.groupedPageBackground,
          body: Stack(children: [
            Center(
                child: Text('来电横幅组件预览',
                    style: TextStyle(color: context.appColors.textSecondary))),
            Positioned(
                top: MediaQuery.paddingOf(context).top +
                    IncomingBannerContent.topGap,
                left: IncomingBannerContent.horizontalInset,
                right: IncomingBannerContent.horizontalInset,
                child: IncomingBannerContent(
                    userId: 'user1',
                    name: '测试成员1',
                    avatarUrl: '',
                    video: true,
                    multi: true,
                    onShowCalling: () =>
                        setState(() => _preview = _Preview.incoming),
                    onReject: () => _notice('离线预览：拒绝邀请'),
                    onAccept: () => setState(() => _preview = _Preview.three))),
            _sceneMenu(),
          ])));

  Future<void> _showMembers(List<GroupCallMember> members) =>
      showGroupControlPreview(context, members);

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
