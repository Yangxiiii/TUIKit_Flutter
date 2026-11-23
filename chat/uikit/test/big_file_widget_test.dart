import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/chat_media_sender.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/big_file_message.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/custom_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/file_message_widget.dart';

void main() {
  testWidgets('相册压缩时显示活动进度，未知大小不显示为零', (tester) async {
    final message = MessageInfo(
      msgID: 'album_preparing',
      status: MessageStatus.sending,
      messageType: MessageType.file,
      messagePayload: FileMessagePayload(fileName: '视频.mp4'),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FileMessageWidget(
          message: message,
          isSelf: true,
          maxWidth: 300,
          config: const ChatMessageListConfig(),
        ),
      ),
    ));
    expect(find.text('视频.mp4'), findsOneWidget);
    expect(find.text('加载中…'), findsOneWidget);
    expect(find.text('0 B'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
  });

  testWidgets('大文件与普通文件采用同一卡片尺寸，上传进度与失败文字互斥且不覆盖文件信息', (tester) async {
    const file = BigFileMessage(
        url: 'https://files.test/a', name: '长文件名称.pdf', size: 104857601);
    final message = MessageInfo(
        msgID: 'upload',
        status: MessageStatus.sending,
        messageType: MessageType.custom,
        messagePayload: CustomMessagePayload(customData: file.toCustomData()));
    Future<void> show(ChatFileTransferView view) =>
        tester.pumpWidget(MaterialApp(
            theme: AppThemeFactory.create(
                const AppNormalColorScheme(), Brightness.light),
            home: Scaffold(
                body: Center(
                    child: FileMessageWidget(
                        message: message,
                        isSelf: true,
                        maxWidth: 300,
                        bigFile: file,
                        config: ChatMessageListConfig(
                            fileTransfers: {'upload': view},
                            fileIconBuilder: (context, name) =>
                                const SizedBox(width: 44, height: 44)))))));
    await show(const ChatFileTransferView(progress: .5));
    expect(find.text(file.name), findsOneWidget);
    expect(find.text('100.0 MB'), findsOneWidget);
    expect(tester.getSize(find.byType(FileMessageWidget)), const Size(284, 68));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .5);
    expect(find.text('发送失败'), findsNothing);
    message.status = MessageStatus.sendFail;
    await show(const ChatFileTransferView(failed: true));
    expect(find.text('发送失败'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await show(const ChatFileTransferView(failed: true, interrupted: true));
    expect(find.text('发送中断'), findsOneWidget);
    expect(find.text('发送失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收发两侧的单个 WAV 图文附件采用独立文件卡片尺寸', (tester) async {
    const attachment = RichFileBlock(
        'https://files.test/voice.wav', '较长的录音文件名.wav', 119091, 'audio/wav');
    const content = RichContentMessage([attachment]);
    final message = MessageInfo(
      msgID: 'rich-wav',
      messageType: MessageType.custom,
      messagePayload: CustomMessagePayload(customData: content.toCustomData()),
    );
    const icon = SizedBox(key: ValueKey('wav-icon'), width: 44, height: 44);

    for (final isSelf in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomMessageWidget(
            message: message,
            isSelf: isSelf,
            maxWidth: 400,
            config: ChatMessageListConfig(
              fileIconBuilder: (_, name) =>
                  name == attachment.name ? icon : const SizedBox(),
            ),
          ),
        ),
      ));
      final card = find.byType(FileMessageWidget);
      expect(card, findsOneWidget);
      expect(tester.getSize(card), const Size(284, 68));
      expect(find.byKey(const ValueKey('wav-icon')), findsOneWidget);
      expect(tester.widget<Text>(find.text(attachment.name)).maxLines, 1);
      expect(find.text('116.3 KB'), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsNothing);
    }
  });

  testWidgets('图文混排中的重复附件可各自定位并使用宿主文件下载', (tester) async {
    const attachment = RichFileBlock(
        'https://files.test/voice.wav', '录音.wav', 2048, 'audio/wav');
    const content = RichContentMessage([
      RichTextBlock('录音说明'),
      attachment,
      RichTextBlock('再次附上同一份录音'),
      attachment,
    ]);
    final message = MessageInfo(
      msgID: 'repeated-wav',
      messageType: MessageType.custom,
      messagePayload: CustomMessagePayload(customData: content.toCustomData()),
    );
    final download = Completer<String>();
    final requests = <BigFileMessage>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomMessageWidget(
          message: message,
          isSelf: false,
          maxWidth: 400,
          config: ChatMessageListConfig(fileDownloader: (file) {
            requests.add(file);
            return download.future;
          }),
        ),
      ),
    ));

    final cards = find.byType(FileMessageWidget);
    expect(cards, findsNWidgets(2));
    final identifiers = tester
        .widgetList<FileMessageWidget>(cards)
        .map((card) => card.attachment!.semanticsIdentifier)
        .toList();
    expect(identifiers.toSet(), hasLength(2));
    final second = find.bySemanticsIdentifier(identifiers.last);
    expect(second, findsOneWidget);
    await tester.tap(second);
    await tester.pump();
    expect(requests, hasLength(1));
    expect(requests.single.url, attachment.url);
    expect(requests.single.name, attachment.name);
    expect(requests.single.size, attachment.size);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // 离开气泡后完成下载请求，避免测试调用系统文件打开能力。
    await tester.pumpWidget(const SizedBox());
    download.complete('');
    await tester.pump();
  });
}
