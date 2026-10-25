import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

/// 复用单聊或群聊设置，并按当前会话决定返回聊天页还是新建聊天页。
class ChatSettingPage extends StatelessWidget {
  /// 设置操作所属的单聊或群聊。
  final ConversationInfo conversation;

  /// 进入设置前的聊天会话，用于避免重复打开同一聊天页。
  final ConversationInfo conversationOfChatPage;

  /// 联系人或群组被删除时由宿主关闭原聊天页。
  final VoidCallback? onDestroyCallback;

  const ChatSettingPage({
    super.key,
    required this.conversation,
    required this.conversationOfChatPage,
    this.onDestroyCallback,
  });

  /// 从设置中的联系入口打开会话，优先使用SDK会话信息并复用已打开的聊天页。
  void _onSendMessageClick(
      {required BuildContext context, String? userID, String? groupID}) async {
    ConversationListStore conversationListStore =
        ConversationListStore.create();
    ConversationInfo conversation;
    // 单聊和群聊使用SDK各自的会话前缀，不将两种标识混用。
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

    // 查询后页面可能已关闭；相同会话只返回，避免聊天路由叠加。
    if (context.mounted) {
      if (conversationOfChatPage.conversationID ==
          conversation.conversationID) {
        context.popChatUIKitPage();
      } else {
        context.pushChatUIKitPage(
          ChatPage(
            conversation: conversation,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (conversation.type == ConversationType.c2c) {
      String userID = conversation.conversationID;
      if (userID.startsWith('c2c_')) {
        userID = userID.substring(4);
      }

      return C2CChatSetting(
        userID: userID,
        onContactDelete: onDestroyCallback,
        onSendMessageClick: ({String? userID, String? groupID}) {
          _onSendMessageClick(context: context, userID: userID);
        },
      );
    } else if (conversation.type == ConversationType.group) {
      String groupID = conversation.conversationID;
      if (groupID.startsWith('group_')) {
        groupID = groupID.substring(6);
      }

      return GroupChatSetting(
        groupID: groupID,
        onGroupDelete: onDestroyCallback,
        onSendMessageClick: ({String? userID, String? groupID}) {
          _onSendMessageClick(
              context: context, userID: userID, groupID: groupID);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('')),
      body: Container(),
    );
  }
}
