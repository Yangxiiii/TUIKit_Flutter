import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';
import 'package:tencent_calls_uikit/src/manager/call_page_router.dart';

/// 未配置宿主组织选人器时的群成员回退入口，提交始终经过场次校验。
class InviteUserWidget extends StatefulWidget {
  const InviteUserWidget({super.key, this.callbacks});

  /// 选人结束后恢复原通话路由。
  final InviteUserCallbacks? callbacks;

  @override
  State<InviteUserWidget> createState() => _InviteUserWidgetState();
}

/// 加载当前群的分页成员，选择仅在本页保留，不另建邀请信令。
class _InviteUserWidgetState extends State<InviteUserWidget> {
  /// 捕获原场次与群，异步返回后不允许作用于新通话。
  late final String _callId, _groupId;
  final List<_InviteMember> _members = [];
  final Set<String> _selected = {};

  /// 禁用重复提交，并在失败时保留用户选择。
  bool _submitting = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _callId = CallStore.shared.state.activeCall.value.callId;
    _groupId = CallStore.shared.state.activeCall.value.chatGroupId;
    _loadMembers();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('邀请成员'),
            leading: Semantics(
                identifier: 'call.group.picker.back',
                child: IconButton(
                    onPressed: _goBack,
                    tooltip: '返回通话',
                    icon: const Icon(AppIcons.back))),
            actions: [
              Semantics(
                  identifier: 'call.group.picker.confirm',
                  child: TextButton(
                      onPressed:
                          _selected.isEmpty || _submitting ? null : _invite,
                      child: Text(
                          _submitting ? '邀请中…' : '邀请（${_selected.length}）')))
            ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListenableBuilder(
                    listenable: CallStore.shared.state.allParticipants,
                    builder: (context, _) => ListView.builder(
                        itemCount: _members.length,
                        itemBuilder: (context, index) =>
                            _row(_members[index]))),
      );

  Set<String> get _excluded => {
        CallStore.shared.state.selfInfo.value.id,
        ...CallStore.shared.state.allParticipants.value
            .map((member) => member.id)
      };

  Widget _row(_InviteMember member) {
    final excluded = _excluded.contains(member.id);
    return Semantics(
        identifier: 'call.group.picker.member.${member.id}',
        child: CheckboxListTile(
            value: excluded || _selected.contains(member.id),
            onChanged: excluded || _submitting
                ? null
                : (selected) {
                    if (selected == true &&
                        _selected.length + _excluded.length >= 9) {
                      AppToast.show('通话最多支持9人');
                      return;
                    }
                    setState(() {
                      if (selected == true) {
                        _selected.add(member.id);
                      } else {
                        _selected.remove(member.id);
                      }
                    });
                  },
            title:
                Text(member.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            secondary: AppUserAvatar(
                userId: member.id,
                name: member.name,
                url: member.avatarUrl,
                size: 40),
            controlAffinity: ListTileControlAffinity.leading));
  }

  /// 顺序获取全部分页，并防止异常游标重复造成无限循环。
  Future<void> _loadMembers() async {
    final seen = <String>{};
    final loaded = <String, _InviteMember>{};
    var cursor = '0';
    try {
      do {
        if (!seen.add(cursor)) throw StateError('重复分页游标');
        final result = await TencentImSDKPlugin.v2TIMManager
            .getGroupManager()
            .getGroupMemberList(
                groupID: _groupId,
                filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
                nextSeq: cursor);
        if (!mounted || !_sameCall) return;
        if (result.code != 0 || result.data == null) {
          throw StateError('读取群成员失败');
        }
        for (final info in result.data!.memberInfoList ?? []) {
          if (info == null || info.userID.isEmpty) continue;
          final remark = info.friendRemark ?? '';
          final name = info.nickName ?? '';
          loaded[info.userID] = _InviteMember(
              info.userID,
              remark.isNotEmpty
                  ? remark
                  : name.isNotEmpty
                      ? name
                      : info.userID,
              info.faceUrl ?? '');
        }
        cursor = result.data!.nextSeq ?? '0';
      } while (cursor != '0');
      if (mounted) {
        setState(() {
          _members.addAll(loaded.values);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '群成员加载失败，请返回后重试';
        });
      }
    }
  }

  /// 点击时重新过滤已入场成员，只有 SDK 邀请成功后才返回通话。
  Future<void> _invite() async {
    if (_submitting || !_sameCall) return;
    setState(() => _submitting = true);
    try {
      final ids = _selected.where((id) => !_excluded.contains(id)).toList();
      final result =
          await CallManager.instance.invite(ids, expectedCallId: _callId);
      if (!mounted || !_sameCall) return;
      if (result.errorCode == 0) {
        _goBack();
      } else {
        AppToast.show('邀请失败（${result.errorCode}），请重试');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 群与场次同时一致才接受迟到的加载结果或提交。
  bool get _sameCall =>
      CallStore.shared.state.activeCall.value.callId == _callId &&
      CallStore.shared.state.activeCall.value.chatGroupId == _groupId;

  void _goBack() => widget.callbacks?.onShowCalling?.call();
}

/// 回退选人列表所需的腾讯基础资料，不猜测机构、岗位或职级。
class _InviteMember {
  const _InviteMember(this.id, this.name, this.avatarUrl);

  /// 腾讯用户标识。
  final String id;

  /// 备注优先的显示姓名。
  final String name;

  /// SDK 头像地址。
  final String avatarUrl;
}
