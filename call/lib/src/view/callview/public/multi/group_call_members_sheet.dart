import 'dart:async';
import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart' show PinyinHelper;
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';

import 'group_call_member.dart';
import 'group_call_member_row.dart';
import 'group_call_more_sheet.dart';
import 'group_call_control_feedback.dart';

/// 成员管理按当前主持权限与真实设备状态呈现操作，等待回执时保留实际结果。
class GroupCallMembersSheet extends StatefulWidget {
  const GroupCallMembersSheet(
      {super.key,
      required this.members,
      required this.selfId,
      required this.ended,
      required this.onMicrophone,
      required this.onCamera,
      required this.onRetry,
      this.controlState,
      this.onMemberDevice,
      this.onMuteAll,
      this.onUnmuteAll,
      this.onMore});

  /// 每次 SDK 通知后刷新，包含已移出实时列表的真实邀请结果。
  final List<GroupCallMember> members;

  /// 只有当前登录用户的设备操作可以直接执行。
  final String selfId;

  /// 已结束场次关闭设备和邀请入口，不能恢复旧会话。
  final bool ended;

  /// 本人设备复用 SDK 权限与错误处理。
  final VoidCallback onMicrophone, onCamera;

  /// 已拒绝、超时、忙线或离开成员的重新邀请。
  final ValueChanged<String> onRetry;

  /// 本场可信主持身份、策略和命令进度的唯一展示来源。
  final GroupControlState? controlState;

  /// 设备指令由编排层复核场次、策略与真实回执。
  final void Function(String userId, GroupControlDevice device, bool enabled)?
      onMemberDevice;

  /// 全员静音先确认，解除静音同时解除限制并下发开麦，不在本组件执行 SDK。
  final VoidCallback? onMuteAll, onUnmuteAll;

  /// 展示基于当前策略的更多管理；未配置时仅供只读预览。
  final VoidCallback? onMore;

  @override
  State<GroupCallMembersSheet> createState() => _GroupCallMembersSheetState();
}

/// 搜索和折叠仅影响当前视图，不改变邀请结果或 SDK 成员列表。
class _GroupCallMembersSheetState extends State<GroupCallMembersSheet> {
  /// 避免每个输入字符重复过滤，搜索等待时间为需求规定的 300 毫秒。
  Timer? _searchDebounce;
  String _query = '';
  bool _joinedExpanded = true;
  bool _waitingExpanded = true;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.members.where((member) => _matches(member.name));
    final joined = visible.where((member) => member.joined).toList();
    // 仅使用真实加入事件序号；缺少历史事件的成员保持原展示顺序。
    joined.sort((first, second) {
      final order = second.joinedOrder.compareTo(first.joinedOrder);
      return order != 0
          ? order
          : widget.members
              .indexOf(first)
              .compareTo(widget.members.indexOf(second));
    });
    final waiting =
        visible.where((member) => !member.joined).toList().reversed.toList();
    return SafeArea(
        top: false,
        child: Column(children: [
          // 标题与搜索固定在顶端；成员分组单独滚动，底部会控保持可见。
          _header(),
          _searchInput(),
          Expanded(
              child: ListView(children: [
            _section('joined', '已加入', joined.length, _joinedExpanded,
                () => setState(() => _joinedExpanded = !_joinedExpanded)),
            if (_joinedExpanded)
              for (final member in joined)
                GroupCallMemberRow(
                    member: member,
                    selfId: widget.selfId,
                    ended: widget.ended,
                    onMicrophone: widget.onMicrophone,
                    onCamera: widget.onCamera,
                    controlState: widget.controlState,
                    onMemberDevice: widget.onMemberDevice,
                    onRetry: widget.onRetry),
            _section('waiting', '未加入', waiting.length, _waitingExpanded,
                () => setState(() => _waitingExpanded = !_waitingExpanded)),
            if (_waitingExpanded)
              for (final member in waiting)
                GroupCallMemberRow(
                    member: member,
                    selfId: widget.selfId,
                    ended: widget.ended,
                    onMicrophone: widget.onMicrophone,
                    onCamera: widget.onCamera,
                    controlState: widget.controlState,
                    onMemberDevice: widget.onMemberDevice,
                    onRetry: widget.onRetry),
            if (visible.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text('暂无匹配成员',
                          style: TextStyle(
                              color: context.appColors.textSecondary)))),
          ])),
          _footer(),
        ]));
  }

  /// 复用聊天组件的拼音词典，姓名、全拼与首字母使用同一搜索边界。
  bool _matches(String name) =>
      _query.isEmpty ||
      name.toLowerCase().contains(_query) ||
      PinyinHelper.getPinyinE(name, separator: '')
          .toLowerCase()
          .contains(_query.replaceAll(RegExp(r'\s+'), '')) ||
      PinyinHelper.getShortPinyin(name).toLowerCase().contains(_query);

  /// 输入保持 50 字上限；延迟回调随页面销毁取消。
  void _search(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  /// 标题关闭入口独占原生语义节点，触发后仅收起当前管理面板。
  Widget _header() => SizedBox(
      height: 48,
      child: Row(children: [
        Semantics(
            identifier: 'call.group.members.close',
            container: true,
            button: true,
            label: '收起管理成员',
            enabled: true,
            onTap: () => Navigator.pop(context),
            excludeSemantics: true,
            child: SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                    tooltip: '收起管理成员',
                    onPressed: () => Navigator.pop(context),
                    icon: Transform.rotate(
                        angle: math.pi,
                        child: Icon(AppIcons.expand,
                            size: 16, color: context.appColors.textPrimary))))),
        Text('管理成员',
            style: TextStyle(
                fontSize: 16,
                height: 20 / 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
                color: context.appColors.textPrimary)),
      ]));

  Widget _searchInput() => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: context.appColors.controlBackground,
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(AppIcons.black1,
              size: 16, color: context.appColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
              child: Semantics(
                  identifier: 'call.group.members.search',
                  child: TextField(
                      maxLength: 50,
                      onChanged: _search,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                          fontSize: 16, height: 1.5, letterSpacing: 0),
                      decoration: InputDecoration(
                          hintText: '搜索',
                          counterText: '',
                          hintStyle:
                              TextStyle(color: context.appColors.textSecondary),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero)))),
        ]),
      ));

  Widget _section(String id, String name, int count, bool expanded,
          VoidCallback toggle) =>
      Semantics(
          identifier: 'call.group.members.$id',
          button: true,
          expanded: expanded,
          child: InkWell(
              onTap: toggle,
              child: Container(
                  height: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: context.appColors.outline, width: .5))),
                  child: Row(children: [
                    Text('$name（$count）',
                        style: const TextStyle(fontSize: 14, letterSpacing: 0)),
                    const Spacer(),
                    Transform.rotate(
                        angle: expanded ? 0 : math.pi,
                        child: const Icon(AppIcons.expand, size: 16))
                  ]))));

  /// 主持身份、全局策略与在途命令共同决定按钮，不从设备图标推断全员策略。
  Widget _footer() {
    final state = widget.controlState;
    final canManage = !widget.ended &&
        state?.canManage == true &&
        state!.pendingByUserId.isEmpty;
    final status = widget.ended
        ? '当前通话已结束'
        : groupControlStatusText(state, widget.members);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _footerButton('muteAll', '全员静音', 92,
              canManage && !state.muteAll ? widget.onMuteAll : null),
          const SizedBox(width: 12),
          _footerButton('unmuteAll', '解除全员静音', 124,
              canManage && state.muteAll ? widget.onUnmuteAll : null),
          const SizedBox(width: 12),
          _footerButton(
              'more',
              '更多管理',
              92,
              widget.onMore ??
                  () => showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: context.appColors.groupedPageBackground,
                      barrierColor: context.appColors.scrim,
                      shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(16))),
                      builder: (_) => GroupCallMoreSheet(
                          allowSelfUnmute: state?.policyKnown == true
                              ? state!.allowSelfUnmute
                              : null,
                          allowVideo: state?.policyKnown == true
                              ? state!.allowVideo
                              : null,
                          policyVersion: state?.version ?? 0))),
        ]),
        if (status != null) ...[
          const SizedBox(height: 6),
          Text(status,
              style: TextStyle(
                  fontSize: 11, color: context.appColors.textSecondary)),
        ],
      ]),
    );
  }

  /// 按设计保留描边按钮，原生标识与点击动作放在同一节点，未知会控只改变可用性。
  Widget _footerButton(
          String id, String label, double width, VoidCallback? onPressed) =>
      Semantics(
          identifier: 'call.group.$id',
          container: true,
          button: true,
          label: label,
          enabled: onPressed != null,
          onTap: onPressed,
          excludeSemantics: true,
          child: SizedBox(
              width: width,
              height: 40,
              child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: context.appColors.textPrimary,
                      side: BorderSide(color: context.appColors.outline),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  onPressed: onPressed,
                  child: Text(label,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0)))));
}
