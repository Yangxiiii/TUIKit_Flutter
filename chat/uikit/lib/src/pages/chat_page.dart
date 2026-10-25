import 'dart:async';
import '../message_input/widget/message_edit_limit_dialog.dart';
import 'package:app_ui/app_ui.dart';
import '../emoji_picker/emoji_picker_model.dart';
import '../message_input/widget/message_edit_composer.dart';
import '../message_list/widgets/message_action_sheet.dart';
import '../message_list/widgets/message_actions_scope.dart';
import '../message_list/widgets/message_overlay_avoider.dart';
import '../message_list/widgets/message_tooltip.dart';
import 'package:flutter/material.dart' hide IconButton;
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:tuikit_atomic_x/base_component/utils/tui_event_bus.dart';
import 'package:tencent_chat_uikit/src/contact_list/pages/add_friend.dart';
import 'package:tencent_chat_uikit/src/message_list/listen/listen_playback_bar.dart';

export 'chat_setting_page.dart' show ChatSettingPage;

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

  /// 宿主提供的文本编辑及云端元数据能力；为空时保持原聊天行为。
  final ChatMessageEditConfig? messageEditConfig;

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
    this.messageEditConfig,
    this.isShowAppBarActions = true,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

/// 协调会话页的消息展示和输入交互。
class _ChatPageState extends State<ChatPage> {
  late SemanticColorScheme colorsTheme;

  /// 临时面板绘制偏移，不改动SDK消息窗口或普通输入草稿。
  final MessageOverlayController _overlay = MessageOverlayController();

  /// 当前编辑目标与开始时原文；实际输入只保存在编辑组件内。
  MessageInfo? _editingMessage;

  /// 本次开始时的原文快照，用于判断输入是否发生变化，不随SDK回调覆盖输入。
  String _editingText = '';

  /// 原列表持有的目标气泡锚点，用于键盘或面板尺寸变化后的实测避让。
  GlobalKey? _editingBubble;

  /// 取消或重新打开编辑时递增，旧保存结果不能关闭新的编辑会话。
  int _editRevision = 0;

  @override
  void dispose() {
    _editRevision++;
    _overlay.dispose();
    super.dispose();
  }

  /// 底部操作路由完成布局后上报边界，消息气泡仍由原列表持有。
  void _showActions(
      MessageInfo message,
      GlobalKey bubble,
      List<MessageMenuItem> original,
      void Function(EmojiPickerModelItem)? reaction) {
    Future<void> open() async {
      // 长按始终进入操作面板，先退出旧多选；只有面板中的明确点击才能重新进入多选。
      _multiSelectState?.onCancel();
      // 先收起普通输入面板，消息操作与普通草稿互不替换。
      _messageInputKey.currentState?.collapseAllPanels();
      FocusScope.of(context).unfocus();
      final items = [...original];
      if (widget.messageEditConfig?.canEdit(message) ?? false) {
        items.add(MessageMenuItem(
            id: 'edit',
            title: '编辑消息',
            icon: AppIcons.editMessage,
            onTap: () => unawaited(_beginEditing(message, bubble))));
      }
      // 浮层不占据列表布局高度，实际遮挡由路由动画后的边界测量决定。
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.transparent,
        builder: (sheetContext) => MessageActionSheet(
          editExpiresAt: message.timestamp == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (message.timestamp! + 300) * 1000),
          items: items,
          onClose: () => Navigator.of(sheetContext).pop(),
          onBounds: (bounds) {
            if (mounted) {
              _overlay.avoid(bubble, bounds.top);
            }
          },
          onReaction: reaction,
          onMoreReactions: reaction == null
              ? null
              : () async {
                  Navigator.of(sheetContext).pop();
                  final selected = await ReactionEmojiPickerSheet.show(context);
                  if (mounted && selected != null) {
                    reaction(selected);
                  }
                },
        ),
      );
      if (mounted && _editingMessage == null) {
        // 进入编辑后由新编辑区继续报告边界，普通关闭才在这里复原位移。
        _overlay.clear();
      }
    }

    final guard = widget.messageInputConfig.actionGuard;
    unawaited(guard == null
        ? open()
        : guard.singleFlight<void>('tim.message.actions', open));
  }

  /// SDK校验完成后进入编辑；普通输入保持隐藏挂载，原草稿不会被原文替换。
  Future<void> _beginEditing(MessageInfo message, GlobalKey bubble) async {
    final config = widget.messageEditConfig;
    if (config == null) {
      return;
    }
    final revision = ++_editRevision;
    // 异步资格校验通过后才切换本地视图，不能用气泡旧快照直接开始编辑。
    final result = await config.prepare(message.msgID);
    if (!mounted || revision != _editRevision) {
      return;
    }
    if (result.error != null) {
      _showEditError(result.error!);
      return;
    }
    if (result.text == null) {
      return;
    }
    setState(() {
      _editingMessage = message;
      _editingText = result.text!;
      _editingBubble = bubble;
    });
  }

  /// 取消只释放本次编辑视图；迟到的SDK结果通过版本号丢弃界面副作用。
  void _cancelEditing() {
    _editRevision++;
    FocusScope.of(context).unfocus();
    _overlay.clear();
    setState(() {
      _editingMessage = null;
      _editingBubble = null;
      _editingText = '';
    });
  }

  /// 保存结果仅影响发起该请求的编辑会话，失败保留当前输入及普通草稿。
  Future<String?> _saveEdit(String text) async {
    final message = _editingMessage;
    final config = widget.messageEditConfig;
    if (message == null || config == null) {
      return '消息不存在';
    }
    final revision = _editRevision;
    final error = await config.save(message.msgID, text);
    if (!mounted || revision != _editRevision) {
      return error;
    }
    if (error == null) {
      _cancelEditing();
    } else {
      _showEditError(error);
    }
    return error;
  }

  /// 次数上限使用设计中的单按钮提示，其余错误复用现有Toast。
  void _showEditError(String message) {
    if (message != '单条消息最多编辑20次') {
      Toast.error(context, message);
      return;
    }
    final colors = context.appColors;
    unawaited(showDialog<void>(
      context: context,
      barrierColor: colors.scrim.withValues(alpha: 0.7),
      builder: (_) => const MessageEditLimitDialog(),
    ));
  }

  /// 只派生当前SDK窗口的标识；目标被撤回或删除时立即结束其可保存状态。
  void _onEditWindowChanged(List<MessageInfo> messages) {
    widget.messageEditConfig
        ?.onMessageWindowChanged(messages.map((m) => m.msgID).toList());
    final target = _editingMessage;
    if (target == null) {
      return;
    }
    final matching = messages.where((m) => m.msgID == target.msgID);
    if (matching.isEmpty ||
        matching.first.status == MessageStatus.revoked ||
        matching.first.status == MessageStatus.deleted) {
      _cancelEditing();
      _showEditError('消息不存在');
    }
  }

  // 多选模式状态
  MultiSelectState? _multiSelectState;

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

  /// 复用聊天导航与设置入口，编辑期间返回由PopScope先退出编辑。
  PreferredSizeWidget _buildAppBar() => AppBar(
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
          : null);

  /// 原列表与普通输入始终保持挂载，临时编辑区不替换草稿控制器。
  Widget _buildConversation() => GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          _messageInputKey.currentState?.collapseAllPanels();
        },
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            MessageList(
              overlayController: _overlay,
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
              Visibility(
                visible: _editingMessage == null,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: MessageInput(
                  key: _messageInputKey,
                  conversationID: widget.conversation.conversationID,
                  config: widget.messageInputConfig,
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      resizeToAvoidBottomInset: _editingMessage == null,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildConversation(),
          // 聆听浮层保持原有全屏收起手势；编辑区随后绘制，优先接收编辑交互。
          const Positioned.fill(child: ListenPlaybackBar()),
          // 编辑区独立浮在键盘上方，列表原始布局尺寸不因打开编辑而变化。
          if (_editingMessage != null)
            Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.viewInsetsOf(context).bottom,
                child: MessageEditComposer(
                  key: ValueKey(_editingMessage!.msgID),
                  text: _editingText,
                  onCancel: _cancelEditing,
                  onSave: _saveEdit,
                  onBounds: (bounds) {
                    final bubble = _editingBubble;
                    if (mounted && bubble != null) {
                      _overlay.avoid(bubble, bounds.top);
                    }
                  },
                )),
        ],
      ),
    );
    final guardedPage = PopScope(
      canPop: _editingMessage == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _editingMessage != null) {
          _cancelEditing();
        }
      },
      child: page,
    );
    final config = widget.messageEditConfig;
    return config == null
        ? guardedPage
        : MessageActionsScope(
            config: config,
            showActions: _showActions,
            onMessagesChanged: _onEditWindowChanged,
            child: guardedPage);
  }
}
