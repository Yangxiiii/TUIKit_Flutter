import 'package:atomic_x_core/atomicxcore.dart';

/// 补齐本机首屏，并保留已确认的撤回与删除事实，防止迟到窗口恢复旧正文。
class LocalMessageWindow {
  /// 仅保留 SDK 尚未交付的本地消息，不保存退出位置或独立分页游标。
  final Map<String, MessageInfo> _pending = {};

  /// 本地读取期间可能已收到删除事件，迟到的本地结果不能重新插入这些消息。
  final Set<String> _deleted = {};

  /// 当前会话已确认撤回的ID，刷新时保留，重进时从退出快照恢复。
  final Set<String> _revoked = {};

  /// 即使源消息不在当前页，已收到的撤回事实仍用于隐藏 Web 引用摘要。
  bool isRevoked(String id) => _revoked.contains(id);

  /// 安装本地首屏；已记录的删除、撤回与更新结果优先于迟到候选。
  void seed(List<MessageInfo> messages) {
    reconcileRevocations(messages);
    for (final message in messages) {
      if (!_deleted.contains(message.msgID)) {
        _pending.putIfAbsent(message.msgID, () => message);
      }
    }
  }

  /// SDK 结果优先并按 ID 去重；未出现在窗口中不等于已删除。
  List<MessageInfo> merge(Iterable<MessageInfo> newestFirst) {
    final latest = newestFirst.toList();
    reconcileRevocations(latest);
    final byId = <String, MessageInfo>{};
    for (final message in latest) {
      _pending.remove(message.msgID);
      if (!_deleted.contains(message.msgID)) {
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
    reconcileRevocations([message]);
    if (!_deleted.contains(message.msgID)) _pending[message.msgID] = message;
  }

  /// 本机成功状态、远端事件及离开前快照均可确认撤回，后续普通状态不能降级它。
  void reconcileRevocations(List<MessageInfo> messages) {
    // 先收集整批事实，避免同ID的旧副本排在撤回结果前面时恢复正文。
    for (final message in messages) {
      if (message.status == MessageStatus.revoked) revoke(message.msgID);
    }
    for (final message in messages) {
      if (_revoked.contains(message.msgID) &&
          message.status != MessageStatus.deleted) {
        message.status = MessageStatus.revoked;
      }
    }
  }

  /// 保留明确撤回事件，迟到的本地或云端普通状态不能覆盖它。
  void revoke(String id) {
    if (id.isEmpty) return;
    _revoked.add(id);
    final pending = _pending[id];
    if (pending != null && pending.status != MessageStatus.deleted) {
      pending.status = MessageStatus.revoked;
    }
  }

  /// 显式跳转到历史位置后，最新本地窗口不能混入新的定位结果。
  void clear() => _pending.clear();
}
