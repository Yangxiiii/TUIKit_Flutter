import 'dart:async';
import 'dart:ui' show FlutterView;
import 'package:flutter/foundation.dart';
import '../message_input/widget/message_edit_limit_dialog.dart';
import 'package:app_ui/app_ui.dart';
import '../emoji_picker/emoji_picker_model.dart';
import '../message_input/widget/message_edit_composer.dart';
import '../message_list/widgets/message_action_sheet.dart';
import '../message_list/widgets/message_actions_scope.dart';
import '../message_list/widgets/message_overlay_avoider.dart';
import '../message_list/widgets/message_tooltip.dart';
import '../message_list/widgets/message_recall_scope.dart';
import 'package:flutter/material.dart' hide IconButton;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:tuikit_atomic_x/base_component/utils/tui_event_bus.dart';
import 'package:tencent_chat_uikit/src/contact_list/pages/add_friend.dart';
import 'package:tencent_chat_uikit/src/message_list/listen/listen_playback_bar.dart';

export 'chat_setting_page.dart' show ChatSettingPage;

/// 使用应用页面基类承载聊天详情，消息窗口和输入状态由本页持有。
class ChatPage extends AppBaseStatefulPage {
  /// 当前单聊或群聊的标题、类型与会话标识。
  final ConversationInfo conversation;

  /// 宿主派生的姓名与昵称；为空时保留 SDK 会话标题。
  final String? displayName;

  /// 宿主提供的主职组织名称；为空时不展示副标题，也不从长组织路径推测部门。
  final String? subtitle;

  /// SDK 全局真实未读数，仅显示封顶，不改变未读状态。
  final ValueListenable<int>? totalUnreadCount;

  /// 无显式定位或内存快照时先读取本机最新消息，不改变云端分页。
  final Future<List<MessageInfo>> Function()? localMessagesLoader;

  /// 单聊按发送人与相邻时间派生头像分组，默认保持原布局。
  final bool aggregateMessages;

  /// 仅为成功消息开放删除确认，不开启发送中或失败消息菜单。
  final bool enableSuccessfulDelete;

  /// 搜索或引用进入时的定位消息；为空时恢复最新消息窗口。
  final MessageInfo? message;

  /// 消息首次加载成功后交给业务清未读；失败及页面销毁不会触发。
  final VoidCallback? onInitialMessagesLoaded;

  /// 首次窗口请求结束后通知宿主；空会话也触发，只用于记录打开等辅助动作。
  final VoidCallback? onInitialLoadFinished;

  /// 当前宿主允许的输入能力与操作守卫。
  final ChatMessageInputConfig messageInputConfig;

  /// 宿主指定的头像、气泡与消息操作展示配置。
  final ChatMessageListConfig messageListConfig;

  /// 宿主提供的文本编辑及云端元数据能力；为空时保持原聊天行为。
  final ChatMessageEditConfig? messageEditConfig;

  /// 宿主提供的单聊撤回与原设备重新编辑能力；为空时沿用UIKit原行为。
  final ChatMessageRecallConfig? messageRecallConfig;

  /// 单聊回复沿用原引用输入、定位和消息窗口。
  final ChatMessageReplyConfig? messageReplyConfig;

  /// 宿主提供单聊唯一置顶、横幅及状态变化；群聊不传此配置。
  final ChatMessageStickyConfig? messageStickyConfig;

  /// 是否显示现有会话设置入口，不改变设置页面权限。
  final bool isShowAppBarActions;

  /// 宿主自定义设置入口；返回命中消息时在原聊天窗口定位，未传时沿用UIKit设置。
  final Future<MessageInfo?> Function()? onOpenSettings;

  const ChatPage({
    super.key,
    required this.conversation,
    this.displayName,
    this.subtitle,
    this.totalUnreadCount,
    this.localMessagesLoader,
    this.aggregateMessages = false,
    this.enableSuccessfulDelete = false,
    this.message,
    this.onInitialMessagesLoaded,
    this.onInitialLoadFinished,
    this.messageInputConfig = const ChatMessageInputConfig(
      isShowAudioCall: true,
      isShowVideoCall: true,
    ),
    this.messageListConfig = const ChatMessageListConfig(),
    this.messageEditConfig,
    this.messageRecallConfig,
    this.messageReplyConfig,
    this.messageStickyConfig,
    this.isShowAppBarActions = true,
    this.onOpenSettings,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

/// 协调会话页的消息展示、输入交互和键盘收起期间的帧请求。
class _ChatPageState extends AppBaseStatefulPageState<ChatPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 覆盖实测约 400 毫秒的收起过程，遮挡未归零时也能及时释放帧请求。
  static const _keyboardDismissFrameLimit = Duration(milliseconds: 600);

  /// 仅为 iOS 创建，由页面的 TickerMode 和生命周期约束。
  Ticker? _keyboardDismissTicker;

  /// 仅跟踪当前路由所属窗口，页面被覆盖时不响应其他路由的键盘。
  FlutterView? _keyboardView;

  /// 上一次系统回报的底部遮挡，单位为物理像素，仅用于判断变化方向。
  double _lastKeyboardInset = 0;

  /// 每次连续下降最多启动一次，超时后等到归零或重新升起才允许补帧。
  bool _keyboardDismissStarted = false;

  /// 快选分隔线的实测锚点，点击时使用当前位置，不缓存滚动前的边界。
  final GlobalKey _selectBelowLineKey = GlobalKey();

  /// 临时面板绘制偏移，不改动SDK消息窗口或普通输入草稿。
  final MessageOverlayController _overlay = MessageOverlayController();

  /// 当前编辑目标与开始时原文；实际输入只保存在编辑组件内。
  MessageInfo? _editingMessage;

  /// 本次开始时的原文快照，用于判断输入是否发生变化，不随SDK回调覆盖输入。
  String _editingText = '';

  /// 仅记录本窗口的搜索或置顶定位意图，不复制对应业务状态。
  MessageInfo? _locateMessage;

  /// 原列表持有的目标气泡锚点，用于键盘或面板尺寸变化后的实测避让。
  GlobalKey? _editingBubble;

  /// 取消或重新打开编辑时递增，旧保存结果不能关闭新的编辑会话。
  int _editRevision = 0;

  @override
  void dispose() {
    if (_keyboardDismissTicker != null) {
      WidgetsBinding.instance.removeObserver(this);
      _keyboardDismissTicker!.dispose();
    }
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
      if (widget.messageStickyConfig != null &&
          StickyMessageEvent.canPin(message)) {
        items.add(MessageMenuItem(
            id: 'top',
            title: '置顶消息',
            icon: AppIcons.topMessage,
            onTap: () => unawaited(_pinStickyMessage(message))));
      }
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
          recallExpiresAt:
              widget.messageRecallConfig == null || message.timestamp == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      (message.timestamp! + 120) * 1000),
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

  /// 防重保护完整反馈过程，重复调用方不能各自展示相同提示。
  Future<void> _pinStickyMessage(MessageInfo message) async {
    Future<void> submit() async {
      final error = await widget.messageStickyConfig?.pin(message);
      if (mounted && error != null) AppToast.show(error);
    }

    final guard = widget.messageInputConfig.actionGuard;
    if (guard == null) {
      await submit();
    } else {
      await guard.singleFlight<void>(
          'tim.sticky.ui.${widget.conversation.conversationID}', submit);
    }
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

  /// 确认后才执行受保护的SDK动作，提示和关闭只属于当前聊天页。
  void _recallMessage(MessageInfo message) {
    final config = widget.messageRecallConfig;
    if (config == null) return;
    Future<void> run() async {
      final colors = context.appColors;
      // 确认框只返回用户选择，取消及关闭过程中不得提前撤回原消息。
      final confirmed = await AppDialog.showAlert(
        content: '撤回该消息？',
        cancelText: '取消',
        confirmText: '撤回',
        semanticsIdentifier: 'tim.message.recallDialog',
        confirmBackgroundColor: colors.danger,
        maskColor: colors.scrim.withValues(alpha: .7),
      );
      if (!mounted || confirmed != true) return;
      // 复用公开AtomicX动作的成功通知，确保本机也刷新原消息，而非依赖接收端回调。
      final error = await config.recall(message.msgID, () async {
        final result = await MessageActionStore.create(message).revoke();
        return result.errorCode;
      });
      if (mounted && error != null) {
        AppToast.show(error, duration: const Duration(seconds: 3));
      }
    }

    final guard = widget.messageInputConfig.actionGuard;
    unawaited(
      guard == null
          ? run()
          : guard.singleFlight<void>(
              'tim.message.recallDialog.${widget.conversation.conversationID}',
              run,
            ),
    );
  }

  /// 点击时重查原设备的回填资格，再交由普通输入组件恢复完整草稿。
  void _reeditMessage(String messageId) {
    final guard = widget.messageInputConfig.actionGuard;
    if (guard != null) {
      guard.throttle(
        'tim.message.reedit.${widget.conversation.conversationID}.$messageId',
        () => _restoreRecalledMessage(messageId),
      );
      return;
    }
    _restoreRecalledMessage(messageId);
  }

  /// 保留普通草稿并追加撤回原文，只有通过宿主复核后才移动输入焦点。
  void _restoreRecalledMessage(String messageId) {
    final result = widget.messageRecallConfig?.prepareReedit(messageId);
    if (result == null) return;
    if (result.error != null) {
      AppToast.show(result.error!, duration: const Duration(seconds: 3));
      return;
    }
    if (result.draft != null) {
      _messageInputKey.currentState?.restoreRecalledDraft(result.draft!);
    }
  }

  /// 只派生当前SDK窗口的标识；目标被撤回或删除时立即结束其可保存状态。
  void _onEditWindowChanged(List<MessageInfo> messages) {
    // 普通引用随撤回失效；单聊回复保留到提交时，以便提示具体失败原因。
    if (widget.messageReplyConfig == null) {
      _messageInputKey.currentState?.invalidateRecalledQuote(messages);
    }
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // 键盘高度和页面位置仍来自系统；Ticker 只让下一个 VSync 有待处理的帧请求。
      _keyboardDismissTicker = createTicker((elapsed) {
        if (elapsed >= _keyboardDismissFrameLimit) {
          _keyboardDismissTicker!.stop();
        }
      });
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticker = _keyboardDismissTicker;
    if (ticker == null) return;
    final view =
        ModalRoute.isCurrentOf(context) == false ? null : View.of(context);
    if (identical(view, _keyboardView)) return;
    // 切换路由或窗口后重新记录起点，旧窗口的遮挡不能触发新窗口补帧。
    ticker.stop();
    _keyboardView = view;
    _lastKeyboardInset = view?.viewInsets.bottom ?? 0;
    _keyboardDismissStarted = false;
  }

  @override
  void didChangeMetrics() {
    final view = _keyboardView;
    if (view == null) return;
    final inset = view.viewInsets.bottom;
    final previousInset = _lastKeyboardInset;
    if (inset == previousInset) return;
    _lastKeyboardInset = inset;
    if (inset == 0 || inset > previousInset) {
      // 键盘收完或反向弹出时立即停下，后续收起允许重新启动。
      _keyboardDismissTicker!.stop();
      _keyboardDismissStarted = false;
    } else if (!_keyboardDismissStarted) {
      _keyboardDismissStarted = true;
      _keyboardDismissTicker!.start();
    }
  }

  void _onDestroyCallback() {
    if (mounted) {
      context.popChatUIKitPage();
    }
  }

  void _onChatSettingsTap() async {
    final open = widget.onOpenSettings;
    if (open != null) {
      Future<void> action() async {
        final target = await open();
        if (mounted && target != null) setState(() => _locateMessage = target);
      }

      // 守卫包含设置、搜索及返回定位，多个等待方不能重复应用同一导航结果。
      final guard = widget.messageInputConfig.actionGuard;
      if (guard != null) {
        await guard.singleFlight<void>('chat.settings.open', action);
      } else {
        await action();
      }
      return;
    }
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
      "timeout": 45,
    };
    TUIEventBus.shared.publish("call.startCall", null, params);
    UIKitUtil.reportChatInvokeCall();
  }

  @override
  double get navigationBarHeight => 48;

  @override
  bool get showAppBarBottomDivider => true;

  @override
  bool get safeAreaTop => false;

  @override
  bool get safeAreaBottom => false;

  @override
  bool get dismissKeyboardOnTap => false;

  @override
  bool get resizeToAvoidBottomInset => _editingMessage == null;

  @override
  Color backgroundColorOf(BuildContext context) => context.appColors.surface;

  @override
  Color navigationBarBackgroundColorOf(BuildContext context) =>
      context.appColors.surface;

  @override
  Widget titleWidgetOf(BuildContext context, Locale locale) {
    final title = Text(
      widget.displayName ??
          widget.conversation.title ??
          AppLocalization.text(context, LocaleKeys.chat_title, '聊天'),
      style: FontScheme.caption1Medium,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    final subtitle = widget.subtitle?.trim();
    if (subtitle == null || subtitle.isEmpty) return title;
    // 姓名和组织分属两行，固定导航栏高度内保留各自的字号与省略边界。
    return Column(mainAxisSize: MainAxisSize.min, children: [
      title,
      Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
            child: Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    height: 14 / 10,
                    fontWeight: FontWeight.w400,
                    color: context.appColors.textTertiary))),
        const SizedBox(width: 4),
        Icon(AppIcons.expand, size: 10, color: context.appColors.textTertiary),
      ]),
    ]);
  }

  @override
  double? get leadingWidth => widget.totalUnreadCount == null ? null : 84;

  @override
  Widget leadingOf(BuildContext context, Locale locale) {
    final back = Semantics(
      identifier: 'tim.chat.back',
      // 首次返回遵守PopScope，只退出编辑或多选，再次返回才离开会话。
      child: BackButton(
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: WidgetStatePropertyAll(Size(32, 48)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => Navigator.of(context).maybePop()),
    );
    final unread = widget.totalUnreadCount;
    if (unread == null) return back;
    // 返回入口保留完整点击高度，数量只作为实时信息，不截断原始未读值。
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(children: [
        SizedBox(width: 32, child: back),
        Flexible(
            child: ValueListenableBuilder<int>(
          valueListenable: unread,
          builder: (context, count, _) => count <= 0
              ? const SizedBox.shrink()
              : Semantics(
                  identifier: 'tim.chat.unread',
                  label: '$count',
                  liveRegion: true,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _buildTotalUnreadBadge(context, count))),
        )),
      ]),
    );
  }

  /// 与消息列表按实际文字宽高计算圆形或胶囊，圆角随字体缩放保持为高度的一半。
  Widget _buildTotalUnreadBadge(BuildContext context, int count) {
    final label = count > 99 ? '99+' : '$count';
    final style = DefaultTextStyle.of(context).style.copyWith(
          color: context.appColors.textPrimary,
          fontSize: 12,
          height: 1.5,
        );
    final metrics = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    // 短数字不加横向留白，避免把本应为圆形的角标撑宽；长文本两侧各留4px。
    final height = metrics.height;
    final width = metrics.width <= height ? height : metrics.width + 8;
    metrics.dispose();
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.appColors.controlBackground,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Text(label, style: style, maxLines: 1, softWrap: false),
    );
  }

  @override
  List<Widget>? actionsOf(BuildContext context, Locale locale) =>
      widget.isShowAppBarActions
          ? [
              Semantics(
                identifier: 'tim.chat.settings',
                label: '设置',
                button: true,
                child: IconButton.buttonContent(
                  content: IconOnlyContent(
                    Icon(AppIcons.more, color: context.appColors.textPrimary),
                  ),
                  type: ButtonType.noBorder,
                  size: ButtonSize.l,
                  onClick: _onChatSettingsTap,
                ),
              ),
            ]
          : null;

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
              localMessagesLoader: widget.localMessagesLoader,
              aggregateMessages: widget.aggregateMessages,
              // 多选切换保持同一列表State，避免重新加载时丢失选择与阅读位置。
              key: ValueKey(widget.conversation.conversationID),
              overlayController: _overlay,
              conversationID: widget.conversation.conversationID,
              config: widget.messageListConfig,
              replyConfig: widget.messageReplyConfig,
              locateMessage: _locateMessage ?? widget.message,
              onMessagesChanged: widget.messageStickyConfig?.onMessagesChanged,
              onMessagesDeleted: widget.messageStickyConfig?.onMessagesDeleted,
              onInitialMessagesLoaded: widget.onInitialMessagesLoaded,
              onInitialLoadFinished: () {
                widget.onInitialLoadFinished?.call();
                widget.messageStickyConfig?.onInitialLoadFinished?.call();
              },
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
                if (state?.isActive == true &&
                    _multiSelectState?.isActive != true) {
                  _messageInputKey.currentState?.collapseAllPanels();
                  FocusScope.of(context).unfocus();
                }
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
                onMergedForward: () =>
                    _multiSelectState!.onMergedForward?.call(context),
                onSeparateForward: () =>
                    _multiSelectState!.onSeparateForward?.call(context),
              ),
            Visibility(
              key: const ValueKey('normal-chat-input'),
              visible: _multiSelectState?.isActive != true &&
                  _editingMessage == null,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: _multiSelectState?.isActive != true,
              child: MessageInput(
                conversationDisplayName: widget.displayName,
                key: _messageInputKey,
                conversationID: widget.conversation.conversationID,
                config: widget.messageInputConfig,
                replyConfig: widget.messageReplyConfig,
                onLocalMessageSent:
                    widget.messageRecallConfig?.onLocalMessageSent,
              ),
            ),
          ],
        ),
      );

  /// 将分隔线的屏幕纵坐标交给原消息列表，选择状态仍由列表唯一持有。
  void _selectMessagesBelowLine() {
    final line = _selectBelowLineKey.currentContext?.findRenderObject();
    if (line is! RenderBox || !line.hasSize) return;
    final boundary = line.localToGlobal(Offset(0, line.size.height / 2)).dy;
    _multiSelectState?.onSelectBelow?.call(boundary);
  }

  /// 快选入口浮在导航下方，外层不绘制背景，消息可从按钮后方滚过。
  Widget _buildSelectBelow() => SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(children: [
          Expanded(
              child: Divider(
                  key: _selectBelowLineKey,
                  height: 1,
                  color: context.appColors.outline)),
          Semantics(
              identifier: 'tim.forward.select_below',
              button: true,
              child: InkWell(
                onTap: _selectMessagesBelowLine,
                child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                        color: context.appColors.surface,
                        border: Border.all(
                            color: context.appColors.outline, width: .5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Center(
                        child: Text('选择以下消息',
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: context.appColors.textPrimary)))),
              )),
          Expanded(child: Divider(height: 1, color: context.appColors.outline)),
        ]),
      ));

  @override
  Widget buildBody(BuildContext context, WidgetRef ref, Locale locale) {
    final page = Stack(
      children: [
        _buildConversation(),
        // 聆听浮层保持原有全屏收起手势；编辑区随后绘制，优先接收编辑交互。
        const Positioned.fill(child: ListenPlaybackBar()),
        // 快选入口不占用消息窗口高度，仅按钮和分隔线覆盖消息。
        if (_multiSelectState?.isActive == true)
          Positioned(top: 0, left: 0, right: 0, child: _buildSelectBelow()),
        // 置顶横幅覆盖消息列表上部，不挤压原消息窗口和输入区。
        if (widget.messageStickyConfig case final sticky?)
          Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: sticky.bannerBuilder(context, (target) {
                if (mounted) setState(() => _locateMessage = target);
              })),
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
    );
    final guardedPage = PopScope(
      canPop: _editingMessage == null && _multiSelectState?.isActive != true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _editingMessage != null) {
          _cancelEditing();
        } else if (!didPop && _multiSelectState?.isActive == true) {
          _multiSelectState?.onCancel();
        }
      },
      child: page,
    );
    final config = widget.messageEditConfig;
    // 转发、成功态删除、编辑或置顶任一能力接入时，均使用统一操作面板。
    final editPage = config == null &&
            widget.messageStickyConfig == null &&
            !widget.enableSuccessfulDelete &&
            widget.messageListConfig.forwardHandler == null
        ? guardedPage
        : MessageActionsScope(
            enableSuccessfulDelete: widget.enableSuccessfulDelete,
            actionGuard: widget.messageInputConfig.actionGuard,
            config: config,
            showActions: _showActions,
            onMessagesChanged: _onEditWindowChanged,
            onMessagesDeleted: widget.messageStickyConfig?.onMessagesDeleted,
            child: guardedPage);
    final recallConfig = widget.messageRecallConfig;
    return recallConfig == null
        ? editPage
        : MessageRecallScope(
            config: recallConfig,
            onRecall: _recallMessage,
            onReedit: _reeditMessage,
            child: editPage,
          );
  }
}
