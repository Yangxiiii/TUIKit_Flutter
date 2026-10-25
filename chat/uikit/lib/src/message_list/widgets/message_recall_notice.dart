import 'dart:async';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 撤回消息在原位置展示的文字提示；局部Timer仅控制链接到期隐藏。
class MessageRecallNotice extends StatefulWidget {
  const MessageRecallNotice(
      {super.key,
      required this.messageId,
      required this.text,
      this.editableUntil,
      this.onReedit});

  /// 原消息标识，只用于稳定语义定位，不创建新的系统消息ID。
  final String messageId;

  /// 当前用户视角下的本人或他人撤回提示。
  final String text;

  /// 宿主已经确认的原设备回填截止时间；null时只显示提示。
  final DateTime? editableUntil;

  /// 点击后仍由宿主复核截止时间，Timer不授予回填资格。
  final VoidCallback? onReedit;

  @override
  State<MessageRecallNotice> createState() => _MessageRecallNoticeState();
}

/// 只管理链接的到期重绘，不缓存原文或改变消息列表状态。
class _MessageRecallNoticeState extends State<MessageRecallNotice> {
  /// 仅负责当前链接到期的重绘，销毁或收到新截止时间时取消。
  Timer? _timer;

  /// 到期后不可因组件重建重新显示链接，只有新截止时间才会重新调度。
  bool _expired = true;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(MessageRecallNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editableUntil != widget.editableUntil) _schedule();
  }

  /// 截止时间来自宿主，重新挂载也不能重开五分钟窗口。
  void _schedule() {
    _timer?.cancel();
    final remaining = widget.editableUntil?.difference(DateTime.now());
    _expired = remaining == null || remaining <= Duration.zero;
    if (!_expired) {
      _timer = Timer(remaining!, () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
        child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(widget.text,
            style: TextStyle(
                fontSize: 12, height: 16 / 12, color: colors.textTertiary)),
        // 本人原设备才附带重新编辑，提示与链接同一行，长文本允许自然换行。
        if (!_expired && widget.onReedit != null)
          Semantics(
              identifier: 'tim.message.reedit.${widget.messageId}',
              button: true,
              child: GestureDetector(
                  onTap: widget.onReedit,
                  child: Text(' 重新编辑',
                      style: TextStyle(
                          fontSize: 12,
                          height: 16 / 12,
                          color: colors.primary)))),
      ],
    ));
  }
}
