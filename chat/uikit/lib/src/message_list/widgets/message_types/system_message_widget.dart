import 'package:app_ui/app_ui.dart' show AppColorBuildContext;
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/conversation_notice.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';

/// 居中展示原生与后端系统提示，群资料变更可从正文中的姓名进入名片。
class SystemMessageWidget extends StatelessWidget {
  /// 原生提示、撤回原消息或后端提示对应的 SDK 消息。
  final MessageInfo? message;

  /// 后端业务协议解析后生成的纯文本。
  final String? customContent;

  /// 后端资料变更事件中已经解析好的操作人。
  final ({String id, String name})? operator;

  /// 宿主提供的群资料变更操作人名片入口。
  final void Function(BuildContext, String)? onOperatorTap;

  const SystemMessageWidget({
    super.key,
    this.message,
    this.customContent,
    this.operator,
    this.onOperatorTap,
  }) : assert(message != null || customContent != null,
            'Either message or customContent must be provided');

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);
    final payload = message?.messagePayload;
    // 单条群提示可合并多种变更，只移除聊天窗口中需要隐藏的部分。
    final tips = payload is TipsMessagePayload
        ? payload.groupTips
                ?.where((tip) => !ConversationNotice.isHiddenInChatWindowTip(tip))
                .toList() ??
            const <GroupTipsInfo>[]
        : const <GroupTipsInfo>[];
    final systemContent = customContent ??
        (message?.status == MessageStatus.revoked
            ? MessageUtil.getRevokeDisplayString(message!, context)
            : MessageUtil.getSystemInfoDisplayString(tips, context));
    if (systemContent.isEmpty) return const SizedBox.shrink();
    final actor = operator ?? _groupInfoOperator(tips);
    final onTap = onOperatorTap;

    // 只有资料变更姓名可点，其他事件及撤回继续使用原系统提示样式。
    if (actor != null &&
        onTap != null &&
        (message?.status != MessageStatus.revoked) &&
        systemContent.startsWith(actor.name)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text.rich(
            TextSpan(children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Semantics(
                  identifier: 'tim.groupInfo.notice.operator.${message?.msgID}',
                  button: true,
                  child: InkWell(
                    onTap: () => onTap(context, actor.id),
                    child: Text(
                      actor.name,
                      style: FontScheme.caption3Regular.copyWith(
                        color: context.appColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
              TextSpan(text: systemContent.substring(actor.name.length)),
            ]),
            textAlign: TextAlign.center,
            style: FontScheme.caption3Regular.copyWith(
              color: colorsTheme.textColorTertiary,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorsTheme.strokeColorPrimary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            systemContent,
            textAlign: TextAlign.center,
            style: FontScheme.caption3Regular.copyWith(
              color: colorsTheme.textColorTertiary,
            ),
          ),
        ),
      ),
    );
  }

  /// 只有首条可见事件的名称位于文案开头，可作为名片入口。
  ({String id, String name})? _groupInfoOperator(List<GroupTipsInfo> tips) {
    final operator = switch (tips.firstOrNull) {
      ChangeGroupName(:final opUser) ||
      ChangeGroupIntroduction(:final opUser) =>
        opUser,
      _ => null,
    };
    if (operator == null || operator.userID.isEmpty) return null;
    return (
      id: operator.userID,
      name: UIKitUtil.memberDisplayName(operator),
    );
  }
}

/// 按建群通知样式居中排列文案，姓名跨行时仍可打开对应成员的名片。
final class GroupCreationNotice extends StatefulWidget {
  const GroupCreationNotice({
    required this.notice,
    required this.onPersonTap,
    super.key,
  });

  /// 当前行已校验的建群事件，姓名和名片 ID 均来自同一份载荷。
  final ConversationNotice notice;

  /// 宿主按用户 ID 打开个人名片，未接入时仅展示通知。
  final void Function(BuildContext, String)? onPersonTap;

  @override
  State<GroupCreationNotice> createState() => _GroupCreationNoticeState();
}

/// 管理同一条通知各姓名的手势，列表回收行时同时释放。
final class _GroupCreationNoticeState extends State<GroupCreationNotice> {
  /// 按事件中的成员身份复用手势，消息列表重建不会中断正在按下的链接。
  final _nameTaps = <String, TapGestureRecognizer>{};

  @override
  void dispose() {
    for (final recognizer in _nameTaps.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final linkStyle = TextStyle(color: colors.chatMention);
    return Center(
      // 复用消息列表的留白，姓名与正文在同一段落中连续换行。
      child: Text.rich(
        TextSpan(
          children: [
            for (final (text: text, userId: id)
                in widget.notice.groupCreationParts())
              if (id == null)
                TextSpan(text: text)
              else
                TextSpan(
                  text: text,
                  style: linkStyle,
                  semanticsIdentifier:
                      'tim.groupCreation.${widget.notice.eventId}.$id',
                  recognizer: widget.onPersonTap == null
                      ? null
                      : _nameTaps.putIfAbsent(
                          id,
                          () => TapGestureRecognizer()
                            ..onTap = () => widget.onPersonTap?.call(context, id),
                        ),
                ),
          ],
        ),
        textAlign: TextAlign.center,
        style: FontScheme.caption3Regular.copyWith(
          height: 16 / 12,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
