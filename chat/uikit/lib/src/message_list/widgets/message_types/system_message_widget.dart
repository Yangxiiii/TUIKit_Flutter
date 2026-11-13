import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';
import 'package:atomic_x_core/atomicxcore.dart';

/// 将原生事件和已解析的系统文案居中展示，较长的提示按行居中。
class SystemMessageWidget extends StatelessWidget {
  /// 原生提示或处于撤回状态的原消息。
  final MessageInfo? message;

  /// 后端业务协议解析后生成的纯文本。
  final String? customContent;

  const SystemMessageWidget({
    super.key,
    this.message,
    this.customContent,
  }) : assert(message != null || customContent != null,
            'Either message or customContent must be provided');

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);

    String systemContent;
    if (customContent != null) {
      systemContent = customContent!;
    } else if (message != null && message!.status == MessageStatus.revoked) {
      systemContent = MessageUtil.getRevokeDisplayString(message!, context);
    } else {
      systemContent = MessageUtil.getSystemInfoDisplayString(
          (message?.messagePayload as TipsMessagePayload?)?.groupTips ?? [],
          context);
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
}
