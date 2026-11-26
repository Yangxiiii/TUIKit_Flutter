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
                ?.where(
                    (tip) => !ConversationNotice.isHiddenInChatWindowTip(tip))
                .toList() ??
            const <GroupTipsInfo>[]
        : const <GroupTipsInfo>[];
    final systemContent = customContent ??
        (message?.status == MessageStatus.revoked
            ? MessageUtil.getRevokeDisplayString(message!, context)
            : MessageUtil.getSystemInfoDisplayString(tips, context));
    if (systemContent.isEmpty) return const SizedBox.shrink();
    final actor = operator ?? _groupInfoOperator(context, tips);
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
  ({String id, String name})? _groupInfoOperator(
      BuildContext context, List<GroupTipsInfo> tips) {
    final operator = switch (tips.firstOrNull) {
      ChangeGroupName(:final opUser) ||
      ChangeGroupIntroduction(:final opUser) =>
        opUser,
      _ => null,
    };
    if (operator == null || operator.userID.isEmpty) return null;
    return (
      id: operator.userID,
      name: UIKitUtil.memberDisplayName(operator, context: context),
    );
  }
}

/// 居中排列带个人名片入口的系统通知，姓名可与正文在同一段落换行。
final class ConversationPeopleNotice extends StatefulWidget {
  const ConversationPeopleNotice({
    required this.parts,
    required this.semanticsPrefix,
    required this.onPersonTap,
    super.key,
  });

  /// 按正文顺序排列的文本片段，仅带有效用户 ID 的姓名可以打开名片。
  final List<({String text, String? userId})> parts;

  /// 通知类型与事件标识组成的前缀，用于区分同一会话内的名片入口。
  final String semanticsPrefix;

  /// 宿主按用户 ID 打开个人名片，未接入时仅展示通知。
  final void Function(BuildContext, String)? onPersonTap;

  @override
  State<ConversationPeopleNotice> createState() =>
      _ConversationPeopleNoticeState();
}

/// 管理同一条通知各姓名的手势，列表回收行时同时释放。
final class _ConversationPeopleNoticeState
    extends State<ConversationPeopleNotice> {
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
            for (final (text: text, userId: id) in widget.parts)
              if (id == null)
                TextSpan(text: text)
              else
                TextSpan(
                  text: text,
                  style: linkStyle,
                  semanticsIdentifier: '${widget.semanticsPrefix}.$id',
                  recognizer: widget.onPersonTap == null
                      ? null
                      : _nameTaps.putIfAbsent(
                          id,
                          () => TapGestureRecognizer()
                            ..onTap =
                                () => widget.onPersonTap?.call(context, id),
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
