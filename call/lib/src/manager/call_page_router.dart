import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:app_ui/app_ui.dart';
import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import '../state/global_state.dart';
import '../state/group_control_state.dart';
import '../common/utils/error_parser.dart';
import 'call_manager.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:tencent_calls_uikit/src/common/utils/app_lifecycle.dart';
import '../common/metrics/key_metrics.dart';
import '../view/call_main_widget.dart';
import '../view/call_presentation_theme.dart';
import '../view/callview/public/float/call_compact_widget.dart';
import '../view/callview/public/multi/group_device_open_dialog.dart';
import '../view/component/incoming_banner/incoming_banner_widget.dart';
import '../view/component/inviter/invite_user_widget.dart';

enum CallPageType { none, calling, floating, invite, banner, pip }

class CallPageCallbacks {
  final VoidCallback? onShowCalling;
  final VoidCallback? onShowFloating;
  final VoidCallback? onShowPip;
  final VoidCallback? onShowInvitePage;
  final void Function(DragUpdateDetails details, Size screenSize)?
      onFloatDragUpdate;
  final Size Function()? getOriginScreenSize;
  final void Function(Size size)? setOriginScreenSize;

  /// 路由是否仍属于原通话浮层，可在 SDK 尚未分配呼叫标识时校验操作。
  final bool Function()? isCurrentPresentation;

  const CallPageCallbacks({
    this.onShowCalling,
    this.onShowFloating,
    this.onShowPip,
    this.onShowInvitePage,
    this.onFloatDragUpdate,
    this.getOriginScreenSize,
    this.setOriginScreenSize,
    this.isCurrentPresentation,
  });
}

class InviteUserCallbacks {
  final VoidCallback? onShowCalling;

  const InviteUserCallbacks({this.onShowCalling});
}

/// 以单一浮层协调通话、来电横幅与小窗，权限返回后核对邀请仍有效。
class CallPageRouter {
  /// 每次浮层关闭后换键，防止同一帧的新浮层继承上一场的导航栈。
  GlobalKey<NavigatorState> _callNavigatorKey = GlobalKey<NavigatorState>();
  final NavigatorState? Function() _navigatorGetter;
  final AndroidPipFeature pipController = AndroidPipFeature();

  CallPageType _currentPageType = CallPageType.none;
  CallPageType getCurrentPageRoute() => _currentPageType;

  CallPageType _pageTypeBeforeInvite = CallPageType.none;

  OverlayEntry? _callOverlayEntry;

  /// 切换通话页或离场前取消所属确认，不干扰后续页面路由。
  VoidCallback? _cancelDeviceOpen;

  bool _hasManuallyShownCalling = false;
  bool _shouldAnimateRect = false;

  Size _originScreenSize = Size.zero;
  Size get originScreenSize => _originScreenSize;
  void setOriginScreenSize(Size size) {
    // Only grow, never shrink — prevents small-window constraints from polluting the value.
    //
    // 只增长，绝不缩小——防止小窗口限制污染数值。
    _originScreenSize = Size(
      max(size.width, _originScreenSize.width),
      max(size.height, _originScreenSize.height),
    );
  }

  /// 应用内小窗遵循当前媒体尺寸，不缩放整个通话页导致文字不可读。
  double get _floatWindowWidth => _isSingleCall
      ? (_isVideoCall ? 98 : CallCompactAudioContent.dimension)
      : 80;
  double get _floatWindowHeight => _isSingleCall
      ? (_isVideoCall ? 211 : CallCompactAudioContent.dimension)
      : 80;

  /// 群及临时多人统一显示 80 像素头像浮窗，两人临时多人以展示快照区分。
  bool get _isSingleCall =>
      GlobalState.instance.groupCall.value == null &&
      CallStore.shared.state.activeCall.value.chatGroupId.isEmpty &&
      CallStore.shared.state.activeCall.value.inviteeIds.length <= 1;
  bool get _isVideoCall =>
      CallStore.shared.state.activeCall.value.mediaType == CallMediaType.video;

  /// 只有单聊语音卡片需要在通话路由外包裹带阴影的外壳。
  bool get _isAudioCard =>
      _currentPageType == CallPageType.floating &&
      _isSingleCall &&
      CallStore.shared.state.activeCall.value.mediaType == CallMediaType.audio;

  /// 保留既有拖动坐标系，语音卡片额外按状态栏定位。
  static const double _initialFloatViewTop = 148.0;

  /// 初始位置对齐聊天右上角；拖动仍由现有路由统一维护。
  double _floatViewTop = _initialFloatViewTop;

  /// 小窗距右侧的逻辑像素偏移，拖动由同一路由持有。
  double _floatViewRight = 8.0;

  NavigatorState? get callNavigator => _callNavigatorKey.currentState;

  CallPageRouter({required NavigatorState? Function() navigatorGetter})
      : _navigatorGetter = navigatorGetter;

  /// 只在可操作的通话页获取本人同意，到期只关闭该指令自己的弹窗。
  Future<bool> confirmGroupDeviceOpen(
      GroupControlDevice device, Duration remaining) async {
    final navigator = callNavigator;
    if (_currentPageType != CallPageType.calling ||
        navigator == null ||
        _cancelDeviceOpen != null) {
      return false;
    }
    late final DialogRoute<bool> route;
    void finish(bool agreed) {
      if (navigator.mounted && route.isActive) {
        navigator.removeRoute(route, agreed);
      }
    }

    route = DialogRoute<bool>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (context) =>
            buildGroupDeviceOpenDialog(context, device, finish));
    // 关闭当前确认路由，避免进入小窗时替换到弹窗而非通话页。
    void cancel() => finish(false);
    _cancelDeviceOpen = cancel;
    final expiration = Timer(remaining, cancel);
    try {
      return await navigator.push(route) == true &&
          _currentPageType == CallPageType.calling;
    } finally {
      expiration.cancel();
      _cancelDeviceOpen = null;
    }
  }

  void showCallingPage() {
    pipController.onEnterPip = () {
      if (_currentPageType != CallPageType.none) {
        _showPage(CallPageType.pip, isManualSwitch: true);
      }
    };

    pipController.onLeavePip = () {
      if (_currentPageType != CallPageType.none) {
        _showPage(CallPageType.calling, isManualSwitch: true);
      }
    };

    pipController.enable();
    _showPage(CallPageType.calling, isManualSwitch: true);
  }

  void showFloatingPage() =>
      _showPage(CallPageType.floating, isManualSwitch: true);
  void showPipPage() => _showPage(CallPageType.pip, isManualSwitch: true);

  /// 通话中追加邀请；全员未接时通过同一个宿主选人入口准备下次呼叫。
  void showInvitePage() {
    final callId = CallStore.shared.state.activeCall.value.callId;
    final epoch = CallManager.instance.sessionEpoch;
    final result = GlobalState.instance.groupCall.value;
    if (result case final retry? when retry.canRetry) {
      unawaited(AppServiceLocator.get<ActionGuard>().singleFlight(
          ('tim.call.picker', epoch, retry.callId),
          () => _pickRetryInvitees(retry, epoch)));
      return;
    }
    unawaited(AppServiceLocator.get<ActionGuard>().singleFlight(
        ('tim.call.picker', epoch, callId),
        () => _pickInvitees(callId, epoch)));
  }

  /// 选人只更新下一次呼叫参数，返回时确认仍在原结果页及登录代次。
  Future<void> _pickRetryInvitees(GroupCallSnapshot result, int epoch) async {
    final context = _callNavigatorKey.currentContext;
    final presentation = _callOverlayEntry;
    final manager = CallManager.instance;
    final excluded = manager.groupRetryParticipantIds(result.callId);
    if (context == null || presentation == null || excluded == null) return;
    final text = AppLocalization.of(context);
    final picker = GlobalState.instance.groupMemberPicker;
    if (picker == null) {
      AppToast.show(text.resolve(
          'chat.uikit.groupCallPickerUnavailable', '暂时无法添加成员，请稍后重试'));
      return;
    }
    final remaining = CallManager.maxParticipants - excluded.length;
    if (remaining <= 0) {
      AppToast.show(text.resolve('chat.uikit.groupCallFull', '通话人数已达9人上限'));
      return;
    }
    bool isCurrent() =>
        context.mounted &&
        identical(presentation, _callOverlayEntry) &&
        epoch == manager.sessionEpoch &&
        manager.groupRetryParticipantIds(result.callId) != null;
    try {
      // 原场次已经结束，选人确认后只保存名单，由「重新呼叫」发起新场次。
      final selected = await picker(context,
          result.groupId.isEmpty ? null : result.groupId, excluded, remaining);
      if (selected == null || selected.isEmpty || !isCurrent()) return;
      if (manager.addGroupRetryInvitees(result.callId, selected)) {
        AppToast.show(text.resolve(
            'chat.uikit.groupCallRetryMembersAdded', '已加入下次呼叫名单'));
      }
    } on Object {
      if (isCurrent()) {
        AppToast.show(text.resolve(
            'chat.uikit.groupCallPickerUnavailable', '暂时无法添加成员，请稍后重试'));
      }
    }
  }

  /// 临时多人必须由宿主提供组织选人；缺少入口时明确提示，不查询空群 ID。
  Future<void> _pickInvitees(String callId, int epoch) async {
    final call = CallStore.shared.state.activeCall.value;
    final accountId = LoginStore.shared.loginState.loginUserInfo?.userID;
    final context = _callNavigatorKey.currentContext;
    final presentation = _callOverlayEntry;
    if (context == null ||
        callId.isEmpty ||
        call.mediaType == null ||
        CallStore.shared.state.selfInfo.value.status !=
            CallParticipantStatus.accept) {
      return;
    }
    // 宿主可提供完整组织选人；只有明确群来源才允许退回 SDK 群成员列表。
    final picker = GlobalState.instance.groupMemberPicker;
    if (picker == null) {
      if (call.chatGroupId.isNotEmpty) {
        _pageTypeBeforeInvite = _currentPageType;
        _showPage(CallPageType.invite, isManualSwitch: true);
      } else {
        AppToast.show(AppLocalization.of(context).resolve(
            'chat.uikit.groupCallPickerUnavailable', '暂时无法添加成员，请稍后重试'));
      }
      return;
    }
    // 等待中的邀请同样占名额，传给宿主的是只读集合，提交仍会再次校验。
    final excluded =
        Set<String>.unmodifiable(CallManager.instance.occupiedUserIds);
    final remaining = CallManager.maxParticipants - excluded.length;
    if (remaining <= 0) {
      AppToast.show(AppLocalization.of(context)
          .resolve('chat.uikit.groupCallFull', '通话人数已达9人上限'));
      return;
    }
    bool isCurrent() =>
        context.mounted &&
        identical(presentation, _callOverlayEntry) &&
        epoch == CallManager.instance.sessionEpoch &&
        accountId == LoginStore.shared.loginState.loginUserInfo?.userID &&
        callId == CallStore.shared.state.activeCall.value.callId;
    try {
      // 选人完成不能直接邀请：原浮层、账号、场次及代次必须都还有效。
      final selected = await picker(
          context,
          call.chatGroupId.isEmpty ? null : call.chatGroupId,
          excluded,
          remaining);
      if (!context.mounted ||
          !isCurrent() ||
          selected == null ||
          selected.isEmpty) {
        return;
      }
      final result =
          await CallManager.instance.invite(selected, expectedCallId: callId);
      if (!context.mounted || !isCurrent() || result.errorCode == 0) return;
      final text = AppLocalization.of(context);
      AppToast.show(ErrorParser.getErrorMessage(result.errorCode, text) ??
          text.callFailedToInitiateOrJoinCall);
    } catch (_) {
      if (context.mounted && isCurrent()) {
        AppToast.show(
            AppLocalization.of(context).callFailedToInitiateOrJoinCall);
      }
    }
  }

  void showIncomingBanner() {
    if (_hasManuallyShownCalling) return;
    _showPage(CallPageType.banner, isManualSwitch: false);
  }

  void closeCallingPage() => _hidePage(CallPageType.calling);
  void closeFloatingPage() => _hidePage(CallPageType.floating);
  void closeInvitePage() => _hidePage(CallPageType.invite);
  void closeIncomingBanner() => _hidePage(CallPageType.banner);

  void closeAllPage() {
    pipController.onEnterPip = null;
    pipController.onLeavePip = null;

    if (pipController.isInPipMode) {
      pipController.closePictureInPicture();
    }

    pipController.disable();
    _removeCallOverlay();
    _hasManuallyShownCalling = false;
    _originScreenSize = Size.zero;
  }

  void dispose() {
    _removeCallOverlay();
    _hasManuallyShownCalling = false;
  }

  void _showPage(CallPageType pageType, {bool isManualSwitch = false}) {
    KeyMetrics.instance.countUV(EventId.wakeup);

    final overlay = _navigatorGetter()?.overlay;
    if (overlay == null) return;
    if (AppLifecycle.instance.currentState.value ==
        AppLifecycleState.detached) {
      return;
    }

    if (isManualSwitch &&
        (pageType == CallPageType.calling ||
            pageType == CallPageType.floating ||
            pageType == CallPageType.pip)) {
      _hasManuallyShownCalling = true;
    }

    if (_currentPageType == pageType && _callOverlayEntry != null) {
      _shouldAnimateRect = false;
      _callOverlayEntry?.markNeedsBuild();
      return;
    }

    _cancelDeviceOpen?.call();
    SystemChannels.textInput.invokeMethod('TextInput.hide');

    if (_callOverlayEntry == null) {
      _currentPageType = pageType;
      _callOverlayEntry = OverlayEntry(
        builder: (_) => CallPresentationTheme(builder: _buildCallNavigator),
      );
      overlay.insert(_callOverlayEntry!);
      return;
    }

    final previousPageType = _currentPageType;
    final targetPageType = pageType;
    final navigatorKey = _callNavigatorKey;
    final isFromSmallToFull =
        _isSmallWindow(previousPageType) && !_isSmallWindow(targetPageType);

    if (isFromSmallToFull) {
      // Small window → Fullscreen:
      // Immediately update page type and rebuild overlay, then navigate route.
      //
      // 小窗口 → 全屏：立即更新页面类型并重建覆盖层，然后导航路由。
      _shouldAnimateRect = true;
      _currentPageType = targetPageType;
      _callOverlayEntry?.markNeedsBuild();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToPage(targetPageType, navigatorKey);
      });
      // Reset after AnimatedPositioned finishes (250ms), so subsequent
      // rebuilds (e.g. drag updates) use Duration.zero instead of animating.
      //
      // AnimatedPositioned 完成后重置（250毫秒），这样后续重建（例如拖动更新）使用 Duration.zero 而不是动画。
      Future.delayed(const Duration(milliseconds: 250), () {
        _shouldAnimateRect = false;
      });
    } else {
      // Fullscreen → Small window, or same-size switch:
      // Animate when at least one side is not a small window;
      // skip animation for small↔small transitions (e.g. floating → banner).
      //
      // 全屏 → 小窗口，或同尺寸切换：
      //
      // 跳过小↔小过渡动画（例如浮动 → 横幅）。
      _shouldAnimateRect =
          !_isSmallWindow(previousPageType) || !_isSmallWindow(targetPageType);
      _currentPageType = targetPageType;
      _callOverlayEntry?.markNeedsBuild();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToPage(targetPageType, navigatorKey);
      });
      if (_shouldAnimateRect) {
        Future.delayed(const Duration(milliseconds: 250), () {
          _shouldAnimateRect = false;
        });
      }
    }
  }

  void _hidePage(CallPageType type) {
    if (_currentPageType != type) return;

    if (type == CallPageType.invite) {
      final navigator = _callNavigatorKey.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
        _currentPageType = _pageTypeBeforeInvite;
        _pageTypeBeforeInvite = CallPageType.none;
        _callOverlayEntry?.markNeedsBuild();
        return;
      }
    }

    _removeCallOverlay();
  }

  void _removeCallOverlay() {
    _cancelDeviceOpen?.call();
    _callOverlayEntry?.remove();
    _callOverlayEntry = null;
    _callNavigatorKey = GlobalKey<NavigatorState>();
    _currentPageType = CallPageType.none;
  }

  /// 帧末切页只操作发起切换的原浮层，避免旧场次的动画跳转覆盖新来电。
  void _navigateToPage(
      CallPageType pageType, GlobalKey<NavigatorState> navigatorKey) {
    if (navigatorKey != _callNavigatorKey || pageType != _currentPageType) {
      return;
    }
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final routeName = _getRouteName(pageType);

    if (pageType == CallPageType.invite) {
      navigator.pushNamed(routeName);
    } else {
      if (!navigator.canPop()) {
        navigator.pushNamed(routeName);
      } else {
        navigator.pushReplacementNamed(routeName);
      }
    }
  }

  String _getRouteName(CallPageType pageType) {
    switch (pageType) {
      case CallPageType.calling:
        return '/calling';
      case CallPageType.floating:
        return '/floating';
      case CallPageType.pip:
        return '/pip';
      case CallPageType.invite:
        return '/invite';
      case CallPageType.banner:
        return '/banner';
      case CallPageType.none:
        return '/';
    }
  }

  /// 在通话主题内建立导航和小窗外壳，子路由及内嵌弹窗均继承同一配色。
  Widget _buildCallNavigator(BuildContext _) {
    return _CallOverlayLayout(
      rectGetter: _getPageRect,
      borderRadiusGetter: _getPageBorderRadius,
      isAnimatingGetter: () => _shouldAnimateRect,
      showAudioSurface: _isAudioCard,
      child: Navigator(
        key: _callNavigatorKey,
        initialRoute: _getRouteName(_currentPageType),
        onGenerateRoute: (settings) {
          return _buildRoute(settings);
        },
      ),
    );
  }

  Rect _getPageRect(Size screenSize, EdgeInsets viewPadding) {
    switch (_currentPageType) {
      case CallPageType.floating:
        final left = screenSize.width - _floatViewRight - _floatWindowWidth;
        final top = _isAudioCard
            ? viewPadding.top +
                CallCompactAudioContent.topGap +
                (_floatViewTop - _initialFloatViewTop)
            : _floatViewTop - 40;
        return Rect.fromLTWH(left, top, _floatWindowWidth, _floatWindowHeight);
      case CallPageType.banner:
        // 浮层只占横幅及状态栏所需的高度，底层消息页保留交互。
        final bannerHeight = viewPadding.top +
            IncomingBannerContent.topGap +
            IncomingBannerContent.height;
        return Rect.fromLTWH(0, 0, screenSize.width, bannerHeight);
      case CallPageType.calling:
      case CallPageType.invite:
      case CallPageType.pip:
      case CallPageType.none:
        return Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
    }
  }

  BorderRadius _getPageBorderRadius() {
    switch (_currentPageType) {
      case CallPageType.floating:
        return BorderRadius.circular(12.0);
      case CallPageType.banner:
        return BorderRadius.zero;
      default:
        return BorderRadius.zero;
    }
  }

  bool _isSmallWindow(CallPageType type) {
    return type == CallPageType.floating ||
        type == CallPageType.banner ||
        type == CallPageType.pip;
  }

  void updateFloatPosition(DragUpdateDetails details, Size screenSize) {
    _floatViewRight -= details.delta.dx;
    _floatViewTop += details.delta.dy;
    if (_floatViewTop < 100) {
      _floatViewTop = 100;
    }
    if (_floatViewTop > screenSize.height - 216) {
      _floatViewTop = screenSize.height - 216;
    }
    if (_floatViewRight < 0) {
      _floatViewRight = 0;
    }
    if (_floatViewRight > screenSize.width - 110) {
      _floatViewRight = screenSize.width - 110;
    }
    _callOverlayEntry?.markNeedsBuild();
  }

  Route<dynamic>? _buildRoute(RouteSettings settings) {
    Widget page;
    bool fullscreenDialog = false;

    switch (settings.name) {
      case '/calling':
        page = CallMainWidget(
          callPageType: CallPageType.calling,
          callbacks: _buildCallPageCallbacks(),
        );
        break;
      case '/floating':
        page = CallMainWidget(
          callPageType: CallPageType.floating,
          callbacks: _buildCallPageCallbacks(),
        );
        break;
      case '/pip':
        page = CallMainWidget(
          callPageType: CallPageType.pip,
          callbacks: _buildCallPageCallbacks(),
        );
        break;
      case '/invite':
        fullscreenDialog = true;
        page = InviteUserWidget(
          callbacks: InviteUserCallbacks(
            onShowCalling: () {
              closeInvitePage();
            },
          ),
        );
        break;
      case '/banner':
        page = SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              IncomingBannerContent.horizontalInset,
              IncomingBannerContent.topGap,
              IncomingBannerContent.horizontalInset,
              0,
            ),
            child: IncomingBannerWidget(
              onShowCalling: () {
                showCallingPage();
              },
              onCloseAll: () => closeAllPage(),
            ),
          ),
        );
        break;
      default:
        page = const SizedBox.shrink();
    }

    final bool noAnimation =
        settings.name == '/calling' || settings.name == '/pip';

    final bool isFloating = settings.name == '/floating';

    if (isFloating) {
      return PageRouteBuilder(
        settings: settings,
        // 语音小窗外壳提供底色，停止绘制后面的全屏通话页。
        opaque: _isAudioCard,
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );
    }

    if (noAnimation) {
      return PageRouteBuilder(
        settings: settings,
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );
    }

    if (settings.name == '/banner') {
      return PageRouteBuilder(
        settings: settings,
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      );
    }

    return MaterialPageRoute(
      builder: (context) => page,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }

  CallPageCallbacks _buildCallPageCallbacks() {
    final presentation = _callOverlayEntry;
    return CallPageCallbacks(
      onShowCalling: () => showCallingPage(),
      onShowFloating: () => showFloatingPage(),
      onShowPip: () => showPipPage(),
      onShowInvitePage: () => showInvitePage(),
      onFloatDragUpdate: (details, screenSize) =>
          updateFloatPosition(details, screenSize),
      getOriginScreenSize: () => originScreenSize,
      setOriginScreenSize: (size) => setOriginScreenSize(size),
      isCurrentPresentation: () =>
          presentation != null && identical(_callOverlayEntry, presentation),
    );
  }

  /// 拒绝权限时只结束触发提示的旧邀请，不能拒绝权限弹窗期间新到达的通话。
  Future<void> handleNoPermissionAndEndCall(
      {PermissionType type = PermissionType.microphone}) async {
    final blockedCallId = CallStore.shared.state.activeCall.value.callId;
    final overlay = _navigatorGetter()?.overlay;
    if (overlay == null) return;
    final camera = type == PermissionType.camera;
    final goSettings = await _showPermissionAlert(overlay, camera: camera);
    final current = CallStore.shared.state.activeCall.value;
    if (blockedCallId.isNotEmpty &&
        current.callId == blockedCallId &&
        CallStore.shared.state.selfInfo.value.status ==
            CallParticipantStatus.waiting) {
      if (current.inviterId == CallStore.shared.state.selfInfo.value.id) {
        await CallStore.shared.hangup();
      } else {
        await CallStore.shared.reject();
      }
    }
    if (goSettings && !await Permission.openAppSettings() && overlay.mounted) {
      await _showPermissionAlert(overlay, camera: camera, settingsFailed: true);
    }
  }

  /// 使用公共基础弹窗保留权限类型及设置失败的独立文案，关闭后释放 OverlayEntry。
  Future<bool> _showPermissionAlert(OverlayState overlay,
      {required bool camera, bool settingsFailed = false}) {
    final completer = Completer<bool>();
    late OverlayEntry entry;
    void finish(bool result) {
      entry.remove();
      entry.dispose();
      if (!completer.isCompleted) completer.complete(result);
    }

    // 权限提示单独插入宿主浮层，需在同样的通话主题下读取颜色。
    Widget buildAlert(BuildContext context) {
      // 无法跳转设置时改为手动开启指引，且不再提供跳转按钮。
      final text = AppLocalization.of(context);
      final device = camera ? 'camera' : 'microphone';
      final title = settingsFailed
          ? text.resolve('chat.uikit.callSettingsFailedTitle', '无法自动跳转')
          : text.resolve('chat.uikit.callPermissionTitle.$device',
              camera ? '摄像头权限未开启' : '麦克风权限未开启');
      final guide = Platform.isIOS ? 'ios' : 'android';
      final content = settingsFailed
          ? text.resolve(
              'chat.uikit.callSettingsGuide.$device.$guide',
              camera
                  ? '抱歉，系统未能自动为您打开设置页面。请手动前往系统设置，找到并允许本应用访问摄像头。\n\n操作指引：打开设置→应用管理，找到应用名称→权限，开启摄像头权限。'
                  : '抱歉，系统未能自动为您打开设置页面。请手动前往系统设置，找到并允许本应用访问麦克风。\n\n操作指引：打开手机设置→应用管理，找到应用名称→权限，开启麦克风权限。')
          : text.resolve('chat.uikit.callPermissionContent.$device',
              camera ? '无法使用视频功能，请前往系统设置开启摄像头权限。' : '无法使用语音功能，请前往系统设置开启麦克风权限。');
      return Material(
        color: context.appColors.scrim.withValues(alpha: .7),
        child: AppAlertDialog(
            title: title,
            content: content,
            semanticsIdentifier: 'call.permission',
            cancelText: text.resolve('chat.uikit.callPermissionLater', '暂不开启'),
            confirmText: settingsFailed
                ? text.resolve('chat.uikit.callUnderstood', '我知道了')
                : text.callGoToSettings,
            showCancelButton: !settingsFailed,
            onCancel: () => finish(false),
            onConfirm: () => finish(!settingsFailed)),
      );
    }

    entry = OverlayEntry(
      builder: (_) => CallPresentationTheme(builder: buildAlert),
    );
    overlay.insert(entry);
    return completer.future;
  }
}

/// 用当前路由的几何裁剪通话浮层，保留必要的卡片阴影。
class _CallOverlayLayout extends StatelessWidget {
  final Rect Function(Size screenSize, EdgeInsets viewPadding) rectGetter;
  final BorderRadius Function() borderRadiusGetter;
  final bool Function() isAnimatingGetter;

  /// 语音浮窗在导航层之外裁剪卡片并绘制阴影。
  final bool showAudioSurface;
  final Widget child;

  const _CallOverlayLayout({
    required this.rectGetter,
    required this.borderRadiusGetter,
    required this.isAnimatingGetter,
    required this.showAudioSurface,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenSize = mq.size;
    final rect = rectGetter(screenSize, mq.viewPadding);
    final borderRadius = borderRadiusGetter();
    final shouldAnimate = isAnimatingGetter();
    final duration =
        shouldAnimate ? const Duration(milliseconds: 250) : Duration.zero;

    return Stack(
      children: [
        AnimatedPositioned(
          duration: duration,
          curve: Curves.easeOutCubic,
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: showAudioSurface
              ? CallCompactAudioSurface(child: child)
              : ClipRRect(borderRadius: borderRadius, child: child),
        ),
      ],
    );
  }
}
