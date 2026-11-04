import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 按设计固定呈现合并、逐条、复制消息链接与删除四项，不在底栏另建选择状态。
class MultiSelectBottomBar extends StatelessWidget {
  const MultiSelectBottomBar(
      {super.key,
      required this.selectedCount,
      required this.onCancel,
      required this.onDelete,
      required this.onForward,
      this.onMergedForward,
      this.onSeparateForward,
      this.onCopyLink,
      this.isDeleteEnabled = true,
      this.isForwardEnabled = true});

  /// 有效选择数量；空选时动作仍可见但禁用。
  final int selectedCount;

  /// 保留旧调用契约，取消由导航或系统返回执行，设计底栏不增加第五项。
  final VoidCallback onCancel;

  /// 当前选择的删除确认入口。
  final VoidCallback onDelete;

  /// 未提供独立方式时保留原转发类型选择器。
  final VoidCallback onForward;

  /// 已明确方式的合并入口，不再二次选择转发类型。
  final VoidCallback? onMergedForward;

  /// 已明确方式的逐条入口，与合并使用同一选择集合。
  final VoidCallback? onSeparateForward;

  /// 由宿主提供可验证的消息链接协议，未提供时明确反馈能力缺失。
  final VoidCallback? onCopyLink;

  /// 宿主权限控制；空选仍额外禁用。
  final bool isDeleteEnabled;

  /// 宿主能力控制；空选仍额外禁用。
  final bool isForwardEnabled;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 142 + bottom,
      color: context.appColors.surface,
      padding: EdgeInsets.fromLTRB(4, 24, 4, 38 + bottom),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 四项均分空间，图形用统一字体库；长标签不能改变相邻项对齐。
        _action(context, 'merged', '合并转发', AppIcons.mergeForward,
            isForwardEnabled ? onMergedForward ?? onForward : null),
        _action(context, 'separate', '逐条转发', AppIcons.forward,
            isForwardEnabled ? onSeparateForward ?? onForward : null),
        _action(context, 'copy_link', '复制消息链接', AppIcons.copyLink1,
            onCopyLink ?? () => AppToast.show('暂无法复制消息链接')),
        _action(context, 'delete', '删除', AppIcons.delete,
            isDeleteEnabled ? onDelete : null),
      ]),
    );
  }

  /// 标识落在有点击动作的节点上；禁用时只保留名称与图形，避免误触副作用。
  Widget _action(BuildContext context, String id, String text, IconData icon,
      VoidCallback? action) {
    final enabled = selectedCount > 0 && action != null;
    final color = enabled
        ? context.appColors.textPrimary
        : context.appColors.textTertiary;
    return Expanded(
        child: Semantics(
            identifier: 'tim.forward.toolbar.$id',
            button: true,
            enabled: enabled,
            child: InkWell(
              onTap: enabled ? action : null,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: context.appColors.controlBackground,
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 24, color: color)),
                const SizedBox(height: 12),
                Text(text,
                    maxLines: 1,
                    style:
                        TextStyle(fontSize: 14, height: 20 / 14, color: color)),
              ]),
            )));
  }
}
