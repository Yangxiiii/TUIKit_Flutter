import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/message_text.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_markdown_parser.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_markdown_span.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

import '../fixtures/emoji_fixture.dart';

void main() {
  setUp(configureEmojiFixture);

  test('空目录不误匹配，注册后计数和退格立刻使用新目录', () {
    EmojiManager.configure(assetPackage: 'feature_tim', emojis: const []);
    expect(EmojiManager.tokenPattern.hasMatch('甲[ZDEmoji_Smile]乙'), isFalse);
    expect(messageTextCharacterCount('[ZDEmoji_Smile]'), 15);
    configureEmojiFixture();
    expect(messageTextCharacterCount('${'字' * 3999}[ZDEmoji_Smile]'), 4000);
    expect(messageTextCharacterCount('[TUIEmoji_Smile]'), 16);
    final old = deleteMessageCharacterBefore(const TextEditingValue(
        text: '[TUIEmoji_Smile]',
        selection: TextSelection.collapsed(offset: 16)));
    expect(old.text, '[TUIEmoji_Smile');
    final known = deleteMessageCharacterBefore(const TextEditingValue(
        text: '甲[ZDEmoji_Smile]乙',
        selection: TextSelection.collapsed(offset: 8)));
    expect(known.text, '甲乙');
    expect(known.selection.baseOffset, 1);
  });

  test('重复或旧编码配置失败时保留原目录，不发生部分替换', () {
    final emoji = EmojiManager.emojis.first;
    expect(
        () => EmojiManager.configure(
            assetPackage: 'feature_tim', emojis: [emoji, emoji]),
        throwsArgumentError);
    expect(
        () =>
            EmojiManager.configure(assetPackage: 'feature_tim', emojis: const [
              EmojiPickerModelItem(
                  name: '[TUIEmoji_Smile]', path: 'old.png', label: '旧'),
            ]),
        throwsArgumentError);
    expect(EmojiManager.emojis.length, 2);
    expect(EmojiManager.getEmoji('[ZDEmoji_Smile]'), isNotNull);
    expect(EmojiManager.getEmoji('[TUIEmoji_Smile]'), isNull);
  });

  testWidgets('快捷回应只使用新目录和独立近期缓存，重复与旧项被过滤', (tester) async {
    SharedPreferences.setMockInitialValues({
      'recent_reaction_emojis': ['[TUIEmoji_Smile]'],
      'zd_emoji_v1_recent_reactions': [
        '[TUIEmoji_Smile]',
        '[ZDEmoji_Smile]',
        '[ZDEmoji_Unknown]',
        '[ZDEmoji_Smile]',
      ],
    });
    await StorageUtil.init();
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    expect(await RecentEmojiManager.getRecentEmojiIds(), ['[ZDEmoji_Smile]']);
    expect(
        (await RecentEmojiManager.getQuickEmojis(context)).map((e) => e.name),
        ['[ZDEmoji_Smile]', '[ZDEmoji_Like]']);
    await RecentEmojiManager.addRecentEmoji('[ZDEmoji_Like]');
    await RecentEmojiManager.addRecentEmoji('[TUIEmoji_Smile]');
    expect(await RecentEmojiManager.getRecentEmojiIds(),
        ['[ZDEmoji_Like]', '[ZDEmoji_Smile]']);
  });

  testWidgets('输入、摘要、富文本和回应共用业务目录，未知令牌不构造空图片', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    const source = '甲[ZDEmoji_Smile]乙[TUIEmoji_Smile][ZDEmoji_Unknown]';
    final editor = ChatSpecialTextSpanBuilder(
            onTapUrl: (_) {}, colorScheme: SemanticColorScheme.of(context))
        .build(source);
    final images = editor.children!.whereType<ImageSpan>().toList();
    expect(images, hasLength(1));
    expect(images.single.actualText, '[ZDEmoji_Smile]');
    expect(images.single.start, 1);
    expect(editor.toPlainText(), contains('[TUIEmoji_Smile][ZDEmoji_Unknown]'));
    expect(EmojiManager.createLocalizedStringFromEmojiCodes(context, source),
        '甲[微笑]乙[TUIEmoji_Smile][ZDEmoji_Unknown]');
    expect(EmojiManager.findEmojiKeyListFromText('$source😀'),
        ['[ZDEmoji_Smile]', '😀']);
    final spans = EmojiManager.buildInlineSpans(source);
    final image = (spans.whereType<WidgetSpan>().single.child as Image).image
        as AssetImage;
    expect(image.package, 'feature_tim');
    expect(image.assetName, endsWith('zd_emoji_smile.png'));
    expect(RecentEmojiManager.getAllEmojis(context).map((e) => e.name),
        ['[ZDEmoji_Like]', '[ZDEmoji_Smile]']);
    expect(RecentEmojiManager.getEmojiPath('[TUIEmoji_Smile]'), isNull);
    // 富文本叶子节点与普通正文读取相同目录，摘要仅显示名称。
    final nodes = parseRichContentMarkdown('**$source**');
    final rich =
        richContentMarkdownSpan(context, nodes.first, const TextStyle());
    expect(_images(rich), hasLength(1));
    final compact = richContentMarkdownSpan(
        context, nodes.first, const TextStyle(),
        compact: true);
    expect(compact.toPlainText(), contains('[微笑]乙[TUIEmoji_Smile]'));
  });
}

/// 遍历嵌套格式，检查正文表情没有因Markdown样式而退回文字。
Iterable<WidgetSpan> _images(InlineSpan span) sync* {
  if (span is WidgetSpan) yield span;
  if (span is TextSpan) {
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* _images(child);
    }
  }
}
