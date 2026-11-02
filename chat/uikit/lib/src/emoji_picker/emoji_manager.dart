import 'package:flutter/widgets.dart';

import 'emoji_picker_model.dart';

/// 管理业务注入的唯一表情目录，供面板、输入、正文、摘要和回应共同使用。
///
/// 不包含内置表情或旧编码映射；未注册的令牌始终按普通文字处理。
class EmojiManager {
  /// 当前已注册的完整目录，替换时整体更新，避免各展示入口持有不同映射。
  static Map<String, EmojiPickerModelItem> _emojis = const {};

  /// 目录资源统一所属包，在开放页面前由业务设置。
  static String _assetPackage = '';

  /// 仅匹配已注册的完整令牌；空目录必须无匹配，避免计数和退格误处理普通文字。
  static RegExp _tokenPattern = RegExp(r'(?!)');

  /// 当前唯一目录，顺序由业务提供；外部不能修改全局映射。
  static Iterable<EmojiPickerModelItem> get emojis => _emojis.values;

  /// 表情资源所属包，图片加载必须与业务声明一致。
  static String get assetPackage => _assetPackage;

  /// 输入、计数和预览共用的已知令牌匹配规则。
  static RegExp get tokenPattern => _tokenPattern;

  /// 在开放聊天页面前一次性安装业务表情，不保留上一版目录或隐式回退。
  static void configure({
    required List<EmojiPickerModelItem> emojis,
    required String assetPackage,
  }) {
    // 先校验完整目录再替换，防止错误配置产生只更新一部分的全局状态。
    final items = <String, EmojiPickerModelItem>{};
    for (final emoji in emojis) {
      if (!RegExp(r'^\[ZDEmoji_[A-Z][A-Za-z0-9]*\]$').hasMatch(emoji.name) ||
          emoji.path.isEmpty ||
          emoji.label.isEmpty ||
          items.containsKey(emoji.name)) {
        throw ArgumentError('表情编码必须唯一且符合ZDEmoji规范，名称和资源不能为空');
      }
      items[emoji.name] = emoji;
    }
    if (assetPackage.isEmpty) throw ArgumentError('表情资源所属包不能为空');
    // 验证通过后整体替换目录和匹配规则，所有展示与输入入口立即使用相同版本。
    _emojis = Map.unmodifiable(items);
    _assetPackage = assetPackage;
    _tokenPattern = RegExp(
        items.isEmpty ? r'(?!)' : items.keys.map(RegExp.escape).join('|'));
  }

  /// 从当前目录精确查找令牌，未知内容不替换成其他表情。
  static EmojiPickerModelItem? getEmoji(String code) => _emojis[code];

  /// 会话行沿用名称映射入口，内容仅由当前业务目录生成。
  static Map<String, String> getEmojiMap(BuildContext context) => {
        for (final emoji in emojis) emoji.name: '[${emoji.label}]',
      };

  /// 将已知令牌显示为业务资源；保留未知编码和相邻原文。
  static List<InlineSpan> buildInlineSpans(String text, {double size = 18}) {
    final spans = <InlineSpan>[];
    var offset = 0;
    // 仅把已知令牌替换为图片，令牌之间的文字及旧编码均按原文保留。
    for (final match in tokenPattern.allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      final emoji = getEmoji(match.group(0)!)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Image.asset(emoji.path,
            package: assetPackage,
            width: size,
            height: size,
            semanticLabel: emoji.label),
      ));
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return spans;
  }

  /// 为纯文字摘要把已知令牌转换为带方括号的展示名称，未知编码保留原文。
  static String createLocalizedStringFromEmojiCodes(
      BuildContext context, String text) {
    return text.replaceAllMapped(
        tokenPattern, (match) => '[${getEmoji(match.group(0)!)!.label}]');
  }

  /// 提取已注册业务令牌及系统Unicode表情，供翻译分段保留原始表情内容。
  static List<String> findEmojiKeyListFromText(String text) => [
        ...tokenPattern.allMatches(text).map((match) => match.group(0)!),
        ...getUniversalEmojiRegex()
            .allMatches(text)
            .map((match) => match.group(0)!),
      ];

  static String getRegexOfUniversalEmoji() {
    // Note: Dart uses \u{XXXX} syntax for Unicode code points, not \UXXXXXXXX like Java.
    // For code points > 0xFFFF, use \u{1XXXX} format.
    //
    // 注意：Dart使用u{XXXX}语法表示Unicode码点，而不是像Java的UXXXXXXXX
    String ri = "[\\u{1F1E6}-\\u{1F1FF}]";

    // Standard emoji that can stand alone or with modifiers
    //
    // 标准表情符号，可以单独使用或搭配修饰符
    String support =
        "\\u{A9}|\\u{AE}|\\u203C|\\u2049|\\u2122|\\u2139|[\\u2194-\\u2199]|[\\u21A9-\\u21AA]"
        "|[\\u231A-\\u231B]|\\u2328|\\u23CF|[\\u23E9-\\u23EF]|[\\u23F0-\\u23F3]|[\\u23F8-\\u23FA]|\\u24C2"
        "|[\\u25AA-\\u25AB]|\\u25B6|\\u25C0|[\\u25FB-\\u25FE]|[\\u2600-\\u2604]|\\u260E|\\u2611|[\\u2614-\\u2615]"
        "|\\u2618|\\u261D|\\u2620|[\\u2622-\\u2623]|\\u2626|\\u262A|[\\u262E-\\u262F]|[\\u2638-\\u263A]|\\u2640"
        "|\\u2642|[\\u2648-\\u264F]|[\\u2650-\\u2653]|\\u265F|\\u2660|\\u2663|[\\u2665-\\u2666]|\\u2668|\\u267B"
        "|[\\u267E-\\u267F]|[\\u2692-\\u2697]|\\u2699|[\\u269B-\\u269C]|[\\u26A0-\\u26A1]|\\u26A7|[\\u26AA-\\u26AB]"
        "|[\\u26B0-\\u26B1]|[\\u26BD-\\u26BE]|[\\u26C4-\\u26C5]|\\u26C8|[\\u26CE-\\u26CF]|\\u26D1|[\\u26D3-\\u26D4]"
        "|[\\u26E9-\\u26EA]|[\\u26F0-\\u26F5]|[\\u26F7-\\u26FA]|\\u26FD|\\u2702|\\u2705|[\\u2708-\\u270D]|\\u270F|\\u2712"
        "|\\u2714|\\u2716|\\u271D|\\u2721|\\u2728|[\\u2733-\\u2734]|\\u2744|\\u2747|\\u274C|\\u274E|[\\u2753-\\u2755]"
        "|\\u2757|[\\u2763-\\u2764]|[\\u2795-\\u2797]|\\u27A1|\\u27B0|\\u27BF|[\\u2934-\\u2935]|[\\u2B05-\\u2B07]"
        "|[\\u2B1B-\\u2B1C]|\\u2B50|\\u2B55|\\u3030|\\u303D|\\u3297|\\u3299|\\u{1F004}|\\u{1F0CF}|[\\u{1F170}-\\u{1F171}]"
        "|[\\u{1F17E}-\\u{1F17F}]|\\u{1F18E}|[\\u{1F191}-\\u{1F19A}]|[\\u{1F1E6}-\\u{1F1FF}]|[\\u{1F201}-\\u{1F202}]"
        "|\\u{1F21A}|\\u{1F22F}|[\\u{1F232}-\\u{1F23A}]|[\\u{1F250}-\\u{1F251}]|[\\u{1F300}-\\u{1F30F}]"
        "|[\\u{1F310}-\\u{1F31F}]|[\\u{1F320}-\\u{1F321}]|[\\u{1F324}-\\u{1F32F}]|[\\u{1F330}-\\u{1F33F}]"
        "|[\\u{1F340}-\\u{1F34F}]|[\\u{1F350}-\\u{1F35F}]|[\\u{1F360}-\\u{1F36F}]|[\\u{1F370}-\\u{1F37F}]"
        "|[\\u{1F380}-\\u{1F38F}]|[\\u{1F390}-\\u{1F393}]|[\\u{1F396}-\\u{1F397}]|[\\u{1F399}-\\u{1F39B}]"
        "|[\\u{1F39E}-\\u{1F39F}]|[\\u{1F3A0}-\\u{1F3AF}]|[\\u{1F3B0}-\\u{1F3BF}]|[\\u{1F3C0}-\\u{1F3CF}]"
        "|[\\u{1F3D0}-\\u{1F3DF}]|[\\u{1F3E0}-\\u{1F3EF}]|\\u{1F3F0}|[\\u{1F3F3}-\\u{1F3F5}]|[\\u{1F3F7}-\\u{1F3FF}]"
        "|[\\u{1F400}-\\u{1F40F}]|[\\u{1F410}-\\u{1F41F}]|[\\u{1F420}-\\u{1F42F}]|[\\u{1F430}-\\u{1F43F}]"
        "|[\\u{1F440}-\\u{1F44F}]|[\\u{1F450}-\\u{1F45F}]|[\\u{1F460}-\\u{1F46F}]|[\\u{1F470}-\\u{1F47F}]"
        "|[\\u{1F480}-\\u{1F48F}]|[\\u{1F490}-\\u{1F49F}]|[\\u{1F4A0}-\\u{1F4AF}]|[\\u{1F4B0}-\\u{1F4BF}]"
        "|[\\u{1F4C0}-\\u{1F4CF}]|[\\u{1F4D0}-\\u{1F4DF}]|[\\u{1F4E0}-\\u{1F4EF}]|[\\u{1F4F0}-\\u{1F4FF}]"
        "|[\\u{1F500}-\\u{1F50F}]|[\\u{1F510}-\\u{1F51F}]|[\\u{1F520}-\\u{1F52F}]|[\\u{1F530}-\\u{1F53D}]"
        "|[\\u{1F549}-\\u{1F54E}]|[\\u{1F550}-\\u{1F55F}]|[\\u{1F560}-\\u{1F567}]|\\u{1F56F}|\\u{1F570}"
        "|[\\u{1F573}-\\u{1F57A}]|\\u{1F587}|[\\u{1F58A}-\\u{1F58D}]|\\u{1F590}|[\\u{1F595}-\\u{1F596}]"
        "|[\\u{1F5A4}-\\u{1F5A5}]|\\u{1F5A8}|[\\u{1F5B1}-\\u{1F5B2}]|\\u{1F5BC}|[\\u{1F5C2}-\\u{1F5C4}]"
        "|[\\u{1F5D1}-\\u{1F5D3}]|[\\u{1F5DC}-\\u{1F5DE}]|\\u{1F5E1}|\\u{1F5E3}|\\u{1F5E8}|\\u{1F5EF}|\\u{1F5F3}"
        "|[\\u{1F5FA}-\\u{1F5FF}]|[\\u{1F600}-\\u{1F60F}]|[\\u{1F610}-\\u{1F61F}]|[\\u{1F620}-\\u{1F62F}]"
        "|[\\u{1F630}-\\u{1F63F}]|[\\u{1F640}-\\u{1F64F}]|[\\u{1F650}-\\u{1F65F}]|[\\u{1F660}-\\u{1F66F}]"
        "|[\\u{1F670}-\\u{1F67F}]|[\\u{1F680}-\\u{1F68F}]|[\\u{1F690}-\\u{1F69F}]|[\\u{1F6A0}-\\u{1F6AF}]"
        "|[\\u{1F6B0}-\\u{1F6BF}]|[\\u{1F6C0}-\\u{1F6C5}]|[\\u{1F6CB}-\\u{1F6CF}]|[\\u{1F6D0}-\\u{1F6D2}]"
        "|[\\u{1F6D5}-\\u{1F6D7}]|[\\u{1F6DD}-\\u{1F6DF}]|[\\u{1F6E0}-\\u{1F6E5}]|\\u{1F6E9}|[\\u{1F6EB}-\\u{1F6EC}]"
        "|\\u{1F6F0}|[\\u{1F6F3}-\\u{1F6FC}]|[\\u{1F7E0}-\\u{1F7EB}]|\\u{1F7F0}|[\\u{1F90C}-\\u{1F90F}]"
        "|[\\u{1F910}-\\u{1F91F}]|[\\u{1F920}-\\u{1F92F}]|[\\u{1F930}-\\u{1F93A}]|[\\u{1F93C}-\\u{1F93F}]"
        "|[\\u{1F940}-\\u{1F945}]|[\\u{1F947}-\\u{1F94C}]|[\\u{1F94D}-\\u{1F94F}]|[\\u{1F950}-\\u{1F95F}]"
        "|[\\u{1F960}-\\u{1F96F}]|[\\u{1F970}-\\u{1F97F}]|[\\u{1F980}-\\u{1F98F}]|[\\u{1F990}-\\u{1F99F}]"
        "|[\\u{1F9A0}-\\u{1F9AF}]|[\\u{1F9B0}-\\u{1F9BF}]|[\\u{1F9C0}-\\u{1F9CF}]|[\\u{1F9D0}-\\u{1F9DF}]"
        "|[\\u{1F9E0}-\\u{1F9EF}]|[\\u{1F9F0}-\\u{1F9FF}]|[\\u{1FA70}-\\u{1FA74}]|[\\u{1FA78}-\\u{1FA7C}]"
        "|[\\u{1FA80}-\\u{1FA86}]|[\\u{1FA90}-\\u{1FA9F}]|[\\u{1FAA0}-\\u{1FAAC}]|[\\u{1FAB0}-\\u{1FABA}]"
        "|[\\u{1FAC0}-\\u{1FAC5}]|[\\u{1FAD0}-\\u{1FAD9}]|[\\u{1FAE0}-\\u{1FAE7}]|[\\u{1FAF0}-\\u{1FAF6}]";

    // Keycap base characters: #, *, 0-9
    // These ONLY form emoji when followed by \uFE0F\u20E3 (variation selector + keycap combining mark)
    // e.g., #️⃣ = # + \uFE0F + \u20E3
    //
    // 按键基字符：#、*、0-9 仅在后跟️⃣（变体选择符 + 按键组合标记）时才形成表情符号
    String keycapBase = "[\\u0023\\u002A\\u0030-\\u0039]";

    // Construct regex of emoji by the rules above.
    //
    // 根据上述规则构建表情符号的正则表达式
    String eMod = "[\\u{1F3FB}-\\u{1F3FF}]";

    String variationSelector = "\\uFE0F";
    String keycap = "\\u20E3";
    String tags = "[\\u{E0020}-\\u{E007E}]";
    String termTag = "\\u{E007F}";
    String zwj = "\\u200D";

    String risequence = "$ri$ri";

    // Keycap emoji: base character + optional variation selector + keycap combining mark
    //
    // 按键表情符号：基字符 + 可选变体选择符 + 按键组合标记
    String keycapEmoji = "$keycapBase$variationSelector?$keycap";

    // Standard emoji element with optional modifiers
    //
    // 带可选修饰符的标准表情符号元素
    String element =
        "(?:$support)(?:$eMod|$variationSelector|$tags+$termTag?)?";

    // Full regex: keycap emoji | RI sequence | standard emoji (with ZWJ sequences)
    //
    // 完整正则表达式：按键表情符号 | RI 序列 | 标准表情符号（带 ZWJ 序列）
    String regexEmoji =
        "$keycapEmoji|$risequence|$element(?:$zwj(?:$risequence|$element))*";

    return regexEmoji;
  }

  /// 缓存固定的Unicode表情规则，与业务目录的可变令牌规则分开维护。
  static RegExp? _universalEmojiRegex;

  static RegExp getUniversalEmojiRegex() {
    _universalEmojiRegex ??= RegExp(getRegexOfUniversalEmoji(), unicode: true);
    return _universalEmojiRegex!;
  }
}
