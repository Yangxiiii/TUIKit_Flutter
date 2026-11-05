import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/voice_microphone_notice.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/asr_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_action_sheet.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_attachments.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_tooltip.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/sound_message_widget.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: Scaffold(body: child),
    );
MessageInfo _voice(int seconds, {String? asr}) => MessageInfo(
    msgID: 'voice',
    conversationType: ConversationType.c2c,
    messageType: MessageType.audio,
    status: MessageStatus.sendSuccess,
    messagePayload: AudioMessagePayload(audioDuration: seconds, asrText: asr));

void main() {
  testWidgets('单聊语音按时长扩展并独立显示红点、转换、过期状态', (tester) async {
    final state = AsrDisplayManager();
    final bubble = GlobalKey();
    Widget body(int seconds) => _host(SoundMessageWidget(
        message: _voice(seconds),
        isSelf: false,
        maxWidth: 390,
        bubbleKey: bubble,
        config: ChatMessageListConfig(),
        conversationID: 'c2c_peer',
        asrDisplayManager: state,
        onConvertToText: () {}));
    await tester.pumpWidget(body(2));
    expect(find.text('2″'), findsOneWidget);
    final shortSize = tester.getSize(find.byKey(bubble));
    expect(shortSize.width, greaterThanOrEqualTo(80));
    expect(shortSize.width, lessThan(182));
    expect(shortSize.height, 40);
    expect(
        find.bySemanticsIdentifier('chat.voice.unheard.voice'), findsOneWidget);
    expect(find.text('转文字'), findsOneWidget);
    await tester.pumpWidget(body(60));
    expect(tester.getSize(find.byKey(bubble)), const Size(182, 40));
    expect(find.text('60″'), findsOneWidget);
    state.markPlayed('voice');
    await tester.pump();
    expect(
        find.bySemanticsIdentifier('chat.voice.unheard.voice'), findsNothing);
    state.setExpired('voice');
    await tester.pump();
    expect(find.text('已过期'), findsOneWidget);
    expect(find.text('转文字'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('识别附件展示等待、失败和缓存正文，失败仍保留可重试状态', (tester) async {
    Widget body({bool loading = false, bool failed = false, String? text}) =>
        _host(AsrAttachmentBubble(
            message: _voice(2, asr: text),
            isSelf: false,
            maxWidth: 390,
            isConverting: loading,
            isFailed: failed));
    await tester.pumpWidget(body(loading: true));
    expect(find.text('正在识别'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(body(failed: true));
    expect(find.text('无法识别'), findsOneWidget);
    expect(find.byIcon(AppIcons.triangleAlert), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(body(text: '缓存识别正文'));
    expect(find.text('缓存识别正文'), findsOneWidget);
    expect(find.text('无法识别'), findsNothing);
  });

  testWidgets('语音路由和转文字在撤回分组之前，点击回调只执行一次', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var route = 0;
    var close = 0;
    await tester.pumpWidget(_host(Align(
        alignment: Alignment.bottomCenter,
        child: MessageActionSheet(items: [
          MessageMenuItem(
              id: 'audio-route', title: '听筒播放', onTap: () => route++),
          MessageMenuItem(id: 'voice-text', title: '语音转文字', onTap: () {}),
          MessageMenuItem(id: 'recall', title: '撤回', onTap: () {}),
        ], onClose: () => close++, onBounds: (_) {}))));
    await tester.pump();
    expect(tester.getTopLeft(find.text('听筒播放')).dy,
        lessThan(tester.getTopLeft(find.text('语音转文字')).dy));
    expect(tester.getTopLeft(find.text('语音转文字')).dy,
        lessThan(tester.getTopLeft(find.text('撤回')).dy));
    await tester.tap(find.text('听筒播放'));
    expect(route, 1);
    expect(close, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('权限提示为300宽单确认，不添加标题或设置跳转', (tester) async {
    await tester
        .pumpWidget(_host(const Center(child: VoiceMicrophoneNotice())));
    expect(tester.getSize(find.byType(VoiceMicrophoneNotice)),
        const Size(300, 148));
    expect(find.text('我知道了'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    expect(find.text('去设置'), findsNothing);
    expect(find.bySemanticsIdentifier('chat.voice.microphone_acknowledge'),
        findsOneWidget);
  });

  test('显示状态按当前列表隔离，重试清除失败并重新显示，清理不删SDK正文', () {
    final state = AsrDisplayManager();
    state.setFailed('a', true);
    state.hide('a');
    state.setConverting('a', true);
    expect(state.hasFailed('a'), isFalse);
    expect(state.isHidden('a'), isFalse);
    expect(state.isConverting('a'), isTrue);
    state.setExpired('a');
    expect(state.wasPlayed('a'), isTrue);
    expect(state.isConverting('a'), isFalse);
    state.clear();
    expect(state.wasPlayed('a'), isFalse);
    expect(state.isExpired('a'), isFalse);
    state.dispose();
  });
}
