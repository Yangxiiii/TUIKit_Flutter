import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_at_info.dart';

import '../../message_list/message_reply_config.dart';
import 'mention_info.dart';

/// 管理消息云端提及协议及最终正文的 UTF-16 定位校验。
abstract final class MessageMentions {
  /// 云端扩展中的提及字段，回复和其他扩展与其并存。
  static const key = 'messageMentions';

  /// 为当前文字块生成定位，避免无效范围被转成真实提醒。
  static List<Map<String, Object>> encode(
      String text, Iterable<MentionInfo> mentions, int blockIndex) {
    var end = 0;
    final items = <Map<String, Object>>[];
    // 只有完整范围才产生定位，尾随空格不进入传输协议。
    for (final mention in mentions) {
      if (mention.startIndex < end || !mention.matches(text)) continue;
      end = mention.endIndex - 1;
      items.add({
        'kind': mention.isAtAll ? 'all' : 'user',
        if (!mention.isAtAll) 'userID': mention.userID,
        'displayName': mention.displayName,
        'blockIndex': blockIndex,
        'start': mention.startIndex,
        'length': end - mention.startIndex,
      });
    }
    return items;
  }

  /// SDK 的提醒名单按首次出现去重，含全体时使用本端 SDK 的全体常量。
  static List<String> targets(List<Map<String, Object>> items) =>
      items.any((item) => item['kind'] == 'all')
          ? [V2TimGroupAtInfo.AT_ALL_TAG]
          : items.map((item) => item['userID'] as String).toSet().toList();

  /// 读取指定块内合法且不重叠的定位。无协议的历史文本保持原样。
  static List<MentionInfo> read(MessageInfo message, String text, int block) {
    final raw = ChatMessageReplyConfig.cloudDataOf(message);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final root = jsonDecode(raw);
      final envelope = root is Map ? root[key] : null;
      final items = envelope is Map && envelope['version'] == 1
          ? envelope['items']
          : null;
      return decodeItems(items, text, block);
    } on FormatException {
      return const [];
    }
  }

  /// 从已解析对象恢复一个文字块内的提及，草稿和消息使用同一校验。
  static List<MentionInfo> decodeItems(Object? items, String text, int block) {
    if (items is! List) return const [];
    final result = <MentionInfo>[];
    // 传输整数或整数文本都在校验后使用，名称相同也按原始区间区分。
    for (final item in items) {
      if (item is! Map || _integer(item['blockIndex']) != block) continue;
      final start = _integer(item['start']);
      final name = item['displayName'];
      final id = switch (item['kind']) {
        'all' when item['userID'] == null || item['userID'] == '' =>
          MentionInfo.atAllUserID,
        'user' when item['userID'] != MentionInfo.atAllUserID => item['userID'],
        _ => null,
      };
      if (start == null || name is! String || id is! String) continue;
      final mention =
          MentionInfo(userID: id, displayName: name, startIndex: start);
      if (_integer(item['length']) != mention.length - 1 ||
          !mention.matches(text)) {
        continue;
      }
      result.add(mention);
    }
    result.sort((a, b) => a.startIndex.compareTo(b.startIndex));
    // 重叠意味着无法可靠识别点击对象，整块回退到普通正文。
    for (var i = 1; i < result.length; i++) {
      if (result[i].startIndex < result[i - 1].endIndex - 1) return const [];
    }
    return result;
  }

  static int? _integer(Object? value) => switch (value) {
        int integer => integer,
        String text => int.tryParse(text),
        _ => null,
      };
}
