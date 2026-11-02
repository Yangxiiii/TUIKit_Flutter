import 'package:atomic_x_core/atomicxcore.dart';

/// 在首次云端同步期间补齐本机窗口；SDK 接管同 ID 后即释放副本，删除不得复活。
class LocalMessageWindow {
  /// 仅保留 SDK 尚未交付的本地消息，不保存退出位置或独立分页游标。
  final Map<String, MessageInfo> _pending = {};

  /// 本地读取期间可能已收到删除事件，迟到的本地结果不能重新插入这些消息。
  final Set<String> _deleted = {};

  /// 撤回事件可能早于本地查询结束，状态只能从普通消息进入撤回态。
  final Set<String> _revoked = {};

  /// 安装本地首屏；已记录的删除、撤回与更新结果优先于迟到候选。
  void seed(List<MessageInfo> messages) {
    for (final message in messages) {
      if (!_deleted.contains(message.msgID)) {
        if (_revoked.contains(message.msgID)) {
          message.status = MessageStatus.revoked;
        }
        _pending.putIfAbsent(message.msgID, () => message);
      }
    }
  }

  /// SDK 结果优先并按 ID 去重；未出现在窗口中不等于已删除。
  List<MessageInfo> merge(Iterable<MessageInfo> newestFirst) {
    final byId = <String, MessageInfo>{};
    for (final message in newestFirst) {
      _pending.remove(message.msgID);
      if (!_deleted.contains(message.msgID)) {
        if (_revoked.contains(message.msgID)) {
          message.status = MessageStatus.revoked;
        }
        byId.putIfAbsent(message.msgID, () => message);
      }
    }
    byId.addAll(_pending);
    return byId.values.toList()
      ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
  }

  /// 显式删除作为墓碑，避免云端或本地迟到结果使旧消息复活。
  void delete(Iterable<String> ids) {
    _deleted.addAll(ids);
    for (final id in ids) {
      _pending.remove(id);
    }
  }

  /// 本地候选尚未进入 SDK 窗口时，也必须响应撤回或正文修改。
  void update(MessageInfo message) {
    if (!_deleted.contains(message.msgID)) _pending[message.msgID] = message;
  }

  /// 保留明确撤回事件，迟到的本地或云端普通状态不能覆盖它。
  void revoke(String id) {
    _revoked.add(id);
    _pending[id]?.status = MessageStatus.revoked;
  }

  /// 显式跳转到历史位置后，最新本地窗口不能混入新的定位结果。
  void clear() => _pending.clear();
}
