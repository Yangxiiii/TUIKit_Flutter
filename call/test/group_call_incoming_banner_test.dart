import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' hide CallEndReason;
import 'package:tencent_calls_uikit/src/bridge/bootloader/bootloader.dart';
import 'package:tencent_calls_uikit/src/manager/call_page_router.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart';
import 'package:tencent_calls_uikit/src/state/group_call_metadata.dart';
import 'package:tencent_calls_uikit/src/tui_call_kit_impl.dart';
import 'package:tencent_calls_uikit/src/view/component/incoming_banner/incoming_banner_widget.dart';

import 'support/call_fakes.dart';

void main() {
  testWidgets('单聊语音和视频主叫先按受邀者取组织，通话 ID 补齐时沿用资料', (tester) async {
    TUICallEngine.instance = _Engine();
    final kit = TUICallKitImpl.instance;
    final state = CallStore.shared.state;
    final active = state.activeCall as ValueNotifier<CallInfo>;
    final self = state.selfInfo as ValueNotifier<CallParticipantInfo>;
    final participants = state.allParticipants as ValueNotifier<List<CallParticipantInfo>>;
    final originalCall = active.value;
    final originalSelf = self.value;
    final originalParticipants = participants.value;
    final queried = <List<String>>[];
    kit.setGroupMemberSubtitleLoader((account, ids) async {
      expect(account, 'self');
      queried.add(ids);
      return {'invitee': '技术研发部 I 工程师'};
    });
    addTearDown(() {
      kit.pageRouter.closeAllPage();
      kit.setGroupMemberSubtitleLoader(null);
      active.value = originalCall;
      self.value = originalSelf;
      participants.value = originalParticipants;
    });
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [Bootloader.instance],
      home: const Scaffold(body: Text('首页')),
    ));
    for (final video in [false, true]) {
      kit.pageRouter.closeAllPage();
      self.value = _Participant('self', status: CallParticipantStatus.none);
      participants.value = [];
      active.value = _Call('', video: video, outgoing: true, id: '');
      self.value = _Participant('self');
      await tester.pump();
      await tester.pump();
      expect(kit.pageRouter.getCurrentPageRoute(), CallPageType.calling);
      final organization = find.text('技术研发部 I 工程师');
      expect(organization, findsOneWidget);
      active.value = _Call('', video: video, outgoing: true, id: 'dial-$video');
      participants.value = [_Participant('invitee', name: '被叫姓名')];
      await tester.pump();
      final name = find.text('被叫姓名');
      expect(name, findsOneWidget);
      expect(tester.getTopLeft(organization).dy, greaterThan(tester.getBottomLeft(name).dy));
    }
    expect(queried, [['invitee'], ['invitee']]);
  });

  testWidgets('超时结果可缩小和恢复，新来电替换旧结果小窗', (tester) async {
    TUICallEngine.instance = _Engine();
    await AppServiceLocator.registerOrReplace(ActionGuard());
    final kit = TUICallKitImpl.instance;
    final state = GlobalState.instance;
    final sdkState = CallStore.shared.state;
    final active = sdkState.activeCall as ValueNotifier<CallInfo>;
    final self = sdkState.selfInfo as ValueNotifier<CallParticipantInfo>;
    final originalCall = active.value;
    final originalSelf = self.value;
    kit.enableFloatWindow(true);
    kit.enableIncomingBanner(true);
    addTearDown(() {
      kit.pageRouter.closeAllPage();
      kit.enableFloatWindow(false);
      kit.enableIncomingBanner(false);
      active.value = originalCall;
      self.value = originalSelf;
      state.clearGroupCall();
    });
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [Bootloader.instance],
      home: const Scaffold(body: Text('首页')),
    ));
    final session = state.groupCallSession;
    session.begin(
      callId: 'ended',
      groupId: 'group',
      groupName: '群通话',
      inviterId: 'self',
      mediaType: CallMediaType.video,
      memberIds: ['self', 'a', 'b'],
    );
    // 主叫已进入本地画面，对端尚未接通，超时结果应停止等待动画。
    session.sync(
      FakeCallInfo(callId: 'ended', mediaType: CallMediaType.video),
      [FakeParticipant('self', status: CallParticipantStatus.accept)],
    );
    session.end('ended', CallEndReason.noResponse, isCaller: true);
    kit.pageRouter.showCallingPage();
    await tester.pumpAndSettle();
    final minimize = find.bySemanticsIdentifier('call.minimize');
    final invite = find.bySemanticsIdentifier('call.group.invite');
    expect(minimize, findsOneWidget);
    expect(invite, findsOneWidget);
    expect(tester.widget<IconButton>(
      find.descendant(of: invite, matching: find.byType(IconButton)),
    ).onPressed, isNotNull);

    await tester.tap(minimize);
    await tester.pumpAndSettle();
    expect(kit.pageRouter.getCurrentPageRoute(), CallPageType.floating);
    expect(find.text('呼叫超时'), findsOneWidget);
    expect(find.bySemanticsIdentifier('call.compact.cancel'), findsNothing);
    await tester.tap(find.bySemanticsIdentifier('call.restore'));
    await tester.pumpAndSettle();
    expect(kit.pageRouter.getCurrentPageRoute(), CallPageType.calling);
    expect(find.text('呼叫超时，无人接听'), findsOneWidget);
    expect(invite, findsOneWidget);

    await tester.tap(minimize);
    await tester.pumpAndSettle();
    // SDK 先通知等待状态，再发送来电事件；旧结果小窗不能阻挡新横幅。
    active.value = _Call('new-group');
    self.value = _Participant('self');
    kit.callEventListener.onCallReceived!(
      'call-new-group',
      CallMediaType.audio,
      '',
    );
    await tester.pump();
    expect(kit.pageRouter.getCurrentPageRoute(), CallPageType.banner);
    expect(find.byType(IncomingBannerContent), findsOneWidget);
    expect(find.text('呼叫超时'), findsNothing);
  });

  testWidgets('群来电及两人临时多人均保留横幅，补充场景不会强制展开', (tester) async {
    // Store 仍用真实状态通知，仅替换原生观察者注册，测试无需加载音视频动态库。
    TUICallEngine.instance = _Engine();
    final state = CallStore.shared.state;
    final active = state.activeCall as ValueNotifier<CallInfo>;
    final self = state.selfInfo as ValueNotifier<CallParticipantInfo>;
    final participants =
        state.allParticipants as ValueNotifier<List<CallParticipantInfo>>;
    final originalCall = active.value;
    final originalSelf = self.value;
    final originalParticipants = participants.value;
    final kit = TUICallKitImpl.instance;
    kit.enableIncomingBanner(true);
    addTearDown(() {
      kit.pageRouter.closeAllPage();
      active.value = originalCall;
      self.value = originalSelf;
      participants.value = originalParticipants;
      GlobalState.instance.clearGroupCall();
      kit.enableIncomingBanner(false);
    });
    Future<void> pumpApp(ThemeMode mode) => tester.pumpWidget(MaterialApp(
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        darkTheme:
            AppThemeFactory.create(const AppDarkColorScheme(), Brightness.dark),
        themeMode: mode,
        themeAnimationDuration: Duration.zero,
        navigatorObservers: [Bootloader.instance],
        home: const Scaffold(body: Text('首页'))));
    await pumpApp(ThemeMode.light);

    for (final groupId in ['group', '']) {
      kit.pageRouter.closeAllPage();
      GlobalState.instance.clearGroupCall();
      active.value = originalCall;
      self.value = _Participant('self', status: CallParticipantStatus.none);
      participants.value = [_Participant('inviter', name: '真实邀请人')];

      // 复现 SDK 的先写场次/待接听，再发送 userData 的真实事件顺序。
      active.value = _Call(groupId);
      self.value = _Participant('self');
      kit.callEventListener.onCallReceived!('call-$groupId',
          CallMediaType.audio, GroupCallMetadata.temporaryMultiUserData);
      await tester.pump();
      expect(kit.pageRouter.getCurrentPageRoute(), CallPageType.banner);
      expect(find.byType(IncomingBannerContent), findsOneWidget);
      expect(find.text('真实邀请人'), findsOneWidget);
      expect(find.text('邀请你加入多人语音通话…'), findsOneWidget);
      final acceptButton = find.bySemanticsIdentifier('call.banner.accept');
      final acceptInk = tester.widget<Ink>(
        find.descendant(of: acceptButton, matching: find.byType(Ink)),
      );
      expect(
        (acceptInk.decoration as BoxDecoration).image!.image,
        const AssetImage('call_assets/dialing.png', package: 'tuikit_atomic_x'),
      );

      // 来电按钮保持原有配色，底层首页仍能切换到深色。
      await pumpApp(ThemeMode.dark);
      final rejectButton = tester.widget<Material>(find.descendant(
          of: find.bySemanticsIdentifier('call.banner.reject'),
          matching: find.byType(Material)));
      expect(rejectButton.color, const AppNormalColorScheme().danger);
      expect(Theme.of(tester.element(find.text('首页'))).brightness,
          Brightness.dark);
      await pumpApp(ThemeMode.light);

      // 补齐群标题不能替换邀请人姓名，也不能触发展开。
      GlobalState.instance.setGroupCallTitle(groupId, '真实群名');
      await tester.pump();
      expect(find.text('真实邀请人'), findsOneWidget);
      expect(find.text('真实群名'), findsNothing);
      expect(kit.pageRouter.getCurrentPageRoute(), CallPageType.banner);
    }

    // 单聊没有多人快照，两个媒体类型都复用当前发起人的异步资料。
    kit.setGroupMemberSubtitleLoader((_, ids) async => {
      if (ids.contains('inviter')) 'inviter': '技术研发部 I 工程师',
    });
    addTearDown(() => kit.setGroupMemberSubtitleLoader(null));
    for (final video in [false, true]) {
      kit.pageRouter.closeAllPage();
      GlobalState.instance.clearGroupCall();
      active.value = originalCall;
      self.value = _Participant('self', status: CallParticipantStatus.none);
      participants.value = [_Participant('inviter', name: '真实邀请人')];
      active.value = _Call('', video: video);
      self.value = _Participant('self');
      await tester.pump();
      await tester.pump();
      expect(find.text('真实邀请人'), findsOneWidget);
      expect(find.text('技术研发部 I 工程师'), findsOneWidget);
      expect(tester.widget<IncomingBannerContent>(
        find.byType(IncomingBannerContent),
      ).video, video);
    }
  });

  testWidgets('多人视频文案及接听、拒绝、展开保持独立入口', (tester) async {
    var accepts = 0;
    var rejects = 0;
    var expands = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IncomingBannerContent(
                userId: 'caller',
                name: '真实邀请人',
                avatarUrl: '',
                organization: '技术研发部 I 工程师',
                video: true,
                multi: true,
                onShowCalling: () => expands++,
                onReject: () => rejects++,
                onAccept: () => accepts++))));
    expect(find.text('邀请你加入多人视频通话…'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('技术研发部 I 工程师')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('真实邀请人')).dy),
    );
    final accept = find.bySemanticsIdentifier('call.banner.accept');
    final reject = find.bySemanticsIdentifier('call.banner.reject');
    expect(tester.getSize(accept), const Size.square(40));
    expect(tester.getSize(reject), const Size.square(40));
    expect(
      find.descendant(of: accept, matching: find.byIcon(AppIcons.cameraOnFilled)),
      findsOneWidget,
    );
    final rejectInk = tester.widget<Ink>(
      find.descendant(of: reject, matching: find.byType(Ink)),
    );
    expect(
      (rejectInk.decoration as BoxDecoration).image!.image,
      const AssetImage('call_assets/hangup.png', package: 'tuikit_atomic_x'),
    );
    await tester.tap(accept);
    await tester.tap(reject);
    await tester.tap(find.bySemanticsIdentifier('call.banner.open'));
    expect((accepts, rejects, expands), (1, 1, 1));
  });
}

class _Call extends FakeCallInfo {
  _Call(String groupId, {bool video = false, bool outgoing = false, String? id})
      : super(
            callId: id ?? 'call-$groupId',
            inviterId: outgoing ? 'self' : 'inviter',
            mediaType: video ? CallMediaType.video : CallMediaType.audio,
            chatGroupId: groupId,
            inviteeIds: outgoing ? const ['invitee'] : const ['self']);

  @override
  String get roomId => '';

  @override
  int get duration => 0;
}

class _Participant extends FakeParticipant {
  _Participant(super.id, {super.status, super.name});

  @override
  String get remark => '';
}

class _Engine extends Fake implements TUICallEngine {
  @override
  Future<void> addObserver(TUICallObserver observer) async {}

  @override
  Future<void> removeObserver(TUICallObserver observer) async {}
}
