import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';

/// 单聊通话菜单只返回媒体类型，关闭浮层后由原聊天入口执行权限与呼叫流程。
class CallSelectionSheet extends StatelessWidget {
  const CallSelectionSheet({super.key, required this.name});

  /// 当前单聊的独立展示名称，不拼接机构字段。
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = AppLocalization.of(context);
    return Material(
      color: colors.surface,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 标题为左侧辅助说明，与下方两个可点击的通话操作分层。
        SizedBox(
          height: 44,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text.resolve('chat.uikit.callPeerTitle', '呼叫{name}',
                    namedArgs: {'name': name}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    height: 20 / 13,
                    fontWeight: FontWeight.w400,
                    color: colors.sheetCaption),
              ),
            ),
          ),
        ),
        Divider(
            height: 1,
            thickness: 1,
            color: colors.outline.withValues(alpha: .5)),
        _option(context, 'audio', text.audioCall, AppIcons.phone3,
            CallMediaType.audio),
        _option(context, 'video', text.videoCall, AppIcons.cameraOn,
            CallMediaType.video),
        // 组间留白属于浮板浅灰背景，不能让聊天遮罩透出或给菜单底部加圆角。
        ColoredBox(
            color: colors.groupedPageBackground,
            child: const SizedBox(height: 8, width: double.infinity)),
        _action(context, 'cancel', text.cancel, () => AppDialog.dismiss()),
      ]),
    );
  }

  Widget _option(BuildContext context, String id, String label, IconData icon,
          CallMediaType type) =>
      DecoratedBox(
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: context.appColors.outline.withValues(alpha: .5)))),
        child: _action(
            context, id, label, () => AppDialog.dismiss(result: type),
            icon: icon),
      );

  /// 标识合并到实际按钮语义；整行48高可点击，图标和文字使用设计中的8像素间距。
  Widget _action(
          BuildContext context, String id, String label, VoidCallback onTap,
          {IconData? icon}) =>
      SizedBox(
        height: 48,
        width: double.infinity,
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: context.appColors.dialogForeground,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const RoundedRectangleBorder(),
          ),
          onPressed: onTap,
          child: Semantics(
            identifier: 'call.select.$id',
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: context.appColors.dialogForeground),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 16,
                      height: 20 / 16,
                      fontWeight: FontWeight.w400,
                      color: context.appColors.dialogForeground)),
            ]),
          ),
        ),
      );
}
