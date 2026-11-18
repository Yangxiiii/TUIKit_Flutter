import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_member.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_members_sheet.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_more_sheet.dart';

import 'group_call_android_preview.dart';
import 'group_call_control_preview_session.dart';
import 'support/repository_assets.dart';

void main() {
  test('离线三端使用正式控制器同步策略并收到各端设备回执', () async {
    final session = GroupControlPreviewSession([
      for (final id in ['self', 'user1', 'user2'])
        GroupCallMember(id: id, name: id, status: GroupCallMemberStatus.joined),
    ]);
    addTearDown(session.dispose);
    await session.start();
    expect(session.host.value.canManage, isTrue);
    final success =
        await session.execute('mute', session.host.value, session.host.muteAll);
    expect(success, isTrue);
    expect(session.host.value.resultsByUserId.keys.toSet(), {'user1', 'user2'});
    expect(session.host.value.allowSelfUnmute, isFalse);
    expect(
        session.members
            .every((member) => member.microphoneOn == (member.id == 'self')),
        isTrue);
    expect(session.host.value.pendingByUserId, isEmpty);
  });

  testWidgets('管理预览复用生产面板，更多管理全员相机和默认静音确认可交互', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DefaultAssetBundle(
        bundle: RepositoryAssets(), child: const GroupCallPreviewApp()));
    await tester.tap(find.bySemanticsIdentifier('call.preview.scene'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('管理成员'));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
        tester
            .widget<GroupCallMembersSheet>(find.byType(GroupCallMembersSheet))
            .controlState!
            .canManage,
        isTrue);
    for (final id in ['members.close', 'muteAll', 'more']) {
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('call.group.$id'))
          .getSemanticsData();
      expect(data.identifier, 'call.group.$id');
      expect(data.label, isNotEmpty);
      expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    }
    final unmuteBefore = tester
        .getSemantics(find.bySemanticsIdentifier('call.group.unmuteAll'))
        .getSemanticsData();
    expect(unmuteBefore.identifier, 'call.group.unmuteAll');
    expect(unmuteBefore.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(unmuteBefore.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(unmuteBefore.hasFlag(SemanticsFlag.isEnabled), isFalse);
    expect(unmuteBefore.hasAction(SemanticsAction.tap), isFalse);
    final more =
        tester.getSemantics(find.bySemanticsIdentifier('call.group.more'));
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(more.id, SemanticsAction.tap);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GroupCallMoreSheet), findsOneWidget);
    for (final id in ['cancel', 'confirm', 'closeCameras', 'openCameras']) {
      final data = tester
          .getSemantics(
              find.bySemanticsIdentifier('call.group.permissions.$id'))
          .getSemanticsData();
      expect(data.identifier, 'call.group.permissions.$id');
      expect(data.label, isNotEmpty);
      expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    }
    expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .map((value) => value.value),
        [true, true]);
    await tester
        .tap(find.bySemanticsIdentifier('call.group.permissions.closeCameras'));
    await tester.pump();
    expect(find.text('处理中…'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
    final members = tester
        .widget<GroupCallMembersSheet>(find.byType(GroupCallMembersSheet));
    expect(
        members.members
            .where((member) => member.joined)
            .every((member) => member.cameraOn == (member.id == 'self')),
        isTrue);
    await tester
        .tap(find.bySemanticsIdentifier('call.group.permissions.cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsIdentifier('call.group.muteAll'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    await tester
        .tap(find.bySemanticsIdentifier('call.group.muteAllConfirm.confirm'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
    final muted = tester
        .widget<GroupCallMembersSheet>(find.byType(GroupCallMembersSheet));
    expect(muted.controlState!.muteAll, isTrue);
    expect(muted.controlState!.allowSelfUnmute, isFalse);
    for (final id in ['muteAll', 'unmuteAll']) {
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('call.group.$id'))
          .getSemanticsData();
      expect(data.hasFlag(SemanticsFlag.isEnabled), id == 'unmuteAll');
      expect(data.hasAction(SemanticsAction.tap), id == 'unmuteAll');
    }
    expect(
        muted.members
            .where((member) => member.joined)
            .every((member) => member.microphoneOn == (member.id == 'self')),
        isTrue);
    expect(tester.takeException(), isNull);
  });
}
