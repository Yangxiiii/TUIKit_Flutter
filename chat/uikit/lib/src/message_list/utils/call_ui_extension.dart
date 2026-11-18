import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/cupertino.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/join_in_group_call_widget.dart';

/// 腾讯群属性中的有效通话快照，只用于展示和传递真实 callId。
final class GroupCallBannerData {
  const GroupCallBannerData(
      {required this.callId, required this.mediaType, required this.userIds});

  /// 腾讯维护的场次标识，不允许用 roomId 或群 ID 代替。
  final String callId;

  /// 已验证为语音或视频的媒体类型。
  final CallMediaType mediaType;

  /// 群属性中的参与者顺序；去重后至少两人才展示仍可加入的场次。
  final List<String> userIds;
}

/// 将腾讯维护的群属性转换为横幅，不写入群属性或生成新的邀请信令。
abstract final class CallUIExtension {
  /// 属性缺失、过期为单人或结构非法时隐藏横幅，不留下可点击的无效入口。
  static Widget getJoinInGroupCallWidget(
      String groupId, Map<String, String>? groupAttributes) {
    final data = parseGroupCallData(groupAttributes);
    if (groupId.trim().isEmpty || data == null) return const SizedBox.shrink();
    return JoinInGroupCallWidget(
      userIDs: data.userIds,
      mediaType: data.mediaType,
      groupId: groupId,
      callId: data.callId,
    );
  }

  /// 解析第三方动态群属性协议；字段不符合当前已知契约时不推断媒体或用户。
  ///
  /// 该载荷由腾讯维护且不属于项目 DTO，必须手工校验动态 JSON 边界。
  static GroupCallBannerData? parseGroupCallData(
      Map<String, String>? attributes) {
    final raw = attributes?['inner_attr_kit_info'];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['business_type'] != 'callkit') {
        return null;
      }
      final callId = decoded['call_id'];
      final users = decoded['user_list'];
      final mediaType = switch (decoded['call_media_type']) {
        'audio' => CallMediaType.audio,
        'video' => CallMediaType.video,
        _ => null,
      };
      if (callId is! String ||
          callId.trim().isEmpty ||
          callId != callId.trim() ||
          mediaType == null ||
          users is! List) {
        return null;
      }
      // 不把数字或对象转成用户 ID；重复条目不增加人数。
      final ids = <String>{};
      for (final entry in users) {
        if (entry is! Map<String, dynamic>) return null;
        final id = entry['userid'];
        if (id is! String || id.trim().isEmpty || id != id.trim()) return null;
        ids.add(id);
      }
      if (ids.length < 2) return null;
      return GroupCallBannerData(
          callId: callId,
          mediaType: mediaType,
          userIds: List.unmodifiable(ids));
    } on FormatException {
      return null;
    }
  }
}
