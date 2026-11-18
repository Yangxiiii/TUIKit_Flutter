import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_controls.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_member.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_members_sheet.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_more_sheet.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_mute_all_dialog.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_presentation.dart';

Widget _app(Widget child) => MaterialApp(
    theme:
        AppThemeFactory.create(const AppNormalColorScheme(), Brightness.light),
    home: Scaffold(body: child));

GroupControlState _control(
        {String hostId = 'self',
        String sessionId = 'session',
        int version = 1,
        bool known = true,
        bool allowUnmute = false,
        bool allowVideo = false,
        Map<String, Set<GroupControlDevice?>> pending = const {},
        Map<String, GroupControlOutcome> results = const {}}) =>
    GroupControlState(
        callId: 'call',
        sessionId: sessionId,
        selfId: 'self',
        hostId: hostId,
        policyKnown: known,
        version: version,
        allowSelfUnmute: allowUnmute,
        allowVideo: allowVideo,
        muteAll: true,
        cameraAllClosed: false,
        microphoneOn: true,
        cameraOn: false,
        pendingByUserId: pending,
        resultsByUserId: results);

const _members = [
  GroupCallMember(
      id: 'self',
      name: '本人',
      status: GroupCallMemberStatus.joined,
      microphoneOn: true),
  GroupCallMember(
      id: 'peer',
      name: '对方',
      status: GroupCallMemberStatus.joined,
      microphoneOn: true),
];

void main() {
  test('确认期间换场、主持交接和策略变更均使旧操作失效', () {
    final expected = _control();
    for (final current in [
      _control(sessionId: 'new'),
      _control(hostId: 'peer'),
      _control(version: 2),
      null
    ]) {
      expect(
          isCurrentGroupControlOperation(
              expected: expected,
              current: current,
              presentationIsCurrent: true),
          isFalse);
    }
    expect(
        isCurrentGroupControlOperation(
            expected: expected,
            current: _control(),
            presentationIsCurrent: false),
        isFalse);
    expect(
        isCurrentGroupControlOperation(
            expected: expected,
            current: _control(),
            presentationIsCurrent: true),
        isTrue);
  });

  testWidgets('全员相机独立于权限草稿，等待中禁用且成功后保留管理面板', (tester) async {
    final done = Completer<bool>();
    bool? target;
    var policyCalls = 0;
    await tester.pumpWidget(_app(GroupCallMoreSheet(
        allowSelfUnmute: false,
        allowVideo: false,
        canManage: true,
        onConfirm: (_, __) async {
          policyCalls++;
          return true;
        },
        onAllCameras: (enabled) {
          target = enabled;
          return done.future;
        })));
    await tester
        .tap(find.bySemanticsIdentifier('call.group.permissions.video'));
    await tester.pump();
    await tester
        .tap(find.bySemanticsIdentifier('call.group.permissions.openCameras'));
    await tester.pump();
    expect(target, isTrue);
    expect(policyCalls, 0);
    expect(find.text('处理中…'), findsOneWidget);
    expect(
        tester
            .getSemantics(find
                .bySemanticsIdentifier('call.group.permissions.closeCameras'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    done.complete(true);
    await tester.pump();
    expect(find.byType(GroupCallMoreSheet), findsOneWidget);
  });
  testWidgets('全员静音确认每次默认禁止自行开麦，复选只改变本次草稿', (tester) async {
    bool? draft;
    await tester.pumpWidget(
        _app(GroupMuteAllContent(onChanged: (value) => draft = value)));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(draft, isNull);
    await tester.tap(find
        .bySemanticsIdentifier('call.group.muteAllConfirm.allowSelfUnmute'));
    await tester.pump();
    expect(draft, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('更多管理取当前权限，等待结果不重复提交，失败保持面板', (tester) async {
    final completed = Completer<bool>();
    var count = 0;
    (bool, bool)? submitted;
    await tester.pumpWidget(_app(GroupCallMoreSheet(
        allowSelfUnmute: true,
        allowVideo: false,
        canManage: true,
        onConfirm: (unmute, video) {
          count++;
          submitted = (unmute, video);
          return completed.future;
        })));
    expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .map((value) => value.value),
        [true, false]);
    await tester
        .tap(find.bySemanticsIdentifier('call.group.permissions.video'));
    await tester.pump();
    await tester
        .tap(find.bySemanticsIdentifier('call.group.permissions.confirm'));
    await tester.pump();
    expect(submitted, (true, true));
    expect(find.text('处理中…'), findsOneWidget);
    expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .every((value) => value.onChanged == null),
        isTrue);
    expect(count, 1);
    completed.complete(false);
    await tester.pump();
    expect(find.text('确认'), findsOneWidget);
    expect(find.byType(GroupCallMoreSheet), findsOneWidget);
  });

  testWidgets('新策略重置旧草稿，非主持人仍能读取真实开关但不能修改', (tester) async {
    await tester.pumpWidget(_app(const GroupCallMoreSheet(
        allowSelfUnmute: true,
        allowVideo: true,
        policyVersion: 1,
        canManage: true)));
    await tester
        .tap(find.bySemanticsIdentifier('call.group.permissions.video'));
    await tester.pump();
    await tester.pumpWidget(_app(const GroupCallMoreSheet(
        allowSelfUnmute: false,
        allowVideo: true,
        policyVersion: 2,
        canManage: false)));
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches.map((value) => value.value), [false, true]);
    expect(switches.every((value) => value.onChanged == null), isTrue);
    expect(find.text('仅主持人可以修改权限'), findsOneWidget);
  });

  testWidgets('可信主持人发出明确设备目标，等待ACK保留媒体状态，拒绝显示真实失败', (tester) async {
    final semantics = tester.ensureSemantics();
    (String, GroupControlDevice, bool)? command;
    Widget sheet(GroupControlState state) => GroupCallMembersSheet(
        members: _members,
        selfId: 'self',
        ended: false,
        controlState: state,
        onMicrophone: () {},
        onCamera: () {},
        onRetry: (_) {},
        onMemberDevice: (id, device, enabled) =>
            command = (id, device, enabled));
    await tester.pumpWidget(_app(sheet(_control())));
    final target =
        find.bySemanticsIdentifier('call.group.members.microphone.peer');
    await tester.tap(target);
    expect(command, ('peer', GroupControlDevice.microphone, false));
    await tester.pumpWidget(_app(
        sheet(_control(pending: {'peer': {GroupControlDevice.microphone}}))));
    expect(
        tester
            .getSemantics(target)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    final cameraTarget =
        find.bySemanticsIdentifier('call.group.members.camera.peer');
    expect(tester.getSemantics(cameraTarget).getSemanticsData()
        .hasAction(SemanticsAction.tap), isTrue);
    expect(find.text('正在等待1位成员确认'), findsOneWidget);
    await tester.pumpWidget(_app(sheet(_control(results: {
      'peer': const GroupControlOutcome(GroupControlStatus.denied,
          error: '麦克风权限已拒绝')
    }))));
    expect(find.text('对方：麦克风权限已拒绝'), findsOneWidget);
    expect(find.text('已设置静音'), findsNothing);
    await tester.pumpWidget(_app(sheet(_control(hostId: 'peer'))));
    expect(
        tester
            .getSemantics(target)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    semantics.dispose();
  });

  testWidgets('策略禁止自行开启不阻止关闭已有设备，等待时不乐观翻转状态', (tester) async {
    var microphone = 0;
    var camera = 0;
    Widget controls({bool pending = false}) => GroupCallControls(
        incoming: false,
        connected: true,
        ended: false,
        retryable: false,
        microphoneOn: true,
        cameraOn: false,
        canFlip: false,
        canOpenMicrophone: false,
        canOpenCamera: false,
        microphonePending: pending,
        onEnd: () {},
        onAccept: () {},
        onMicrophone: () => microphone++,
        onCamera: () => camera++,
        onFlip: () {},
        onRetry: () {});
    await tester.pumpWidget(_app(controls()));
    await tester.tap(find.bySemanticsIdentifier('call.group.microphone'));
    expect(microphone, 1);
    expect(
        tester
            .getSemantics(find.bySemanticsIdentifier('call.group.camera'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    await tester.pumpWidget(_app(controls(pending: true)));
    expect(find.text('麦克风已开'), findsOneWidget);
    expect(
        tester
            .getSemantics(find.bySemanticsIdentifier('call.group.microphone'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    expect(camera, 0);
  });
}
