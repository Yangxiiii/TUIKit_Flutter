import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/chat_media_sender.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/big_file_message.dart';
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
}
