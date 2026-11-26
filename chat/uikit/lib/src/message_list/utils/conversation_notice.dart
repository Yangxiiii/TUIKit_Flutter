import 'dart:convert';

import 'package:app_api/app_api_models.dart' show readNullableStringValue;
import 'package:atomic_x_core/atomicxcore.dart';

/// 统一系统通知，为聊天正文和会话摘要保留事件身份与姓名。
final class ConversationNotice {
  const ConversationNotice._(
      this.eventId, this.type, this.occurredAt, this._data);

  /// 按会话去重的标识，只有原始载荷或 SDK 消息 ID 可用时才设置。
  final String eventId;

  /// 已验证的事件类型，用于选择后端通知文案。
  final String type;

  /// 由建群事件生成行内姓名与文案，正文保留全名，摘要可按当前账号称呼本人。
  List<({String text, String? userId})> groupCreationParts({
    String? viewerId,
  }) {
    if (type != 'group.created') return const [];
    ({String text, String? userId}) person(Map user) {
      final id = user['userId'] as String;
      return (
        text: id == viewerId ? '你' : user['nameSnapshot'] as String,
        userId: id,
      );
    }

    final operator = person(_data['operator'] as Map);
    // 同一人只展示一次，建群发起人不计入邀请名单。
    final seen = {operator.userId};
    final invited = (_data['initialMembers'] as List)
        .cast<Map>()
        .where((member) => seen.add(member['userId'] as String))
        .map(person)
        .toList();
    if (invited.isEmpty) {
      return [operator, (text: ' 创建了群聊', userId: null)];
    }
    return [
      operator,
      (text: ' 发起群聊，并邀请 ', userId: null),
      for (final (index, member) in invited.indexed) ...[
        if (index > 0) (text: '、', userId: null),
        member,
      ],
      (text: ' 加入此群', userId: null),
    ];
  }

  /// 成员退群与移出消息共享群内通知的受众策略。
  bool get isGroupDeparture =>
      type == 'group.member_left' || type == 'group.members_removed';

  /// 邀请通知沿用成员变动样式，受众仍由该消息的投递范围决定。
  bool get isGroupInvitation => type == 'group.members_invited';

  /// 手机号查看通知使用独立载荷，名片目标来自载荷中的用户 ID。
  bool get isPhoneView => type == _viewPhoneBusinessId;

  /// 返回姓名和正文片段，历史通知缺少人员 ID 时仍展示原有姓名。
  List<({String text, String? userId})> phoneViewParts() {
    if (!isPhoneView) return const [];
    return [
      (
        text: _data['operatorName'] as String,
        userId: _data['operatorUserId'] as String?,
      ),
      (text: ' 查看了 ', userId: null),
      (
        text: _data['targetName'] as String,
        userId: _data['targetUserId'] as String?,
      ),
      (text: ' 的手机号', userId: null),
    ];
  }

  /// 欢迎语正文与摘要共用文案，聊天行只强调事件中的群名快照。
  ({String prefix, String groupName, String suffix})? get groupWelcomeParts {
    if (type != 'group.welcome') return null;
    return (
      prefix: '欢迎加入 ',
      groupName: (_data['group'] as Map)['nameSnapshot'] as String,
      suffix: ' 群组',
    );
  }

  /// 管理员身份变更面向全群，不受退群通知的展示开关限制。
  bool get isGroupAdminChange => type == _adminAdded || type == _adminRemoved;

  /// 设置群管理员的自定义通知类型。
  static const _adminAdded = 'group.add_manager';

  /// 撤销群管理员的自定义通知类型。
  static const _adminRemoved = 'group.remove_manager';

  /// 返回成员变动行内片段，摘要可将当前账号称为「你」。
  List<({String text, String? userId})> groupMemberParts({String? viewerId}) {
    ({String text, String? userId}) person(Map user) => (
          text:
              user['userId'] == viewerId ? '你' : user['nameSnapshot'] as String,
          userId: user['userId'] as String
        );
    if (type == 'group.member_left') {
      return [
        person(_data['member'] as Map),
        (text: ' 退出了群组', userId: null),
      ];
    }
    final ending = switch (type) {
      'group.members_invited' => ' 加入了群组',
      'group.members_removed' => ' 移出了群组',
      _adminAdded => ' 添加为群管理员',
      _adminRemoved => ' 从群管理员中移除',
      _ => null,
    };
    if (ending == null) return const [];
    // 操作人已在句首展示，避免同一用户在行内出现重复名片入口。
    final seen = <Object?>{(_data['operator'] as Map)['userId']};
    final people = (_data['members'] as List)
        .cast<Map>()
        .where((member) => seen.add(member['userId']))
        .toList();
    return [
      person(_data['operator'] as Map),
      (text: isGroupInvitation ? ' 邀请 ' : ' 将 ', userId: null),
      for (var index = 0; index < people.length; index++) ...[
        if (index > 0) (text: '、', userId: null),
        person(people[index]),
      ],
      (text: ending, userId: null),
    ];
  }

  /// 群描述和群名变更统一展示操作人姓名，该身份也用于打开名片。
  ({String id, String name})? descriptionOperator() {
    if (type != 'group.description_changed') return null;
    final operator = _data['operator'] as Map;
    return (
      id: operator['userId'] as String,
      name: operator['nameSnapshot'] as String,
    );
  }

  /// 后端事件时间或 SDK 消息时间，仅解析手机号查看载荷时可为空。
  final DateTime? occurredAt;

  /// 撤回由原消息状态展示，独立的协议记录不进入会话正文或摘要。
  bool get usesOriginalMessage => type == 'message.recalled';

  /// 已按事件类型校验的载荷，姓名使用发送时的快照。
  final Map<String, dynamic> _data;

  /// 自定义元素中标识 OA 系统提示的业务字段值。
  static const businessId = 'oa_system_notice';

  /// 手机号查看使用独立业务标识，载荷提供两人的用户 ID 和展示名。
  static const _viewPhoneBusinessId = 'oa_view_phone';

  /// 已由 OA 建群通知替代的旧格式，聊天正文和会话摘要均不再展示。
  static const legacyGroupCreationBusinessId = 'group_create';

  /// 聊天历史、实时反馈和会话摘要共用隐藏规则，旧提示不会占据末条消息。
  static bool hidesMessage(
    MessageInfo message, {
    bool inChatWindow = false,
  }) {
    final payload = message.messagePayload;
    if (payload is CustomMessagePayload &&
        payload.customData.trimLeft().startsWith('{')) {
      return ChatUtil.jsonData2Dictionary(payload.customData)?['businessID'] ==
          legacyGroupCreationBusinessId;
    }
    return hidesNativeMessage(message, inChatWindow: inChatWindow);
  }

  /// 这些原生提示已有后端通知，混合消息仍保留未迁移的部分。
  static bool isBackendOwnedTip(GroupTipsInfo tip) =>
      tip is InviteToGroup ||
      tip is JoinGroup ||
      tip is QuitGroup ||
      tip is KickedFromGroup ||
      tip is SetGroupAdmin ||
      tip is CancelGroupAdmin ||
      tip is PinGroupMessage ||
      tip is UnpinGroupMessage;

  /// 聊天窗口额外隐藏头像变更，会话摘要仍只过滤由后端接管的提示。
  static bool isHiddenInChatWindowTip(GroupTipsInfo tip) =>
      tip is ChangeGroupAvatar || isBackendOwnedTip(tip);

  /// 混合提示中只要还有可见事件，就保留该消息供对应界面展示。
  static bool hidesNativeMessage(
    MessageInfo message, {
    bool inChatWindow = false,
  }) {
    if (message.status == MessageStatus.revoked) return false;
    final payload = message.messagePayload;
    if (payload is! TipsMessagePayload) return false;
    final tips = payload.groupTips;
    return tips != null &&
        tips.isNotEmpty &&
        tips.every(inChatWindow ? isHiddenInChatWindowTip : isBackendOwnedTip);
  }

  /// 两种来源的描述通知只有在操作人、正文和事件时间一致时才合并。
  ({String operatorId, String description, int second})?
      get _descriptionChange {
    if (type != 'group.description_changed') return null;
    return (
      operatorId: (_data['operator'] as Map)['userId'] as String,
      description: _data['newDescription'] as String,
      second: occurredAt!.millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// 仅用有效的原生消息匹配同一群里的后端描述通知。
  static Iterable<({String operatorId, String description, int second})>
      _nativeDescriptionChanges(MessageInfo message) sync* {
    final second = message.timestamp;
    final payload = message.messagePayload;
    if (message.status == MessageStatus.revoked ||
        message.status == MessageStatus.deleted ||
        second == null ||
        second <= 0 ||
        payload is! TipsMessagePayload) {
      return;
    }
    for (final tip in payload.groupTips ?? const <GroupTipsInfo>[]) {
      if (tip is ChangeGroupIntroduction) {
        yield (
          operatorId: tip.opUser.userID,
          description: tip.groupIntroduction,
          second: second,
        );
      }
    }
  }

  /// 原生变更已经展示时，迟到的后端副本不再触发实时新消息反馈。
  bool matchesNativeDescriptionIn(Iterable<MessageInfo> messages) {
    final change = _descriptionChange;
    return change != null &&
        messages.expand(_nativeDescriptionChanges).contains(change);
  }

  /// 过滤隐藏提示，描述变更优先展示同一事件的 IM 原生提示。
  /// 同一事件保留最早收到的版本，缺少事件标识时保留各自独立的通知。
  static List<MessageInfo> visibleMessages(List<MessageInfo> messages) {
    // 提前收集原生事件，避免 SDK 与后端副本的到达顺序影响结果。
    final nativeDescriptions =
        messages.expand(_nativeDescriptionChanges).toSet();
    final seen = <String>{};
    final visible = <MessageInfo>[];
    for (final message in messages.reversed) {
      if (hidesMessage(message, inChatWindow: true)) continue;
      final notice = fromMessage(message);
      if (notice == null ||
          (!notice.usesOriginalMessage &&
              !nativeDescriptions.contains(notice._descriptionChange) &&
              (notice.eventId.isEmpty || seen.add(notice.eventId)))) {
        visible.add(message);
      }
    }
    return visible.reversed.toList();
  }

  /// 聊天历史和实时消息均从自定义元素正文解析，手机号查看提示补充 SDK 元数据。
  static ConversationNotice? fromMessage(MessageInfo message) {
    if (message.status == MessageStatus.revoked ||
        message.status == MessageStatus.deleted) {
      return null;
    }
    final payload = message.messagePayload;
    return payload is CustomMessagePayload
        ? _tryParse(payload.customData, message)
        : null;
  }

  /// 只识别当前版本和字段完整的已知类型，其他数据交还通用消息渲染。
  static ConversationNotice? tryParse(String? raw) => _tryParse(raw, null);

  /// 两种通知协议各自校验载荷，仅 SDK 消息可为手机号查看通知提供投递信息。
  static ConversationNotice? _tryParse(String? raw, MessageInfo? message) {
    if (raw == null || !raw.trimLeft().startsWith('{')) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] is! int ||
        decoded['version'] != 1) {
      return null;
    }
    final protocol = decoded['businessID'];
    if (protocol == _viewPhoneBusinessId) {
      return _parseViewPhone(decoded['payload'], message);
    }
    if (protocol != businessId) return null;

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
    final member = data['member'];
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
      'group.members_removed' ||
      _adminAdded ||
      _adminRemoved =>
        _person(data['operator']) && _members(data['members']),
      'group.members_joined' => _members(data['members']),
      'group.member_left' => _person(member),
      // 欢迎语只显示群名，兼容服务端仅提供成员 ID 的载荷。
      'group.welcome' => _named(data['group'], 'groupId') &&
          member is Map &&
          _nonEmpty(member['userId']),
      'group.description_changed' =>
        _person(data['operator']) && data['newDescription'] is String,
      _ => false,
    };
    return valid
        ? ConversationNotice._(id as String, type, occurredAt, data)
        : null;
  }

  /// 仅从载荷读取名片身份，通知顺序和唯一性仍来自 SDK 消息。
  static ConversationNotice? _parseViewPhone(
      Object? payload, MessageInfo? message) {
    if (payload is! Map<String, dynamic>) return null;
    final operatorName = payload['operatorName'];
    final targetName = payload['targetName'];
    if (!_nonEmpty(operatorName) || !_nonEmpty(targetName)) return null;
    final operatorUserId = _readPhoneViewUserId(payload['operatorUserId']);
    final targetUserId = _readPhoneViewUserId(payload['targetUserId']);
    final messageId = message?.msgID ?? '';
    final timestamp = message?.timestamp;
    return ConversationNotice._(
      messageId.isEmpty ? '' : '$_viewPhoneBusinessId:$messageId',
      _viewPhoneBusinessId,
      timestamp == null || timestamp <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true),
      {
        'operatorName': operatorName,
        'targetName': targetName,
        // 旧通知没有人员 ID，无法定位的姓名仍保留为普通文本。
        if (_nonEmpty(operatorUserId)) 'operatorUserId': operatorUserId,
        if (_nonEmpty(targetUserId)) 'targetUserId': targetUserId,
      },
    );
  }

  /// 兼容服务端的 JSON 整数和字符串 ID，超出这两种类型的值只展示姓名。
  static String? _readPhoneViewUserId(Object? value) =>
      value is int || value is String ? readNullableStringValue(value) : null;

  static bool _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty;

  static bool _named(Object? value, String idKey) =>
      value is Map &&
      _nonEmpty(value[idKey]) &&
      _nonEmpty(value['nameSnapshot']);

  static bool _person(Object? value) => _named(value, 'userId');

  static bool _members(Object? value, {bool allowEmpty = false}) =>
      value is List && (allowEmpty || value.isNotEmpty) && value.every(_person);

  /// 腾讯 IM 原生提示与后端通知共用描述更新和清空文案。
  static String groupDescriptionText(String operator, String description) =>
      description.isEmpty
          ? '$operator 清空了群描述'
          : '$operator 更新了群描述：$description';

  /// 成员类提示按账号称呼本人，资料变更和欢迎语使用事件中的名称快照。
  String textFor(String? viewerId) {
    final welcome = groupWelcomeParts;
    if (welcome != null) {
      return '${welcome.prefix}${welcome.groupName}${welcome.suffix}';
    }

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
      _viewPhoneBusinessId => phoneViewParts().map((part) => part.text).join(),
      'member.phone_viewed' => '${person('viewer')}查看了${person('target')}的手机号',
      'group.created' =>
        groupCreationParts(viewerId: viewerId).map((part) => part.text).join(),
      'group.members_invited' =>
        '${person('operator')} 邀请 ${people('members')} 加入了群组',
      'group.members_joined' => '${people('members')} 加入了群组',
      'group.member_left' => '${person('member')} 退出了群组',
      'group.members_removed' =>
        '${person('operator')} 将 ${people('members')} 移出了群组',
      _adminAdded ||
      _adminRemoved =>
        groupMemberParts(viewerId: viewerId).map((part) => part.text).join(),
      'group.description_changed' => groupDescriptionText(
          descriptionOperator()!.name,
          _data['newDescription'] as String,
        ),
      _ => '',
    };
  }
}
