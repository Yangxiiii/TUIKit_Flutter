import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart' hide SearchBar, IconButton;
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/contact_list/pages/start_c2c_chat.dart';
import 'package:tencent_chat_uikit/src/contact_list/pages/start_group_chat.dart';
import 'package:tencent_chat_uikit/src/search/search_bar.dart';

import 'chat_page.dart';

const String startC2CChatMenuString = "startC2CChat";
const String startGroupChatMenuString = "startGroupChat";

class ConversationsPage extends StatefulWidget {
  final VoidCallback? onBackPressed;

  const ConversationsPage({
    super.key,
    this.onBackPressed,
  });

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  late SemanticColorScheme colorsTheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorsTheme = SemanticColorScheme.of(context);
  }

  void _startC2CChat() {
    context.pushChatUIKitPage(
      StartC2CChat(
        onSelect: (AZOrderedListItem item) {
          ContactInfo contactInfo = item.extraData;
          final conversation = ConversationInfo(
            conversationID: 'c2c_${contactInfo.userID}',
            title: contactInfo.nickname,
            avatarURL: contactInfo.avatarURL,
            type: ConversationType.c2c,
          );
          context.pushChatUIKitPage(ChatPage(conversation: conversation));
        },
      ),
    );
  }

  void _startGroupChat() {
    context.pushChatUIKitPage(
      StartGroupChat(
        onGroupCreated: (String groupID, String groupName, String? avatar) {
          final conversation = ConversationInfo(
            conversationID: 'group_$groupID',
            title: groupName,
            avatarURL: avatar,
            type: ConversationType.group,
          );

          context.pushChatUIKitPage(ChatPage(conversation: conversation));
        },
      ),
    );
  }

  void _onSelectContact(FriendSearchInfo friendSearchInfo) {
    final displayName = friendSearchInfo.friendRemark?.isNotEmpty == true
        ? friendSearchInfo.friendRemark!
        : (friendSearchInfo.userInfo?.nickname?.isNotEmpty == true
            ? friendSearchInfo.userInfo!.nickname!
            : friendSearchInfo.userID);
    final conversation = ConversationInfo(
      conversationID: 'c2c_${friendSearchInfo.userID}',
      title: displayName,
      avatarURL: friendSearchInfo.userInfo?.avatarURL,
      type: ConversationType.c2c,
    );
    context.pushChatUIKitPage(ChatPage(conversation: conversation));
  }

  void _onSelectGroup(GroupSearchInfo groupSearchInfo) {
    final conversation = ConversationInfo(
      conversationID: 'group_${groupSearchInfo.groupID}',
      title: (groupSearchInfo.groupName?.isNotEmpty == true)
          ? groupSearchInfo.groupName!
          : groupSearchInfo.groupID,
      avatarURL: groupSearchInfo.groupAvatarURL,
      type: ConversationType.group,
    );
    context.pushChatUIKitPage(ChatPage(conversation: conversation));
  }

  void _onSelectConversation(MessageSearchResultItem messageSearchResultItem) {
    final conversation = ConversationInfo(
      conversationID: messageSearchResultItem.conversationID,
      title: messageSearchResultItem.conversationShowName,
      avatarURL: messageSearchResultItem.conversationAvatarURL,
      type: messageSearchResultItem.conversationID.startsWith('c2c_')
          ? ConversationType.c2c
          : ConversationType.group,
    );
    context.pushChatUIKitPage(ChatPage(conversation: conversation));
  }

  void _onSelectMessage(MessageInfo messageInfo) async {
    // 搜索结果只携带消息对象，需要先按会话类型还原 SDK 会话 ID。
    final conversationID = messageInfo.conversationType ==
            ConversationType.group
        ? 'group_${messageInfo.to}'
        : 'c2c_${messageInfo.to.isNotEmpty ? messageInfo.to : messageInfo.from.userID}';

    // 优先读取完整会话资料，查询不到时再用消息发送方信息补齐页面标题和头像。
    ConversationListStore conversationListStore =
        ConversationListStore.create();
    final convResult = await conversationListStore.getConversationInfo(
        conversationID: conversationID);
    ConversationInfo conversation = convResult.conversationInfo ??
        ConversationInfo(
          conversationID: conversationID,
          title: messageInfo.from.nickname ?? messageInfo.from.userID,
          avatarURL: messageInfo.from.avatarURL,
          type: conversationID.startsWith('c2c_')
              ? ConversationType.c2c
              : ConversationType.group,
        );

    if (mounted) {
      context.pushChatUIKitPage(
        ChatPage(
          conversation: conversation,
          message: messageInfo,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorsTheme.bgColorOperate,
      appBar: AppBar(
        backgroundColor: colorsTheme.bgColorOperate,
        automaticallyImplyLeading: false,
        leading: widget.onBackPressed != null
            ? IconButton.buttonContent(
                content: IconOnlyContent(Icon(Icons.arrow_back_ios,
                    color: colorsTheme.buttonColorPrimaryDefault)),
                type: ButtonType.noBorder,
                size: ButtonSize.l,
                onClick: widget.onBackPressed,
              )
            : null,
        title: Text(AppLocalization.text(context, LocaleKeys.chat_title, '聊天'),
            style: FontScheme.title3Medium
                .copyWith(color: colorsTheme.textColorPrimary)),
        centerTitle: false,
        scrolledUnderElevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.create_outlined,
                color: colorsTheme.textColorPrimary),
            offset: const Offset(0, 40),
            padding: EdgeInsets.zero,
            color: colorsTheme.bgColorDialog,
            onSelected: (String result) {
              switch (result) {
                case startC2CChatMenuString:
                  _startC2CChat();
                  break;
                case startGroupChatMenuString:
                  _startGroupChat();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: startC2CChatMenuString,
                padding: EdgeInsets.zero,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_outlined,
                        color: colorsTheme.textColorPrimary),
                    const SizedBox(width: 8),
                    Text(
                        AppLocalization.text(
                            context, LocaleKeys.chat_startConversation, '发起会话'),
                        style: TextStyle(color: colorsTheme.textColorPrimary)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: startGroupChatMenuString,
                padding: EdgeInsets.zero,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.group_add_outlined,
                        color: colorsTheme.textColorPrimary),
                    const SizedBox(width: 8),
                    Text(
                        AppLocalization.text(
                            context, LocaleKeys.chat_createGroupChat, '创建群聊'),
                        style: TextStyle(color: colorsTheme.textColorPrimary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!AppBuilder.getInstance().searchConfig.hideSearch)
            SearchBar(
              onContactSelect: _onSelectContact,
              onGroupSelect: _onSelectGroup,
              onConversationSelect: _onSelectConversation,
              onMessageSelect: _onSelectMessage,
            ),
          Expanded(
            child: ConversationList(
              onConversationClick: (conversation) {
                context.pushChatUIKitPage(
                  ChatPage(conversation: conversation),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
