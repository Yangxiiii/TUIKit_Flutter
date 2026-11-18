import 'dart:ui' show Tristate;

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_controls.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_media.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_member.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_member_tile.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_members_sheet.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_scene.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/call_grid_waiting_widget.dart';
import 'package:tencent_calls_uikit/src/view/component/incoming_banner/incoming_banner_widget.dart';

import 'group_call_android_preview.dart';
import 'support/repository_assets.dart';

Widget _app(Widget child) => MaterialApp(
    theme:
        AppThemeFactory.create(const AppNormalColorScheme(), Brightness.light),
    home: DefaultAssetBundle(
        bundle: RepositoryAssets(), child: Scaffold(body: child)));

GroupCallMember _member(int index,
        {GroupCallMemberStatus status = GroupCallMemberStatus.joined}) =>
    GroupCallMember(
        id: '$index', name: '成员$index', status: status, microphoneOn: true);

void main() {
  testWidgets('姓名蒙层随短名字收缩，长名字仍受卡片宽度约束', (tester) async {
    for (final name in ['我', '这是一个超出单张成员卡片显示宽度的长姓名']) {
      await tester.pumpWidget(_app(Center(
          child: SizedBox(
              width: 195,
              height: 195,
              child: GroupCallMemberTile(
                  member: GroupCallMember(
                      id: '0',
                      name: name,
                      status: GroupCallMemberStatus.joined),
                  video: const SizedBox.shrink())))));
      final label = find.byWidgetPredicate((widget) =>
          widget is Text &&
          widget.data == name &&
          widget.style?.fontSize == 12);
      final surface =
          find.ancestor(of: label, matching: find.byType(Container)).first;
      expect(tester.getSize(surface).width, name == '我' ? lessThan(50) : 195);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('管理页搜索32高、状态同行、重新呼叫保持小描边按钮', (tester) async {
    var retries = 0;
    await tester.pumpWidget(_app(GroupCallMembersSheet(
        members: [
          _member(0),
          const GroupCallMember(
              id: '1',
              name: '成员1',
              subtitle: '开发部',
              status: GroupCallMemberStatus.noResponse),
        ],
        selfId: '0',
        ended: false,
        onMicrophone: () {},
        onCamera: () {},
        onRetry: (_) => retries++)));
    expect(tester.getTopLeft(find.text('管理成员')).dx, 48);
    expect(
        tester
            .getSize(find
                .ancestor(
                    of: find.bySemanticsIdentifier('call.group.members.search'),
                    matching: find.byType(Container))
                .first)
            .height,
        32);
    expect(find.byIcon(AppIcons.black1), findsOneWidget);
    expect(
        (tester.getCenter(find.text('成员1')).dy -
                tester.getCenter(find.text('已超时')).dy)
            .abs(),
        lessThan(1));
    expect(
        tester
            .getSize(find.bySemanticsIdentifier('call.group.members.retry.1')),
        const Size(56, 28));
    expect(find.byType(Divider), findsNWidgets(2));
    final retry = find.bySemanticsIdentifier('call.group.members.retry.1');
    expect(retry, findsOneWidget);
    expect(
        tester
            .getSemantics(retry)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    await tester.tap(retry);
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('成员搜索支持汉字、完整拼音和首字母，不匹配时显示空状态', (tester) async {
    await tester.pumpWidget(_app(GroupCallMembersSheet(
        members: const [
          GroupCallMember(
              id: 'zhang', name: '张三', status: GroupCallMemberStatus.joined)
        ],
        selfId: 'zhang',
        ended: false,
        onMicrophone: () {},
        onCamera: () {},
        onRetry: (_) {})));
    for (final query in ['张', 'zhangsan', 'ZHANG SAN', 'zs']) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Text &&
              widget.data == '张三' &&
              widget.style?.fontSize == 14),
          findsOneWidget);
      expect(find.text('暂无匹配成员'), findsNothing);
    }
    await tester.enterText(find.byType(TextField), 'lisi');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('张三'), findsNothing);
    expect(find.text('暂无匹配成员'), findsOneWidget);
  });

  testWidgets('底部安全区至少34并尊重更大系统边距，大图麦克风紧邻姓名', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final bottom in [0.0, 16.0, 34.0, 48.0]) {
      await tester.pumpWidget(_app(MediaQuery(
          data: MediaQueryData(
              size: const Size(390, 844),
              padding: EdgeInsets.only(top: 46, bottom: bottom)),
          child: GroupCallScene(
              title: '群名',
              status: const SizedBox.shrink(),
              members: const [
                GroupCallMember(
                    id: 'self', name: '我', status: GroupCallMemberStatus.joined)
              ],
              inviterId: 'self',
              selfId: 'self',
              incoming: false,
              video: true,
              initialFocusedId: 'self',
              videoBuilder: (_) => const SizedBox.shrink(),
              controls:
                  const SizedBox(key: ValueKey('controls'), height: 216)))));
      final controls = tester.getRect(find.byKey(const ValueKey('controls')));
      expect(844 - controls.bottom, (bottom < 34 ? 34 : bottom) + 16);
      final main = find.bySemanticsIdentifier('call.group.member.self');
      final microphone =
          find.descendant(of: main, matching: find.byIcon(AppIcons.micOff));
      final label = find.descendant(
          of: main,
          matching: find.byWidgetPredicate((widget) =>
              widget is Text &&
              widget.data == '我' &&
              widget.style?.fontSize == 12));
      expect(microphone, findsOneWidget);
      expect(tester.getRect(microphone).left - tester.getRect(label).right, 8);
      expect(tester.getCenter(microphone).dy, tester.getCenter(label).dy);
      expect(
          tester.getRect(main).bottom - tester.getRect(microphone).bottom, 3);
      final thumbnailMic = find.descendant(
          of: find.bySemanticsIdentifier('call.group.thumbnail.self'),
          matching: find.byIcon(AppIcons.micOff));
      expect(
          tester.getRect(thumbnailMic).top -
              tester
                  .getRect(
                      find.bySemanticsIdentifier('call.group.thumbnail.self'))
                  .top,
          5);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('390×844画布双人起点220，大图340且缩略条从450开始', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final focused in [false, true]) {
      await tester.pumpWidget(_app(MediaQuery(
        data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 46, bottom: 34)),
        child: GroupCallScene(
            key: ValueKey(focused),
            title: '群名',
            status: const SizedBox.shrink(),
            members: List.generate(2, _member),
            inviterId: '0',
            selfId: '0',
            incoming: false,
            video: true,
            controls: const SizedBox(height: 216),
            initialFocusedId: focused ? '0' : null,
            videoBuilder: (_) => const SizedBox.shrink()),
      )));
      await tester.pump();
      final main =
          tester.getRect(find.bySemanticsIdentifier('call.group.member.0'));
      expect(main.top, focused ? 110 : 220);
      expect(main.size, focused ? const Size(390, 340) : const Size(195, 195));
      if (focused) {
        final thumbnail = tester
            .getRect(find.bySemanticsIdentifier('call.group.thumbnail.1'));
        expect(thumbnail.top, 450);
        expect(thumbnail.size, const Size(94, 94));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('九格、双人和大画面只保留每个成员一份视频纹理', (tester) async {
    final keys = {
      for (var index = 0; index < 9; index++) '$index': GlobalKey()
    };
    final semantics = tester.ensureSemantics();
    for (final count in [2, 3, 9]) {
      await tester.pumpWidget(_app(Center(
          child: SizedBox(
              width: 390,
              height: 434,
              child: GroupCallMedia(
                  key: ValueKey(count),
                  members: List.generate(count, _member),
                  videoBuilder: (id) => SizedBox(key: keys[id]))))));
      await tester.pump();
      expect(find.bySemanticsIdentifier(RegExp(r'^call.group.member\.')),
          findsNWidgets(count));
      final first =
          tester.getRect(find.bySemanticsIdentifier('call.group.member.0'));
      expect(first.width, closeTo(count <= 4 ? 195 : 124.67, 1));
      await tester.tap(find.bySemanticsIdentifier('call.group.member.0'));
      await tester.pump();
      expect(find.bySemanticsIdentifier('call.group.thumbnail.0'),
          count == 2 ? findsNothing : findsOneWidget);
      expect(find.byKey(keys['0']!, skipOffstage: false), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('call.group.thumbnail.1'));
      await tester.pump();
      expect(find.byKey(keys['0']!, skipOffstage: false), findsOneWidget);
      expect(find.byKey(keys['1']!, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('来电只显示拒绝接听，接通后挂断，云录制及未验证翻转禁用', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final incoming in [true, false]) {
      await tester.pumpWidget(_app(GroupCallControls(
          incoming: incoming,
          connected: !incoming,
          ended: false,
          retryable: false,
          microphoneOn: true,
          cameraOn: true,
          canFlip: !incoming,
          onEnd: () {},
          onAccept: () {},
          onMicrophone: () {},
          onCamera: () {},
          onFlip: () {},
          onRetry: () {})));
      await tester.pump();
      expect(find.text('挂断'), incoming ? findsNothing : findsOneWidget);
      expect(find.bySemanticsIdentifier('call.group.accept'),
          incoming ? findsOneWidget : findsNothing);
      expect(find.bySemanticsIdentifier('call.group.microphone'),
          incoming ? findsNothing : findsOneWidget);
      if (!incoming) {
        for (final id in ['record', 'flip']) {
          final data = tester
              .getSemantics(find.bySemanticsIdentifier('call.group.$id'))
              .getSemanticsData();
          expect(data.flagsCollection.isEnabled, isNot(Tristate.isTrue));
          expect(data.hasAction(SemanticsAction.tap), isFalse);
        }
      }
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('管理成员仅本人设备可操作，搜索防抖，未知会控不显示伪权限', (tester) async {
    final semantics = tester.ensureSemantics();
    var selfTaps = 0;
    await tester.pumpWidget(_app(GroupCallMembersSheet(
        members: [
          _member(0),
          _member(1),
          _member(2, status: GroupCallMemberStatus.noResponse)
        ],
        selfId: '0',
        ended: false,
        onMicrophone: () => selfTaps++,
        onCamera: () {},
        onRetry: (_) {})));
    await tester.pump();
    await tester
        .tap(find.bySemanticsIdentifier('call.group.members.microphone.0'));
    expect(selfTaps, 1);
    expect(
        tester
            .getSemantics(
                find.bySemanticsIdentifier('call.group.members.microphone.1'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    await tester.enterText(find.byType(TextField), '成员2');
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.text('成员0'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('成员0'), findsNothing);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == '成员2'),
        findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('call.group.more'));
    await tester.pumpAndSettle();
    expect(find.text('未同步'), findsNWidgets(2));
    expect(find.byType(Switch), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('翻转能力不可用不限制本人开关摄像头', (tester) async {
    var taps = 0;
    for (final cameraOn in [false, true]) {
      await tester.pumpWidget(_app(GroupCallControls(
          incoming: false,
          connected: true,
          ended: false,
          retryable: false,
          microphoneOn: true,
          cameraOn: cameraOn,
          canFlip: false,
          onEnd: () {},
          onAccept: () {},
          onMicrophone: () {},
          onCamera: () => taps++,
          onFlip: () {},
          onRetry: () {})));
      expect(find.bySemanticsIdentifier('call.group.flip'), findsNothing);
      await tester.tap(find.bySemanticsIdentifier('call.group.camera'));
    }
    expect(taps, 2);
  });

  testWidgets('来电预览仅展示前三头像与真实溢出数量', (tester) async {
    await tester.pumpWidget(_app(CallGridWaitingWidget(
        inviter: _member(0),
        members: List.generate(8, (index) => _member(index + 1)),
        video: false)));
    await tester.pump();
    expect(find.text('+5'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is AppUserAvatar && widget.size == 40),
        findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android离线预览不依赖SDK即可启动并切换代表场景', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DefaultAssetBundle(
        bundle: RepositoryAssets(), child: const GroupCallPreviewApp()));
    await tester.pump();
    expect(find.byType(GroupCallMedia), findsOneWidget);
    expect(find.bySemanticsIdentifier('call.minimize'), findsOneWidget);
    expect(find.bySemanticsIdentifier('call.group.invite'), findsOneWidget);
    // 成员宫格只有单行姓名；机构字段只属于独立的成员管理资料。
    expect(find.text('开发部'), findsNothing);
    expect(find.text('已拒绝'), findsOneWidget);
    expect(find.bySemanticsIdentifier('call.group.reinvite.user5'),
        findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('call.preview.scene'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('大画面'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.bySemanticsIdentifier('call.group.thumbnail.user1'),
        findsOneWidget);
    expect(find.text('摄像头已开'), findsOneWidget);
    expect(find.text('麦克风已关'), findsOneWidget);
    final flip = tester
        .getSemantics(find.bySemanticsIdentifier('call.group.flip'))
        .getSemanticsData();
    expect(flip.hasAction(SemanticsAction.tap), isFalse);
    for (final scene in ['双人大画面', '来电横幅']) {
      await tester.tap(find.bySemanticsIdentifier('call.preview.scene'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(scene));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (scene == '双人大画面') {
        expect(find.bySemanticsIdentifier(RegExp(r'^call.group.thumbnail\.')),
            findsOneWidget);
        expect(find.bySemanticsIdentifier('call.group.thumbnail.self'),
            findsNothing);
        expect(find.text('摄像头已开'), findsOneWidget);
      } else {
        expect(find.byType(IncomingBannerContent), findsOneWidget);
        expect(find.byType(GroupCallScene), findsNothing);
        expect(find.text('来电横幅组件预览'), findsOneWidget);
        expect(
            find.bySemanticsIdentifier('call.banner.accept'), findsOneWidget);
      }
    }
    expect(tester.takeException(), isNull);
  });
}
