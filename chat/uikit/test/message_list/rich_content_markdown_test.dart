import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/conversation_list/rich_content_preview.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_markdown_parser.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/rich_content_markdown.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

void main() {
  testWidgets('格式文字回车后编辑器、聊天和列表保留每行的嵌套样式', (tester) async {
    const source = '**前*甲乙*后**';
    final offset = source.indexOf('乙');
    final value =
        activeMarkdownFormatInputFormatter(() => <String>{}).formatEditUpdate(
      TextEditingValue(
          text: source, selection: TextSelection.collapsed(offset: offset)),
      TextEditingValue(
          text: source.replaceRange(offset, offset, '\n'),
          selection: TextSelection.collapsed(offset: offset + 1)),
    );
    late BuildContext context;
    late TextSpan editor;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (valueContext) {
      context = valueContext;
      editor = ChatSpecialTextSpanBuilder(
              onTapUrl: (_) {},
              colorScheme: SemanticColorScheme.of(context),
              mapMarkdownMarkers: true)
          .build(value.text, textStyle: const TextStyle(fontSize: 14));
      return RichContentMarkdown(
          data: value.text, textStyle: const TextStyle(fontSize: 14));
    })));
    expect(editor.toPlainText(), '前甲\n乙后');
    final bubble = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .join();
    expect(bubble, '前甲\n乙后');
    final preview = richContentConversationPreview(
        context,
        MessageInfo(
            messageType: MessageType.custom,
            messagePayload: CustomMessagePayload(
                customData: RichContentMessage([RichTextBlock(value.text)])
                    .toCustomData())),
        const TextStyle(fontSize: 14))!;
    expect(preview.toPlainText(), '前甲 乙后');
    for (final spans in [
      _textSpans(editor).toList(),
      tester
          .widgetList<RichText>(find.byType(RichText))
          .expand((w) => _textSpans(w.text))
          .toList(),
      _textSpans(preview).toList()
    ]) {
      for (final word in ['甲', '乙']) {
        final style = spans.singleWhere((s) => s.text == word).style!;
        expect(style.fontWeight, FontWeight.bold);
        expect(style.fontStyle, FontStyle.italic);
      }
    }
  });

  testWidgets('编辑器发送的紧邻格式段在三处展示一致', (tester) async {
    const cases = [
      '**甲****乙**',
      '~~甲~~~~乙~~',
      '~甲~~乙~',
      '***甲******乙***',
      '**~~甲~~****~~乙~~**',
    ];
    for (final source in cases) {
      final sent =
          RichContentDraft(blocks: [RichContentDraftTextBlock(1, source)])
              .toMessage()!;
      late BuildContext context;
      late TextSpan editor;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
        context = value;
        editor = ChatSpecialTextSpanBuilder(
          onTapUrl: (_) {},
          colorScheme: SemanticColorScheme.of(value),
          mapMarkdownMarkers: true,
        ).build(source, textStyle: const TextStyle(fontSize: 14));
        return RichContentMarkdown(
            data: (sent.blocks.single as RichTextBlock).text,
            textStyle: const TextStyle(fontSize: 14));
      })));
      expect(editor.toPlainText(), '甲乙', reason: '编辑器：$source');
      final bubble = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((widget) => widget.text.toPlainText())
          .join();
      expect(bubble, editor.toPlainText(), reason: '聊天窗口：$source');
      final preview = richContentConversationPreview(
          context,
          MessageInfo(
            messageType: MessageType.custom,
            messagePayload:
                CustomMessagePayload(customData: sent.toCustomData()),
          ),
          const TextStyle(fontSize: 14))!;
      expect(preview.toPlainText(), editor.toPlainText(),
          reason: '会话列表：$source');
    }
  });

  testWidgets('局部嵌套不丢失外层格式，聊天链接保留点击及地址校验', (tester) async {
    const source = '**前缀 *斜体* 后缀** ~下划线 ~~叠加~~ 末尾~ '
        '[**链接**](https://example.com) ~~[删除链接](https://example.com/delete)~~';
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const RichContentMarkdown(
          data: source, textStyle: TextStyle(fontSize: 14));
    })));
    final bubbleSpans = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((widget) => _textSpans(widget.text))
        .toList();
    final preview = richContentConversationPreview(
        context,
        MessageInfo(
          messageType: MessageType.custom,
          messagePayload: CustomMessagePayload(
              customData: const RichContentMessage([RichTextBlock(source)])
                  .toCustomData()),
        ),
        const TextStyle(fontSize: 14))!;
    expect(preview.toPlainText(), '前缀 斜体 后缀 下划线 叠加 末尾 链接 删除链接');
    final editor = ChatSpecialTextSpanBuilder(
      onTapUrl: (_) {},
      colorScheme: SemanticColorScheme.of(context),
      mapMarkdownMarkers: true,
    ).build(source, textStyle: const TextStyle(fontSize: 14));
    expect(editor.toPlainText(), preview.toPlainText());
    for (final spans in [
      _textSpans(editor).toList(),
      bubbleSpans,
      _textSpans(preview).toList()
    ]) {
      TextStyle styleOf(String text) =>
          spans.singleWhere((span) => span.text == text).style!;
      expect(styleOf('斜体').fontWeight, FontWeight.bold);
      expect(styleOf('斜体').fontStyle, FontStyle.italic);
      expect(
          styleOf('叠加').decoration!.contains(TextDecoration.underline), isTrue);
      expect(styleOf('叠加').decoration!.contains(TextDecoration.lineThrough),
          isTrue);
      expect(styleOf('链接').fontWeight, FontWeight.bold);
      expect(
          styleOf('链接').decoration!.contains(TextDecoration.underline), isTrue);
      expect(styleOf('删除链接').decoration!.contains(TextDecoration.underline),
          isTrue);
      expect(styleOf('删除链接').decoration!.contains(TextDecoration.lineThrough),
          isTrue);
    }
    final link = bubbleSpans.singleWhere((span) => span.text == '链接');
    (link.recognizer as TapGestureRecognizer).onTap!();
    await tester.pump();
    expect(calls.single.method, 'launch');
    expect((calls.single.arguments as Map)['url'], 'https://example.com');
    expect(
        _textSpans(preview).every((span) => span.recognizer == null), isTrue);

    // 重建时销毁旧链接资源，非法地址仍可显示文字但不能触发外部打开。
    await tester.pumpWidget(const MaterialApp(
        home: RichContentMarkdown(
      data: '~[**非法**](file:///tmp/private)~',
      textStyle: TextStyle(fontSize: 14),
    )));
    final invalid = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((widget) => _textSpans(widget.text))
        .singleWhere((span) => span.text == '非法');
    expect(invalid.recognizer, isNull);
    expect(calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('代码围栏、行内代码和转义文字不进入嵌套格式解析', (tester) async {
    const cases = {
      '~~~dart\n~**代码**~\n~~~': '~**代码**~',
      '`~**行内代码**~`': '~**行内代码**~',
      r'\~\*\*原样\*\*\~': '~**原样**~',
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(MaterialApp(
          home: RichContentMarkdown(
        data: entry.key,
        textStyle: const TextStyle(fontSize: 14),
      )));
      final visible = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((widget) => widget.text.toPlainText())
          .join()
          .trim();
      expect(visible, entry.value, reason: entry.key);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('编辑器、聊天和列表共用全部二至四层嵌套格式', (tester) async {
    for (final markers in _nestedFormatOrders()) {
      final source = '${markers.join()}多重嵌套${markers.reversed.join()}';
      late BuildContext context;
      late TextSpan editor;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
        context = value;
        editor = ChatSpecialTextSpanBuilder(
          onTapUrl: (_) {},
          colorScheme: SemanticColorScheme.of(value),
          mapMarkdownMarkers: true,
        ).build(source, textStyle: const TextStyle(fontSize: 14));
        return RichContentMarkdown(
            data: source, textStyle: const TextStyle(fontSize: 14));
      })));
      final bubbleSpans = tester
          .widgetList<RichText>(find.byType(RichText))
          .expand((widget) => _textSpans(widget.text))
          .toList();
      expect(
          tester
              .widgetList<RichText>(find.byType(RichText))
              .map((widget) => widget.text.toPlainText())
              .join(),
          '多重嵌套',
          reason: source);
      final preview = richContentConversationPreview(
          context,
          MessageInfo(
            messageType: MessageType.custom,
            messagePayload: CustomMessagePayload(
                customData:
                    RichContentMessage([RichTextBlock(source)]).toCustomData()),
          ),
          const TextStyle(fontSize: 14))!;
      expect(preview.toPlainText(), '多重嵌套', reason: source);
      expect(editor.toPlainText(), '多重嵌套', reason: source);
      for (final spans in [
        _textSpans(editor).toList(),
        bubbleSpans,
        _textSpans(preview).toList()
      ]) {
        final style = spans.singleWhere((span) => span.text == '多重嵌套').style!;
        expect(style.fontWeight ?? FontWeight.normal,
            markers.contains('**') ? FontWeight.bold : FontWeight.normal,
            reason: source);
        expect(style.fontStyle ?? FontStyle.normal,
            markers.contains('*') ? FontStyle.italic : FontStyle.normal,
            reason: source);
        expect(style.decoration?.contains(TextDecoration.underline) ?? false,
            markers.contains('~'),
            reason: source);
        expect(style.decoration?.contains(TextDecoration.lineThrough) ?? false,
            markers.contains('~~'),
            reason: source);
      }
    }
  });

  test('摘要保留代码和转义原文，块级排版转为文字并分隔相邻条目', () {
    const cases = {
      r'\*\*原样\*\* `**代码**`': '**原样** **代码**',
      '# 标题\n\n1. 第一项\n2. 第二项\n\n> 引用': '标题 第一项 第二项 引用',
      '```\n**代码**\n~原样~\n```': '**代码** ~原样~',
      '~~~dart\n**代码** ~原样~\n~~~': '**代码** ~原样~',
      '~ **保留空格** ~': '保留空格',
      '![替代文字](https://example.com/image.png)': '替代文字',
      'A &amp; B https://example.com/a_b?q=1&x=2':
          'A & B https://example.com/a_b?q=1&x=2',
      '**没有结束': '**没有结束',
      '**粗体*****叠加***': '粗体叠加',
    };
    for (final entry in cases.entries) {
      expect(
        singleLineConversationPreview(richContentMarkdownPlainText(entry.key)),
        entry.value,
        reason: entry.key,
      );
    }
  });

  testWidgets('文字块渲染常用 Markdown 与单波浪号下划线', (tester) async {
    const source = '**粗体** ~~删除~~ ~下划线~ *斜体* [链接](https://example.com)\n\n'
        '1. 第一项\n2. 第二项\n\n'
        '- 无序项\n\n'
        '> 引用内容\n\n'
        '```\n代码内容\n```';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RichContentMarkdown(
              data: source,
              textStyle: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final visibleText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join(' ');
    for (final value in [
      '粗体',
      '删除',
      '下划线',
      '斜体',
      '链接',
      '第一项',
      '第二项',
      '无序项',
      '引用内容',
      '代码内容',
    ]) {
      expect(visibleText, contains(value));
    }
    expect(visibleText, isNot(contains('~~删除~~')));
    expect(visibleText, isNot(contains('~下划线~')));
    expect(visibleText, isNot(contains('**粗体**')));
    expect(visibleText, isNot(contains('*斜体*')));
    expect(visibleText, isNot(contains('[链接]')));
    expect(
      tester
          .widgetList<RichText>(find.byType(RichText))
          .expand((widget) => _textSpans(widget.text))
          .singleWhere((span) => span.text == '下划线')
          .style
          ?.decoration,
      TextDecoration.underline,
    );
  });

  testWidgets('相邻的单格式与组合格式不会显示 Markdown 标记', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RichContentMarkdown(
          data: '**粗体*****叠加***',
          textStyle: TextStyle(fontSize: 14),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final visibleText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join();
    expect(visibleText, contains('粗体叠加'));
    expect(visibleText, isNot(contains('*')));
  });
}

/// 枚举格式叠加顺序，覆盖下划线位于内层、外层及连续波浪号的组合。
Iterable<List<String>> _formatOrders(List<String> values) sync* {
  if (values.isEmpty) {
    yield const [];
    return;
  }
  for (var index = 0; index < values.length; index++) {
    for (final suffix in _formatOrders([...values]..removeAt(index))) {
      yield [values[index], ...suffix];
    }
  }
}

/// 展开实际渲染的文字样式，不以可见文字正确代替格式正确。
Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _textSpans(child);
    }
  }
}

/// 枚举所有二至四层格式及顺序，避免只覆盖同时开启四种样式的情况。
Iterable<List<String>> _nestedFormatOrders() sync* {
  final seen = <String>{};
  for (final order in _formatOrders(['**', '~~', '*', '~'])) {
    for (var length = 2; length <= order.length; length++) {
      final markers = order.take(length).toList();
      if (seen.add(markers.join('|'))) yield markers;
    }
  }
}
