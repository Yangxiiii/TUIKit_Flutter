import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/rich_content_markdown.dart';

void main() {
  testWidgets('文字块渲染常用 Markdown 与单波浪号下划线', (tester) async {
    const source = '**粗体** ~~删除~~ ~下划线~ *斜体* [链接](https://example.com)\n\n'
        '1. 第一项\n2. 第二项\n\n'
        '- 无序项\n\n'
        '> 引用内容\n\n'
        '```\n代码内容\n```';

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RichContentMarkdown(
            data: source,
            textStyle: TextStyle(fontSize: 14),
          ),
        ),
      ),
    ));

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
      tester.widget<Text>(find.text('下划线')).style?.decoration,
      TextDecoration.underline,
    );
  });
}
