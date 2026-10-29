import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/conversation_list/rich_content_preview.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/rich_content_markdown.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

void main() {
  testWidgets('单行富文本保留列表、引用、代码和转义，撤回及未知协议不使用旧正文', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    const cases = {
      '1. **第一项**\n2. 第二项': '1. 第一项 2. 第二项',
      '- 第一项\n- 第二项': '• 第一项 • 第二项',
      '> 引用': '▎ 引用',
      r'\*\*原样\*\* `**代码**`': '**原样** **代码**',
      '![原图](https://example.com/a.png)': '[图片]',
    };
    for (final entry in cases.entries) {
      final preview = richContentConversationPreview(
          context,
          MessageInfo(
            messageType: MessageType.custom,
            messagePayload: CustomMessagePayload(
                customData: RichContentMessage([RichTextBlock(entry.key)])
                    .toCustomData()),
          ),
          const TextStyle(fontSize: 14));
      expect(preview!.toPlainText(), entry.value);
    }
    for (final message in [
      MessageInfo(
        status: MessageStatus.revoked,
        messageType: MessageType.custom,
        messagePayload: CustomMessagePayload(
            customData: const RichContentMessage([RichTextBlock('不可显示的正文')])
                .toCustomData()),
      ),
      MessageInfo(
          messageType: MessageType.custom,
          messagePayload: CustomMessagePayload(customData: 'invalid-json')),
      MessageInfo(
          messageType: MessageType.text,
          messagePayload: TextMessagePayload(text: '**普通消息原文**')),
    ]) {
      expect(
          richContentConversationPreview(
              context, message, const TextStyle(fontSize: 14)),
          isNull);
    }
  });

  testWidgets('会话行保留富文本格式及全部块顺序，媒体显示占位且点击进入会话', (tester) async {
    const content = RichContentMessage([
      RichTextBlock(
          '**粗体** *斜体* ~下划线~ ~~删除~~ [链接](https://example.com) **~组合~**'),
      RichImageBlock('https://example.com/image.png', 640, 360),
      RichTextBlock('**后续**'),
      RichFileBlock(
          'https://example.com/a.pdf', '报告.pdf', 1024, 'application/pdf'),
      RichFileBlock('https://example.com/a.mp4', '视频.mp4', 1024, 'video/mp4',
          width: 160, height: 90),
    ]);
    var openCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ConversationItem(
        conversation: ConversationInfo(
          conversationID: 'c2c_rich',
          avatarURL: '',
          lastMessage: MessageInfo(
            messageType: MessageType.custom,
            messagePayload:
                CustomMessagePayload(customData: content.toCustomData()),
          ),
        ),
        contentBuilder: (_, subtitle) => SizedBox(width: 320, child: subtitle),
        config: const ChatConversationActionConfig(
            isSupportPin: false, isSupportDelete: false),
        onTap: () => openCount++,
      )),
    ));
    final preview = tester.widget<RichText>(find.byType(RichText));
    expect(preview.text.toPlainText(), '粗体 斜体 下划线 删除 链接 组合 [图片] 后续 [文件] [视频]');
    expect(preview.maxLines, 1);
    expect(preview.overflow, TextOverflow.ellipsis);
    final spans = _textSpans(preview.text).toList();
    TextStyle styleOf(String text) =>
        spans.singleWhere((span) => span.text == text).style!;
    expect(styleOf('粗体').fontWeight, FontWeight.bold);
    expect(styleOf('斜体').fontStyle, FontStyle.italic);
    expect(
        styleOf('下划线').decoration!.contains(TextDecoration.underline), isTrue);
    expect(
        styleOf('删除').decoration!.contains(TextDecoration.lineThrough), isTrue);
    expect(
        styleOf('链接').decoration!.contains(TextDecoration.underline), isTrue);
    expect(styleOf('组合').fontWeight, FontWeight.bold);
    expect(
        styleOf('组合').decoration!.contains(TextDecoration.underline), isTrue);
    expect(spans.every((span) => span.recognizer == null), isTrue);
    await tester.tap(find.byType(RichText));
    expect(openCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('富文本摘要与聊天气泡显示相同文字，不暴露格式及链接语法', (tester) async {
    const source = '**粗体** ~~删除~~ ~下划线~ *斜体* [链接](https://example.com)';
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (value) {
        context = value;
        return const RichContentMarkdown(
          data: source,
          textStyle: TextStyle(fontSize: 14),
        );
      }),
    ));
    final visibleText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join();
    final message = MessageInfo(
      messageType: MessageType.custom,
      messagePayload: CustomMessagePayload(
        customData:
            const RichContentMessage([RichTextBlock(source)]).toCustomData(),
      ),
    );
    expect(visibleText, '粗体 删除 下划线 斜体 链接');
    expect(MessageUtil.getMessageAbstract(message, context), visibleText);
    expect(
      MessageUtil.getMessageAbstract(
        MessageInfo(
          messageType: MessageType.text,
          messagePayload: TextMessagePayload(text: source),
        ),
        context,
      ),
      source,
    );
  });

  test('摘要按一个换行替换一个空格且保持URL原样', () {
    const source = '甲\r\n乙\r丙\nhttps://example.com/a?q=1';
    expect(
      singleLineConversationPreview(source),
      '甲 乙 丙 https://example.com/a?q=1',
    );
    expect(source, contains('\r\n'));
  });
}

/// 展开样式树，核对实际送入会话行渲染的文字及格式。
Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _textSpans(child);
    }
  }
}
