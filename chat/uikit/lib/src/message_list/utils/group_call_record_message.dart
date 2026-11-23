import 'package:app_api/app_api_models.dart';
import 'package:app_core/app_core.dart' show formatCallDuration;
import 'package:atomic_x_core/atomicxcore.dart';

/// 校验个人通话结果的发送身份和会话范围，并合并同场各端报告。
abstract final class GroupCallRecordMessage {
  /// 畸形的已知协议也不回退为普通自定义消息，避免暴露原始参与者载荷。
  static bool isMessage(MessageInfo message) {
    final payload = message.messagePayload;
    return payload is CustomMessagePayload &&
        GroupCallRecordData.isRecord(payload.customData);
  }

  /// 校验发起气泡的真实发件人及受邀范围，支持群聊和独立多人单聊。
  static GroupCallStartData? startFromMessage(MessageInfo message, String viewerId) {
    final payload = message.messagePayload;
    final group = message.conversationType == ConversationType.group;
    if (payload is! CustomMessagePayload ||
        message.status == MessageStatus.deleted ||
        message.status == MessageStatus.revoked ||
        message.status == MessageStatus.violation ||
        (!group && message.conversationType != ConversationType.c2c)) {
      return null;
    }
    final start = GroupCallStartData.parse(payload.customData,
        senderId: message.from.userID, groupId: group ? message.to : '');
    if (start == null ||
        (group && start.groupId.isEmpty) ||
        (viewerId != start.callerId && !start.inviteeIds.contains(viewerId))) {
      return null;
    }
    return group || message.to == start.callerId ||
            message.to == start.inviteeIds.single
        ? start
        : null;
  }

  /// 只允许受邀本人查看所属群或主叫与被叫之间的消息，不从载荷授予会控权限。
  static GroupCallRecordData? fromMessage(
      MessageInfo message, String viewerId) {
    final payload = message.messagePayload;
    if (payload is! CustomMessagePayload ||
        viewerId.isEmpty ||
        message.status == MessageStatus.deleted ||
        message.status == MessageStatus.revoked ||
        message.status == MessageStatus.violation) {
      return null;
    }
    final record = GroupCallRecordData.parse(payload.customData,
        senderId: message.from.userID);
    if (record == null || !record.participantIds.contains(viewerId)) {
      return null;
    }
    if (record.groupId.isNotEmpty) {
      // 群里其他成员的个人离开不代表本人结束；只接受本人报告或主叫的目标结果。
      if (record.reporterId != viewerId &&
          (record.reporterId != record.callerId ||
              !record.outcomesByUserId.containsKey(viewerId))) {
        return null;
      }
      return message.conversationType == ConversationType.group &&
              message.to == record.groupId
          ? record
          : null;
    }
    final pair = {record.callerId, record.calleeId};
    return message.conversationType == ConversationType.c2c &&
            pair.contains(viewerId) &&
            pair.contains(message.to)
        ? record
        : null;
  }

  /// 保留独立的发起气泡，同场个人结果只展示优先级最高的一条。
  static List<MessageInfo> visibleMessages(
      Iterable<MessageInfo> messages, String viewerId) {
    final visible = <MessageInfo>[];
    final removed = <int>{};
    final selected = <String, ({int index, GroupCallRecordData record})>{};
    for (final message in messages) {
      if (!isMessage(message)) {
        visible.add(message);
        continue;
      }
      final record = fromMessage(message, viewerId);
      if (record == null) continue;
      final key = record.conversationRecordKey;
      final old = selected[key];
      if (old == null) {
        selected[key] = (index: visible.length, record: record);
        visible.add(message);
      } else if (_prefer(record, old.record, viewerId)) {
        // 更新后的记录保留自己的真实时间位置，不能移动到旧报告所在的日期分组。
        removed.add(old.index);
        selected[key] = (index: visible.length, record: record);
        visible.add(message);
      }
    }
    return [
      for (final (index, message) in visible.indexed)
        if (!removed.contains(index)) message
    ];
  }

  static bool _prefer(
      GroupCallRecordData next, GroupCallRecordData old, String viewerId) {
    final own = next.reporterId == viewerId;
    final previousOwn = old.reporterId == viewerId;
    if (own != previousOwn) return own;
    // 另一台设备的真实个人结果优先于本机的接听提示，即使 IM 送达顺序颠倒。
    final elsewhere = next.outcome == GroupCallRecordOutcome.otherDeviceAccepted;
    final wasElsewhere = old.outcome == GroupCallRecordOutcome.otherDeviceAccepted;
    if (elsewhere != wasElsewhere) return !elsewhere;
    if (next.reporterId == old.reporterId && next.revision != old.revision) {
      return next.revision > old.revision;
    }
    return next.endedAtMs > old.endedAtMs;
  }

  /// 对端报告只提供结果，不把对方的累计时长显示成本人的通话时长。
  static String content(GroupCallRecordData record, String viewerId) {
    final caller = record.callerId == viewerId;
    final own = record.reporterId == viewerId;
    final group = record.groupId.isNotEmpty;
    final outcome = group && !own
        ? record.outcomesByUserId[viewerId] ?? record.outcome
        : record.outcome;
    final time = formatCallDuration(record.durationSeconds);
    return switch (outcome) {
      GroupCallRecordOutcome.cancelled => caller ? '已取消' : '对方已取消',
      GroupCallRecordOutcome.unanswered => caller ? '无人接听' : '未接听',
      GroupCallRecordOutcome.rejected => caller ? '对方已拒接' : '已拒绝',
      GroupCallRecordOutcome.otherDeviceAccepted =>
        caller ? '已接听' : '已在其它设备接听',
      GroupCallRecordOutcome.busy => caller && !group ? '对方忙线' : '忙线未接听',
      GroupCallRecordOutcome.completed => own
          ? '通话时长 $time'
          : group
              ? '发起人已结束通话'
              : '对方已结束通话',
      GroupCallRecordOutcome.interrupted => own
          ? '通话中断 $time'
          : (group && record.outcome != GroupCallRecordOutcome.interrupted
                  ? '通话状态未确认'
                  : group
                      ? '发起人通话中断'
                      : '对方通话中断'),
    };
  }
}
