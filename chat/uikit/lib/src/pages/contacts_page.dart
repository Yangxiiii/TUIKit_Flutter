import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart' hide IconButton;
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/contact_list/pages/add_friend.dart';
import 'package:tencent_chat_uikit/src/contact_list/pages/add_group.dart';

const String addFriendMenuString = "addFriend";
const String addGroupMenuString = "addGroup";

class ContactsPage extends StatelessWidget {
  final VoidCallback? onBackPressed;

  const ContactsPage({
    super.key,
    this.onBackPressed,
  });

  void _onSendMessageClick(BuildContext context,
      {String? userID, String? groupID}) async {
    ConversationInfo conversation;
    ConversationListStore conversationListStore =
        ConversationListStore.create();
    if (userID != null) {
      String conversationID = '$c2cConversationIDPrefix$userID';
      final convResult = await conversationListStore.getConversationInfo(
          conversationID: conversationID);
      conversation = convResult.conversationInfo ??
          ConversationInfo(
            conversationID: conversationID,
            title: userID,
            type: ConversationType.c2c,
          );
    } else if (groupID != null) {
      String conversationID = '$groupConversationIDPrefix$groupID';
      final convResult = await conversationListStore.getConversationInfo(
          conversationID: conversationID);
      conversation = convResult.conversationInfo ??
          ConversationInfo(
            conversationID: conversationID,
            title: groupID,
            type: ConversationType.group,
          );
    } else {
      return;
    }

    if (context.mounted) {
      context.pushChatUIKitPage(
        ChatPage(
          conversation: conversation,
        ),
      );
    }
  }

  void _onGroupClick(BuildContext context, ContactInfo contactInfo) {
    ConversationInfo conversationInfo = ConversationInfo(
      conversationID: 'group_${contactInfo.userID}',
      type: ConversationType.group,
      avatarURL: contactInfo.avatarURL,
      title: contactInfo.nickname,
    );
    context.pushChatUIKitPage(
      ChatPage(
        conversation: conversationInfo,
      ),
    );
  }

  void _onContactClick(BuildContext context, ContactInfo contactInfo) {
    context.pushChatUIKitPage<void>(
      C2CChatSetting(
        userID: contactInfo.userID,
        onSendMessageClick: ({String? userID, String? groupID}) {
          _onSendMessageClick(context, userID: userID);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SemanticColorScheme colorsScheme = SemanticColorScheme.of(context);
    return Scaffold(
      backgroundColor: colorsScheme.bgColorOperate,
      appBar: AppBar(
        backgroundColor: colorsScheme.bgColorOperate,
        automaticallyImplyLeading: false,
        leading: onBackPressed != null
            ? IconButton.buttonContent(
                content: IconOnlyContent(Icon(Icons.arrow_back_ios,
                    color: colorsScheme.buttonColorPrimaryDefault)),
                type: ButtonType.noBorder,
                size: ButtonSize.l,
                onClick: onBackPressed,
              )
            : null,
        title: Text(
            AppLocalization.text(context, LocaleKeys.chat_contacts, '联系人'),
            style: FontScheme.title3Medium
                .copyWith(color: colorsScheme.textColorPrimary)),
        centerTitle: false,
        scrolledUnderElevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.add, color: colorsScheme.textColorPrimary),
            offset: const Offset(0, 40),
            color: colorsScheme.bgColorDialog,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: addFriendMenuString,
                padding: EdgeInsets.zero,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_add,
                        color: colorsScheme.textColorPrimary),
                    const SizedBox(width: 8),
                    Text(
                        AppLocalization.text(
                            context, LocaleKeys.chat_addFriend, '添加好友'),
                        style: TextStyle(color: colorsScheme.textColorPrimary)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                padding: EdgeInsets.zero,
                value: addGroupMenuString,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.group_add, color: colorsScheme.textColorPrimary),
                    const SizedBox(width: 8),
                    Text(
                        AppLocalization.text(
                            context, LocaleKeys.chat_addGroup, '添加群组'),
                        style: TextStyle(color: colorsScheme.textColorPrimary)),
                  ],
                ),
              ),
            ],
            onSelected: (String value) {
              switch (value) {
                case addFriendMenuString:
                  context.pushChatUIKitPage(const AddFriend());
                  break;
                case addGroupMenuString:
                  context.pushChatUIKitPage(const AddGroup());
                  break;
              }
            },
          ),
        ],
      ),
      body: ContactList(
        onGroupClick: (ContactInfo contactInfo) {
          _onGroupClick(context, contactInfo);
        },
        onContactClick: (ContactInfo contactInfo) {
          _onContactClick(context, contactInfo);
        },
      ),
    );
  }
}
