import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';

/// 校验后端系统提示，聊天正文和会话摘要按当前用户生成同一份纯文本。
final class ConversationNotice {
  const ConversationNotice._(
      this.eventId, this.type, this.occurredAt, this._data);

  /// 后端重试沿用同一个事件标识，按会话去重。
  final String eventId;

  /// 已验证的事件类型，用于选择后端通知文案。
  final String type;

  /// 后端给出的可信事件时间，保留精度以免按接收时间误合并。
  final DateTime occurredAt;

  /// 撤回由原消息状态展示，独立的协议记录不进入会话正文或摘要。
  bool get usesOriginalMessage => type == 'message.recalled';

  /// 已按事件类型校验的载荷，姓名使用发送时的快照。
  final Map<String, dynamic> _data;

  /// 自定义元素中标识 OA 系统提示的业务字段值。
  static const businessId = 'oa_system_notice';

  /// 这些原生提示已有后端通知，混合消息仍保留未迁移的部分。
  static bool isBackendOwnedTip(GroupTipsInfo tip) =>
      tip is InviteToGroup ||
      tip is JoinGroup ||
      tip is QuitGroup ||
      tip is KickedFromGroup ||
      tip is ChangeGroupIntroduction ||
      tip is PinGroupMessage ||
      tip is UnpinGroupMessage;

  /// 只含已迁移提示的消息不占聊天行或覆盖会话摘要。
  static bool hidesNativeMessage(MessageInfo message) {
    if (message.status == MessageStatus.revoked) return false;
    final payload = message.messagePayload;
    if (payload is! TipsMessagePayload) return false;
    final tips = payload.groupTips;
    return tips != null && tips.isNotEmpty && tips.every(isBackendOwnedTip);
  }

  /// 保留同一事件最早收到的后端通知，撤回继续显示在原消息位置。
  static List<MessageInfo> visibleMessages(List<MessageInfo> messages) {
    final seen = <String>{};
    final visible = <MessageInfo>[];
    for (final message in messages.reversed) {
      if (hidesNativeMessage(message)) continue;
      final notice = fromMessage(message);
      if (notice == null ||
          (!notice.usesOriginalMessage && seen.add(notice.eventId))) {
        visible.add(message);
      }
    }
    return visible.reversed.toList();
  }

  /// 群聊历史和实时消息均从自定义元素正文解析。
  static ConversationNotice? fromMessage(MessageInfo message) {
    if (message.status == MessageStatus.revoked ||
        message.status == MessageStatus.deleted) {
      return null;
    }
    final payload = message.messagePayload;
    return payload is CustomMessagePayload
        ? tryParse(payload.customData)
        : null;
  }

  /// 只识别当前版本和字段完整的已知类型，其他数据交还通用消息渲染。
  static ConversationNotice? tryParse(String? raw) {
    if (raw == null || !raw.trimLeft().startsWith('{')) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['businessID'] != businessId ||
        decoded['version'] is! int ||
        decoded['version'] != 1) {
      return null;
    }
    final id = decoded['eventId'];
    final type = decoded['type'];
    final time = decoded['occurredAt'];
    final data = decoded['data'];
    // 要求显式时区，避免同一事件在设备本地时区被解析为不同时间。
    if (!_nonEmpty(id) ||
        type is! String ||
        time is! String ||
        !RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(time) ||
        data is! Map<String, dynamic>) {
      return null;
    }
    final occurredAt = DateTime.tryParse(time);
    if (occurredAt == null) return null;
    final valid = switch (type) {
      'message.recalled' ||
      'message.pinned' ||
      'message.unpinned' =>
        _person(data['operator']) && _nonEmpty(data['messageId']),
      'member.phone_viewed' =>
        _person(data['viewer']) && _person(data['target']),
      'group.created' => _person(data['operator']) &&
          _named(data['group'], 'groupId') &&
          _members(data['initialMembers'], allowEmpty: true),
      'group.members_invited' ||
      'group.members_removed' =>
        _person(data['operator']) && _members(data['members']),
      'group.members_joined' => _members(data['members']),
      'group.member_left' => _person(data['member']),
      'group.welcome' =>
        _named(data['group'], 'groupId') && _person(data['member']),
      'group.description_changed' =>
        _person(data['operator']) && data['newDescription'] is String,
      _ => false,
    };
    return valid
        ? ConversationNotice._(id as String, type, occurredAt, data)
        : null;
  }

  static bool _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty;

  static bool _named(Object? value, String idKey) =>
      value is Map &&
      _nonEmpty(value[idKey]) &&
      _nonEmpty(value['nameSnapshot']);

  static bool _person(Object? value) => _named(value, 'userId');

  static bool _members(Object? value, {bool allowEmpty = false}) =>
      value is List && (allowEmpty || value.isNotEmpty) && value.every(_person);

  /// 只有 ID 匹配才替换为“你”；成员重复时保留首次出现的姓名和顺序。
  String textFor(String? viewerId) {
    String name(Map user) =>
        user['userId'] == viewerId ? '你' : user['nameSnapshot'] as String;
    String person(String key) => name(_data[key] as Map);
    String people(String key) {
      final seen = <Object?>{};
      return (_data[key] as List)
          .cast<Map>()
          .where((user) => seen.add(user['userId']))
          .map(name)
          .join('、');
    }

    return switch (type) {
      'message.recalled' => '${person('operator')}撤回了一条消息',
      'message.pinned' => '${person('operator')}置顶了内容',
      'message.unpinned' => '${person('operator')}移除了置顶内容',
      'member.phone_viewed' => '${person('viewer')}查看了${person('target')}的手机号',
      'group.created' => (_data['initialMembers'] as List).isEmpty
          ? '${person('operator')} 创建了群聊'
          : '${person('operator')} 发起群聊，并邀请 ${people('initialMembers')} 加入此群',
      'group.members_invited' =>
        '${person('operator')} 邀请 ${people('members')} 加入了群组',
      'group.members_joined' => '${people('members')} 加入了群组',
      'group.member_left' => '${person('member')} 退出了群组',
      'group.members_removed' =>
        '${person('operator')} 将 ${people('members')} 移出了群组',
      'group.welcome' => '欢迎加入 ${(_data['group'] as Map)['nameSnapshot']} 群组',
      'group.description_changed' => _data['newDescription'] == ''
          ? '${person('operator')} 清空了群描述'
          : '${person('operator')} 更新了群描述：${_data['newDescription']}',
      _ => '',
    };
  }
}
