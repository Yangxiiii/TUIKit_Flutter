import 'package:app_ui/app_ui.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:tencent_chat_uikit/src/navigation/chat_uikit_navigation.dart';
import 'package:flutter/material.dart' hide AlertDialog;
import 'package:flutter_svg/svg.dart';

import '../widgets/setting_widgets.dart';
import 'c2c_chat_setting.dart';
import 'choose_group_avatar.dart';
import 'group_add_member.dart';
import 'group_management.dart';
import 'group_member_list.dart';
import 'group_notice.dart';
import 'group_permission_manager.dart';
import 'group_transfer_owner.dart';

enum GroupMethodType {
  join,
  invite,
}

class MethodSheetConfig {
  final String forbidText;
  final String authText;
  final String anyText;

  MethodSheetConfig({
    required this.forbidText,
    required this.authText,
    required this.anyText,
  });
}

class GroupChatSetting extends StatefulWidget {
  final String groupID;
  final VoidCallback? onGroupDelete;
  final OnSendMessageClick? onSendMessageClick;

  const GroupChatSetting({
    super.key,
    required this.groupID,
    this.onGroupDelete,
    this.onSendMessageClick,
  });

  @override
  State<GroupChatSetting> createState() => _GroupChatSettingState();
}

class _GroupChatSettingState extends State<GroupChatSetting> {
  late GroupMemberStore _memberStore;
  late ConversationListStore _conversationListStore;
  late SemanticColorScheme colorsTheme;
  late AppLocalizedText atomicLocale;
  late String conversationID;

  GroupInfo? _groupInfo;
  bool _isNotDisturb = false;
  bool _isPinned = false;
  String _selfNameCard = '';
  GroupMemberRole _currentUserRole = GroupMemberRole.member;

  /// True while we're driving an explicit quit / dismiss flow from this page.
  ///
  /// `quitGroup` / `dismissGroup` succeed synchronously and the SDK
  /// immediately mutates `joinedGroupList`, which fires
  /// `_onJoinedGroupListChanged` while `await` is still bouncing back
  /// to `_onDeleteAndQuit` / `_onDismissGroup`. Both code paths then
  /// race to pop ChatSettingPage + ChatPage, ending up popping 4
  /// routes off a 3-route stack and emptying the navigator (black
  /// screen). Set this true before `await`, clear it on failure, and
  /// let the listener short-circuit when it's true — the explicit
  /// flow owns the navigation. External "kicked out / group
  /// dismissed elsewhere" still goes through the listener as before.
  ///
  /// 当我们从这个页面驱动显式退出/解散流程时为 true。
  ///
  /// `quitGroup` / `dismissGroup` 同步成功，SDK 会立即修改 `joinedGroupList`，这会在 `await` 仍在返回 `_onDeleteAndQuit` /
  /// `_onDismissGroup` 时触发 `_onJoinedGroupListChanged`。两个代码路径随后争先恐后地弹出 ChatSettingPage + ChatPage，最终在 3
  /// 路由栈上弹出 4 个路由，使导航器为空（黑屏）。在 `await` 之前设置为 true，失败时清除，并且
  ///
  /// 流程拥有导航。外部“被踢出/群聊在其他地方被解散”仍然会像以前一样通过监听器处理。
  bool _isHandlingPopExplicitly = false;

  @override
  void initState() {
    super.initState();
    conversationID = groupConversationIDPrefix + widget.groupID;
    _memberStore = GroupMemberStore.create(groupID: widget.groupID);
    _conversationListStore = ConversationListStore.create();
    GroupStore.shared.state.joinedGroupList
        .addListener(_onJoinedGroupListChanged);
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorsTheme = SemanticColorScheme.of(context);
    atomicLocale = AppLocalization.of(context);
  }

  @override
  void dispose() {
    GroupStore.shared.state.joinedGroupList
        .removeListener(_onJoinedGroupListChanged);
    super.dispose();
  }

  /// React to changes in the global joinedGroupList. Two cases:
  ///   1. Group still present → sync _groupInfo + _currentUserRole so that
  ///      _hasPermission() recomputes against the latest selfRole.
  ///   2. Group removed (only after we've already loaded once) → it has been
  ///      dismissed / we were kicked / we quit elsewhere. Pop this page.
  ///
  /// 对全局 joinedGroupList 的变化做出反应。有两种情况：1. 群组仍然存在 → 同步 _groupInfo + _currentUserRole，这样 _hasPermission()
  /// 会根据最新的 selfRole 重新计算。2. 群组被移除（只在我们已经加载过一次之后）→ 群组被解散 / 我们被踢 / 我们在其他地方退出。弹出这个页面。
  void _onJoinedGroupListChanged() {
    if (!mounted) return;
    final list = GroupStore.shared.state.joinedGroupList.value;
    GroupInfo? updated;
    for (final g in list) {
      if (g.groupID == widget.groupID) {
        updated = g;
        break;
      }
    }
    if (updated == null) {
      // Skip the auto-pop when our own quit/dismiss handler is already
      // unwinding the stack — see `_isHandlingPopExplicitly`. Without
      // this guard the explicit flow and this listener both pop twice
      // and we drain the navigator empty.
      //
      // 当我们自己的退出/解散处理器已经在回溯堆栈时，跳过自动弹出 — 见 `_isHandlingPopExplicitly`。没有这个保护，显式流程和这个监听器都会弹出两次，导致导航器被清空。
      if (_groupInfo != null && !_isHandlingPopExplicitly) {
        widget.onGroupDelete?.call();
        Navigator.of(context).maybePop();
      }
      return;
    }
    setState(() {
      _groupInfo = updated;
      if (updated?.selfRole != null) {
        _currentUserRole = updated!.selfRole!;
      }
    });
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadGroupInfo(),
      _loadMembers(),
      _loadSelfMemberInfo(),
      _loadConversationInfo(),
    ]);
  }

  Future<void> _loadGroupInfo() async {
    final result =
        await GroupStore.shared.getGroupInfo(groupID: widget.groupID);
    if (result.isSuccess && result.groupInfo != null && mounted) {
      setState(() {
        _groupInfo = result.groupInfo;
      });
    }
  }

  Future<void> _loadMembers() async {
    await _memberStore.loadMembers();
  }

  Future<void> _loadSelfMemberInfo() async {
    final result = await _memberStore.getMemberInfo(
      userIDList: [LoginStore.shared.loginState.loginUserInfo?.userID ?? ''],
    );
    if (result.isSuccess && result.memberInfoList.isNotEmpty && mounted) {
      final selfMember = result.memberInfoList.first;
      setState(() {
        _selfNameCard = selfMember.nameCard ?? '';
        _currentUserRole = selfMember.role;
      });
    }
  }

  Future<void> _loadConversationInfo() async {
    final result = await _conversationListStore.getConversationInfo(
        conversationID: conversationID);
    if (result.isSuccess && result.conversationInfo != null && mounted) {
      final conv = result.conversationInfo!;
      setState(() {
        _isPinned = conv.isPinned;
        _isNotDisturb = conv.receiveOption != ReceiveMessageOption.receive;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorsTheme.bgColorOperate,
      appBar: SettingWidgets.buildAppBar(
        context: context,
        title: atomicLocale.groupDetail,
      ),
      body: _groupInfo == null
          ? Center(
              child: CircularProgressIndicator(
                  color: colorsTheme.textColorSecondary))
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildGroupProfile(),
                  const SizedBox(height: 24),
                  _buildActionButtons(),
                  const SizedBox(height: 24),
                  _buildBasicSettings(),
                  const SizedBox(height: 24),
                  _buildGroupSettings(),
                  const SizedBox(height: 24),
                  _buildGroupRemark(),
                  const SizedBox(height: 24),
                  _buildGroupMembers(),
                  const SizedBox(height: 24),
                  _buildDangerousActions(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildGroupProfile() {
    final groupInfo = _groupInfo!;
    return Column(
      children: [
        GestureDetector(
          onTap: _hasPermission(GroupPermission.setGroupAvatar)
              ? _onAvatarTap
              : null,
          child: Avatar(
            content: AvatarImageContent(
                url: groupInfo.avatarURL ?? '',
                name: groupInfo.groupName ?? ''),
            size: AvatarSize.xl,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  (groupInfo.groupName?.isNotEmpty == true)
                      ? groupInfo.groupName!
                      : widget.groupID,
                  style: FontScheme.body2Medium.copyWith(
                    color: colorsTheme.textColorPrimary,
                  ),
                  textAlign: TextAlign.center,
                  softWrap: true,
                ),
              ),
              if (_hasPermission(GroupPermission.setGroupName))
                const SizedBox(width: 8),
              if (_hasPermission(GroupPermission.setGroupName))
                GestureDetector(
                  onTap: _showGroupNameEditDialog,
                  child: SvgPicture.asset(
                    'chat_assets/icon/name_edit.svg',
                    package: 'tencent_chat_uikit',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'ID: ${widget.groupID}',
          style: FontScheme.caption3Regular.copyWith(
            color: colorsTheme.textColorPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    List<Widget> buttons = [];

    if (_hasPermission(GroupPermission.sendMessage)) {
      buttons.add(_buildActionButton(
        icon: Icons.message,
        label: atomicLocale.sendMessage,
        onTap: _navigateToMessageList,
      ));
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: buttons,
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: colorsTheme.listColorHover,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorsTheme.bgColorOperate,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  color: colorsTheme.buttonColorPrimaryDefault, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: FontScheme.caption1Regular
                  .copyWith(color: colorsTheme.textColorPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicSettings() {
    List<Widget> settings = [];

    if (_hasPermission(GroupPermission.setDoNotDisturb)) {
      settings.add(SettingWidgets.buildSettingRow(
        context: context,
        title: atomicLocale.doNotDisturb,
        value: _isNotDisturb,
        onChanged: (value) async {
          final result = await _conversationListStore.setReceiveMessageOpt(
            conversationID: conversationID,
            opt: value
                ? ReceiveMessageOption.notNotify
                : ReceiveMessageOption.receive,
          );
          if (result.errorCode == 0) {
            setState(() {
              _isNotDisturb = value;
            });
          }
        },
      ));
    }

    if (_hasPermission(GroupPermission.pinGroup)) {
      if (settings.isNotEmpty)
        settings.add(SettingWidgets.buildDivider(context));
      settings.add(SettingWidgets.buildSettingRow(
        context: context,
        title: atomicLocale.pin,
        value: _isPinned,
        onChanged: (value) async {
          final result = await _conversationListStore.pinConversation(
              conversationID: conversationID, pin: value);
          if (result.errorCode == 0) {
            setState(() {
              _isPinned = value;
            });
          }
        },
      ));
    }

    if (settings.isEmpty) return const SizedBox.shrink();

    return SettingWidgets.buildSettingGroup(
        context: context, children: settings);
  }

  Widget _buildGroupSettings() {
    final groupInfo = _groupInfo!;
    List<Widget> settings = [];

    settings.add(SettingWidgets.buildNavigationRow(
      context: context,
      title: atomicLocale.groupOfAnnouncement,
      subtitle: (groupInfo.notification?.isNotEmpty == true)
          ? groupInfo.notification!
          : atomicLocale.groupNoticeEmpty,
      onTap: () => _onGroupNotice(),
    ));

    if (_hasPermission(GroupPermission.setGroupManagement)) {
      settings.add(SettingWidgets.buildDivider(context));
      settings.add(SettingWidgets.buildNavigationRow(
        context: context,
        title: atomicLocale.groupManagement,
        onTap: () => _onGroupManagement(),
      ));
    }

    if (_hasPermission(GroupPermission.getGroupType)) {
      settings.add(SettingWidgets.buildDivider(context));
      settings.add(SettingWidgets.buildInfoRow(
        context: context,
        title: atomicLocale.groupType,
        value: GroupPermissionManager.getGroupTypeDescription(
            groupInfo.groupType ?? GroupType.work, context),
      ));
    }

    settings.add(SettingWidgets.buildDivider(context));
    settings.add(SettingWidgets.buildNavigationRow(
      context: context,
      title: atomicLocale.addGroupWay,
      value: _getJoinOptionText(groupInfo.joinOption ?? GroupJoinOption.forbid),
      onTap: _hasPermission(GroupPermission.setJoinGroupApprovalType)
          ? () => _onJoinGroupMethod()
          : null,
    ));

    settings.add(SettingWidgets.buildDivider(context));
    settings.add(SettingWidgets.buildNavigationRow(
      context: context,
      title: atomicLocale.inviteGroupType,
      value: _getInviteOptionText(
          groupInfo.inviteOption ?? GroupInviteOption.forbid),
      onTap: _hasPermission(GroupPermission.setInviteToGroupApprovalType)
          ? () => _onInviteMethod()
          : null,
    ));

    return SettingWidgets.buildSettingGroup(
        context: context, children: settings);
  }

  Widget _buildGroupRemark() {
    if (!_hasPermission(GroupPermission.setGroupRemark)) {
      return const SizedBox.shrink();
    }

    return SettingWidgets.buildSettingGroup(
      context: context,
      children: [
        SettingWidgets.buildNavigationRow(
          context: context,
          title: atomicLocale.myAliasInGroup,
          value: _selfNameCard,
          onTap: () => _onGroupRemark(),
        ),
      ],
    );
  }

  Widget _buildGroupMembers() {
    final groupInfo = _groupInfo!;
    List<Widget> memberWidgets = [];

    memberWidgets.add(SettingWidgets.buildNavigationRow(
      context: context,
      title: '${atomicLocale.groupMember} (${groupInfo.memberCount ?? 0})',
      onTap: _hasPermission(GroupPermission.getGroupMemberList)
          ? () => _onGroupMemberList()
          : null,
    ));

    if (_hasPermission(GroupPermission.addGroupMember) &&
        (groupInfo.inviteOption ?? GroupInviteOption.forbid) !=
            GroupInviteOption.forbid) {
      memberWidgets.add(SettingWidgets.buildDivider(context));
      memberWidgets.add(SettingWidgets.buildActionRow(
        context: context,
        icon: Icons.add,
        title: atomicLocale.addMembers,
        onTap: () => _onAddMembers(),
      ));
    }

    // Show first 3 members
    //
    // 显示前 3 个成员
    return ValueListenableBuilder<List<GroupMember>>(
      valueListenable: _memberStore.state.memberList,
      builder: (context, members, child) {
        final displayMembers = members.take(3).toList();
        List<Widget> allWidgets = List.from(memberWidgets);
        for (int i = 0; i < displayMembers.length; i++) {
          allWidgets.add(SettingWidgets.buildDivider(context));
          allWidgets.add(_buildMemberRow(displayMembers[i]));
        }

        return SettingWidgets.buildSettingGroup(
            context: context, children: allWidgets);
      },
    );
  }

  Widget _buildDangerousActions() {
    List<Widget> actions = [];

    if (_hasPermission(GroupPermission.clearHistoryMessages)) {
      actions.add(SettingWidgets.buildDangerousActionRow(
        context: context,
        title: atomicLocale.clearMessage,
        onTap: () => _onClearHistory(),
      ));
    }

    if (_hasPermission(GroupPermission.deleteAndQuit)) {
      if (actions.isNotEmpty) actions.add(SettingWidgets.buildDivider(context));
      actions.add(SettingWidgets.buildDangerousActionRow(
        context: context,
        title: atomicLocale.quitGroup,
        onTap: () => _onDeleteAndQuit(),
      ));
    }

    if (_hasPermission(GroupPermission.transferOwner)) {
      if (actions.isNotEmpty) actions.add(SettingWidgets.buildDivider(context));
      actions.add(SettingWidgets.buildDangerousActionRow(
        context: context,
        title: atomicLocale.transferGroupOwner,
        onTap: () => _onTransferOwner(),
      ));
    }

    if (_hasPermission(GroupPermission.dismissGroup)) {
      if (actions.isNotEmpty) actions.add(SettingWidgets.buildDivider(context));
      actions.add(SettingWidgets.buildDangerousActionRow(
        context: context,
        title: atomicLocale.dismissGroup,
        onTap: () => _onDismissGroup(),
      ));
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return SettingWidgets.buildSettingGroup(
        context: context, children: actions);
  }

  Widget _buildMemberRow(GroupMember member) {
    return GestureDetector(
      onTap: _hasPermission(GroupPermission.getGroupMemberInfo)
          ? () => _onMemberInfo(member)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Avatar.image(
              url: member.avatarURL,
              name: UIKitUtil.memberDisplayName(member),
              size: AvatarSize.m,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                UIKitUtil.memberDisplayName(member),
                style: FontScheme.caption1Regular
                    .copyWith(color: colorsTheme.textColorPrimary),
              ),
            ),
            if (member.role != GroupMemberRole.member)
              Text(
                GroupPermissionManager.getMemberRoleDescription(
                    member.role, context),
                style: FontScheme.caption1Regular
                    .copyWith(color: colorsTheme.textColorSecondary),
              ),
            if (_hasPermission(GroupPermission.getGroupMemberInfo))
              const SizedBox(width: 8),
            if (_hasPermission(GroupPermission.getGroupMemberInfo))
              SvgPicture.asset(
                'chat_assets/icon/chevron_right.svg',
                package: 'tencent_chat_uikit',
                width: 12,
                height: 24,
                colorFilter: ColorFilter.mode(
                    colorsTheme.textColorPrimary, BlendMode.srcIn),
              ),
          ],
        ),
      ),
    );
  }

  bool _hasPermission(GroupPermission permission) {
    return GroupPermissionManager.hasPermission(
      groupType: _groupInfo?.groupType ?? GroupType.work,
      memberRole: _currentUserRole,
      permission: permission,
    );
  }

  void _onAvatarTap() async {
    final result = await context.pushChatUIKitPage<String>(
      ChooseGroupAvatar(
        groupID: widget.groupID,
        groupType: (_groupInfo?.groupType ?? GroupType.work).toString(),
        selectedAvatarURL: _groupInfo?.avatarURL ?? '',
      ),
    );
    if (result != null && result.isNotEmpty) {
      final updatedGroupInfo =
          GroupInfo(groupID: widget.groupID, avatarURL: result);
      // UI refresh is driven by GroupStore.joinedGroupList listener
      // (see _onJoinedGroupListChanged); no manual reload needed here.
      //
      // UI 刷新由 GroupStore.joinedGroupList 的监听器驱动（见 _onJoinedGroupListChanged）；这里不需要手动重新加载。
      await GroupStore.shared.updateProfile(groupInfo: updatedGroupInfo);
    }
  }

  void _onGroupNotice() {
    context.pushChatUIKitPage<void>(
      GroupNotice(
        groupID: widget.groupID,
        groupInfo: _groupInfo!,
        currentUserRole: _currentUserRole,
      ),
    );
  }

  void _onGroupManagement() {
    context.pushChatUIKitPage<void>(
      GroupManagement(
        groupID: widget.groupID,
        memberStore: _memberStore,
      ),
    );
  }

  void _onJoinGroupMethod() {
    _showGroupMethodSheet(
      type: GroupMethodType.join,
      onSelected: (option) async {
        // UI refresh is driven by GroupStore.joinedGroupList listener.
        //
        // UI 刷新由 GroupStore.joinedGroupList 的监听器驱动。
        await GroupStore.shared
            .setJoinOption(groupID: widget.groupID, option: option);
      },
    );
  }

  void _onInviteMethod() {
    final config = _getMethodSheetConfig(GroupMethodType.invite);
    // UI refresh after each setInviteOption is driven by
    // GroupStore.joinedGroupList listener (_onJoinedGroupListChanged).
    //
    // 每次 setInviteOption 后的 UI 刷新是由 GroupStore.joinedGroupList 监听器 (_onJoinedGroupListChanged) 驱动的。
    ActionSheet.show(
      context,
      actions: [
        ActionSheetItem(
          title: config.forbidText,
          onTap: () => GroupStore.shared.setInviteOption(
            groupID: widget.groupID,
            option: GroupInviteOption.forbid,
          ),
        ),
        ActionSheetItem(
          title: config.authText,
          onTap: () => GroupStore.shared.setInviteOption(
            groupID: widget.groupID,
            option: GroupInviteOption.auth,
          ),
        ),
        ActionSheetItem(
          title: config.anyText,
          onTap: () => GroupStore.shared.setInviteOption(
            groupID: widget.groupID,
            option: GroupInviteOption.any,
          ),
        ),
      ],
    );
  }

  void _onGroupRemark() async {
    final result = await BottomInputSheet.show(
      context,
      title: atomicLocale.modifyGroupNickname,
      hintText: '',
      initialText: _selfNameCard,
    );

    if (result != null) {
      final updateResult = await _memberStore.setSelfNameCard(nameCard: result);
      if (updateResult.errorCode == 0) {
        setState(() {
          _selfNameCard = result;
        });
      }
    }
  }

  void _showGroupMethodSheet({
    required GroupMethodType type,
    required void Function(GroupJoinOption) onSelected,
  }) {
    final config = _getMethodSheetConfig(type);

    ActionSheet.show(
      context,
      actions: [
        ActionSheetItem(
            title: config.forbidText,
            onTap: () => onSelected(GroupJoinOption.forbid)),
        ActionSheetItem(
            title: config.authText,
            onTap: () => onSelected(GroupJoinOption.auth)),
        ActionSheetItem(
            title: config.anyText,
            onTap: () => onSelected(GroupJoinOption.any)),
      ],
    );
  }

  MethodSheetConfig _getMethodSheetConfig(GroupMethodType type) {
    switch (type) {
      case GroupMethodType.join:
        return MethodSheetConfig(
          forbidText: atomicLocale.groupAddForbid,
          authText: atomicLocale.groupAddAuth,
          anyText: atomicLocale.groupAddAny,
        );
      case GroupMethodType.invite:
        return MethodSheetConfig(
          forbidText: atomicLocale.groupInviteForbid,
          authText: atomicLocale.groupAddAuth,
          anyText: atomicLocale.groupAddAny,
        );
    }
  }

  void _onGroupMemberList() {
    context.pushChatUIKitPage<void>(
      GroupMemberList(
        groupID: widget.groupID,
        memberStore: _memberStore,
        groupInfo: _groupInfo!,
        currentUserRole: _currentUserRole,
        onSendMessageClick: widget.onSendMessageClick,
      ),
    );
  }

  void _onAddMembers() {
    context.pushChatUIKitPage<void>(
      GroupAddMember(
        groupID: widget.groupID,
        memberStore: _memberStore,
      ),
    );
  }

  void _onMemberInfo(GroupMember member) {
    context.pushChatUIKitPage<void>(
      C2CChatSetting(
        userID: member.userID,
        onSendMessageClick: widget.onSendMessageClick,
      ),
    );
  }

  void _onClearHistory() {
    _showConfirmDialog(
      title: atomicLocale.clearMessage,
      content: atomicLocale.clearMsgTip,
      onConfirm: () async {
        await _conversationListStore.clearConversationMessages(
            conversationID: conversationID);
      },
    );
  }

  void _onDeleteAndQuit() {
    _showConfirmDialog(
      title: atomicLocale.quitGroup,
      content: atomicLocale.quitGroupTip,
      onConfirm: () async {
        _isHandlingPopExplicitly = true;
        final result =
            await GroupStore.shared.quitGroup(groupID: widget.groupID);
        if (result.errorCode == 0) {
          _conversationListStore.deleteConversation(
              conversationID: conversationID);
          if (mounted) Navigator.of(context).pop();
          widget.onGroupDelete?.call();
        } else {
          _isHandlingPopExplicitly = false;
        }
      },
    );
  }

  void _onTransferOwner() {
    context.pushChatUIKitPage<void>(
      GroupTransferOwner(
        groupID: widget.groupID,
        memberStore: _memberStore,
      ),
    );
  }

  void _onDismissGroup() {
    _showConfirmDialog(
      title: atomicLocale.dismissGroup,
      content: atomicLocale.dismissGroupTip,
      onConfirm: () async {
        _isHandlingPopExplicitly = true;
        final result =
            await GroupStore.shared.dismissGroup(groupID: widget.groupID);
        if (result.errorCode == 0) {
          _conversationListStore.deleteConversation(
              conversationID: conversationID);
          if (mounted) Navigator.of(context).pop();
          widget.onGroupDelete?.call();
        } else {
          _isHandlingPopExplicitly = false;
        }
      },
    );
  }

  void _showConfirmDialog({
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) {
    final locale = AppLocalization.of(context);
    AtomicAlertDialog.showWithConfig(
      context,
      config: AlertDialogConfig(
        title: title,
        content: content,
        cancelConfig: ButtonConfig(text: locale.cancel),
        confirmConfig: ButtonConfig(
          text: locale.confirm,
          type: TextColorPreset.red,
          onClick: onConfirm,
        ),
      ),
    );
  }

  void _showGroupNameEditDialog() async {
    final result = await BottomInputSheet.show(
      context,
      title: atomicLocale.modifyGroupName,
      hintText: '',
      initialText: _groupInfo?.groupName ?? '',
    );

    if (result != null) {
      final updatedGroupInfo =
          GroupInfo(groupID: widget.groupID, groupName: result);
      // UI refresh is driven by GroupStore.joinedGroupList listener.
      //
      // UI 刷新是由 GroupStore.joinedGroupList 监听器驱动的。
      await GroupStore.shared.updateProfile(groupInfo: updatedGroupInfo);
    }
  }

  void _navigateToMessageList() {
    widget.onSendMessageClick?.call(groupID: widget.groupID);
  }

  String _getJoinOptionText(GroupJoinOption option) {
    switch (option) {
      case GroupJoinOption.forbid:
        return atomicLocale.groupAddForbid;
      case GroupJoinOption.auth:
        return atomicLocale.groupAddAuth;
      case GroupJoinOption.any:
        return atomicLocale.groupAddAny;
    }
  }

  String _getInviteOptionText(GroupInviteOption option) {
    switch (option) {
      case GroupInviteOption.forbid:
        return atomicLocale.groupInviteForbid;
      case GroupInviteOption.auth:
        return atomicLocale.groupAddAuth;
      case GroupInviteOption.any:
        return atomicLocale.groupAddAny;
    }
  }
}
