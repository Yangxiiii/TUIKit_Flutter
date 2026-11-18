import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:tencent_calls_uikit/src/bridge/bootloader/bootloader.dart';
import 'package:tencent_calls_uikit/src/manager/call_page_router.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart';
import 'package:tencent_calls_uikit/src/state/group_call_metadata.dart';
import 'package:tencent_calls_uikit/src/tui_call_kit_impl.dart';
import 'package:tencent_calls_uikit/src/view/component/incoming_banner/incoming_banner_widget.dart';

import 'support/call_fakes.dart';

void main() {
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
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [Bootloader.instance],
        home: const Scaffold(body: Text('首页'))));

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

      // 补齐群标题不能替换邀请人姓名，也不能触发展开。
      GlobalState.instance.setGroupCallTitle(groupId, '真实群名');
      await tester.pump();
      expect(find.text('真实邀请人'), findsOneWidget);
      expect(find.text('真实群名'), findsNothing);
      expect(kit.pageRouter.getCurrentPageRoute(), CallPageType.banner);
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
                video: true,
                multi: true,
                onShowCalling: () => expands++,
                onReject: () => rejects++,
                onAccept: () => accepts++))));
    expect(find.text('邀请你加入多人视频通话…'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('call.banner.accept'));
    await tester.tap(find.bySemanticsIdentifier('call.banner.reject'));
    await tester.tap(find.bySemanticsIdentifier('call.banner.open'));
    expect((accepts, rejects, expands), (1, 1, 1));
  });
}

class _Call extends FakeCallInfo {
  _Call(String groupId)
      : super(
            callId: 'call-$groupId',
            inviterId: 'inviter',
            mediaType: CallMediaType.audio,
            chatGroupId: groupId,
            inviteeIds: const ['self']);

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
