import 'package:flutter/widgets.dart';

import 'mention_info.dart';

/// 管理编辑区内通过选人插入的提及及其 UTF-16 范围。
class MentionTextEditingController extends TextEditingController {
  /// 每个选人结果保留独立范围，相同成员可出现多次。
  final List<MentionInfo> _mentions = [];

  /// 程序已同步更新范围时跳过自动偏移计算。
  bool isInternalUpdate = false;

  /// 返回当前编辑区内绑定身份的提及，发送前仍须校验正文。
  List<MentionInfo> get mentionList => List.unmodifiable(_mentions);

  /// 提及的原文起止偏移，用于格式改写时保持成员名为完整范围。
  Map<int, int> get mentionEnds => {
        for (final mention in _mentions) mention.startIndex: mention.endIndex,
      };

  /// 格式改写只移动提及位置，保留已选成员，跳过普通增删逻辑。
  void applySelectionFormat(TextEditingValue value, Map<int, int> offsets) {
    for (final mention in _mentions) {
      mention.startIndex = offsets[mention.startIndex] ?? mention.startIndex;
    }
    super.value = value;
  }

  /// 按原文顺序登记已选成员，便于编辑和发送校验。
  void addMention(MentionInfo mention) {
    _mentions.add(mention);
    _mentions.sort((a, b) => a.startIndex.compareTo(b.startIndex));
  }

  /// 原子删除提及后移动其后方的范围。
  void removeMention(MentionInfo mention) {
    _mentions.remove(mention);
    // 移除某个提及后更新其他提及的位置
    final removedLength = mention.length;
    for (final m in _mentions) {
      if (m.startIndex > mention.startIndex) {
        m.startIndex -= removedLength;
      }
    }
  }

  /// 草稿清空时同时释放全部提及身份。
  void clearMentions() {
    _mentions.clear();
  }

  /// 取出完整落在当前发送文字块中的身份，并转成块内坐标。
  List<MentionInfo> mentionsIn(int start, int end) => [
        for (final m in _mentions)
          if (m.startIndex >= start && m.endIndex - 1 <= end && m.matches(text))
            m.copyWith(startIndex: m.startIndex - start),
      ];

  /// 使用已确认的选人结果原子替换选区，坐标随结果顺序计算。
  void insertMentions(TextSelection selection, List<MentionInfo> members) {
    var offset = 0;
    final text = StringBuffer();
    final positioned = <MentionInfo>[];
    for (final member in members) {
      positioned.add(member.copyWith(startIndex: offset));
      text.write(member.mentionText);
      offset += member.length;
    }
    insertClipboardText(selection, text.toString(), positioned);
  }

  /// 用同一次替换更新提及坐标，覆盖选区中的旧提及不随新正文发送。
  void insertClipboardText(
      TextSelection selection, String insertion, List<MentionInfo> mentions) {
    final delta = insertion.length - (selection.end - selection.start);
    _mentions.removeWhere((mention) =>
        mention.startIndex < selection.end &&
        mention.endIndex > selection.start);
    for (final mention in _mentions) {
      if (mention.startIndex >= selection.end) mention.startIndex += delta;
    }
    for (final mention in mentions) {
      addMention(
          mention.copyWith(startIndex: selection.start + mention.startIndex));
    }
    // 直接提交已校正的值，避免原有单字符监听再次移动提及坐标。
    super.value = TextEditingValue(
      text: text.replaceRange(selection.start, selection.end, insertion),
      selection:
          TextSelection.collapsed(offset: selection.start + insertion.length),
    );
  }

  /// 获取在指定位置结束的提及
  MentionInfo? getMentionEndingAt(int position) {
    for (final mention in _mentions) {
      if (mention.endIndex == position) {
        return mention;
      }
    }
    return null;
  }

  /// 获取包含给定位置的提及（不包括边界）
  MentionInfo? getMentionContaining(int position) {
    for (final mention in _mentions) {
      if (position > mention.startIndex && position < mention.endIndex) {
        return mention;
      }
    }
    return null;
  }

  /// 获取位置处于或包含在内的提及（用于删除检测）
  MentionInfo? getMentionAt(int position) {
    for (final mention in _mentions) {
      if (position > mention.startIndex && position <= mention.endIndex) {
        return mention;
      }
    }
    return null;
  }

  /// 获取提及的锚点位置（跳到最近的边界）
  int getAnchorPosition(MentionInfo mention, int position) {
    final distanceToStart = position - mention.startIndex;
    final distanceToEnd = mention.endIndex - position;
    return distanceToStart <= distanceToEnd
        ? mention.startIndex
        : mention.endIndex;
  }

  @override
  set value(TextEditingValue newValue) {
    final oldText = text;
    final nextText = newValue.text;
    if (isInternalUpdate || oldText == nextText || _mentions.isEmpty) {
      super.value = newValue;
      return;
    }
    var start = 0;
    var oldEnd = oldText.length;
    var newEnd = nextText.length;
    final oldSelection = selection;
    // 优先用实际选区识别同名或重复文字中的替换位置，余下情况用前后缀求差。
    if (oldSelection.isValid &&
        !oldSelection.isCollapsed &&
        nextText.startsWith(oldText.substring(0, oldSelection.start)) &&
        nextText.endsWith(oldText.substring(oldSelection.end)) &&
        nextText.length >=
            oldText.length - (oldSelection.end - oldSelection.start)) {
      start = oldSelection.start;
      oldEnd = oldSelection.end;
      newEnd = nextText.length - (oldText.length - oldEnd);
    } else {
      while (start < oldEnd &&
          start < newEnd &&
          oldText.codeUnitAt(start) == nextText.codeUnitAt(start)) {
        start++;
      }
      while (oldEnd > start &&
          newEnd > start &&
          oldText.codeUnitAt(oldEnd - 1) == nextText.codeUnitAt(newEnd - 1)) {
        oldEnd--;
        newEnd--;
      }
    }

    // 删除碰到提及时扩展为整个令牌，普通替换只撤销被覆盖的身份。
    if (newEnd == start) {
      var from = start;
      var to = oldEnd;
      for (final mention in _mentions) {
        if (mention.startIndex < oldEnd && mention.endIndex > start) {
          if (mention.startIndex < from) from = mention.startIndex;
          if (mention.endIndex > to && mention.endIndex <= oldText.length) {
            to = mention.endIndex;
          }
        }
      }
      if (from != start || to != oldEnd) {
        insertClipboardText(
            TextSelection(baseOffset: from, extentOffset: to), '', const []);
        return;
      }
    }
    _mentions.removeWhere((m) => m.startIndex < oldEnd && m.endIndex > start);
    for (final mention in _mentions) {
      if (mention.startIndex >= oldEnd) {
        mention.startIndex += nextText.length - oldText.length;
      }
    }
    super.value = newValue;
  }
}
