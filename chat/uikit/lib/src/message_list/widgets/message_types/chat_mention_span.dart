import 'package:app_ui/app_ui.dart' show AppColorBuildContext;
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../message_input/mention/mention_info.dart';

/// 蓝底强调只属于收到的群聊消息，按当前 IM 账号匹配已校验的个人提及。
String? incomingGroupMentionUserId(MessageInfo? message) {
  if (message == null ||
      message.conversationType != ConversationType.group ||
      message.isSentBySelf) {
    return null;
  }
  return LoginStore.shared.loginState.loginUserInfo?.userID;
}

/// 普通正文和 Markdown 共用同一提及外观，胶囊保留个人名片的点击入口。
InlineSpan buildChatMentionSpan(
  BuildContext context,
  MentionInfo mention, {
  required TextStyle style,
  required String? highlightedUserId,
  TapGestureRecognizer? recognizer,
}) {
  final colors = context.appColors;
  final label = '@${mention.displayName}';
  if (mention.isAtAll || mention.userID != highlightedUserId) {
    return TextSpan(
      text: label,
      style: TextStyle(color: colors.chatMention),
      recognizer: recognizer,
    );
  }

  // WidgetSpan 已跟随正文缩放，胶囊内文字无需再次读取系统字号。
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    style: const TextStyle(fontSize: 16),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: recognizer?.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.chatMention,
          borderRadius: BorderRadius.circular(27),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: style.copyWith(
              color: colors.onPrimary,
              fontSize: 16,
              height: 20 / 16,
            ),
          ),
        ),
      ),
    ),
  );
}
