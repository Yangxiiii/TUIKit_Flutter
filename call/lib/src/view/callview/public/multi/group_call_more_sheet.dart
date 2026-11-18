import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 展示当前可信权限，并将编辑草稿交回场次编排；不直接修改房间策略。
class GroupCallMoreSheet extends StatefulWidget {
  const GroupCallMoreSheet(
      {super.key,
      this.allowSelfUnmute,
      this.allowVideo,
      this.policyVersion = 0,
      this.canManage = false,
      this.pending = false,
      this.status,
      this.onConfirm,
      this.onAllCameras});

  /// 空值表示尚未同步，不能用默认关闭代替未知策略。
  final bool? allowSelfUnmute, allowVideo;

  /// 版本变化时丢弃旧编辑草稿，避免确认过期的权限组合。
  final int policyVersion;

  /// 仅当前经过协议确认的主持人可提交修改。
  final bool canManage;

  /// 当前策略仍在等待真实执行回执，期间不接受第二次提交。
  final bool pending;

  /// 会控提供的等待、失败或不可用原因，不把发送成功作为设备成功。
  final String? status;

  /// 返回真实执行结果；成功才关闭，失败保留面板供检查和重试。
  final Future<bool> Function(bool allowSelfUnmute, bool allowVideo)? onConfirm;

  /// 全员设备操作独立于权限草稿，开启时由各目标成员本人确认。
  final Future<bool> Function(bool enabled)? onAllCameras;

  @override
  State<GroupCallMoreSheet> createState() => _GroupCallMoreSheetState();
}

/// 开关草稿只在本面板存续，后台策略与主持权限始终以参数为准。
class _GroupCallMoreSheetState extends State<GroupCallMoreSheet> {
  /// 未提交的权限草稿，只有确认动作才交给控制器执行。
  bool? _allowSelfUnmute, _allowVideo;

  /// 表示当前确认动作尚未返回；实际命令去重由编排层 ActionGuard 负责。
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _resetDraft();
  }

  @override
  void didUpdateWidget(covariant GroupCallMoreSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policyVersion != widget.policyVersion ||
        oldWidget.allowSelfUnmute != widget.allowSelfUnmute ||
        oldWidget.allowVideo != widget.allowVideo) {
      _resetDraft();
    }
  }

  void _resetDraft() {
    _allowSelfUnmute = widget.allowSelfUnmute;
    _allowVideo = widget.allowVideo;
  }

  /// 未知策略、非主持与等待回执时不能编辑，避免把草稿误作生效权限。
  bool get _editable =>
      widget.canManage &&
      !widget.pending &&
      !_saving &&
      _allowSelfUnmute != null &&
      _allowVideo != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final status = widget.status ??
        (widget.allowSelfUnmute == null || widget.allowVideo == null
            ? '会控权限尚未同步，暂不可修改'
            : !widget.canManage
                ? '仅主持人可以修改权限'
                : null);
    return SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 34),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: colors.outline,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Container(
                decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  _permission('selfUnmute', '允许成员自行解除静音', _allowSelfUnmute,
                      (value) => setState(() => _allowSelfUnmute = value)),
                  Divider(height: .5, thickness: .5, color: colors.outline),
                  _permission('video', '允许成员开启视频', _allowVideo,
                      (value) => setState(() => _allowVideo = value)),
                ])),
            const SizedBox(height: 16),
            _cameraActions(),
            if (status != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(status,
                      style: TextStyle(
                          fontSize: 12, color: colors.textSecondary))),
            const SizedBox(height: 16),
            _actions(),
          ]),
        ));
  }

  /// 未知策略保留说明；已知策略的开关只编辑草稿，不乐观写入远端状态。
  Widget _permission(
          String id, String label, bool? value, ValueChanged<bool> onChanged) =>
      SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child:
                          Text(label, style: const TextStyle(fontSize: 14)))),
              Semantics(
                  identifier: 'call.group.permissions.$id',
                  label: label,
                  child: value == null
                      ? Text('未同步',
                          style: TextStyle(
                              fontSize: 12,
                              color: context.appColors.textSecondary))
                      : Switch(
                          value: value,
                          onChanged: _editable ? onChanged : null)),
            ]),
          ));

  /// 显式保留按钮名称、禁用状态与点击动作，避免原生语义合并时丢失自动化标识。
  Widget _actions() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
            child: Semantics(
                identifier: 'call.group.permissions.cancel',
                container: true,
                button: true,
                label: '取消',
                enabled: true,
                onTap: () => Navigator.pop(context),
                excludeSemantics: true,
                child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            backgroundColor: context.appColors.outline,
                            foregroundColor: context.appColors.textPrimary,
                            side: BorderSide.none),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消',
                            style: TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                letterSpacing: 0)))))),
        const SizedBox(width: 10),
        Expanded(
            child: Semantics(
                identifier: 'call.group.permissions.confirm',
                container: true,
                button: true,
                label: _saving || widget.pending ? '处理中…' : '确认',
                enabled: _editable && widget.onConfirm != null,
                onTap: _editable && widget.onConfirm != null ? _confirm : null,
                excludeSemantics: true,
                child: SizedBox(
                    height: 42,
                    child: FilledButton(
                        onPressed: _editable && widget.onConfirm != null
                            ? _confirm
                            : null,
                        child: Text(_saving || widget.pending ? '处理中…' : '确认',
                            style: const TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                letterSpacing: 0)))))),
      ]));

  /// 批量关闭直接执行，开启按钮向成员发出确认请求。
  Widget _cameraActions() => Row(children: [
        for (final enabled in [false, true]) ...[
          if (enabled) const SizedBox(width: 10),
          Expanded(
              child: Semantics(
                  identifier:
                      'call.group.permissions.${enabled ? 'openCameras' : 'closeCameras'}',
                  container: true,
                  button: true,
                  label: enabled ? '请求全员开启摄像头' : '关闭全员摄像头',
                  enabled: _editable && widget.onAllCameras != null,
                  onTap: _editable && widget.onAllCameras != null
                      ? () => _setAllCameras(enabled)
                      : null,
                  excludeSemantics: true,
                  child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8))),
                      onPressed: _editable && widget.onAllCameras != null
                          ? () => _setAllCameras(enabled)
                          : null,
                      child: Text(enabled ? '请全员开摄像头' : '关闭全员摄像头',
                          maxLines: 1, style: const TextStyle(fontSize: 14))))),
        ],
      ]);

  /// 仅提交全员设备目标，不把尚未确认的策略草稿一起发送。
  Future<void> _setAllCameras(bool enabled) async {
    if (!_editable || widget.onAllCameras == null) return;
    setState(() => _saving = true);
    try {
      await widget.onAllCameras!(enabled);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 仅关闭仍存续且真实执行成功的面板；失败状态由上层会控事实继续展示。
  Future<void> _confirm() async {
    if (!_editable || widget.onConfirm == null) return;
    setState(() => _saving = true);
    try {
      final success = await widget.onConfirm!(_allowSelfUnmute!, _allowVideo!);
      if (mounted && success) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
