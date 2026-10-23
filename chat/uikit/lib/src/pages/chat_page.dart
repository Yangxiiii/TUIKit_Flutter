import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart' hide IconButton;
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:tuikit_atomic_x/base_component/utils/tui_event_bus.dart';
import 'package:tencent_chat_uikit/src/contact_list/pages/add_friend.dart';
import 'package:tencent_chat_uikit/src/message_list/listen/listen_playback_bar.dart';

class ChatSettingPage extends StatelessWidget {
  final ConversationInfo conversation;
  final ConversationInfo conversationOfChatPage;
  final VoidCallback? onDestroyCallback;

  const ChatSettingPage({
    super.key,
    required this.conversation,
    required this.conversationOfChatPage,
    this.onDestroyCallback,
  });

  void _onSendMessageClick(
      {required BuildContext context, String? userID, String? groupID}) async {
    ConversationListStore conversationListStore =
        ConversationListStore.create();
    ConversationInfo conversation;
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

/// 展示完整聊天详情，并统一使用宿主 app_ui 提供的页面语义色。
class ChatPage extends StatefulWidget {
  /// 当前单聊或群聊的标题、类型与会话标识。
  final ConversationInfo conversation;

  /// 搜索或引用进入时的定位消息；为空时恢复最新消息窗口。
  final MessageInfo? message;

  /// 消息首次加载成功后交给业务清未读；失败及页面销毁不会触发。
  final VoidCallback? onInitialMessagesLoaded;

  /// 当前宿主允许的输入能力与操作守卫。
  final ChatMessageInputConfig messageInputConfig;

  /// 宿主指定的头像、气泡与消息操作展示配置。
  final ChatMessageListConfig messageListConfig;

  /// 是否显示现有会话设置入口，不改变设置页面权限。
  final bool isShowAppBarActions;

  const ChatPage({
    super.key,
    required this.conversation,
    this.message,
    this.onInitialMessagesLoaded,
    this.messageInputConfig = const ChatMessageInputConfig(
      isShowAudioCall: true,
      isShowVideoCall: true,
    ),
    this.messageListConfig = const ChatMessageListConfig(),
    this.isShowAppBarActions = true,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

/// 协调会话页的消息展示和输入交互。
class _ChatPageState extends State<ChatPage> {
  late SemanticColorScheme colorsTheme;

  // Multi-select mode state
  //
  // 多选模式状态
  MultiSelectState? _multiSelectState;

  // MessageInput key for @ mention feature
  //
  // 用于 @ 提及功能的消息输入键
  final GlobalKey<MessageInputState> _messageInputKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorsTheme = SemanticColorScheme.of(context);
  }

  void _onDestroyCallback() {
    if (mounted) {
      context.popChatUIKitPage();
    }
  }

  void _onChatSettingsTap() async {
    String userID = ChatUtil.getUserID(widget.conversation.conversationID);
    ContactInfo? contactInfo;
    if (userID.isNotEmpty) {
      final contactStore = ContactStore.shared;
      final result = await contactStore.getContactInfo(userIDList: [userID]);
      if (result.isSuccess && result.contactInfoList.isNotEmpty) {
        contactInfo = result.contactInfoList.first;
      }
    }

    if (!mounted) {
      return;
    }

    if (contactInfo != null && contactInfo.isFriend == false) {
      context.pushChatUIKitPage(
        AddFriend(contactInfo: contactInfo),
      );
    } else {
      context.pushChatUIKitPage<void>(
        ChatSettingPage(
          conversation: widget.conversation,
          conversationOfChatPage: widget.conversation,
          onDestroyCallback: _onDestroyCallback,
        ),
      );
    }
  }

  void _onUserClick(String userID) async {
    final contactStore = ContactStore.shared;
    final result = await contactStore.getContactInfo(userIDList: [userID]);
    ContactInfo? contactInfo =
        result.isSuccess && result.contactInfoList.isNotEmpty
            ? result.contactInfoList.first
            : null;
    if (contactInfo != null && contactInfo.isFriend == false && mounted) {
      context.pushChatUIKitPage(
        AddFriend(contactInfo: contactInfo),
      );
      return;
    }

    ConversationListStore conversationListStore =
        ConversationListStore.create();
    String conversationID = '$c2cConversationIDPrefix$userID';
    final convResult = await conversationListStore.getConversationInfo(
        conversationID: conversationID);
    ConversationInfo conversation = convResult.conversationInfo ??
        ConversationInfo(
          conversationID: conversationID,
          title: userID,
          type: ConversationType.c2c,
        );

    if (mounted) {
      context.pushChatUIKitPage<void>(
        ChatSettingPage(
          conversation: conversation,
          conversationOfChatPage: widget.conversation,
          onDestroyCallback: _onDestroyCallback,
        ),
      );
    }
  }

  void _onCallMessageClick(String userID, bool isVideoCall) {
    PublishParams params = PublishParams();
    params.isSticky = false;
    params.data = {
      "participantIds": [userID],
      "mediaType": isVideoCall ? CallMediaType.video : CallMediaType.audio,
      "chatGroupId": null,
      "timeout": 30,
    };
    TUIEventBus.shared.publish("call.startCall", null, params);
    UIKitUtil.reportChatInvokeCall();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          toolbarHeight: 48,
          backgroundColor: colorsTheme.bgColorOperate,
          // 导航栏底部保留主题分隔线，描边不额外占用消息区域高度。
          shape: Border(
            bottom: BorderSide(color: colorsTheme.strokeColorPrimary),
          ),
          titleSpacing: 4.0,
          centerTitle: true,
          title: Text(
            widget.conversation.title ??
                AppLocalization.text(context, LocaleKeys.chat_title, '聊天'),
            style: FontScheme.caption1Medium,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          scrolledUnderElevation: 0.0,
          leading: IconButton.buttonContent(
            content: IconOnlyContent(
                Icon(AppIcons.back, color: colorsTheme.textColorPrimary)),
            type: ButtonType.noBorder,
            size: ButtonSize.l,
            onClick: () => Navigator.of(context).pop(),
          ),
          actions: widget.isShowAppBarActions
              ? [
                  IconButton.buttonContent(
                    content: IconOnlyContent(
                      Icon(AppIcons.more, color: colorsTheme.textColorPrimary),
                    ),
                    type: ButtonType.noBorder,
                    size: ButtonSize.l,
                    onClick: _onChatSettingsTap,
                  ),
                ]
              : null),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              _messageInputKey.currentState?.collapseAllPanels();
            },
            behavior: HitTestBehavior.translucent,
            child: Column(
              children: [
                MessageList(
                  conversationID: widget.conversation.conversationID,
                  config: widget.messageListConfig,
                  locateMessage: widget.message,
                  onInitialMessagesLoaded: widget.onInitialMessagesLoaded,
                  onUserClick: (String userID) => _onUserClick(userID),
                  onUserLongPress: (String userID, String displayName) {
                    _messageInputKey.currentState?.insertMention(
                      userID: userID,
                      displayName: displayName,
                    );
                  },
                  onCallMessageClick: _onCallMessageClick,
                  onQuoteMessage: (MessageInfo message) {
                    _messageInputKey.currentState?.setQuotedMessage(message);
                  },
                  onMultiSelectStateChanged: (state) {
                    setState(() {
                      _multiSelectState = state;
                    });
                  },
                  groupAtInfoList: widget.conversation.groupAtInfoList,
                  initialUnreadCount: widget.conversation.unreadCount,
                ),
                if (_multiSelectState != null && _multiSelectState!.isActive)
                  MultiSelectBottomBar(
                    selectedCount: _multiSelectState!.selectedCount,
                    onCancel: _multiSelectState!.onCancel,
                    onDelete: _multiSelectState!.onDelete,
                    onForward: () => _multiSelectState!.onForward(context),
                  )
                else
                  MessageInput(
                    key: _messageInputKey,
                    conversationID: widget.conversation.conversationID,
                    config: widget.messageInputConfig,
                  ),
              ],
            ),
          ),
          // Floating "listen from here" status bar — hovers mid-right over the
          // message list (only visible while listening). Fills the area so the
          // expanded state can show a full-screen tap-to-collapse barrier;
          // collapsed/inactive states don't intercept taps on the chat.
          //
          // 浮动“从这里听”状态栏 — 在消息列表的中右方悬停（仅在聆听时可见）。填充区域，因此
          //
          // 收起/不活跃状态不会拦截聊天点击。
          const Positioned.fill(child: ListenPlaybackBar()),
        ],
      ),
    );
  }
}
