import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/float/call_scene.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/float/call_compact_widget.dart';
import 'package:tencent_calls_uikit/src/view/component/incoming_banner/incoming_banner_widget.dart';
import 'package:tencent_calls_uikit/src/view/harmony_call_overlay.dart';

void main() {
  testWidgets('鸿蒙来电、全屏、小窗与结束使用共享 Flutter 通话组件', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 45.76);
    tester.view.viewPadding = const FakeViewPadding(top: 45.76);
    addTearDown(tester.view.reset);
    final channel =
        const MethodChannel('tencent_calls_uikit/harmony_presentation');
    final messenger = tester.binding.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    final snapshot = <String, Object?>{
      'id': 'call-1',
      'banner': true,
      'incoming': true,
      'video': false,
      'accepted': false,
      'duration': 0,
      'self': {'id': 'self', 'name': '本人', 'avatar': '', 'camera': false},
      'peer': {'id': 'peer', 'name': '对端', 'avatar': '', 'camera': false},
    };
    final actions = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'harmonyPresentationAction') {
        final data = call.arguments as Map<Object?, Object?>;
        actions.add(data);
        if (data['action'] == 'expand') snapshot['banner'] = false;
        return null;
      }
      return snapshot;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(
      home: HarmonyCallOverlay(child: Scaffold(body: Text('聊天页'))),
    ));
    await tester.pumpAndSettle();
    final banner = find.byType(IncomingBannerContent);
    expect(tester.getRect(banner), const Rect.fromLTWH(12, 50, 366, 74));
    expect(
      tester.getRect(find.bySemanticsIdentifier('call.banner.reject')),
      const Rect.fromLTWH(266, 67, 40, 40),
    );
    expect(
      tester.getRect(find.bySemanticsIdentifier('call.banner.accept')),
      const Rect.fromLTWH(322, 67, 40, 40),
    );

    await tester.tap(find.bySemanticsIdentifier('call.banner.open'));
    await tester.pumpAndSettle();
    expect(actions.single, {'id': 'call-1', 'action': 'expand'});
    expect(find.byType(CallScene), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier('call.minimize'));
    await tester.pumpAndSettle();
    expect(find.byType(CallScene), findsNothing);
    await tester.tap(find.bySemanticsIdentifier('call.restore'));
    await tester.pumpAndSettle();
    expect(find.byType(CallScene), findsOneWidget);

    // 原生结束事件立即清空页面，旧通话的动作与轮询不应再恢复浮层。
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
          const MethodCall('harmonyPresentationChanged', false)),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byType(CallScene), findsNothing);
    expect(find.text('聊天页'), findsOneWidget);
  });

  testWidgets('鸿蒙语音设备和结束按钮发送原通话操作，空快照清除残留页面', (tester) async {
    const channel = MethodChannel('tencent_calls_uikit/harmony_presentation');
    final messenger = tester.binding.defaultBinaryMessenger;
    final snapshot = <String, Object?>{
      'id': 'call-1',
      'banner': false,
      'incoming': false,
      'video': false,
      'accepted': true,
      'duration': 8,
      'microphone': true,
      'speaker': false,
      'self': {'id': 'self', 'name': '本人', 'avatar': '', 'camera': false},
      'peer': {'id': 'peer', 'name': '对端', 'avatar': '', 'camera': false},
    };
    var active = true;
    final actions = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'harmonyPresentationAction') {
        return active ? snapshot : null;
      }
      final data = call.arguments as Map<Object?, Object?>;
      expect(data['id'], 'call-1');
      final action = data['action'] as String;
      actions.add(action);
      if (action == 'microphone') snapshot['microphone'] = false;
      if (action == 'speaker') snapshot['speaker'] = true;
      if (action == 'end') active = false;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(
      home: HarmonyCallOverlay(child: Scaffold(body: Text('聊天页'))),
    ));
    await tester.pumpAndSettle();

    for (final (control, action) in [
      ('microphone', 'microphone'),
      ('speaker', 'speaker'),
      ('end', 'end'),
    ]) {
      await tester.tap(find.bySemanticsIdentifier('call.$control'));
      await tester.pumpAndSettle();
      expect(actions.last, action);
    }
    // 即使没有收到原生结束事件，空快照也要释放旧通话界面。
    expect(find.byType(CallScene), findsNothing);
    expect(find.text('聊天页'), findsOneWidget);
  });

  testWidgets('远端关开摄像头不改变已交换的画面和小窗坐标', (tester) async {
    const channel = MethodChannel('tencent_calls_uikit/harmony_presentation');
    final messenger = tester.binding.defaultBinaryMessenger;
    final local = {'id': 'self', 'name': '本人', 'avatar': '', 'camera': true};
    final peer = {'id': 'peer', 'name': '对端', 'avatar': '', 'camera': true};
    final snapshot = <String, Object?>{
      'id': 'video-1',
      'video': true,
      'accepted': true,
      'duration': 8,
      'self': local,
      'peer': peer,
    };
    messenger.setMockMethodCallHandler(channel, (_) async => snapshot);
    var creations = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        creations++;
        return 7;
      }
      if (call.method == 'resize') {
        final size = call.arguments as Map<Object?, Object?>;
        return {'width': size['width'], 'height': size['height']};
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    });
    await tester.pumpWidget(const MaterialApp(
      home: HarmonyCallOverlay(child: Scaffold(body: Text('聊天页'))),
    ));
    await tester.pumpAndSettle();
    Finder video(String id, {bool skipOffstage = true}) =>
        find.byWidgetPredicate(
            (widget) => widget is AndroidView && widget.creationParams == id,
            skipOffstage: skipOffstage);
    final localRenderer = tester.state(video('self'));
    final peerRenderer = tester.state(video('peer'));
    expect(creations, 2);

    // 先把本端换到主画面，再拖动对端小画面。
    final swap = find.bySemanticsIdentifier('call.swap');
    await tester.tap(swap);
    await tester.pumpAndSettle();
    final beforeDrag = tester.getCenter(swap);
    await tester.drag(swap, const Offset(-90, 60));
    await tester.pumpAndSettle();
    final smallRect = tester.getRect(swap);
    final mainRect = tester.getRect(video('self'));
    expect(smallRect.center.dx, lessThan(beforeDrag.dx));
    expect(tester.getRect(video('peer')), smallRect);

    // 远端关闭时小画面显示同源头像，本端和原生视图身份保持不变。
    peer['camera'] = false;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(video('peer'), findsNothing);
    expect(
        tester.state(video('peer', skipOffstage: false)), same(peerRenderer));
    expect(tester.getRect(swap), smallRect);
    expect(tester.getRect(video('self')), mainRect);
    expect(
        find.descendant(
            of: swap,
            matching: find.byWidgetPredicate((widget) =>
                widget is AppUserAvatar && widget.userId == 'peer')),
        findsWidgets);

    peer['camera'] = true;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(tester.state(video('peer')), same(peerRenderer));
    expect(tester.getRect(video('peer')), smallRect);
    expect(tester.getRect(video('self')), mainRect);

    // 悬浮窗内关闭再开启同样保留位置，点击画面仍可恢复。
    await tester.tap(find.bySemanticsIdentifier('call.minimize'));
    await tester.pumpAndSettle();
    final compact = find.byType(CallCompactVideoContent);
    final compactMain = tester.getRect(video('self'));
    final compactSmall = tester.getRect(video('peer'));
    expect(compact, findsOneWidget);
    peer['camera'] = false;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(tester.getRect(video('self')), compactMain);
    peer['camera'] = true;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(tester.getRect(video('peer')), compactSmall);
    await tester.tapAt(tester.getCenter(compact));
    await tester.pumpAndSettle();
    expect(find.byType(CallScene), findsOneWidget);
    expect(tester.state(video('self')), same(localRenderer));
    expect(tester.state(video('peer')), same(peerRenderer));
    expect(creations, 2);
  });
}
