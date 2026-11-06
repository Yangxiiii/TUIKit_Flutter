import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/participant/call_participant_pane.dart';

void main() {
  testWidgets('切换摄像头保留已挂载的视频视图，避免重新绑定原生纹理', (tester) async {
    var initialized = 0;
    for (final on in [false, true, false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: CallParticipantPane(
        userId: 'peer',
        name: '对端',
        avatarUrl: '',
        hasVideo: on,
        video: _VideoProbe(onInitialize: () => initialized++),
      )));
      expect(initialized, 1);
      expect(find.text('原生视频替身'), on ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('双方摄像头四种组合独立，头像复用公共展示与对方整页背景', (tester) async {
    for (final localOn in [false, true]) {
      for (final remoteOn in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          theme: AppThemeFactory.create(
              const AppNormalColorScheme(), Brightness.light),
          home: Row(children: [
            for (final (id, on) in [('local', localOn), ('remote', remoteOn)])
              Expanded(
                  child: CallParticipantPane(
                userId: id,
                name: id,
                avatarUrl: '',
                hasVideo: on,
                backgroundUserId: 'remote',
                backgroundName: 'remote',
                backgroundAvatarUrl: '',
                video: Text('video.$id'),
              )),
          ]),
        ));
        expect(
            find.text('video.local'), localOn ? findsOneWidget : findsNothing);
        expect(find.text('video.remote'),
            remoteOn ? findsOneWidget : findsNothing);
        final avatars =
            tester.widgetList<AppUserAvatar>(find.byType(AppUserAvatar));
        expect(avatars.length, (localOn ? 0 : 2) + (remoteOn ? 0 : 2));
        for (final background
            in avatars.where((a) => a.borderRadius == BorderRadius.zero)) {
          expect(background.userId, 'remote');
          expect(background.size, greaterThanOrEqualTo(600));
        }
      }
    }
  });
}

class _VideoProbe extends StatefulWidget {
  const _VideoProbe({required this.onInitialize});
  final VoidCallback onInitialize;
  @override
  State<_VideoProbe> createState() => _VideoProbeState();
}

class _VideoProbeState extends State<_VideoProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  Widget build(BuildContext context) => const Text('原生视频替身');
}
