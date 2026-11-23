import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/controls/single_call_controls.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/float/call_scene.dart';
import 'support/repository_assets.dart';

void main() {
  testWidgets('网络不佳仍保留全部设备操作且提示位于按钮上方', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) =>
            DefaultAssetBundle(bundle: RepositoryAssets(), child: child!),
        home: CallScene(
          self: (
            id: 'self',
            name: '本人',
            avatarUrl: '',
            subtitle: '',
            cameraOn: false
          ),
          remote: (
            id: 'peer',
            name: '对端',
            avatarUrl: '',
            subtitle: '',
            cameraOn: true
          ),
          video: true,
          accepted: true,
          localInMainView: false,
          onSwap: () {},
          videoBuilder: (_) => const SizedBox.shrink(),
          hint: const Text('当前通话你的网络不佳\n当前通话对方网络不佳'),
          timer: const Text('02:09'),
          controls: SingleCallControls(
              video: true,
              incoming: false,
              accepted: true,
              microphoneOn: true,
              speakerOn: true,
              cameraOn: false,
              onEnd: () {},
              onAccept: () {},
              onMicrophone: () {},
              onSpeaker: () {},
              onCamera: () {},
              onFlip: () {}),
        )));
    await tester.pump();
    for (final id in ['microphone', 'speaker', 'camera', 'end', 'flip']) {
      expect(find.bySemanticsIdentifier('call.$id'), findsOneWidget);
    }
    expect(
        tester.getBottomLeft(find.textContaining('当前通话你的网络不佳')).dy,
        lessThan(tester
            .getTopLeft(find.bySemanticsIdentifier('call.microphone'))
            .dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('语音和视频的主被叫操作区与接通状态完整且按钮标识可点击', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    for (final video in [false, true]) {
      for (final (incoming, accepted) in [
        (false, false),
        (true, false),
        (false, true)
      ]) {
        var end = 0;
        var accept = 0;
        await tester.pumpWidget(MaterialApp(
          builder: (_, child) =>
              DefaultAssetBundle(bundle: RepositoryAssets(), child: child!),
          theme: AppThemeFactory.create(
              const AppNormalColorScheme(), Brightness.light),
          home: CallScene(
            self: (
              id: 'self',
              name: '本人',
              avatarUrl: '',
              subtitle: '',
              cameraOn: false
            ),
            remote: (
              id: 'peer',
              name: '对端',
              avatarUrl: '',
              subtitle: '',
              cameraOn: false
            ),
            video: video,
            accepted: accepted,
            localInMainView: false,
            onSwap: () {},
            videoBuilder: (id) => Text('video.$id'),
            hint: const Text('当前状态'),
            timer: Text(accepted ? '02:09' : ''),
            controls: SingleCallControls(
                video: video,
                incoming: incoming,
                accepted: accepted,
                microphoneOn: true,
                speakerOn: false,
                cameraOn: false,
                onEnd: () => end++,
                onAccept: () => accept++,
                onMicrophone: () {},
                onSpeaker: () {},
                onCamera: () {},
                onFlip: () {}),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (!video || !accepted) {
          expect(
              find.byWidgetPredicate((widget) =>
                  widget is AppUserAvatar && widget.size == (video ? 72 : 96)),
              findsOneWidget);
        }
        expect(find.bySemanticsIdentifier('call.accept'),
            incoming ? findsOneWidget : findsNothing);
        expect(find.bySemanticsIdentifier('call.camera'),
            video ? findsOneWidget : findsNothing);
        expect(find.bySemanticsIdentifier('call.microphone'),
            !video && incoming ? findsNothing : findsOneWidget);
        expect(find.bySemanticsIdentifier('call.swap'),
            video && accepted ? findsOneWidget : findsNothing);
        final controls = find.byType(SingleCallControls);
        expect(tester.getRect(controls).bottom, 844 - (video ? 50 : 84));
        if (video) {
          final rows = find.descendant(
            of: controls,
            matching: find.byType(Row),
          );
          expect(rows, findsNWidgets(2));
          for (final row in [rows.first, rows.last]) {
            final rect = tester.getRect(row);
            expect(rect.left, 34);
            expect(rect.right, 390 - 34);
          }
        }
        // 按实际出现的按钮校验原版图片，并核对点击区尺寸。
        const assets = {
          'microphone': 'mute',
          'speaker': 'handsfree',
          'camera': 'camera_off',
          'end': 'hangup',
          'accept': 'dialing',
          'flip': 'switch_camera',
        };
        for (final MapEntry(key: id, value: asset) in assets.entries) {
          final button = find.bySemanticsIdentifier('call.$id');
          if (button.evaluate().isNotEmpty) {
            expect(tester.getSize(button), const Size(60, 60));
            final ink = tester.widget<Ink>(
              find.descendant(of: button, matching: find.byType(Ink)),
            );
            final image = (ink.decoration as BoxDecoration).image!.image;
            expect(
              image,
              AssetImage('call_assets/$asset.png', package: 'tuikit_atomic_x'),
            );
          }
        }
        if (video && accepted) {
          expect(
              tester
                  .getSemantics(find.bySemanticsIdentifier('call.swap'))
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              isTrue);
        }
        if (incoming) {
          expect(tester.getCenter(find.bySemanticsIdentifier('call.end')).dx,
              closeTo(video ? 87.67 : 97.5, 1));
          expect(tester.getCenter(find.bySemanticsIdentifier('call.accept')).dx,
              closeTo(video ? 302.33 : 292.5, 1));
        }
        await tester.tap(find.bySemanticsIdentifier('call.end'));
        expect(end, 1);
        if (incoming) {
          await tester.tap(find.bySemanticsIdentifier('call.accept'));
          expect(accept, 1);
        }
      }
    }
    semantics.dispose();
  });
}
