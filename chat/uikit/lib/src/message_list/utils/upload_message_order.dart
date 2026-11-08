import 'package:atomic_x_core/atomicxcore.dart';

import 'big_file_message.dart';

/// 保留当前消息窗口内的上传气泡位置，让 SDK 正式消息在原位接管。
final class UploadMessageOrder {
  /// 本地占位的原始时间，以及直传交接后唯一绑定的 SDK 消息 ID。
  final _slots = <String, ({int timestamp, String? sdkId})>{};

  /// 正式消息更新或撤回后，即使不再携带扩展字段也能找到原占位。
  final _sdkToSlot = <String, String>{};

  /// 上一次展示顺序，用于找到同秒消息和上传气泡原来的相邻位置。
  List<String> _previousKeys = const [];

  /// 时间分组使用占位时刻，定位和分页仍使用原始 SDK 消息时间。
  int? displayTimestamp(MessageInfo message) =>
      _slots[_sdkToSlot[message.msgID] ?? message.msgID]?.timestamp ??
      message.timestamp;

  /// 输入按最新到最旧排列，正式消息与占位同时出现时只保留正式消息。
  List<MessageInfo> apply(List<MessageInfo> newestFirst) {
    // 先登记窗口内的占位，正式消息可能已被 SDK 追加到占位之前。
    for (final message in newestFirst) {
      if (message.isSentBySelf &&
          (message.msgID.startsWith('oa_upload_') ||
              message.msgID.startsWith('album_'))) {
        _slots.putIfAbsent(message.msgID,
            () => (timestamp: message.timestamp ?? 0, sdkId: null));
      }
    }
    if (_slots.isEmpty) return newestFirst;

    // 直传消息的扩展字段携带原占位 ID；绑定一次，避免后续转发被当成同一条消息。
    final byKey = <String, MessageInfo>{};
    for (final message in newestFirst) {
      final boundSlot = _sdkToSlot[message.msgID];
      if (boundSlot != null) {
        byKey[boundSlot] = message;
        continue;
      }
      final payload = message.messagePayload;
      final uploadId = payload is CustomMessagePayload && message.isSentBySelf
          ? payload.extensionInfo
          : null;
      final slot = _slots[uploadId];
      if (uploadId != null &&
          slot != null &&
          slot.sdkId == null &&
          payload is CustomMessagePayload &&
          BigFileMessage.tryParse(payload.customData) != null) {
        _slots[uploadId] = (timestamp: slot.timestamp, sdkId: message.msgID);
        _sdkToSlot[message.msgID] = uploadId;
        byKey[uploadId] = message;
      } else if (_slots[message.msgID]?.sdkId == null) {
        // 已交接的旧占位即使迟到，也不能在正式消息删除后重新出现。
        byKey.putIfAbsent(message.msgID, () => message);
      }
    }

    // 普通消息仍按 SDK 顺序；已显示过的上传气泡回到原来的较旧邻居之前。
    final previousUploads = _previousKeys.where(_slots.containsKey).toSet();
    final remaining =
        byKey.keys.where((key) => !previousUploads.contains(key)).toList();
    final before = <String?, List<String>>{};
    String? olderKey;
    for (final key in _previousKeys.reversed) {
      if (!byKey.containsKey(key)) continue;
      final slot = _slots[key];
      if (slot == null) {
        olderKey = key;
        continue;
      }
      // 邻居不在窗口内时，用原占位时间避开刚加载的更旧历史。
      final anchor = olderKey ??
          remaining.where((key) {
            final timestamp = byKey[key]!.timestamp;
            return timestamp != null && timestamp < slot.timestamp;
          }).firstOrNull;
      before.putIfAbsent(anchor, () => []).add(key);
    }
    _previousKeys = [
      for (final key in remaining) ...[...?before[key]?.reversed, key],
      ...?before[null]?.reversed,
    ];
    // 删除或离开窗口后丢弃位置记录，不能用旧占位复活已消失的消息。
    _slots.removeWhere((key, _) =>
        !byKey.containsKey(key) &&
        !newestFirst.any((message) => message.msgID == key));
    _sdkToSlot.removeWhere((_, key) => !_slots.containsKey(key));
    return [for (final key in _previousKeys) byKey[key]!];
  }
}
