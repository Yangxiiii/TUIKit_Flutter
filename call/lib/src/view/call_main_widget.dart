import 'dart:math';
import 'dart:io';
import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:tuikit_atomic_x/permission/permission.dart';
import 'package:app_ui/app_ui.dart';
import 'callview/public/float/call_compact_widget.dart';
import 'callview/public/float/call_minimize_button.dart';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_calls_uikit/src/bridge/voip/fcm_data_sync_handler.dart';
import 'package:tencent_calls_uikit/src/common/utils/foreground_service.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart';
import 'package:tencent_calls_uikit/src/manager/call_page_router.dart';
import 'package:tencent_calls_uikit/src/view/callview/call_view.dart';

/// 管理通话全屏、应用内小窗和系统画中画，保留 SDK 前台生命周期。
class CallMainWidget extends StatefulWidget {
  /// 路由层提供的浮窗、邀请和恢复动作，不持有第二套通话状态。
  final CallPageCallbacks? callbacks;

  /// 当前路由展示类型，更新时只改变画面形态。
  final CallPageType? callPageType;

  const CallMainWidget({Key? key, this.callbacks, this.callPageType})
      : super(key: key);

  @override
  State<CallMainWidget> createState() => _CallMainWidgetState();
}

/// 跟随 SDK 页面类型维护浮窗拖动与恢复，生命周期订阅在销毁时解除。
class _CallMainWidgetState extends State<CallMainWidget>
    with WidgetsBindingObserver {
  final GlobalKey _callViewKey = GlobalKey();
  bool isMultiPerson = false;

  /// 当前展示形态，由路由更新，不复制 SDK 通话事实。
  CallPageType? _currentPageType;

  /// 等待路由切换首帧结束后才允许恢复，避免初始化期间重复切换。
  bool _isInitializing = true;

  double get originWidth =>
      widget.callbacks?.getOriginScreenSize?.call().width ?? 0;
  double get originHeight =>
      widget.callbacks?.getOriginScreenSize?.call().height ?? 0;

  @override
  void initState() {
    _currentPageType = widget.callPageType;
    _isInitializing = true;
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      ForegroundService.start();
    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    });

    super.initState();
  }

  @override
  void didUpdateWidget(CallMainWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.callPageType != widget.callPageType) {
      _currentPageType = widget.callPageType;
      _isInitializing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FcmDataSyncHandler().closeNotificationView();
      ForegroundService.start();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final realScreenSize = view.physicalSize / view.devicePixelRatio;
    final mediaSize = MediaQuery.of(context).size;
    final bestWidth = max(mediaSize.width, realScreenSize.width);
    final bestHeight = max(mediaSize.height, realScreenSize.height);
    widget.callbacks?.setOriginScreenSize?.call(Size(bestWidth, bestHeight));

    final pageType = _currentPageType ?? widget.callPageType;

    switch (pageType) {
      case CallPageType.calling:
        return _buildCallingPageWidget();
      case CallPageType.floating:
        return _buildFloatWindowWidget();
      case CallPageType.pip:
        return _buildPipWindowWidget();
      default:
        return _buildCallingPageWidget();
    }
  }

  Widget _buildPipWindowWidget() {
    final pipWidth = MediaQuery.of(context).size.width;
    final pipHeight = MediaQuery.of(context).size.height;
    final scale = originWidth > 0 ? pipWidth / originWidth : 1.0;

    return Scaffold(
      body: SizedBox(
        width: pipWidth,
        height: pipHeight,
        child: Container(
          width: pipWidth,
          height: pipHeight,
          decoration: const BoxDecoration(color: Colors.transparent),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: Size(
                originWidth > 0 ? originWidth : pipWidth,
                originHeight > 0 ? originHeight : pipHeight,
              ),
            ),
            child: ClipRect(
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: OverflowBox(
                  maxWidth: originWidth,
                  maxHeight: originHeight,
                  alignment: Alignment.center,
                  child: CallView(
                    key: _callViewKey,
                    isPipMode: true,
                    enableAITranscriber:
                        GlobalState.instance.enableAITranscriber,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 由外层接收整个悬浮窗的拖动和恢复手势。
  Widget _buildFloatWindowWidget() => Semantics(
        identifier: 'call.restore',
        button: true,
        onTap: _openCallingPage,
        label: AppLocalization.of(context)
            .resolve('chat.uikit.callRestore', '返回通话'),
        child: GestureDetector(
          // 即使腾讯视频区域忽略触摸，点击画面仍能恢复全屏。
          behavior: HitTestBehavior.opaque,
          onTap: _openCallingPage,
          excludeFromSemantics: true,
          onPanUpdate: (details) => widget.callbacks?.onFloatDragUpdate
              ?.call(details, MediaQuery.sizeOf(context)),
          child: _buildCompactContent(),
        ),
      );

  /// 单聊直接展示可读小窗；群聊沿用原 SDK 的缩放通话视图。
  Widget _buildCompactContent() {
    final call = CallStore.shared.state.activeCall.value;
    if (call.chatGroupId.isEmpty && call.inviteeIds.length <= 1) {
      return const CallCompactWidget();
    }
    final screenWidth = MediaQuery.sizeOf(context).width;
    final scale = 120 / screenWidth;
    return Transform.scale(
      scale: scale,
      alignment: Alignment.center,
      child: OverflowBox(
        maxWidth: screenWidth,
        maxHeight: 180 / scale,
        child: CallView(
            key: _callViewKey,
            isPipMode: true,
            enableAITranscriber: GlobalState.instance.enableAITranscriber),
      ),
    );
  }

  Widget _buildCallingPageWidget() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark),
        child: Scaffold(
          body: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Stack(
              children: [
                _buildCallView(),
                _buildFloatingWindowBtnWidget(),
                _buildInviterUserBtnWidget(),
              ],
            ),
          ),
        ));
  }

  Widget _buildCallView() {
    return Positioned(
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
      child: CallView(
        key: _callViewKey,
        enableAITranscriber: GlobalState.instance.enableAITranscriber,
      ),
    );
  }

  Widget _buildFloatingWindowBtnWidget() {
    return GlobalState.instance.enableFloatWindow
        ? CallMinimizeButton(onPressed: _openFloatWindow)
        : const SizedBox();
  }

  Widget _buildInviterUserBtnWidget() {
    return CallStore.shared.state.activeCall.value.chatGroupId.isNotEmpty
        ? Positioned(
            right: 12,
            top: 52,
            width: 40,
            height: 40,
            child: InkWell(
              onTap: () => _openInviteUser(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Image.asset(
                    'assets/images/add_user.png',
                    package: 'tencent_calls_uikit',
                  ),
                ),
              ),
            ),
          )
        : const SizedBox();
  }

  /// 安卓在系统授权后继续当前通话的最小化流程，其他平台直接切换。
  Future<void> _openFloatWindow() => AppServiceLocator.get<ActionGuard>()
          .singleFlight('tim.call.minimize', () async {
        final callId = CallStore.shared.state.activeCall.value.callId;
        if (!_canMinimize(callId)) return;
        if (Platform.isAndroid &&
            await Permission.check(PermissionType.systemAlertWindow) !=
                PermissionStatus.granted) {
          if (!mounted || !_canMinimize(callId)) return;
          final text = AppLocalization.of(context);
          final openSettings = await AppDialog.showAlert(
            title: text.resolve(
                'chat.uikit.callOverlayPermissionTitle', '未开启悬浮窗权限'),
            content: text.resolve(
                'chat.uikit.callOverlayPermissionContent', '请前往系统设置开启'),
            confirmText: text.callGoToSettings,
            showCancelButton: false,
            semanticsIdentifier: 'call.overlayPermission',
            theme: Theme.of(context),
          );
          if (openSettings != true || !_canMinimize(callId)) return;

          // 安卓插件打开悬浮窗设置页，并在返回时读取实际授权状态。
          const permission = PermissionType.systemAlertWindow;
          final permissions = await Permission.request([permission]);
          if (permissions[permission] != PermissionStatus.granted) return;
        }
        // 设置页面停留期间，旧通话可能结束或被另一通电话替换。
        if (_canMinimize(callId)) widget.callbacks?.onShowFloating?.call();
      });

  /// 只有仍在全屏展示的原通话可以响应最小化。
  bool _canMinimize(String callId) {
    if (!mounted || callId.isEmpty) return false;
    final state = CallStore.shared.state;
    return (_currentPageType ?? CallPageType.calling) == CallPageType.calling &&
        state.activeCall.value.callId == callId &&
        state.activeCall.value.mediaType != null &&
        state.selfInfo.value.status != CallParticipantStatus.none;
  }

  void _openInviteUser() {
    widget.callbacks?.onShowInvitePage?.call();
  }

  void _openCallingPage() {
    if (_isInitializing) {
      return;
    }
    widget.callbacks?.onShowCalling?.call();
  }
}
