import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 返回确认后的自行开麦选项；取消返回空值，每次打开都默认禁止自行开麦。
Future<bool?> showGroupMuteAllConfirmation(BuildContext context) async {
  var allowSelfUnmute = false;
  final confirmed = await AppDialog.showAlert(
      title: '全员静音',
      semanticsIdentifier: 'call.group.muteAllConfirm',
      customContent:
          GroupMuteAllContent(onChanged: (value) => allowSelfUnmute = value),
      cancelText: '取消',
      confirmText: '全员静音',
      theme: Theme.of(context));
  return confirmed == true ? allowSelfUnmute : null;
}

/// 全员静音确认中的本地选项，仅确认后才交由会控执行，不提前修改房间策略。
class GroupMuteAllContent extends StatefulWidget {
  const GroupMuteAllContent({super.key, required this.onChanged});

  /// 当前草稿的自行开麦选择，不代表远端成员已收到策略。
  final ValueChanged<bool> onChanged;

  @override
  State<GroupMuteAllContent> createState() => _GroupMuteAllContentState();
}

/// 复选框仅在本次确认弹窗内存续，默认值遵循用户确认的禁止规则。
class _GroupMuteAllContentState extends State<GroupMuteAllContent> {
  /// 每次重新打开都从未勾选开始，不继承上一次弹窗的选择。
  bool _allowSelfUnmute = false;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('所有以及新加入的成员将被静音',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: context.appColors.textPrimary)),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Semantics(
                identifier: 'call.group.muteAllConfirm.allowSelfUnmute',
                child: SizedBox.square(
                    dimension: 18,
                    child: Checkbox(
                        value: _allowSelfUnmute,
                        shape: const CircleBorder(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _allowSelfUnmute = value);
                          widget.onChanged(value);
                        }))),
            const SizedBox(width: 6),
            Flexible(
                child: Text('允许成员自行解除静音',
                    style: TextStyle(
                        fontSize: 14,
                        height: 20 / 14,
                        color: context.appColors.textPrimary))),
          ]),
        ],
      );
}
