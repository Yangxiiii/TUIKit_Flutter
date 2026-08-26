import 'package:app_ui/app_ui.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:flutter/material.dart' hide AlertDialog;

typedef OnSendMessageClick = void Function({String? userID, String? groupID});

class C2CChatSetting extends StatefulWidget {
  final String userID;

  final VoidCallback? onContactDelete;
  final OnSendMessageClick? onSendMessageClick;

  const C2CChatSetting({
    super.key,
    required this.userID,
    this.onContactDelete,
    this.onSendMessageClick,
  });

  @override
  State<C2CChatSetting> createState() => _C2CChatSettingState();
}

class _C2CChatSettingState extends State<C2CChatSetting> {
  final ContactStore _contactStore = ContactStore.shared;
  late ConversationListStore _conversationListStore;
  late SemanticColorScheme colorsTheme;
  late AppLocalizedText atomicLocale;
  late String conversationID;

  ContactInfo? _contactInfo;
  bool _isNotDisturb = false;
  bool _isPinned = false;
  bool _isInBlacklist = false;

  @override
  void initState() {
    super.initState();
    conversationID = c2cConversationIDPrefix + widget.userID;
    _conversationListStore = ConversationListStore.create();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorsTheme = SemanticColorScheme.of(context);
    atomicLocale = AppLocalization.of(context);
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadContactInfo(),
      _loadConversationInfo(),
      _loadBlacklistStatus(),
    ]);
  }

  Future<void> _loadContactInfo() async {
    final handler =
        await _contactStore.getContactInfo(userIDList: [widget.userID]);
    if (handler.isSuccess && handler.contactInfoList.isNotEmpty && mounted) {
      setState(() {
        _contactInfo = handler.contactInfoList.first;
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

  Future<void> _loadBlacklistStatus() async {
    await _contactStore.loadBlackList();
    if (mounted) {
      final blackList = _contactStore.state.blackList.value;
      setState(() {
        _isInBlacklist = blackList.any((c) => c.userID == widget.userID);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorsTheme.bgColorOperate,
      appBar: SettingWidgets.buildAppBar(
        context: context,
        title: atomicLocale.contactInfo,
      ),
      body: _contactInfo == null
          ? Center(
              child: CircularProgressIndicator(
                  color: colorsTheme.textColorSecondary))
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildUserProfile(),
                  const SizedBox(height: 24),
                  _buildActionButtons(),
                  const SizedBox(height: 24),
                  _buildSettingsSection(),
                  const SizedBox(height: 24),
                  _buildDangerousActions(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildUserProfile() {
    final nickname = _contactInfo?.nickname ?? '';
    final avatarURL = _contactInfo?.avatarURL ?? '';
    return Column(
      children: [
        Avatar(
          content: AvatarImageContent(url: avatarURL, name: nickname),
          size: AvatarSize.xl,
        ),
        const SizedBox(height: 16),
        Text(
          nickname.isNotEmpty ? nickname : widget.userID,
          style: FontScheme.body2Medium.copyWith(
            color: colorsTheme.textColorPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          SettingWidgets.buildActionButton(
            context: context,
            icon: Icons.message,
            label: atomicLocale.sendMessage,
            onTap: _navigateToMessageList,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    final remark = _contactInfo?.friendRemark ?? '';
    return SettingWidgets.buildSettingGroup(
      context: context,
      children: [
        _buildRemarkRow(remark),
        SettingWidgets.buildDivider(context),
        SettingWidgets.buildSettingRow(
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
        ),
        SettingWidgets.buildDivider(context),
        SettingWidgets.buildSettingRow(
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
        ),
        SettingWidgets.buildDivider(context),
        SettingWidgets.buildSettingRow(
          context: context,
          title: atomicLocale.profileBlack,
          value: _isInBlacklist,
          onChanged: (value) async {
            CompletionHandler result;
            if (value) {
              result =
                  await _contactStore.addToBlacklist(userID: widget.userID);
            } else {
              result = await _contactStore.removeFromBlacklist(
                  userID: widget.userID);
            }
            if (result.errorCode == 0) {
              setState(() {
                _isInBlacklist = value;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildRemarkRow(String remark) {
    return GestureDetector(
      onTap: _showRemarkEditDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              atomicLocale.profileRemark,
              style: FontScheme.caption1Regular.copyWith(
                color: colorsTheme.textColorPrimary,
              ),
            ),
            Expanded(
              child: Text(
                remark.isNotEmpty ? remark : '',
                textAlign: TextAlign.right,
                style: FontScheme.caption1Regular.copyWith(
                  color: colorsTheme.textColorPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: colorsTheme.scrollbarColorHover,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerousActions() {
    return SettingWidgets.buildSettingGroup(
      context: context,
      children: [
        SettingWidgets.buildDangerousActionRow(
          context: context,
          title: atomicLocale.clearMessage,
          onTap: () {
            _showConfirmDialog(
              title: atomicLocale.clearMessage,
              content: atomicLocale.clearMsgTip,
              onConfirm: () async {
                await _conversationListStore.clearConversationMessages(
                    conversationID: conversationID);
              },
            );
          },
        ),
        SettingWidgets.buildDivider(context),
        if (!_isInBlacklist)
          SettingWidgets.buildDangerousActionRow(
            context: context,
            title: atomicLocale.deleteFriend,
            onTap: () {
              _showConfirmDialog(
                title: atomicLocale.deleteFriend,
                content: atomicLocale.deleteFriendTip,
                onConfirm: () async {
                  final result =
                      await _contactStore.deleteFriend(userID: widget.userID);
                  if (result.errorCode == 0) {
                    _conversationListStore.deleteConversation(
                        conversationID: conversationID);
                    if (mounted) Navigator.of(context).pop();
                    widget.onContactDelete?.call();
                  }
                },
              );
            },
          ),
      ],
    );
  }

  void _showRemarkEditDialog() {
    final TextEditingController controller =
        TextEditingController(text: _contactInfo?.friendRemark ?? '');

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colorsTheme.bgColorDialog,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    atomicLocale.remarkEdit,
                    style: FontScheme.caption1Medium.copyWith(
                      color: colorsTheme.textColorPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: colorsTheme.bgColorInput,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    autofocus: true,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor:
                              colorsTheme.buttonColorSecondaryDefault,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          atomicLocale.cancel,
                          style: FontScheme.caption1Regular
                              .copyWith(color: colorsTheme.textColorPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final newRemark = controller.text.trim();
                          Navigator.of(context).pop();

                          final result = await _contactStore.setFriendRemark(
                            userID: widget.userID,
                            remark: newRemark,
                          );
                          if (result.errorCode == 0) {
                            _loadContactInfo();
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor:
                              colorsTheme.buttonColorPrimaryDefault,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          atomicLocale.confirm,
                          style: FontScheme.caption1Medium.copyWith(
                            color: colorsTheme.textColorButton,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
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

  void _navigateToMessageList() {
    widget.onSendMessageClick?.call(userID: widget.userID);
  }
}
