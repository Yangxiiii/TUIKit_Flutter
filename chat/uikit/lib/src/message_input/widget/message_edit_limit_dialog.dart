import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 展示单条消息二十次上限；确认只关闭提示，不清空仍在编辑的正文。
class MessageEditLimitDialog extends StatelessWidget {
  const MessageEditLimitDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: 342,
        height: 120,
        child: Column(children: [
          // 上限正文不附加标题，保持设计的单段提示结构及产品裁决的20次文案。
          Expanded(
            child: Center(
              child: Text('单条消息最多编辑20次',
                  style: TextStyle(fontSize: 16, color: colors.textPrimary)),
            ),
          ),
          Divider(height: 0, thickness: 0.5, color: colors.outline),
          Semantics(
            identifier: 'tim.message.editLimitConfirm',
            button: true,
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colors.primary,
                  textStyle: const TextStyle(fontSize: 16, height: 1.5),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('我知道了'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
