import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'message_actions_scope.dart';

/// 确认与执行共用单消息守卫，取消零调用，重复入口不会重复提交 SDK 操作。
Future<void> confirmMessageAction(
  BuildContext context, {
  required String messageId,
  required bool isDelete,
  required bool Function() isEligible,
  required Future<void> Function() execute,
}) async {
  final guard = MessageActionsScope.maybeOf(context)?.actionGuard;
  final action = isDelete ? 'delete' : 'retry';
  Future<void> confirm() async {
    if (!context.mounted || !isEligible()) return;
    final text = AppLocalization.of(context);
    final colors = context.appColors;
    final accepted = await AppDialog.showAlert(
      semanticsIdentifier: 'tim.message.$action.confirm',
      content: isDelete
          ? text.messageDeleteConfirmation
          : text.messageRetryConfirmation,
      cancelText: text.cancel,
      confirmText: isDelete ? text.delete : text.messageRetryAction,
      confirmBackgroundColor: isDelete ? colors.danger : null,
      theme: Theme.of(context),
    );
    // 弹窗期间消息可能已撤回或页面已离开，不能继续执行旧目标。
    if (accepted == true && context.mounted && isEligible()) {
      try {
        await execute();
      } on Object {
        // 发送器异常仍须释放完整守卫，让同一失败消息能够再次确认重试。
        if (context.mounted) {
          AppToast.show(isDelete ? '删除失败，请稍后重试' : text.sendMessageFail);
        }
      }
    }
  }

  if (guard == null) {
    await confirm();
  } else {
    await guard.singleFlight<void>('tim.message.$action.$messageId', confirm);
  }
}
