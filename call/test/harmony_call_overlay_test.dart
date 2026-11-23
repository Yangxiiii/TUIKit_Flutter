import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/float/call_scene.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/float/call_compact_widget.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_scene.dart';
import 'package:tencent_calls_uikit/src/view/component/incoming_banner/incoming_banner_widget.dart';
import 'package:tencent_calls_uikit/src/view/harmony_call_overlay.dart';

void main() {
  testWidgets('鸿蒙多人来电、宫格和小窗复用共享界面，动作仍发送给原生场次', (tester) async {
    const channel = MethodChannel('tencent_calls_uikit/harmony_presentation');
    final messenger = tester.binding.defaultBinaryMessenger;
    Map<String, Object?> member(String id, {bool joined = true}) => {
      'id': id,
      'name': id,
      'avatar': '',
      'joined': joined,
      'camera': joined,
      'microphone': joined,
    };

    final self = member('self', joined: false);
    final inviter = member('inviter');
    final snapshot = <String, Object?>{
      'id': 'native-group',
      'chatGroup': true,
      'inviterId': 'inviter',
      'banner': true,
      'incoming': true,
      'accepted': false,
      'video': true,
      'duration': 0,
      'self': self,
      'peer': inviter,
      'members': [
        inviter,
        self,
        member('joined'),
        member('waiting', joined: false),
      ],
    };
    final actions = <String>[];
    var creating = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'harmonyPresentationAction') return snapshot;
      final data = call.arguments as Map<Object?, Object?>;
      expect(data['id'], 'native-group');
      actions.add(data['action'] as String);
      if (actions.last == 'accept') {
        snapshot.addAll({'accepted': true, 'banner': false, 'incoming': false});
        self.addAll({'joined': true, 'camera': true});
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') return ++creating;
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
    await tester.pumpWidget(
      const MaterialApp(
        home: HarmonyCallOverlay(child: Scaffold(body: Text('聊天页'))),
      ),
    );
    await tester.pumpAndSettle();
    final incoming = tester.widget<IncomingBannerContent>(
      find.byType(IncomingBannerContent),
    );
    expect(incoming.multi, isTrue);
    expect(incoming.userId, 'inviter');

    // 等待成员的动效持续播放，只推进有限帧。
    Future<void> renderGroupFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.tap(find.bySemanticsIdentifier('call.banner.accept'));
    await renderGroupFrame();
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier('call.minimize'),
        matching: find.byIcon(AppIcons.collapseModal),
      ),
      findsOneWidget,
    );
    expect(find.byType(GroupCallScene), findsOneWidget);
    expect(find.byType(CallScene), findsNothing);
    expect(find.text('群通话'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('call.group.member.waiting'),
      findsOneWidget,
    );
    expect(creating, 3);

    // 宫格聚焦继续使用同一个鸿蒙纹理，不为同一成员重复订阅。
    await tester.tap(find.bySemanticsIdentifier('call.group.member.joined'));
    await renderGroupFrame();
    expect(creating, 3);
    await tester.tap(find.bySemanticsIdentifier('call.group.microphone'));
    await renderGroupFrame();
    expect(actions, ['accept', 'microphone']);

    await tester.tap(find.bySemanticsIdentifier('call.minimize'));
    await renderGroupFrame();
    expect(find.byType(CallCompactAudioContent), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('call.restore'));
    await renderGroupFrame();
    expect(find.byType(GroupCallScene), findsOneWidget);
  });

  testWidgets('鸿蒙来电、全屏、小窗与结束使用共享 Flutter 通话组件', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 45.76);
    tester.view.viewPadding = const FakeViewPadding(top: 45.76);
    addTearDown(tester.view.reset);
    final channel = const MethodChannel(
      'tencent_calls_uikit/harmony_presentation',
    );
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
    var allowAccept = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'harmonyPresentationAction') {
        final data = call.arguments as Map<Object?, Object?>;
        actions.add(data);
        if (data['action'] == 'expand') snapshot['banner'] = false;
        if (data['action'] == 'accept' && allowAccept) {
          snapshot['accepted'] = true;
        }
        return null;
      }
      return snapshot;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var chatTaps = 0;
    Future<void> pumpApp(ThemeMode mode) => tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.create(
          const AppNormalColorScheme(),
          Brightness.light,
        ),
        darkTheme: AppThemeFactory.create(
          const AppDarkColorScheme(),
          Brightness.dark,
        ),
        themeMode: mode,
        themeAnimationDuration: Duration.zero,
        home: HarmonyCallOverlay(
          child: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => chatTaps++,
                child: const Text('聊天页'),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpApp(ThemeMode.dark);
    await tester.pumpAndSettle();
    final banner = find.byType(IncomingBannerContent);
    expect(
      tester.element(banner).appColors.danger,
      const AppNormalColorScheme().danger,
    );
    expect(
      Theme.of(tester.element(find.text('聊天页'))).brightness,
      Brightness.dark,
    );
    expect(tester.getRect(banner), const Rect.fromLTWH(12, 50, 366, 74));
    expect(
      tester.getRect(find.bySemanticsIdentifier('call.banner.reject')),
      const Rect.fromLTWH(266, 67, 40, 40),
    );
    expect(
      tester.getRect(find.bySemanticsIdentifier('call.banner.accept')),
      const Rect.fromLTWH(322, 67, 40, 40),
    );
    await tester.tap(find.text('聊天页'));
    expect(chatTaps, 1);

    await tester.tap(find.bySemanticsIdentifier('call.banner.open'));
    await tester.pumpAndSettle();
    expect(actions.single, {'id': 'call-1', 'action': 'expand'});
    final scene = find.byType(CallScene);
    expect(
      tester.element(scene).appColors.danger,
      const AppNormalColorScheme().danger,
    );
    await pumpApp(ThemeMode.light);
    expect(
      tester.element(scene).appColors.danger,
      const AppNormalColorScheme().danger,
    );

    await tester.tap(find.bySemanticsIdentifier('call.minimize'));
    await tester.pumpAndSettle();
    expect(find.byType(CallScene), findsNothing);
    final card = find.byType(CallCompactAudioContent);
    await pumpApp(ThemeMode.dark);
    expect(
      tester.element(card).appColors.surface,
      const AppNormalColorScheme().surface,
    );
    expect(tester.getRect(card), const Rect.fromLTWH(302, 118, 80, 80));
    expect(
      find.ancestor(of: card, matching: find.byType(CallCompactAudioSurface)),
      findsOneWidget,
    );
    expect(find.text('待接听'), findsOneWidget);
    final avatar = find.descendant(
      of: card,
      matching: find.byType(AppUserAvatar),
    );
    expect(tester.getRect(avatar), const Rect.fromLTWH(324, 128, 36, 36));

    // 接听未成功时保留浮窗，确认接通后再恢复同一通话。
    final accept = find.bySemanticsIdentifier('call.compact.accept');
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(actions.last, {'id': 'call-1', 'action': 'accept'});
    expect(card, findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('call.restore'));
    await tester.pumpAndSettle();
    expect(find.byType(CallScene), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('call.minimize'));
    await tester.pumpAndSettle();
    allowAccept = true;
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(tester.widget<CallScene>(find.byType(CallScene)).accepted, isTrue);

    // 原生结束事件立即清空页面，旧通话的动作与轮询不应再恢复浮层。
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('harmonyPresentationChanged', false),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byType(CallScene), findsNothing);
    expect(find.text('聊天页'), findsOneWidget);
  });

  testWidgets('语音主叫可在浮窗取消，接通后同一浮窗更新通话时长', (tester) async {
    const channel = MethodChannel('tencent_calls_uikit/harmony_presentation');
    final messenger = tester.binding.defaultBinaryMessenger;
    final snapshot = <String, Object?>{
      'id': 'voice-outgoing',
      'video': false,
      'accepted': false,
      'incoming': false,
      'duration': 0,
      'self': {'id': 'self', 'name': '本人', 'avatar': '', 'camera': false},
      'peer': {'id': 'peer', 'name': '对端', 'avatar': '', 'camera': false},
    };
    final actions = <Object?>[];
    var active = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'harmonyPresentationAction') {
        actions.add(call.arguments);
        active = false;
        return null;
      }
      return active ? snapshot : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      const MaterialApp(
        home: HarmonyCallOverlay(child: Scaffold(body: Text('聊天页'))),
      ),
    );
    await tester.pumpAndSettle();

    // 点击头像恢复同一通话，点击取消则发送原通话的结束动作。
    final minimize = find.bySemanticsIdentifier('call.minimize');
    final card = find.byType(CallCompactAudioContent);
    final cancel = find.bySemanticsIdentifier('call.compact.cancel');
    await tester.tap(minimize);
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);
    final avatar = find.descendant(
      of: card,
      matching: find.byType(AppUserAvatar),
    );
    await tester.tapAt(tester.getCenter(avatar));
    await tester.pumpAndSettle();
    expect(find.byType(CallScene), findsOneWidget);
    expect(actions, isEmpty);
    await tester.tap(minimize);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(actions, [
      {'id': 'voice-outgoing', 'action': 'end'},
    ]);
    expect(card, findsNothing);

    // 下一次主叫在浮窗等待时收到接通事件，位置保持且取消切换为时长。
    active = true;
    snapshot['id'] = 'voice-next';
    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('harmonyPresentationChanged', true),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    await tester.tap(minimize);
    await tester.pumpAndSettle();
    final rect = tester.getRect(card);
    snapshot['accepted'] = true;
    snapshot['duration'] = 125;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(tester.getRect(card), rect);
    expect(find.text('02:05'), findsOneWidget);
    expect(cancel, findsNothing);
  });

  testWidgets('鸿蒙满一小时挂断，原生成功后只提示一次', (tester) async {
    const channel = MethodChannel('tencent_calls_uikit/harmony_presentation');
    final messenger = tester.binding.defaultBinaryMessenger;
    final snapshot = <String, Object?>{
      'id': 'duration-call',
      'video': false,
      'accepted': false,
      'incoming': false,
      'duration': 3600,
      'self': {'id': 'self', 'name': '本人', 'avatar': '', 'camera': false},
      'peer': {'id': 'peer', 'name': '对端', 'avatar': '', 'camera': false},
    };
    final actions = <Object?>[];
    final hungUp = Completer<void>();
    var active = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'harmonyPresentationAction') {
        return active ? snapshot : null;
      }
      actions.add(call.arguments);
      if (actions.length == 1) {
        throw PlatformException(code: 'CALL_ACTION_FAILED');
      }
      await hungUp.future;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      MaterialApp(
        builder: AppDialog.init(),
        home: const HarmonyCallOverlay(child: Scaffold(body: Text('聊天页'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
    final toast = find.text('已达通话最长时长，通话结束');

    snapshot.addAll({'accepted': true, 'duration': 3599});
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(actions, isEmpty);

    snapshot['duration'] = 3600;
    await tester.pump(const Duration(milliseconds: 250));
    expect(actions, hasLength(1));
    expect(toast, findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    expect(actions, hasLength(2));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      actions,
      List.filled(2, {'id': 'duration-call', 'action': 'endAtDurationLimit'}),
    );
    expect(toast, findsNothing);

    // 原生可能先发送通话结束事件，再回报挂断请求成功。
    active = false;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('harmonyPresentationChanged', false),
      ),
      (_) {},
    );
    await tester.pump();
    expect(find.byType(CallScene), findsNothing);
    hungUp.complete();
    await tester.pumpAndSettle();
    expect(toast, findsOneWidget);
    expect(tester.getSemantics(toast).identifier, 'call.duration-limit');
    await tester.pump(const Duration(seconds: 2));
    expect(toast, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(toast, findsNothing);
    expect(actions, hasLength(2));
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
    await tester.pumpWidget(
      const MaterialApp(
        home: HarmonyCallOverlay(child: Scaffold(body: Text('聊天页'))),
      ),
    );
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

  testWidgets('接通时保留本机预览，远端关开摄像头不改变画面和小窗坐标', (tester) async {
    const channel = MethodChannel('tencent_calls_uikit/harmony_presentation');
    final messenger = tester.binding.defaultBinaryMessenger;
    final local = {'id': 'self', 'name': '本人', 'avatar': '', 'camera': true};
    final peer = {'id': 'peer', 'name': '对端', 'avatar': '', 'camera': true};
    final snapshot = <String, Object?>{
      'id': 'video-1',
      'video': true,
      'accepted': false,
      'duration': 8,
      'self': local,
      'peer': peer,
    };
    messenger.setMockMethodCallHandler(channel, (_) async => snapshot);
    var creations = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
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
    await tester.pumpWidget(
      const MaterialApp(
        home: HarmonyCallOverlay(child: Scaffold(body: Text('聊天页'))),
      ),
    );
    await tester.pumpAndSettle();
    Finder video(String id, {bool skipOffstage = true}) =>
        find.byWidgetPredicate(
          (widget) => widget is AndroidView && widget.creationParams == id,
          skipOffstage: skipOffstage,
        );
    // 等待时只绑定本机，接通后本机从全屏移到小窗并沿用同一个平台视图。
    final localRenderer = tester.state(video('self'));
    expect(video('peer'), findsNothing);
    expect(creations, 1);
    snapshot['accepted'] = true;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(tester.state(video('self')), same(localRenderer));
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
    final peerRect = tester.getRect(video('peer'));
    // 小窗居中裁剪，原生视图与画面都保留竖屏比例。
    expect(peerRect.center, smallRect.center);
    expect(peerRect.height, closeTo(smallRect.height, 0.001));
    expect(peerRect.width / peerRect.height, closeTo(9 / 16, 0.001));
    expect(peerRect.width, greaterThan(smallRect.width));
    final nativeSize = const Size(720, 1280) / tester.view.devicePixelRatio;
    expect(tester.getSize(video('peer')), nativeSize);
    expect(tester.getSize(video('self')), nativeSize);

    // 远端关闭时小画面显示同源头像，本端和原生视图身份保持不变。
    peer['camera'] = false;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(video('peer'), findsNothing);
    expect(
      tester.state(video('peer', skipOffstage: false)),
      same(peerRenderer),
    );
    expect(tester.getRect(swap), smallRect);
    expect(tester.getRect(video('self')), mainRect);
    expect(
      find.descendant(
        of: swap,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppUserAvatar && widget.userId == 'peer',
        ),
      ),
      findsWidgets,
    );

    peer['camera'] = true;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(tester.state(video('peer')), same(peerRenderer));
    expect(tester.getRect(video('peer')), peerRect);
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
