import 'chat_media_sender.dart';
import '../message_list/utils/big_file_message.dart';
import '../message_list/utils/rich_content_markdown_format.dart';
import 'dart:async';
import 'dart:convert';
import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart'
    show AppIcons, AppDialog, AppColorBuildContext;
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_action_store_impl.dart';
import 'package:flutter/material.dart' hide IconButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tuikit_atomic_x/album_picker/album_picker.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:tencent_chat_uikit/src/message_input/album_picker_media_send_manager.dart';
import 'package:tencent_chat_uikit/src/message_input/utils/image_size_reader.dart';
import 'package:tencent_chat_uikit/src/audio_recoder/audio_recorder.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart'
    hide AlertDialog;
import 'package:tuikit_atomic_x/base_component/utils/tui_event_bus.dart';
import 'package:tencent_chat_uikit/src/chat_setting/pages/group_member_picker.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_picker.dart';
import 'package:tencent_chat_uikit/src/file_picker/file_picker.dart';
import 'package:tencent_chat_uikit/src/message_input/src/record_pointer_up_action.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/rich_content_editor_sheet.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/navigation/chat_uikit_navigation.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart';
import 'package:tencent_chat_uikit/src/audio_player/audio_player.dart'
    as voice_audio;
import 'package:tuikit_atomic_x/permission/permission.dart';
import 'package:tencent_chat_uikit/src/user_picker/user_picker.dart';
import 'package:tencent_chat_uikit/src/video_recorder/video_recorder.dart';

import 'mention/mention_info.dart';
import 'mention/mention_member_picker.dart';
import 'message_input_config.dart';
import 'message_text.dart';
import 'input_keyboard_panel.dart';
import 'pending_rich_content_message.dart';
import 'widget/audio_record_overlay.dart';
import 'widget/voice_record_preview.dart';
import 'widget/voice_microphone_notice.dart';
import 'widget/quote_preview_bar.dart';
import '../message_list/message_recall_config.dart';

export 'mention/mention_info.dart';
export 'message_input_config.dart';

/// Three-state input mode for the message input bar.
/// - [idle]: Default state on chat entry. Shows hint "发消息或按住说话...", mic icon, keyboard not shown.
/// - [text]: Text input active. Keyboard shown, mic icon on left.
/// - [voice]: Voice recording mode. Shows "Hold to talk" button, keyboard icon on left.
///
/// 消息输入栏的三态输入模式。
///
/// - [文本]: 文本输入激活。显示键盘，左侧为麦克风图标。- [语音]: 语音录制模式。显示“按住说话”按钮，左侧为键盘图标。
enum _InputMode { idle, text, voice }

/// 聊天页消息输入组件，统一协调文字、富文本、媒体和语音入口。
class MessageInput extends StatefulWidget {
  /// 当前输入和草稿所属的稳定会话标识。
  final String conversationID;

  /// 与导航共享的宿主姓名及昵称；未提供时使用 SDK 会话标题。
  final String? conversationDisplayName;

  /// 宿主配置的可见能力、附件上传器和统一操作守卫。
  final MessageInputConfigProtocol config;

  /// 仅当前输入流程的本机成功发送事件，用于宿主证明原发送设备。
  final ValueChanged<MessageInfo>? onLocalMessageSent;

  const MessageInput({
    super.key,
    required this.conversationID,
    this.conversationDisplayName,
    this.config = const ChatMessageInputConfig(),
    this.onLocalMessageSent,
  });

  @override
  State<MessageInput> createState() => MessageInputState();
}

/// 管理当前会话的输入模式、草稿、焦点和消息发送顺序。
class MessageInputState extends State<MessageInput>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// Group conversation ID prefix
  ///
  /// 群聊 ID 前缀。
  static const String _groupConversationIDPrefix = 'group_';

  late MessageInputStore _messageInputStore;
  late ConversationListStore _conversationListStore;
  late _MentionTextEditingController _textEditingController;
  final FocusNode _textEditingFocusNode = FocusNode();
  Widget stickerWidget = Container();

  late AppLocalizedText atomicLocale;

  /// 按下后等待100毫秒再插入覆盖层，期间仍由原输入按钮接收抬手。
  Timer? _recordingStarter;

  /// 权限和启动等待尚未结束；取消、离开或后台都会使等待失效。
  bool _isWaitingToStartRecord = false;

  /// 当前输入内容的校验结果；发送任务的忙碌状态另行限制按钮。
  bool _showSendButton = false;

  /// 仅驱动发送按钮忙碌态，实际并发由ActionGuard统一保护。
  bool _isSendingText = false;

  /// 宿主注入全局守卫；独立使用UIKit时也复用同一种防重复实现。
  late final ActionGuard _textSendGuard =
      widget.config.actionGuard ?? ActionGuard();

  /// 每次正文或展开草稿实际变化时递增，阻止迟到的旧草稿覆盖新编辑。
  int _draftRevision = 0;

  /// 只用于区分正文变化与选区变化，不作为另一份可编辑文本。
  String _lastObservedText = '';

  /// 记录上次是否超限，仅用于让全局提示在进入超限状态时显示一次。
  bool _wasOverTextLimit = false;
  bool _showEmojiPanel = false;
  bool _showMorePanel = false;

  /// 普通输入区是否显示 Markdown 文字格式工具栏。
  bool _showTextFormattingToolbar = false;

  /// 普通输入内容是否需要按富文本自定义消息发送。
  bool _inlineRichContentEnabled = false;

  /// 普通输入区格式栏中处于选中状态的 Markdown 标记。
  final Set<String> _activeInlineFormats = {};

  /// 上次原文选区；仅光标移动时派生格式，程序切换按钮时先同步以保留下一次输入的选择。
  TextSelection _lastFormatSelection =
      const TextSelection.collapsed(offset: -1);
  late final TextInputFormatter _inlineFormatInputFormatter =
      activeMarkdownFormatInputFormatter(() => _activeInlineFormats);
  int _morePanelPageIndex = 0;
  final GlobalKey<AudioRecordOverlayState> _recordOverlayKey = GlobalKey();
  final GlobalKey<VoiceRecordPreviewState> _voicePreviewKey = GlobalKey();

  /// 与启动等待状态分离，避免首帧尚未创建浮层时松手后仍启动采音。
  bool _recordPointerHeld = false;
  OverlayEntry? _recordOverlayEntry;

  /// When `true`, the next [AudioRecordOverlay.onRecordFinish] callback should
  /// be routed to the overlay's voice-to-text state machine instead of being
  /// sent as a voice message. Set to `true` by [_onStopRecording] when the
  /// user released on the convert-to-text button, and reset back to `false`
  /// inside the overlay callback or when the overlay is cancelled.
  ///
  /// 当为 `true` 时，下一次 [AudioRecordOverlay.onRecordFinish] 回调应路由到覆盖层的语音转文本状态机，而不是作为语音消息发送。当用户在转换为文本按钮上释放时，由
  /// [_onStopRecording] 设置为 `true`，并在覆盖层回调或取消覆盖层时重置为 `false`。
  bool _pendingConvertRecord = false;

  double _bottomPadding = 0.0;

  /// 当前窗口的键盘区域过渡，普通输入持有，展开编辑器使用自己的同类实例。
  InputKeyboardPanel? _keyboardPanel;

  /// Flag to indicate we are actively switching to emoji/more panel.
  /// When true, _onFocusChanged should NOT collapse panels.
  ///
  /// 标志，用于指示我们正在主动切换到表情/更多面板。当为 true 时，_onFocusChanged 不应收起面板。
  bool _isSwitchingPanel = false;

  final GlobalKey<TooltipState> _micTooltipKey = GlobalKey<TooltipState>();

  /// Current input mode: idle (default), text (keyboard shown), or voice (hold-to-talk).
  ///
  /// 当前输入模式：空闲（默认），文本（显示键盘），或语音（按住说话）。
  _InputMode _inputMode = _InputMode.idle;

  // Draft related state
  //
  // 草稿相关状态
  /// 合并连续输入的草稿写入，离开页面时取消并立即补存。
  Timer? _draftSaveTimer;

  /// 首次草稿读取期间，未编辑的空输入不能反向清除尚未读出的草稿。
  bool _isLoadingDraft = false;

  /// 只有成功读取后才能把未编辑的空输入当作空草稿；读取失败不等于草稿为空。
  bool _hasLoadedDraft = false;

  /// 用户停止输入800毫秒后保存，避免每次按键都调用SDK。
  static const _draftSaveDelay = Duration(milliseconds: 800);

  // @ mention related state
  //
  // @ 提及相关状态
  String? _groupID;
  int _previousTextLength = 0;

  /// 当前会话内收起后保留的富文本标题、正文顺序和附件上传状态。
  RichContentDraft _richContentDraft = const RichContentDraft();

  /// 普通输入框内附件令牌对应的富文本草稿块。
  final Map<int, RichContentDraftAttachmentBlock>
      _inlineRichContentAttachments = {};
  final GlobalKey<RichContentEditorSheetState> _richContentEditorKey =
      GlobalKey<RichContentEditorSheetState>();

  /// 保留普通输入区中的工具条几何位置，供顶层工具条视图精确覆盖。
  final GlobalKey _sharedToolbarAnchorKey = GlobalKey();

  /// 同时承载编辑器和顶层工具条视图，子节点顺序保证工具条不被动画遮挡。
  OverlayEntry? _richContentEditorOverlay;
  bool _isRichContentEditorOpen = false;
  bool _isMentionPickerShowing = false;

  // Conversation info for offline push
  //
  // 离线推送的会话信息
  ConversationInfo? _conversationInfo;

  late final _AlbumPickerMediaSendListenerImpl _albumPickerListener;

  /// 持有本输入实例的成功通知订阅；销毁时只取消自身，不清空全局通知。
  StreamSubscription<MessageSendEventData>? _localSendSubscription;

  // Quote reply state
  //
  // 引用回复状态
  MessageInfo? _quotedMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageInputStore = MessageInputStore.create(
      conversationID: widget.conversationID,
    );
    _conversationListStore = ConversationListStore.create();
    _albumPickerListener = _AlbumPickerMediaSendListenerImpl(this);
    AlbumPickerMediaSendManager.shared.restorePlaceholders(
      conversationID: widget.conversationID,
      listener: _albumPickerListener,
    );
    _textEditingController = _MentionTextEditingController();
    _textEditingController.addListener(_onTextChanged);
    _textEditingFocusNode.addListener(_onFocusChanged);
    _loadDraft();
    _extractGroupID();
    _localSendSubscription =
        notificationCenter.addListener<MessageSendEventData>(
      MessageSendNotifyKey.messageSendSuccess,
      (event) {
        final message = event.message;
        if (mounted &&
            event.conversationID == widget.conversationID &&
            message is MessageInfo) {
          widget.onLocalMessageSent?.call(message);
        }
      },
    );
  }

  /// Extract groupID from conversationID for group chats
  ///
  /// 从 conversationID 中提取 groupID 用于群聊
  void _extractGroupID() {
    String groupID = ChatUtil.getGroupID(widget.conversationID);
    _groupID = groupID.isEmpty ? null : groupID;
  }

  bool get _isGroupChat => _groupID != null;

  /// 将撤回原文加入普通草稿；已有内容保留在前，避免静默覆盖用户输入。
  void restoreRecalledDraft(ChatMessageRecallDraft recalled) {
    // 先确认原文可以恢复，再操作焦点与现有草稿，未知协议不能清空用户输入。
    final rich = recalled.toRichDraft();
    if (rich == null && recalled.text == null) return;
    collapseAllPanels();
    if (rich == null && !_inlineRichContentEnabled) {
      // 纯文本保留当前草稿；富文本分支随后按原模型恢复附件和顺序。
      final existing = _textEditingController.text;
      final value = '${existing.isEmpty ? '' : '$existing\n'}${recalled.text!}';
      _textEditingController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    } else {
      final existing = _buildInlineRichContentDraft();
      final incoming = rich ??
          RichContentDraft(
            blocks: [RichContentDraftTextBlock(0, recalled.text!)],
          );
      final combined = [
        ...existing.blocks,
        if (existing.hasContent) const RichContentDraftTextBlock(0, '\n'),
        ...incoming.blocks,
      ];
      // 旧草稿和撤回原文各自的块ID可能重叠，回填时重编为同一输入实例的唯一ID。
      final blocks = <RichContentDraftBlock>[];
      for (var i = 0; i < combined.length; i++) {
        final block = combined[i];
        blocks.add(switch (block) {
          RichContentDraftTextBlock b => RichContentDraftTextBlock(i, b.text),
          RichContentDraftAttachmentBlock b => RichContentDraftAttachmentBlock(
              i,
              attachment: b.attachment,
              remoteUrl: b.remoteUrl,
              status: b.status,
            ),
        });
      }
      _inlineRichContentEnabled = true;
      _restoreInlineRichContentDraft(
        RichContentDraft(title: existing.title, blocks: blocks),
      );
    }
    // 原文回填推进草稿版本，迟到的加载结果不得覆盖；后续发送继续创建新消息。
    _onTextChanged();
    setState(() => _inputMode = _InputMode.text);
    _textEditingFocusNode.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardPanel ??= InputKeyboardPanel(
        view: View.of(context),
        onChanged: () {
          if (mounted) setState(() {});
        });
  }

  @override
  void didUpdateWidget(MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationID != widget.conversationID) {
      _recordingStarter?.cancel();
      _recordPointerHeld = false;
      _isWaitingToStartRecord = false;
      _voicePreviewKey.currentState?.cancel();
    }
    if (oldWidget.conversationDisplayName != widget.conversationDisplayName) {
      // 资料异步返回时，已展开的富文本浮层也要使用与导航相同的名称。
      _richContentEditorOverlay?.markNeedsBuild();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 尚未创建录音浮层时也必须取消等待，不能在返回前台后补启动旧按压。
    if (widget.config.previewVoiceBeforeSend &&
        state != AppLifecycleState.resumed) {
      _recordPointerHeld = false;
      _recordingStarter?.cancel();
      if (_isWaitingToStartRecord) {
        _isWaitingToStartRecord = false;
        _removeRecordOverlay();
      }
    }
  }

  void _onFocusChanged() {
    if (!_textEditingFocusNode.hasFocus) {
      _keyboardPanel?.clear();
      // If we are actively switching to emoji/more panel, do NOT collapse panels.
      if (_isSwitchingPanel) {
        _isSwitchingPanel = false;
        return;
      }
      // While the @ mention picker is being shown, focus loss is caused by the
      // route push, not by the user dismissing the input. Keep the current
      // text mode so we can resume editing after picker returns.
      //
      // 路由跳转，不是用户主动取消输入。保持当前文本模式，以便在选择器返回后继续编辑。
      if (_isMentionPickerShowing) {
        return;
      }
      // When focus is truly lost (e.g., tapping outside), collapse emoji and more panels.
      // Only fall back to idle when the input is empty; if the user has typed
      // anything (including @ mentions), keep text mode so the entered content
      // remains visible after the keyboard collapses.
      //
      // 当焦点真正丢失时（例如，点击外部区域），收起表情和更多面板。仅在输入为空时回到空闲状态；如果用户已经输入了内容（包括@提及），保持文本模式，以便键盘收起后已输入的内容仍可见。
      bool needsRebuild = false;
      if (_showEmojiPanel || _showMorePanel) {
        _showEmojiPanel = false;
        _showMorePanel = false;
        needsRebuild = true;
      }
      if (_inputMode == _InputMode.text &&
          _textEditingController.text.isEmpty) {
        _inputMode = _InputMode.idle;
        needsRebuild = true;
      }
      if (needsRebuild) {
        setState(() {});
      }
    }
  }

  /// Collapse all panels (emoji, more). Called externally when user taps blank area.
  /// In text mode, dismisses the keyboard. Only falls back to idle when the input
  /// is empty, so any already-entered text (including @ mentions) stays visible
  /// after the keyboard collapses. Voice mode is unaffected.
  ///
  /// 收起所有面板（表情、更多）。用户点击空白区域时会从外部调用。在文本模式下，会收起键盘。只有在输入为空时才回到空闲状态，因此已输入的文字（包括@提及）在键盘收起后仍然可见。语音模式不受影响。
  void collapseAllPanels() {
    bool needsRebuild = false;
    if (_showEmojiPanel) {
      _showEmojiPanel = false;
      needsRebuild = true;
    }
    if (_showMorePanel) {
      _showMorePanel = false;
      needsRebuild = true;
    }
    if (_inputMode == _InputMode.text) {
      _textEditingFocusNode.unfocus();
      if (_textEditingController.text.isEmpty) {
        _inputMode = _InputMode.idle;
      }
      needsRebuild = true;
    }
    if (needsRebuild) {
      setState(() {});
    }
  }

  /// Insert a mention into the input field from external source (e.g., long press on avatar)
  /// This is called when user long presses on another member's avatar in the message list
  ///
  /// 从外部源在输入框中插入提及（例如，长按头像）。当用户在消息列表中长按其他成员的头像时会调用这个功能。
  void insertMention({required String userID, required String displayName}) {
    if (!_isGroupChat) return;

    // Don't allow mentioning self
    //
    // 不允许提及自己
    final currentUserID = LoginStore.shared.loginState.loginUserInfo?.userID;
    if (userID == currentUserID) return;

    final text = _textEditingController.text;
    final cursorPos = _textEditingController.selection.baseOffset;
    final insertPos = cursorPos < 0 ? text.length : cursorPos;

    // Create mention info
    //
    // 创建提及信息
    final mention = MentionInfo(
      userID: userID,
      displayName: displayName,
      startIndex: insertPos,
    );
    final mentionText = mention.mentionText; // "@displayName "

    // Build new text
    //
    // 构建新文本
    final beforeCursor = text.substring(0, insertPos);
    final afterCursor = text.substring(insertPos);
    final newText = '$beforeCursor$mentionText$afterCursor';
    final newCursorPos = insertPos + mentionText.length;

    // Update mention positions for existing mentions after insert position
    //
    // 在插入位置后更新现有提及的位置
    for (final m in _textEditingController._mentions) {
      if (m.startIndex >= insertPos) {
        m.startIndex += mentionText.length;
      }
    }

    // Add the new mention
    //
    // 添加新的提及
    _textEditingController.addMention(mention);

    // Update text field
    //
    // 更新文本字段
    _textEditingController.removeListener(_onTextChanged);
    _textEditingController._isInternalUpdate = true;
    _textEditingController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
    _textEditingController._isInternalUpdate = false;
    _previousTextLength = newText.length;
    _textEditingController.addListener(_onTextChanged);

    // Request focus on the input field
    //
    // 请求输入框获取焦点
    _textEditingFocusNode.requestFocus();

    // Update send button state and switch to text mode
    //
    // 更新发送按钮状态并切换到文本模式
    setState(() {
      _inputMode = _InputMode.text;
      _showEmojiPanel = false;
      _showMorePanel = false;
    });
    // 提及回填临时移除了监听，必须补走统一校验和草稿版本更新。
    _onTextChanged();
  }

  /// Set a message to be quoted. Shows the quote preview bar and raises keyboard.
  ///
  /// 设置要引用的消息。显示引用预览栏并弹出键盘。
  void setQuotedMessage(MessageInfo message) {
    setState(() {
      _quotedMessage = message;
      _inputMode = _InputMode.text;
      // Collapse the more / emoji panels so they don't stay layered under
      // the keyboard and obscure the message list once the user enters
      // quote-reply mode (TAPD bug 1020398462158964479).
      //
      // 收起更多/表情面板，以免在用户进入引用回复模式后被键盘覆盖并遮挡消息列表（TAPD bug 1020398462158964479）。
      _showEmojiPanel = false;
      _showMorePanel = false;
    });
    _textEditingFocusNode.requestFocus();
  }

  /// Clear the quoted message.
  ///
  /// 清除引用消息。
  void clearQuotedMessage() {
    setState(() {
      _quotedMessage = null;
    });
  }

  /// 当前引用目标被SDK确认撤回时移除输入引用，禁止继续携带失效原文发送。
  void invalidateRecalledQuote(List<MessageInfo> messages) {
    final target = _quotedMessage;
    if (target != null &&
        messages.any(
          (message) =>
              message.msgID == target.msgID &&
              message.status == MessageStatus.revoked,
        )) {
      clearQuotedMessage();
    }
  }

  /// 键盘或窗口尺寸变化后重测覆盖层锚点，不能依赖已被Scaffold消费的底部Insets。
  @override
  void didChangeMetrics() {
    if (_richContentEditorOverlay == null) return;
    // 系统先通知尺寸变化，等Scaffold完成本帧避让后才能读取工具条的新坐标。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _richContentEditorOverlay?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingStarter?.cancel();
    _recordPointerHeld = false;
    _isWaitingToStartRecord = false;
    _keyboardPanel?.dispose();
    unawaited(_localSendSubscription?.cancel());
    _richContentEditorOverlay?.remove();
    _richContentEditorOverlay = null;
    _removeRecordOverlay();
    _textEditingController.removeListener(_onTextChanged);
    _textEditingFocusNode.removeListener(_onFocusChanged);
    _draftSaveTimer?.cancel();
    // 离开时补存用户已编辑内容；尚未读取的草稿不能被默认空输入覆盖。
    _saveDraftImmediately();
    _textEditingController.dispose();
    _textEditingFocusNode.dispose();
    super.dispose();
  }

  /// 加载会话草稿；只在当前输入仍属于初始版本时回填，不主动唤起键盘。
  Future<void> _loadDraft() async {
    final initialRevision = _draftRevision;
    _isLoadingDraft = true;
    try {
      final result = await _conversationListStore.getConversationInfo(
        conversationID: widget.conversationID,
      );
      // 退出页面后控制器可能已销毁；用户已编辑时也不能再回填旧正文。
      if (!mounted || !result.isSuccess || result.conversationInfo == null) {
        return;
      }
      _hasLoadedDraft = true;
      _conversationInfo = result.conversationInfo;
      final draft = _conversationInfo!.draft;
      if (_draftRevision == initialRevision &&
          draft != null &&
          draft.isNotEmpty) {
        _setDraftToInput(draft);
      } else {
        setState(() {});
      }
    } on Object catch (error) {
      // 读取失败保留当前输入，不能把失败解释成没有草稿并清空内容。
      debugPrint('加载聊天草稿失败: $error');
    } finally {
      _isLoadingDraft = false;
      // 加载期间的用户编辑暂未保存，读取结束后恢复原有防抖保存流程。
      if (mounted && _draftRevision != initialRevision) _scheduleDraftSave();
    }
  }

  /// 从 IM SDK 恢复普通文本或带本地附件路径的富文本草稿。
  void _setDraftToInput(String draft) {
    final richDraft = RichContentDraft.tryParsePersisted(draft);
    if (richDraft != null) {
      _restoreInlineRichContentDraft(richDraft);
      _inlineRichContentEnabled = true;
    } else if (!RichContentDraft.isPersistedString(draft)) {
      _textEditingController.text = draft;
    }
    final inputLength = _textEditingController.text.length;
    // 恢复正文和末尾选区，但只有用户主动点击时才建立键盘焦点。
    _textEditingController.selection = TextSelection.fromPosition(
      TextPosition(offset: inputLength),
    );
    _onTextChanged();
    setState(() => _inputMode = _InputMode.text);
  }

  /// Save draft with debounce
  ///
  /// 防抖保存草稿
  void _scheduleDraftSave() {
    if (_isLoadingDraft) return;

    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(_draftSaveDelay, () {
      _saveDraftImmediately();
    });
  }

  /// 立即把当前普通文本或完整富文本草稿写入 IM SDK。
  void _saveDraftImmediately() {
    // 未成功读取且没有用户编辑时，空输入并不代表用户删除了草稿。
    if (!_hasLoadedDraft && _draftRevision == 0) return;
    final richDraft = _isRichContentEditorOpen
        ? _richContentDraft
        : _buildInlineRichContentDraft();
    final hasRichContent = _inlineRichContentEnabled ||
        richDraft.title.isNotEmpty ||
        richDraft.blocks
            .whereType<RichContentDraftAttachmentBlock>()
            .isNotEmpty;
    final draftText = hasRichContent
        ? (richDraft.hasContent ? richDraft.toPersistedString() : '')
        : _textEditingController.text;
    _conversationListStore.setConversationDraft(
      conversationID: widget.conversationID,
      draft: draftText.isEmpty ? null : draftText,
    );
  }

  /// Clear draft (called before sending message)
  ///
  /// 清除草稿（发送消息前调用）
  void _clearDraft() {
    _draftSaveTimer?.cancel();
    _conversationListStore.setConversationDraft(
      conversationID: widget.conversationID,
      draft: null,
    );
  }

  /// 同步输入校验与草稿版本，所有实际文字变化均走相同的保存与禁发规则。
  void _onTextChanged() {
    // 选区移动不推进编辑版本，避免仅聚焦就阻止旧草稿正常恢复。
    final text = _textEditingController.text;
    final selection = _textEditingController.selection;
    if (_inlineRichContentEnabled &&
        !_isRichContentEditorOpen &&
        text == _lastObservedText &&
        _lastFormatSelection.isValid &&
        selection.isValid &&
        selection.isCollapsed &&
        selection != _lastFormatSelection) {
      final formats =
          richContentMarkdownFormatsAt(text, selection.extentOffset);
      if (_activeInlineFormats.length != formats.length ||
          !_activeInlineFormats.containsAll(formats)) {
        setState(() {
          _activeInlineFormats
            ..clear()
            ..addAll(formats);
        });
      }
    }
    _lastFormatSelection = selection;
    if (text != _lastObservedText) {
      _draftRevision++;
      _lastObservedText = text;
    }
    // 清理已从正文删除的附件，再从当前原文生成同一份富文本快照。
    _inlineRichContentAttachments.removeWhere(
      (id, _) => !_textEditingController.text.contains(
        richContentAttachmentToken(id),
      ),
    );
    if (_inlineRichContentEnabled ||
        _inlineRichContentAttachments.isNotEmpty ||
        _richContentDraft.title.isNotEmpty) {
      _richContentDraft = _buildInlineRichContentDraft();
    }
    // 按钮与实际发送共用同一字符口径，非空到超限的变化也必须刷新。
    final characterCount = _inlineRichContentEnabled
        ? _richContentDraft.characterCount
        : messageTextCharacterCount(text);
    _updateTextLimitFeedback(characterCount);
    final canSend = _inlineRichContentEnabled
        ? _canSubmitRichContentDraft(_richContentDraft)
        : text.trim().isNotEmpty && characterCount <= messageTextCharacterLimit;
    if (canSend != _showSendButton) {
      setState(() {
        _showSendButton = canSend;
      });
    }
    // 正文同步后再保存并检测提及，避免监听到过期的编辑位置。
    _scheduleDraftSave();

    _handleMentionDetection();
  }

  /// 超限时沿用宿主全局Toast，保留输入供修改；回到上限内后允许再次提示。
  void _updateTextLimitFeedback(int characterCount) {
    final exceeded = characterCount > messageTextCharacterLimit;
    final shouldNotify = exceeded && !_wasOverTextLimit;
    _wasOverTextLimit = exceeded;
    if (!shouldNotify) return;
    // 草稿恢复也可能触发校验，等当前帧结束后再展示覆盖层。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _wasOverTextLimit) {
        Toast.error(
            context, AppLocalization.of(context).messageTextLimitExceeded);
      }
    });
  }

  /// Detect @ input and show member picker
  ///
  /// 检测 @ 输入并显示成员选择器
  void _handleMentionDetection() {
    if (!widget.config.enableMention) return;
    if (_isMentionPickerShowing) return;

    final text = _textEditingController.text;
    final currentLength = text.length;

    // Only trigger when adding a single '@' or '＠' character
    //
    // 仅在添加单个 '@' 或 '＠' 字符时触发
    if (currentLength == _previousTextLength + 1 && _isGroupChat) {
      final cursorPos = _textEditingController.selection.baseOffset;
      if (cursorPos > 0) {
        final lastChar = text[cursorPos - 1];
        // Support both half-width '@' and full-width '＠'
        //
        // 支持半角 '@' 和全角 '＠'
        if (lastChar == '@' || lastChar == '＠') {
          _showMentionPicker();
        }
      }
    }

    _previousTextLength = currentLength;
  }

  /// Show the mention member picker
  ///
  /// 显示提及成员选择器
  void _showMentionPicker() {
    if (_groupID == null) return;
    _isMentionPickerShowing = true;

    context
        .pushChatUIKitPage(
      MentionMemberPicker(
        groupID: _groupID!,
        onMembersSelected: _onMembersSelected,
        onCancel: () {
          _isMentionPickerShowing = false;
          // Keep the '@' character when cancelled (per spec requirement)
          // No action needed - '@' remains in input
          //
          // 取消时保留 '@' 字符（根据规范要求）无需操作 - '@' 保留在输入框中
        },
      ),
    )
        .then((_) {
      _isMentionPickerShowing = false;
      // After the picker route pops (whether by selecting members or by
      // cancelling), restore the input state so the typed text is visible
      // and the keyboard pops back up for continued editing.
      //
      // 在选择器弹出后（无论是通过选择成员还是取消），恢复输入状态，使已输入的文字可见，并弹出键盘以继续编辑。
      if (!mounted) return;
      if (_textEditingController.text.isNotEmpty &&
          _inputMode != _InputMode.voice) {
        if (_inputMode != _InputMode.text) {
          setState(() {
            _inputMode = _InputMode.text;
          });
        }
        _textEditingFocusNode.requestFocus();
      }
    });
  }

  /// Handle selected members from picker
  ///
  /// 处理从选择器中选中的成员
  void _onMembersSelected(List<MentionInfo> mentions) {
    Navigator.of(context).pop();
    _isMentionPickerShowing = false;

    if (mentions.isEmpty) {
      // Keep the '@' character when no member selected (per spec requirement)
      //
      // 未选择成员时保留 '@' 字符（根据规范要求）
      return;
    }

    final text = _textEditingController.text;
    final cursorPos = _textEditingController.selection.baseOffset;

    // Find the position of the '@' or '＠' that triggered the picker
    //
    // 查找触发选择器的 '@' 或 '＠' 的位置
    int atPos = cursorPos - 1;
    bool isAtSymbol(String char) => char == '@' || char == '＠';

    if (atPos < 0 || !isAtSymbol(text[atPos])) {
      // '@' not found at expected position, try to find it
      //
      // 在预期位置未找到 '@'，尝试查找它
      for (int i = cursorPos - 1; i >= 0; i--) {
        if (isAtSymbol(text[i])) {
          atPos = i;
          break;
        }
      }
    }

    // Remove the triggering '@' character - use atPos + 1 to skip the '@'
    //
    // 删除触发的 '@' 字符 - 使用 atPos + 1 跳过 '@'
    final beforeAt = text.substring(0, atPos);
    final afterAt = text.substring(
      atPos + 1,
    ); // Skip the '@' that triggered the picker

    // Build the mention text to insert (each mention includes its own '@')
    //
    // 构建要插入的提及文本（每个提及都包含自己的 '@'）
    final StringBuffer mentionBuffer = StringBuffer();
    int currentPos = atPos;

    for (int i = 0; i < mentions.length; i++) {
      final mention = mentions[i];
      final mentionText = mention.mentionText; // "@displayName "
      mentionBuffer.write(mentionText);

      // Update mention with correct position and add to controller
      //
      // 更新提及的正确位置并添加到控制器
      final updatedMention = mention.copyWith(startIndex: currentPos);
      _textEditingController.addMention(updatedMention);
      currentPos += mentionText.length;
    }

    final newText = '$beforeAt$mentionBuffer$afterAt';

    // Temporarily disable listener and mark as internal update to prevent
    // the value setter from incorrectly adjusting mention positions
    //
    // 临时禁用监听器并标记为内部更新，以防值设置器错误调整提及位置
    _textEditingController.removeListener(_onTextChanged);
    _textEditingController._isInternalUpdate = true;
    _textEditingController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: currentPos),
    );
    _textEditingController._isInternalUpdate = false;
    _previousTextLength = newText.length;
    _textEditingController.addListener(_onTextChanged);

    // Explicitly switch back to text mode so the input field renders the
    // mention text instead of the idle hint. Defensive: even if focus state
    // gets out of sync, the UI will still show the typed content.
    //
    // 显式切回文本模式，这样输入框会显示提及的文本而不是空闲提示。防御性处理：即使焦点状态不同步，界面仍会显示已输入的内容。
    setState(() {
      _inputMode = _InputMode.text;
    });
    // 成员选择回填不能用“非空”绕过4000字符上限。
    _onTextChanged();
    _textEditingFocusNode.requestFocus();
  }

  /// 共用键盘仅修改当前活动输入区，展开编辑器时不能写入隐藏的普通草稿。
  void _onEmojiClicked(Map<String, dynamic> data) {
    if (_isRichContentEditorOpen) {
      _richContentEditorKey.currentState?.insertEmoji(data['name'] as String);
      return;
    }
    if (data['eventType'] != 'stickClick' || data['type'] != 0) return;
    final code = data['name'] as String;
    if (EmojiManager.getEmoji(code) == null) return;
    final current = _textEditingController.value;
    final selection = current.selection.isValid
        ? current.selection
        : TextSelection.collapsed(offset: current.text.length);
    _textEditingController.value = TextEditingValue(
      text: current.text.replaceRange(selection.start, selection.end, code),
      selection: TextSelection.collapsed(offset: selection.start + code.length),
    );
  }

  /// 将表情键盘退格交给当前输入区，普通输入仍保留提及和表情的原子删除。
  void _onDeleteClick() {
    if (_isRichContentEditorOpen) {
      _richContentEditorKey.currentState?.deleteEmojiCharacter();
      return;
    }
    final text = _textEditingController.text;
    if (text.isEmpty) return;

    final cursorPos = _textEditingController.selection.baseOffset;
    final targetPos = cursorPos == -1 ? text.length : cursorPos;

    // First check if we're deleting a mention (cursor at end or inside)
    //
    // 先检查是否在删除提及（光标在末尾或内部）
    MentionInfo? mentionToDelete = _textEditingController.getMentionEndingAt(
      targetPos,
    );
    mentionToDelete ??= _textEditingController.getMentionAt(targetPos);

    if (mentionToDelete != null) {
      // Delete the entire mention
      //
      // 删除整个提及
      _textEditingController._isInternalUpdate = true;
      final newText = text.substring(0, mentionToDelete.startIndex) +
          text.substring(mentionToDelete.endIndex);
      _textEditingController._mentions.remove(mentionToDelete);

      // Update positions of mentions after the removed one
      //
      // 更新被删除提及之后的提及位置
      final removedLength = mentionToDelete.length;
      for (final m in _textEditingController._mentions) {
        if (m.startIndex > mentionToDelete.startIndex) {
          m.startIndex -= removedLength;
        }
      }

      _textEditingController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: mentionToDelete.startIndex),
      );
      _textEditingController._isInternalUpdate = false;
      return;
    }

    _textEditingController.value = deleteMessageCharacterBefore(
      _textEditingController.value.copyWith(
        selection: TextSelection.collapsed(offset: targetPos),
      ),
    );
  }

  /// 在统一并发边界内发送普通文字，保留现有发送前清理与失败消息重试策略。
  Future<void> _handleTextSendMessagePayload() async {
    await _runTextSend(() async {
      final rawText = _textEditingController.text;
      if (rawText.trim().isEmpty ||
          messageTextCharacterCount(rawText) > messageTextCharacterLimit) {
        return false;
      }
      final messageInfo = MessageInfo()
        ..messageType = MessageType.text
        ..messagePayload = TextMessagePayload(text: rawText.trim())
        ..atUserList = _textEditingController.mentionList
            .map((mention) => mention.userID)
            .toList();

      // 提及先于正文清理，避免控制器误判提及编辑；清理只由首个受保护任务执行。
      _textEditingController.clearMentions();
      _textEditingController._isInternalUpdate = true;
      _textEditingController.clear();
      _textEditingController._isInternalUpdate = false;
      _clearDraft();
      final result = await _sendMessage(messageInfo);
      return result.isSuccess;
    });
  }

  /// 本地媒体允许点击发送后再上传，未配置上传能力时只接受已就绪的远端草稿。
  bool _canSubmitRichContentDraft(RichContentDraft draft) =>
      draft.canSubmit &&
      (draft.canSend || widget.config.richContentAttachmentUploader != null);

  /// 发送当前活动编辑区的草稿；展开编辑器继续负责校验和发送后的关闭行为。
  Future<void> _handleInputSend() async {
    if (_isRichContentEditorOpen) {
      await _richContentEditorKey.currentState?.send();
      return;
    }
    if (!_inlineRichContentEnabled) {
      await _handleTextSendMessagePayload();
      return;
    }
    await _sendRichContentDraft(
      _buildInlineRichContentDraft(),
      atUserList: _textEditingController.mentionList
          .map((mention) => mention.userID)
          .toList(),
    );
  }

  /// 本地气泡接管后只清理对应的普通草稿，新输入和新打开的编辑器继续保留。
  void _clearSentRichContentDraft(RichContentDraft sent) {
    if (!mounted ||
        _isRichContentEditorOpen ||
        !sent.hasSameContentAs(_buildInlineRichContentDraft())) {
      return;
    }
    // 确认内容仍一致后，一起清理输入、附件和持久化草稿；失败重试交给气泡任务。
    _textEditingController.clearMentions();
    _inlineRichContentAttachments.clear();
    _richContentDraft = const RichContentDraft();
    _textEditingController._isInternalUpdate = true;
    _textEditingController.clear();
    _textEditingController._isInternalUpdate = false;
    _clearDraft();
    setState(() {
      _inlineRichContentEnabled = false;
      _showTextFormattingToolbar = false;
      _activeInlineFormats.clear();
    });
  }

  /// 在现有工具条上方展开富文本编辑器，不重建键盘输入连接。
  void _openRichContentEditor() {
    if (_richContentEditorOverlay != null) return;
    final keepEmoji = _showEmojiPanel;
    final keyboardHeight = _keyboardPanel?.height;
    final selection = _textEditingController.selection;
    // 输入框已聚焦时保留输入连接，等待展开编辑器的正文首帧直接接管焦点。
    if (_textEditingFocusNode.hasFocus) _isSwitchingPanel = true;
    setState(() {
      _showMorePanel = false;
      _isRichContentEditorOpen = true;
    });
    // 工具条完成本帧布局后再建立覆盖层，确保编辑器底部精确贴合工具条顶部。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isRichContentEditorOpen) return;
      final overlay = Overlay.of(context);
      final entry = OverlayEntry(
        builder: (overlayContext) {
          final overlayBox = overlay.context.findRenderObject() as RenderBox?;
          final toolbarBox = _sharedToolbarAnchorKey.currentContext
              ?.findRenderObject() as RenderBox?;
          final overlayHeight = MediaQuery.sizeOf(overlayContext).height;
          final toolbarOffset = overlayBox == null || toolbarBox == null
              ? Offset(0, overlayHeight - 38)
              : toolbarBox.localToGlobal(Offset.zero, ancestor: overlayBox);
          final toolbarSize =
              toolbarBox?.size ?? Size(overlayBox?.size.width ?? 0, 38);
          final toolbarRect = toolbarOffset & toolbarSize;
          final toolbarTop = toolbarRect.top;
          final editorBottom = toolbarTop.clamp(58.0, overlayHeight).toDouble();
          // 编辑器先绘制、共享工具条后绘制，确保动画层级不会压住工具条。
          return RichContentEditorOverlayLayout(
            editorBottom: editorBottom,
            toolbarRect: toolbarRect,
            editor: RichContentEditorSheet(
              key: _richContentEditorKey,
              conversationName: widget.conversationDisplayName ??
                  _conversationInfo?.title ??
                  widget.conversationID,
              initialDraft: _buildInlineRichContentDraft(),
              canUploadAttachments:
                  widget.config.richContentAttachmentUploader != null,
              videoPlayIcon: widget.config.videoPlayIcon,
              imageLoadingPlaceholder: widget.config.imageLoadingPlaceholder,
              videoLoadingPlaceholder: widget.config.videoLoadingPlaceholder,
              onSend: _sendRichContentDraft,
              onClose: _closeRichContentEditor,
              onToolbarChanged: _refreshSharedToolbar,
              onDraftChanged: _rememberRichContentDraft,
              onMediaPrepared: _acceptPreparedRichContentMedia,
              showToolbar: false,
              initialShowFormatting: _showTextFormattingToolbar,
              initialActiveFormats: _activeInlineFormats,
              initialShowEmojiPanel: keepEmoji,
              initialKeyboardHeight: keyboardHeight,
              initialSelection: selection,
            ),
            toolbar: Material(
              type: MaterialType.transparency,
              child: _buildSharedToolbar(
                key: const Key('rich_content_overlay_toolbar'),
              ),
            ),
          );
        },
      );
      _richContentEditorOverlay = entry;
      overlay.insert(entry);
    });
  }

  /// 缓存展开编辑器的最新草稿，并沿用输入区现有防抖保存策略。
  void _rememberRichContentDraft(RichContentDraft draft) {
    if (!draft.hasSameContentAs(_richContentDraft)) {
      _draftRevision++;
    }
    _richContentDraft = draft;
    _updateTextLimitFeedback(draft.characterCount);
    _scheduleDraftSave();
  }

  /// 合并本地处理结果，收起或重开编辑器时仍保留删除操作和新增文字。
  void _acceptPreparedRichContentMedia(RichContentDraftAttachmentBlock original,
      RichContentDraftAttachmentBlock result) {
    if (!mounted) return;
    final editor =
        _isRichContentEditorOpen ? _richContentEditorKey.currentState : null;
    if (editor != null) {
      editor.applyPreparedMedia(original, result);
      return;
    }
    // 块 ID 可被新草稿复用，只有同一附件且令牌仍在正文时才接受结果。
    if (!identical(_inlineRichContentAttachments[original.id]?.attachment,
            original.attachment) ||
        !_textEditingController.text
            .contains(richContentAttachmentToken(original.id))) {
      return;
    }
    setState(() {
      _inlineRichContentAttachments[original.id] = result;
      _richContentDraft = _buildInlineRichContentDraft();
      _showSendButton = _canSubmitRichContentDraft(_richContentDraft);
    });
    _scheduleDraftSave();
  }

  /// 收起时向普通输入交接草稿、选区和键盘模式，成功发送则清空并关闭表情面板。
  void _closeRichContentEditor(RichContentEditorResult result) {
    final editor = _richContentEditorKey.currentState;
    final keepEmoji = !result.sent && (editor?.showEmojiPanel ?? false);
    final keyboardHeight = editor?.keyboardPanel?.height;
    final selection = result.sent ? null : editor?.inlineSelection;
    if (editor != null) {
      _showTextFormattingToolbar = editor.showFormatting;
      _activeInlineFormats
        ..clear()
        ..addAll(editor.activeFormats);
    }
    _richContentEditorOverlay?.remove();
    _richContentEditorOverlay = null;
    if (!mounted) return;
    _restoreInlineRichContentDraft(result.draft, selection: selection);
    if (result.sent) _clearDraft();
    setState(() {
      _isRichContentEditorOpen = false;
      _showEmojiPanel = keepEmoji;
      _inputMode = !result.sent && (result.draft.hasContent || keepEmoji)
          ? _InputMode.text
          : _inputMode;
      _inlineRichContentEnabled = !result.sent &&
          (result.draft.hasContent || _inlineRichContentEnabled);
    });
    if (keepEmoji) {
      // 接收方先按custom模式重建，再交接焦点，收起编辑器不能触发系统键盘。
      _keyboardPanel!
          .showEmoji(_textEditingFocusNode, previousHeight: keyboardHeight);
    }
  }

  /// 把普通输入框的文字与附件令牌还原为有序富文本草稿。
  RichContentDraft _buildInlineRichContentDraft() {
    final blocks = <RichContentDraftBlock>[];
    final text = _textEditingController.text;
    var nextId = _inlineRichContentAttachments.values.fold<int>(
          0,
          (largest, block) => block.id > largest ? block.id : largest,
        ) +
        1;
    var offset = 0;
    // 令牌位置就是块顺序，拆分时保留其前后的 Markdown 原文。
    for (final match in richContentAttachmentTokenPattern.allMatches(text)) {
      final leading = text.substring(offset, match.start);
      if (leading.isNotEmpty) {
        blocks.add(RichContentDraftTextBlock(nextId++, leading));
      }
      final attachment =
          _inlineRichContentAttachments[int.parse(match.group(1)!)];
      if (attachment != null) blocks.add(attachment);
      offset = match.end;
    }
    final trailing = text.substring(offset);
    if (trailing.isNotEmpty) {
      blocks.add(RichContentDraftTextBlock(nextId, trailing));
    }
    return RichContentDraft(title: _richContentDraft.title, blocks: blocks);
  }

  /// 把展开编辑器的有序块转为普通输入框可编辑的附件令牌。
  void _restoreInlineRichContentDraft(RichContentDraft draft,
      {TextSelection? selection}) {
    _richContentDraft = draft;
    _inlineRichContentAttachments.clear();
    final text = StringBuffer();
    // 文字原样写入，附件改写为可逆令牌，不另外维护一份排序。
    for (final block in draft.blocks) {
      switch (block) {
        case RichContentDraftTextBlock block:
          text.write(block.text);
        case RichContentDraftAttachmentBlock block:
          _inlineRichContentAttachments[block.id] = block;
          text.write(richContentAttachmentToken(block.id));
      }
    }
    // 一次替换控制器值，避免中间态让草稿监听器丢失附件。
    final value = text.toString();
    _textEditingController.value = TextEditingValue(
      text: value,
      // 草稿转换后校验选区边界，保留反向选区和光标位置，未提供时沿用末尾回填。
      selection: selection?.isValid == true
          ? selection!.copyWith(
              baseOffset: selection.baseOffset.clamp(0, value.length),
              extentOffset: selection.extentOffset.clamp(0, value.length))
          : TextSelection.collapsed(offset: value.length),
    );
  }

  /// 把编辑器中的工具条模式同步回共享状态，避免展开和收起时回落默认值。
  void _refreshSharedToolbar() {
    if (!mounted) return;
    final editor = _richContentEditorKey.currentState;
    setState(() {
      if (editor == null) return;
      _showTextFormattingToolbar = editor.showFormatting;
      _activeInlineFormats
        ..clear()
        ..addAll(editor.activeFormats);
    });
    // 父级工具条完成本帧布局后再重建覆盖层，避免读取切换前的顶部坐标。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _richContentEditorOverlay?.markNeedsBuild();
    });
  }

  /// 点击发送即发布本地气泡并交出草稿，上传与 SDK 发送由气泡任务继续管理。
  Future<bool> _sendRichContentDraft(
    RichContentDraft draft, {
    List<String> atUserList = const [],
  }) =>
      _runTextSend(() async {
        if (!_canSubmitRichContentDraft(draft)) return false;
        // 纯文字及已上传草稿直接交给 SDK，由其现有气泡管理发送和失败状态。
        if (draft.toMessage() case final RichContentMessage content) {
          final result = await _sendMessage(MessageInfo(
            messageType: MessageType.custom,
            messagePayload: CustomMessagePayload(
              customData: content.toCustomData(),
              description: _trimPushDescription(content.plainTextPreview),
            ),
            atUserList: atUserList,
          ));
          if (result.isSuccess) _clearSentRichContentDraft(draft);
          return result.isSuccess;
        }
        // 固定发送时的引用和推送选项，输入区继续编辑不能改变后台任务。
        final preview = draft.localPreview;
        final message = MessageInfo(
          messageType: MessageType.custom,
          messagePayload: CustomMessagePayload(
            description: _trimPushDescription(preview.plainTextPreview),
          ),
          atUserList: atUserList,
        );
        final option = _createSendOption(message);
        PendingRichContentMessage(
          draft: draft,
          conversationID: widget.conversationID,
          option: option,
          guard: _textSendGuard,
          store: _messageInputStore,
          uploader: widget.config.richContentAttachmentUploader,
          mediaSender: widget.config.mediaSender,
        ).start();
        // 本地气泡已接管内容和失败重试，立即释放输入区，展开编辑器由返回值关闭。
        _clearSentRichContentDraft(draft);
        clearQuotedMessage();
        return true;
      });

  /// 合并同会话的文字发送，确保提示、状态清理和外部调用各执行一次。
  Future<bool> _runTextSend(Future<bool> Function() action) =>
      _textSendGuard.singleFlight<bool>(
        'tim.text-send:${widget.conversationID}',
        () async {
          if (!mounted) return false;
          setState(() => _isSendingText = true);
          try {
            return await action();
          } on Object catch (error) {
            // SDK抛出异常也必须恢复交互，不能让发送按钮永久停留在忙碌态。
            if (mounted) Toast.error(context, atomicLocale.sendMessageFail);
            debugPrint('聊天文字发送异常: $error');
            return false;
          } finally {
            if (mounted) setState(() => _isSendingText = false);
          }
        },
      );

  void _onPickAlbum() async {
    // 点击时重新判断模式，避免切换帧内残留的普通回调把图片作为独立消息发送。
    if (_isRichContentEditorOpen) {
      await _richContentEditorKey.currentState?.pickAlbumMedia();
      return;
    }
    final locale = Localizations.localeOf(context);

    AlbumPickerConfig config = AlbumPickerConfig(
      mediaFilter: AlbumPickerMediaFilter.imageAndVideo,
      maxSelectionCount: 9,
      itemsPerRow: 3,
      showsCameraItem: false,
      style: AlbumPickerStyle.likeWeChat,
      language: _localeToAlbumPickerLanguage(locale),
    );

    AlbumPickerTheme theme = AlbumPickerTheme(
      primaryColor: Theme.of(context).colorScheme.primary,
    );

    try {
      await AlbumPickerMediaSendManager.shared.pickAlbumMedia(
        conversationID: widget.conversationID,
        listener: _albumPickerListener,
        config: config,
        theme: theme,
      );
    } catch (e) {
      debugPrint("_onPickAlbum error: $e");
    }
  }

  AlbumPickerLanguage _localeToAlbumPickerLanguage(Locale? locale) {
    if (locale == null) return AlbumPickerLanguage.system;
    if (locale.languageCode == 'zh') {
      return (locale.scriptCode == 'Hant')
          ? AlbumPickerLanguage.zhHant
          : AlbumPickerLanguage.zhHans;
    }
    if (locale.languageCode == 'ar') return AlbumPickerLanguage.ar;
    if (locale.languageCode == 'en') return AlbumPickerLanguage.en;
    return AlbumPickerLanguage.system;
  }

  /// 所有独立消息在此组合引用与推送选项，再交给宿主统一分流媒体。
  Future<CompletionHandler> _sendMessage(MessageInfo messageInfo) async {
    final payload = _convertToSendPayload(messageInfo.messagePayload);
    if (payload == null) {
      return CompletionHandler()
        ..errorCode = -1
        ..errorMessage = "Unsupported payload";
    }

    // If quoting a message, set quoteInfo on the outgoing message
    MessageInfo? quotedMsg = _quotedMessage;
    if (quotedMsg != null) {
      messageInfo.quoteInfo = MessageQuoteInfo(
        msgID: quotedMsg.msgID,
        timestamp: quotedMsg.timestamp ?? 0,
        sequence: quotedMsg.sequence ?? 0,
        sender: quotedMsg.from,
        messageType: quotedMsg.messageType,
        messagePayload: quotedMsg.messagePayload,
      );
    }

    final option = _createSendOption(messageInfo);

    final result = await sendChatMedia(
      message: messageInfo,
      conversationID: widget.conversationID,
      sender: widget.config.mediaSender,
      onRetryFailure: () {
        if (mounted) Toast.error(context, atomicLocale.sendMessageFail);
      },
      store: _messageInputStore,
      payload: payload,
      option: option,
    );
    if (!result.isSuccess) {
      if (mounted) {
        Toast.error(context, atomicLocale.sendMessageFail);
      }
    } else {
      // Clear quoted message after successful send
      //
      // 成功发送后清除引用消息
      clearQuotedMessage();
    }

    return result;
  }

  /// 固定点击发送时的提及、引用、回执和推送，后台上传不能读取输入框后续状态。
  SendMessageOption _createSendOption(MessageInfo message) => SendMessageOption(
        atUserList: message.atUserList.isNotEmpty ? message.atUserList : null,
        quotedMessage: _quotedMessage,
        needReadReceipt: widget.config.enableReadReceipt,
        offlinePushInfo: _createOfflinePushInfo(message),
      );

  void _sendPlaceholderMessage(MessageInfo placeholder) {
    notificationCenter.post(
      MessageSendNotifyKey.messageSendBegin,
      MessageSendEventData(
        conversationID: widget.conversationID,
        message: placeholder,
      ),
    );
  }

  void _removePlaceholderMessage(MessageInfo placeholder) {
    if (placeholder.msgID.isNotEmpty) {
      notificationCenter.post(
        MessageActionNotifyKey.messageDelete,
        MessageDeleteEventData(messageIDList: [placeholder.msgID]),
      );
    }
  }

  static SendMessagePayload? _convertToSendPayload(MessagePayload? payload) {
    if (payload == null || payload is PendingRichContentMessage) return null;
    switch (payload) {
      case TextMessagePayload p:
        return TextSendMessagePayload(text: p.text);
      case ImageMessagePayload p:
        return ImageSendMessagePayload(
          imagePath: p.originalImagePath ?? '',
          imageWidth: p.originalImageWidth,
          imageHeight: p.originalImageHeight,
        );
      case VideoMessagePayload p:
        return VideoSendMessagePayload(
          videoFilePath: p.videoPath ?? '',
          videoType: p.videoType ?? '',
          duration: p.videoDuration,
          snapshotPath: p.videoSnapshotPath ?? '',
        );
      case AudioMessagePayload p:
        return AudioSendMessagePayload(
          audioFilePath: p.audioPath ?? '',
          duration: p.audioDuration,
        );
      case FileMessagePayload p:
        return FileSendMessagePayload(
          filePath: p.filePath ?? '',
          fileName: p.fileName ?? '',
          fileSize: p.fileSize,
        );
      case FaceMessagePayload p:
        return FaceSendMessagePayload(
          index: p.faceIndex,
          data: p.faceData ?? '',
        );
      case CustomMessagePayload p:
        return CustomSendMessagePayload(
          customData: p.customData,
          description: p.description,
          extensionInfo: p.extensionInfo,
        );
      default:
        return null;
    }
  }

  // ==================== Offline Push Info ====================
  //
  // ==================== 离线推送信息 ====================

  /// Create offline push info for a message
  ///
  /// 为消息创建离线推送信息
  OfflinePushInfo _createOfflinePushInfo(MessageInfo message) {
    final conversationID = widget.conversationID;
    final isGroup = conversationID.startsWith(_groupConversationIDPrefix);
    final groupId = isGroup
        ? conversationID.substring(_groupConversationIDPrefix.length)
        : '';

    final loginUserInfo = LoginStore.shared.loginState.loginUserInfo;
    final selfUserId = loginUserInfo?.userID ?? '';
    final selfName = loginUserInfo?.nickname ?? selfUserId;

    final chatName = (_conversationInfo?.title?.isNotEmpty ?? false)
        ? _conversationInfo?.title
        : null;

    final senderNickName = isGroup ? (chatName ?? groupId) : selfName;

    final description = _createOfflinePushDescription(message);
    final ext = _createOfflinePushExtJson(
      isGroup: isGroup,
      senderId: isGroup ? groupId : selfUserId,
      senderNickName: senderNickName,
      faceUrl: loginUserInfo?.avatarURL,
      version: 1,
      action: 1,
      content: description,
      customData: null,
    );

    final pushInfo = OfflinePushInfo();
    pushInfo.title = senderNickName;
    pushInfo.description = description;
    pushInfo.extensionInfo = {
      'ext': ext,
      'AndroidOPPOChannelID': 'tuikit',
      'AndroidHuaWeiCategory': 'IM',
      'AndroidVIVOCategory': 'IM',
      'AndroidHonorImportance': 'NORMAL',
      'AndroidMeizuNotifyType': 1,
      'iOSInterruptionLevel': 'time-sensitive',
      'enableIOSBackgroundNotification': false,
    };

    return pushInfo;
  }

  /// Create offline push description for a message
  ///
  /// 为消息创建离线推送描述
  String _createOfflinePushDescription(MessageInfo message) {
    String content;
    switch (message.messageType) {
      case MessageType.text:
        // Convert emoji codes to localized names
        //
        // 将表情代码转换为本地化名称
        content = EmojiManager.createLocalizedStringFromEmojiCodes(
          context,
          (message.messagePayload as TextMessagePayload?)?.text ?? '',
        );
        break;
      case MessageType.image:
        content = atomicLocale.messageTypeImage;
        break;
      case MessageType.video:
        content = atomicLocale.messageTypeVideo;
        break;
      case MessageType.file:
        content = atomicLocale.messageTypeFile;
        break;
      case MessageType.audio:
        content = atomicLocale.messageTypeVoice;
        break;
      case MessageType.face:
        content = atomicLocale.messageTypeSticker;
        break;
      case MessageType.merged:
        content = '[${atomicLocale.chatHistory}]';
        break;
      case MessageType.custom:
        final custom = message.messagePayload as CustomMessagePayload?;
        // 本地富文本的推送先使用正文摘要，不能为生成推送把本地路径写入协议。
        content = BigFileMessage.tryParse(custom?.customData) != null
            ? atomicLocale.messageTypeFile
            : RichContentMessage.tryParse(custom?.customData)
                    ?.plainTextPreview ??
                custom?.description ??
                '';
        break;
      default:
        content = '';
    }
    return _trimPushDescription(content);
  }

  /// Trim push description to max length
  ///
  /// 将推送描述截取到最大长度
  String _trimPushDescription(String text, {int maxLength = 50}) {
    final normalized = text.trim().replaceAll('\n', ' ').replaceAll('\r', ' ');
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return normalized.substring(0, maxLength);
  }

  /// Create offline push ext JSON string (same as Swift's createOfflinePushExtJson)
  ///
  /// 创建离线推送扩展 JSON 字符串（和 Swift 的 createOfflinePushExtJson 一样）
  String _createOfflinePushExtJson({
    required bool isGroup,
    required String senderId,
    required String senderNickName,
    String? faceUrl,
    required int version,
    required int action,
    String? content,
    String? customData,
  }) {
    final entity = <String, dynamic>{
      'sender': senderId,
      'nickname': senderNickName,
      'chatType': isGroup ? 2 : 1,
      'version': version,
      'action': action,
    };

    if (content != null && content.isNotEmpty) {
      entity['content'] = content;
    }
    if (faceUrl != null) {
      entity['faceUrl'] = faceUrl;
    }
    if (customData != null) {
      entity['customData'] = customData;
    }

    final timPushFeatures = <String, int>{
      'fcmPushType': 0,
      'fcmNotificationType': 0,
    };

    final extDict = <String, dynamic>{
      'entity': entity,
      'timPushFeatures': timPushFeatures,
    };

    try {
      return jsonEncode(extDict);
    } catch (e) {
      return '{}';
    }
  }

  /// 仅在普通输入模式选择并发送文件，富文本编辑器展开期间不接受文件操作。
  void _onPickFile() async {
    if (_isRichContentEditorOpen) return;
    final selector = widget.config.fileSelector;
    if (selector != null) {
      final messages = await selector(context);
      // 选择页一次返回多份附件，每份独立发送并保留顺序。
      for (final message in messages) {
        if (!mounted) return;
        await _sendMessage(message);
      }
      return;
    }
    // 宿主未接管文件选择时使用 SDK 选择器，仍按独立文件消息逐份发送。
    List<PickerResult> filePickerResults = await FilePicker.pickFiles(
      context: context,
      config: FilePickerConfig(maxCount: 10),
    );

    if (filePickerResults.isNotEmpty) {
      for (final filePickerResult in filePickerResults) {
        final messageInfo = MessageInfo();
        messageInfo.messageType = MessageType.file;
        messageInfo.messagePayload = FileMessagePayload(
          filePath: filePickerResult.filePath,
          fileName: filePickerResult.fileName,
          fileSize: filePickerResult.fileSize,
        );
        final result = await _sendMessage(messageInfo);
        if (!result.isSuccess) {
          debugPrint(
            "_onPickFile, errorCode:${result.errorCode}, errorMessage:${result.errorMessage}",
          );
        }
      }
    }
  }

  Future<void> _onAudioCallTap() => _startCall(CallMediaType.audio);

  Future<void> _onVideoCallTap() => _startCall(CallMediaType.video);

  Future<void> _startCall(CallMediaType mediaType) async {
    final groupID = ChatUtil.getGroupID(widget.conversationID);
    final isGroup = groupID.isNotEmpty;

    List<String> participantIds;
    String? chatGroupId;

    if (!isGroup) {
      // c2c — single peer derived from the conversationID.
      //
      // c2c — 单个对等者，从 conversationID 得出。
      participantIds = [ChatUtil.getUserID(widget.conversationID)];
    } else {
      chatGroupId = groupID;
      final selectedMembers =
          await context.pushChatUIKitPage<List<UserPickerData>>(
        GroupMemberPicker(groupID: groupID),
      );
      if (selectedMembers == null || selectedMembers.isEmpty) {
        // User cancelled the picker — abort the call.
        //
        // 用户取消了选择器 — 中止调用。
        return;
      }
      participantIds = selectedMembers.map((member) => member.key).toList();
    }

    final params = PublishParams()
      ..isSticky = false
      ..data = {
        "participantIds": participantIds,
        "mediaType": mediaType,
        "chatGroupId": chatGroupId,
        "timeout": 30,
      };
    TUIEventBus.shared.publish("call.startCall", null, params);
    UIKitUtil.reportChatInvokeCall();
  }

  void _onTakeVideo() async {
    try {
      VideoRecorderResult result = await VideoRecorder.startRecord(
        context: context,
        config: const VideoRecorderConfig(
          recordMode: RecordMode.mixed,
          minDurationMs: 500,
        ),
      );

      if (result.filePath.isEmpty) {
        return;
      }

      final messageInfo = MessageInfo();

      if (result.mediaType == RecordMediaType.photo) {
        messageInfo.messageType = MessageType.image;
        final size = await ImageSizeReader.read(result.filePath);
        messageInfo.messagePayload = ImageMessagePayload(
          originalImagePath: result.filePath,
          originalImageWidth: size?.width ?? 0,
          originalImageHeight: size?.height ?? 0,
        );
      } else {
        messageInfo.messageType = MessageType.video;
        messageInfo.messagePayload = VideoMessagePayload(
          videoPath: result.filePath,
          videoSnapshotPath: result.thumbnailPath,
          videoType: result.filePath.split('.').last,
          videoDuration: (result.durationMs != null)
              ? (result.durationMs! / 1000).round()
              : 0,
        );
      }

      final sendResult = await _sendMessage(messageInfo);
      if (!sendResult.isSuccess) {
        debugPrint(
          "_onTakeVideo, errorCode:${sendResult.errorCode}, errorMessage:${sendResult.errorMessage}",
        );
      }
    } catch (e) {
      debugPrint("_onTakeVideo error: $e");
    }
  }

  void _onTakePhoto() async {
    try {
      VideoRecorderResult result = await VideoRecorder.startRecord(
        context: context,
        config: const VideoRecorderConfig(recordMode: RecordMode.photoOnly),
      );

      if (result.filePath.isEmpty) {
        return;
      }

      final messageInfo = MessageInfo();
      messageInfo.messageType = MessageType.image;
      final size = await ImageSizeReader.read(result.filePath);
      messageInfo.messagePayload = ImageMessagePayload(
        originalImagePath: result.filePath,
        originalImageWidth: size?.width ?? 0,
        originalImageHeight: size?.height ?? 0,
      );
      final sendResult = await _sendMessage(messageInfo);
      if (!sendResult.isSuccess) {
        debugPrint(
          "_onTakePhoto, errorCode:${sendResult.errorCode}, errorMessage:${sendResult.errorMessage}",
        );
      }
    } catch (e) {
      debugPrint("_onTakePhoto error: $e");
    }
  }

  /// 在宿主上下文内捕获主题，单聊预览与旧录音浮层各自持有独立生命周期。
  void _showRecordOverlay() {
    _removeRecordOverlay();

    if (widget.config.previewVoiceBeforeSend) {
      _recordOverlayEntry = OverlayEntry(
          builder: (_) => InheritedTheme.captureAll(
                context,
                VoiceRecordPreview(
                  key: _voicePreviewKey,
                  guard: _textSendGuard,
                  onSendAudio: _onAudioRecorderFinished,
                  onSendText: _sendTextMessageFromVoice,
                  onClose: _removeRecordOverlay,
                ),
              ));
      Overlay.of(context).insert(_recordOverlayEntry!);
      return;
    }

    // Capture inherited dependencies from current context before creating
    // the OverlayEntry, since the overlay lives in a different widget subtree
    // and cannot look up these InheritedWidgets.
    //
    // 在创建 OverlayEntry 之前捕获当前上下文继承的依赖，因为 overlay 存在于不同的 widget 子树中，无法查找这些 InheritedWidgets。
    final colorScheme = SemanticColorScheme.of(context);
    final atomicLocalizations = AppLocalization.of(context);
    final overlay = Overlay.of(context);
    final enableConvert = widget.config.enableVoiceToTextOnRecord;

    _recordOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Material(
          type: MaterialType.transparency,
          child: AudioRecordOverlay(
            key: _recordOverlayKey,
            colorScheme: colorScheme,
            atomicLocalizations: atomicLocalizations,
            enableVoiceToText: enableConvert,
            onRecordFinish: (recordInfo) {
              // When the user released on the convert button, we DO NOT close
              // the overlay or send the audio: instead, hand the captured
              // file path to the overlay's converting state machine.
              //
              // 当用户在转换按钮上松开时，我们不会关闭 overlay 或发送音频：相反，将捕获的文件路径交给 overlay 的转换状态机。
              if (_pendingConvertRecord) {
                _pendingConvertRecord = false;
                if (recordInfo.errorCode == AudioRecordResultCode.success ||
                    recordInfo.errorCode ==
                        AudioRecordResultCode.successExceedMaxDuration) {
                  _recordOverlayKey.currentState?.enterConverting(
                    recordInfo.path,
                    recordInfo.duration,
                  );
                  return;
                }
                // Recording too short / failed: fall through to default
                // close-and-toast behavior (legacy path).
                //
                // 录音太短/失败：回退到默认关闭并显示提示的行为（旧路径）。
              }
              _removeRecordOverlay();
              _onAudioRecorderFinished(recordInfo);
            },
            onRecordCancelled: () {
              _pendingConvertRecord = false;
              _removeRecordOverlay();
            },
            onSendText: (text) {
              _removeRecordOverlay();
              _sendTextMessageFromVoice(text);
            },
          ),
        );
      },
    );
    overlay.insert(_recordOverlayEntry!);
  }

  void _removeRecordOverlay() {
    _recordOverlayEntry?.remove();
    _recordOverlayEntry = null;
  }

  /// 发送已确认的完整录音，返回SDK真实结果，失败时预览仍可重试。
  Future<bool> _onAudioRecorderFinished(RecordInfo recordInfo) async {
    if (recordInfo.errorCode != AudioRecordResultCode.success &&
        recordInfo.errorCode !=
            AudioRecordResultCode.successExceedMaxDuration) {
      debugPrint("_onAudioRecorderFinished, errorCode:${recordInfo.errorCode}");
      return false;
    }

    final messageInfo = MessageInfo();
    messageInfo.messageType = MessageType.audio;
    messageInfo.messagePayload = AudioMessagePayload(
      audioPath: recordInfo.path,
      audioDuration: recordInfo.duration,
    );

    try {
      final result = await _sendMessage(messageInfo);
      if (!result.isSuccess && mounted) Toast.error(context, '语音消息发送失败');
      return result.isSuccess;
    } catch (_) {
      if (mounted) Toast.error(context, '语音消息发送失败');
      return false;
    }
  }

  /// 语音转文字确认发送也遵守相同文字上限和同会话并发边界。
  Future<bool> _sendTextMessageFromVoice(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (messageTextCharacterCount(text) > messageTextCharacterLimit) {
      Toast.error(context, atomicLocale.messageTextLimitExceeded);
      return false;
    }
    return _runTextSend(() async {
      final messageInfo = MessageInfo()
        ..messageType = MessageType.text
        ..messagePayload = TextMessagePayload(text: trimmed);
      final result = await _sendMessage(messageInfo);
      if (!result.isSuccess && mounted) Toast.error(context, '发送失败，请重试');
      return result.isSuccess;
    });
  }

  /// 先停止共享播放并确认权限，再保留当前指针的延迟启动；授权结果不补启动旧按压。
  void _onStartRecording(PointerDownEvent event) async {
    final conversationId = widget.conversationID;
    // 权限等待前记录按压状态；系统弹窗吞掉抬手时，本次授权也不直接录音。
    _recordingStarter?.cancel();
    _recordPointerHeld = true;
    _isWaitingToStartRecord = true;

    // 录音等待共享播放队列停止，先到达的抬手仍会撤销本次启动。
    try {
      await voice_audio.AudioPlayer.stopAll();
    } catch (_) {
      _recordPointerHeld = false;
      _isWaitingToStartRecord = false;
      if (mounted) Toast.error(context, '语音录制失败');
      return;
    }
    if (!mounted ||
        !_recordPointerHeld ||
        widget.conversationID != conversationId) {
      return;
    }

    final micStatus = await Permission.check(PermissionType.microphone);
    if (!mounted ||
        !_recordPointerHeld ||
        widget.conversationID != conversationId) {
      return;
    }
    if (micStatus != PermissionStatus.granted) {
      _isWaitingToStartRecord = false;
      _recordPointerHeld = false;
      if (widget.config.previewVoiceBeforeSend) {
        await _textSendGuard.singleFlight<void>(
            ('chat.voice.permission', conversationId), () async {
          final requested =
              await Permission.request([PermissionType.microphone]);
          // 仅双重永久拒绝才提示；旧会话返回的结果不能在新会话弹窗。
          if (mounted &&
              widget.conversationID == conversationId &&
              micStatus == PermissionStatus.permanentlyDenied &&
              requested[PermissionType.microphone] ==
                  PermissionStatus.permanentlyDenied) {
            await AppDialog.showContent<void>(
              theme: Theme.of(context),
              maskColor: context.appColors.scrim.withValues(alpha: .4),
              builder: (_) => const VoiceMicrophoneNotice(),
            );
          }
        });
      } else {
        await Permission.checkAndRequest(context, [PermissionType.microphone]);
      }
      return;
    }

    // 等待期间已抬手或切换会话时，不再插入录音浮层。
    if (!_isWaitingToStartRecord) {
      return;
    }

    // 延迟插入全屏录音覆盖层，使按住说话按钮在启动等待期仍能收到 PointerUp 并正常取消。
    _recordingStarter = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_isWaitingToStartRecord || !_recordPointerHeld) return;
      _isWaitingToStartRecord = false;

      _showRecordOverlay();

      // Overlay's State needs a frame to be constructed before we can drive it.
      //
      // 覆盖层的状态需要一帧时间来构建，然后我们才能操作它。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_recordPointerHeld) {
          _voicePreviewKey.currentState?.cancel();
          _removeRecordOverlay();
          return;
        }
        if (widget.config.previewVoiceBeforeSend) {
          unawaited(_voicePreviewKey.currentState
              ?.startRecord(origin: event.position));
          return;
        }
        final overlayState = _recordOverlayKey.currentState;
        if (overlayState == null) return;
        overlayState.resetRecordingState();
        final String path = ChatUtil.generateMediaPath(
          messageType: MessageType.audio,
          prefix: "",
          withExtension: "m4a",
          isCache: true,
        );
        overlayState.startRecord(filePath: path);
      });
    });
  }

  void _onStopRecording(PointerUpEvent event) {
    _recordPointerHeld = false;
    if (_isWaitingToStartRecord) {
      _recordingStarter?.cancel();
      _recordingStarter = null;
      _isWaitingToStartRecord = false;
      _removeRecordOverlay();

      if (widget.config.previewVoiceBeforeSend) {
        Toast.simple(context, '说话时长太短');
        return;
      }
      _micTooltipKey.currentState?.ensureTooltipVisible();
      Future.delayed(const Duration(seconds: 1), () {
        Tooltip.dismissAllToolTips();
      });
    } else {
      if (widget.config.previewVoiceBeforeSend) {
        _voicePreviewKey.currentState?.updatePointerPosition(event.position);
        _voicePreviewKey.currentState?.stopRecord();
        return;
      }
      final overlayState = _recordOverlayKey.currentState;
      final overCancel =
          overlayState?.isPointerOverCancelButton(event.position) ?? false;
      final overConvert =
          overlayState?.isPointerOverConvertButton(event.position) ?? false;
      final action = recordPointerUpAction(
        overCancel: overCancel,
        overConvert: overConvert,
      );
      switch (action) {
        case RecordPointerUpAction.cancel:
          // cancelRecord callback will call _removeRecordOverlay.
          //
          // cancelRecord 回调会调用 _removeRecordOverlay。
          overlayState?.cancelRecord();
          break;
        case RecordPointerUpAction.convert:
          // Stop recording; the captured file is routed to the overlay's
          // converting state machine in the onRecordFinish handler.
          //
          // 停止录制；捕获到的文件会在 onRecordFinish 处理器里送到 overlay 的转换状态机。
          _pendingConvertRecord = true;
          overlayState?.stopRecord();
          break;
        case RecordPointerUpAction.send:
          // stopRecord callback will call _removeRecordOverlay via onRecordFinish.
          //
          // stopRecord 回调会通过 onRecordFinish 调用 _removeRecordOverlay。
          overlayState?.stopRecord();
          break;
      }
    }
  }

  /// Handle pointer cancel events (e.g. system gesture interception on Android
  /// such as edge-swipe for payment shortcuts or back navigation).
  /// When the system steals the pointer, we need to gracefully stop/cancel
  /// the ongoing recording to avoid leaving it in a stuck state.
  ///
  /// 处理指针取消事件（例如 Android 上的系统手势拦截，比如边缘滑动启动支付快捷方式或返回导航）。当系统抢占指针时，我们需要优雅地停止/取消正在进行的录制，以避免录制卡住。
  void _onRecordingPointerCancel(PointerCancelEvent event) {
    _recordPointerHeld = false;
    if (widget.config.previewVoiceBeforeSend) {
      _recordingStarter?.cancel();
      _isWaitingToStartRecord = false;
      _voicePreviewKey.currentState?.cancel();
      _removeRecordOverlay();
      return;
    }
    if (_isWaitingToStartRecord) {
      _recordingStarter?.cancel();
      _recordingStarter = null;
      _isWaitingToStartRecord = false;
      _removeRecordOverlay();
    } else {
      // System cancelled the gesture — treat as user cancellation
      // (don't send the recording) since the pointer position is unreliable.
      // cancelRecord's callback (onRecordCancelled) will call _removeRecordOverlay.
      //
      // 系统取消了手势——当作用户取消处理（不发送录制内容），因为指针位置不可靠。cancelRecord 的回调（onRecordCancelled）会调用 _removeRecordOverlay。
      _recordOverlayKey.currentState?.cancelRecord();
    }
  }

  Widget _buildMorePanelContent(SemanticColorScheme colorsTheme) {
    final List<_MorePanelItem> items = [];

    if (widget.config.isShowAlbum) {
      items.add(
        _MorePanelItem(
          icon: 'chat_assets/icon/image_action.svg',
          title: atomicLocale.album,
          onTap: _onPickAlbum,
        ),
      );
    }

    if (widget.config.isShowPhotoTaker) {
      items.add(
        _MorePanelItem(
          icon: 'chat_assets/icon/camera_action.svg',
          title: atomicLocale.takeAPhoto,
          onTap: _onTakePhoto,
        ),
      );
    }

    if (widget.config.isShowVideoRecorder) {
      items.add(
        _MorePanelItem(
          icon: 'chat_assets/icon/record_action.svg',
          title: atomicLocale.recordAVideo,
          onTap: _onTakeVideo,
        ),
      );
    }

    if (widget.config.isShowFile) {
      items.add(
        _MorePanelItem(
          icon: 'chat_assets/icon/file_action.svg',
          title: atomicLocale.file,
          onTap: _onPickFile,
        ),
      );
    }

    if (widget.config.isShowVideoCall) {
      items.add(
        _MorePanelItem(
          icon: 'chat_assets/icon/video_call_action.svg',
          title: atomicLocale.videoCall,
          onTap: _onVideoCallTap,
        ),
      );
    }
    if (widget.config.isShowAudioCall) {
      items.add(
        _MorePanelItem(
          icon: 'chat_assets/icon/audio_call_action.svg',
          title: atomicLocale.audioCall,
          onTap: _onAudioCallTap,
        ),
      );
    }

    // Each page shows 2 rows × 4 columns = 8 items max
    const int itemsPerPage = 8;
    final int pageCount =
        items.isEmpty ? 0 : (items.length / itemsPerPage).ceil();

    return Container(
      color: colorsTheme.bgColorInput,
      child: Column(
        children: [
          Container(
            height: 0.5,
            color: colorsTheme.textColorPrimary.withValues(alpha: 0.1),
          ),
          Expanded(
            child: pageCount == 0
                ? const SizedBox.shrink()
                : PageView.builder(
                    itemCount: pageCount,
                    onPageChanged: (index) {
                      setState(() {
                        _morePanelPageIndex = index;
                      });
                    },
                    itemBuilder: (context, pageIndex) {
                      final startIndex = pageIndex * itemsPerPage;
                      final endIndex = (startIndex + itemsPerPage).clamp(
                        0,
                        items.length,
                      );
                      final pageItems = items.sublist(startIndex, endIndex);

                      // Each item row: icon 64 + spacing 8 + text ~14 = ~86pt
                      // Two-row content height: 86 + 20 (gap) + 86 = 192pt
                      const double twoRowHeight = 192;

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final topPadding =
                              ((constraints.maxHeight - twoRowHeight) / 2)
                                  .clamp(8.0, double.infinity);
                          return Padding(
                            padding: EdgeInsets.only(
                              left: 24,
                              right: 24,
                              top: topPadding,
                            ),
                            child: _buildMorePanelPage(pageItems, colorsTheme),
                          );
                        },
                      );
                    },
                  ),
          ),
          // Page indicator dots — always reserve space, hide when only 1 page
          //
          // 页面指示点——始终保留空间，当只有 1 页时隐藏。
          Opacity(
            opacity: pageCount > 1 ? 1.0 : 0.0,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(pageCount > 1 ? pageCount : 1, (index) {
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _morePanelPageIndex
                          ? colorsTheme.textColorTertiary
                          : colorsTheme.switchColorOff,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single page of the more panel grid (up to 2 rows × 4 columns)
  ///
  /// 在更多面板网格中构建单页（最多 2 行 × 4 列）
  Widget _buildMorePanelPage(
    List<_MorePanelItem> pageItems,
    SemanticColorScheme colorsTheme,
  ) {
    const int columns = 4;
    // Split items into rows of 4
    //
    // 将项目拆分为每行 4 个
    final List<List<_MorePanelItem>> rows = [];
    for (int i = 0; i < pageItems.length; i += columns) {
      rows.add(pageItems.sublist(i, (i + columns).clamp(0, pageItems.length)));
    }

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
            if (rowIndex > 0) const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int colIndex = 0; colIndex < columns; colIndex++)
                  if (colIndex < rows[rowIndex].length)
                    _buildMorePanelItemWidget(
                      rows[rowIndex][colIndex],
                      colorsTheme,
                    )
                  else
                    const SizedBox(width: 64), // Placeholder for grid alignment
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Build a single action item widget in the more panel
  ///
  /// 在更多面板中构建单个操作项Widget
  Widget _buildMorePanelItemWidget(
    _MorePanelItem item,
    SemanticColorScheme colorsTheme,
  ) {
    return GestureDetector(
      onTap: item.onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorsTheme.bgColorOperate,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: SvgPicture.asset(
                  item.icon,
                  package: 'tencent_chat_uikit',
                  colorFilter: ColorFilter.mode(
                    colorsTheme.textColorSecondary,
                    BlendMode.srcIn,
                  ),
                  width: 26,
                  height: 22,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: FontScheme.caption3Regular.copyWith(
                color: colorsTheme.textColorSecondary,
                decoration: TextDecoration.none,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _bottomPadding = MediaQuery.paddingOf(context).bottom;
    atomicLocale = AppLocalization.of(context);
    final panelHeight = _getBottomContainerHeight();
    final showEmoji = _isEmojiPanelVisible ||
        (_activeKeyboardPanel?.returningToSystem ?? false);
    if (_richContentEditorOverlay != null) {
      // 键盘 Insets 改变后等待工具条完成布局，再校正编辑器底部锚点。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _richContentEditorOverlay?.markNeedsBuild();
      });
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final colors = SemanticColorScheme.of(context);
        return Column(
          children: [
            _buildInputWidget(colors),
            if (_quotedMessage != null)
              QuotePreviewBar(
                quotedMessage: _quotedMessage!,
                onClose: clearQuotedMessage,
              ),
            AnimatedContainer(
              // 表情与系统遮挡共同填满同一区域，按尺寸通知直接重排，不叠加第二份高度动画。
              // 更多面板仍保留独立展开动画，富文本覆盖层继续使用工具条实测锚点。
              duration: _showMorePanel
                  ? const Duration(milliseconds: 300)
                  : Duration.zero,
              curve: Curves.ease,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(color: colors.bgColorInput),
              height: panelHeight,
              constraints: (showEmoji || _showMorePanel)
                  ? BoxConstraints(minHeight: panelHeight)
                  : null,
              child: showEmoji
                  ? ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: _activeKeyboardPanel?.height ?? 280,
                        maxHeight: _activeKeyboardPanel?.height ?? 280,
                        child: EmojiPicker(
                          onEmojiClick: _onEmojiClicked,
                          onSendClick: _handleInputSend,
                          onDeleteClick: _onDeleteClick,
                        ),
                      ),
                    )
                  : _showMorePanel
                      ? _buildMorePanelContent(colors)
                      : Container(),
            ),
          ],
        );
      },
    );
  }

  Future<bool> getEmojiPanelWidget() async {
    stickerWidget = EmojiPicker(
      onEmojiClick: _onEmojiClicked,
      onSendClick: _handleInputSend,
      onDeleteClick: _onDeleteClick,
    );
    return true;
  }

  /// 输入行与44高快捷栏分别承载，展开态仍保留原输入连接。
  Widget _buildInputWidget(SemanticColorScheme colorsTheme) => Container(
        color: colorsTheme.bgColorInput,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 只隐藏输入行，键盘与草稿继续由同一输入状态持有。
            Offstage(
              key: const Key('message_input_normal_input_offstage'),
              offstage: _isRichContentEditorOpen,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _buildInputRow(colorsTheme),
              ),
            ),
            if (_inputMode != _InputMode.voice)
              KeyedSubtree(
                key: _sharedToolbarAnchorKey,
                child: _buildSharedToolbar(
                  key: const Key('message_input_shared_toolbar'),
                ),
              ),
          ],
        ),
      );

  /// 语音入口固定在输入区底部，文本增高时不跟随正文滚动。
  Widget _buildInputRow(SemanticColorScheme colorsTheme) => Row(
        key: const Key('message_input_normal_input_row'),
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.config.isShowAudioRecorder) ...[
            SizedBox(
              width: 36,
              height: 44,
              child: material.IconButton(
                tooltip: _inputMode == _InputMode.voice ? '切换文字输入' : '切换语音输入',
                onPressed: _toggleVoiceMode,
                padding: EdgeInsets.zero,
                icon: Icon(
                  _inputMode == _InputMode.voice
                      ? AppIcons.inputKeyboard
                      : AppIcons.speak,
                  size: 24,
                  color: colorsTheme.textColorPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: _inputMode == _InputMode.voice
                ? _buildHoldToTalkButton(colorsTheme)
                : _buildTextInputArea(colorsTheme),
          ),
        ],
      );

  /// 构建普通输入和展开编辑器共用同一状态与回调的工具条视图。
  Widget _buildSharedToolbar({required Key key}) {
    final richEditor = _richContentEditorKey.currentState;
    return RichContentInputToolbar(
      key: key,
      switcherKey: const Key('message_input_toolbar_switcher'),
      // 覆盖层与底部工具条同时存在，使用不同前缀保持操作语义唯一。
      keyPrefix: key == const Key('rich_content_overlay_toolbar')
          ? 'rich_content_overlay_toolbar'
          : 'message_input_toolbar',
      showFormatting: _isRichContentEditorOpen
          ? richEditor?.showFormatting ?? _showTextFormattingToolbar
          : _showTextFormattingToolbar,
      activeFormats: _isRichContentEditorOpen
          ? richEditor?.activeFormats ?? _activeInlineFormats
          : _activeInlineFormats,
      canSend: !_isSendingText &&
          (_isRichContentEditorOpen
              ? richEditor?.canSend ?? _showSendButton
              : _inlineRichContentEnabled
                  ? _canSubmitRichContentDraft(_buildInlineRichContentDraft())
                  : _showSendButton),
      showKeyboard: _isEmojiPanelVisible,
      emojiTooltip: _isEmojiPanelVisible ? '显示键盘' : '表情',
      imageTooltip: _isRichContentEditorOpen ? '插入图片/视频' : atomicLocale.album,
      fileTooltip: _isRichContentEditorOpen ? '插入文件' : atomicLocale.file,
      sendTooltip: _isRichContentEditorOpen ? '发送富文本消息' : atomicLocale.send,
      onEmoji: _isRichContentEditorOpen
          ? () => _richContentEditorKey.currentState?.toggleEmojiPanel()
          : _toggleEmojiPanel,
      onMention: _isRichContentEditorOpen
          ? () => _richContentEditorKey.currentState?.insertMention()
          : () => _insertPlainText('@'),
      onVideo: _isRichContentEditorOpen
          ? null
          : widget.config.isShowVideoCall
              ? _onVideoCallTap
              : null,
      onImage: _isRichContentEditorOpen || widget.config.isShowAlbum
          ? _onPickAlbum
          : null,
      // 展开编辑器时禁用文件；收起后恢复宿主配置的独立文件发送入口。
      onFile: !_isRichContentEditorOpen && widget.config.isShowFile
          ? _onPickFile
          : null,
      onShowFormatting: _isRichContentEditorOpen
          ? () => _richContentEditorKey.currentState?.showFormattingToolbar()
          : _showInlineFormattingToolbar,
      onCloseFormatting: _isRichContentEditorOpen
          ? () => _richContentEditorKey.currentState?.closeFormattingToolbar()
          : _closeInlineFormattingToolbar,
      onToggleFormat: _isRichContentEditorOpen
          ? (marker) => _richContentEditorKey.currentState?.toggleFormat(marker)
          : _toggleInlineFormat,
      onSend: _isRichContentEditorOpen
          ? () => _richContentEditorKey.currentState?.send()
          : _handleInputSend,
    );
  }

  /// 根据输入状态创建文本框，空闲时移除文本输入连接以便键盘及时收起。
  Widget _buildTextInputArea(SemanticColorScheme colorsTheme) {
    if (_inputMode == _InputMode.idle) {
      return _buildIdleInputArea(colorsTheme);
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: colorsTheme.bgColorOperate,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _buildInputTextField(colorsTheme: colorsTheme),
    );
  }

  /// 进入普通输入区的富文本模式，并在文本框创建后唤起键盘。
  void _showInlineFormattingToolbar() {
    setState(() {
      _inputMode = _InputMode.text;
      _showEmojiPanel = false;
      _showMorePanel = false;
      _showTextFormattingToolbar = true;
      _inlineRichContentEnabled = true;
    });
    // 空闲态会在本帧创建文本框，等待布局完成后再唤起键盘。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _textEditingFocusNode.requestFocus();
      }
    });
  }

  /// 切换普通输入区的格式选中态，只影响下一次输入而不修改已有文字。
  void _toggleInlineFormat(String marker) {
    if (_textEditingController.selection.isCollapsed) {
      final value = exitActiveMarkdownFormats(
        _textEditingController.value,
        _activeInlineFormats,
      );
      _lastFormatSelection = value.selection;
      _textEditingController.value = value;
    }
    if (!_activeInlineFormats.remove(marker)) {
      _activeInlineFormats.add(marker);
    }
    setState(() {});
    _textEditingFocusNode.requestFocus();
  }

  /// 退出格式栏并结束当前格式范围，避免隐藏状态继续影响后续输入。
  void _closeInlineFormattingToolbar() {
    final value = exitActiveMarkdownFormats(
      _textEditingController.value,
      _activeInlineFormats,
    );
    _lastFormatSelection = value.selection;
    _textEditingController.value = value;
    setState(() {
      _activeInlineFormats.clear();
      _showTextFormattingToolbar = false;
    });
  }

  void _insertPlainText(String value) {
    final current = _textEditingController.value;
    final selection = current.selection.isValid
        ? current.selection
        : TextSelection.collapsed(offset: current.text.length);
    _textEditingController.value = TextEditingValue(
      text: current.text.replaceRange(selection.start, selection.end, value),
      selection: TextSelection.collapsed(
        offset: selection.start + value.length,
      ),
    );
    setState(() => _inputMode = _InputMode.text);
    _textEditingFocusNode.requestFocus();
  }

  /// Toggle between voice mode and text input mode.
  /// From text/idle → voice: dismiss keyboard and panels.
  /// From voice → text: show keyboard.
  ///
  /// 在语音模式和文本输入模式之间切换。从文本/空闲 → 语音：收起键盘和面板。从语音 → 文本：显示键盘。
  void _toggleVoiceMode() {
    setState(() {
      if (_inputMode != _InputMode.voice) {
        // Switching to voice mode: hide keyboard and panels
        //
        // 切换到语音模式：隐藏键盘和面板
        _inputMode = _InputMode.voice;
        _textEditingFocusNode.unfocus();
        _showEmojiPanel = false;
        _showMorePanel = false;
      } else {
        // Switching back to text mode: show keyboard
        //
        // 切回文本模式：显示键盘
        _inputMode = _InputMode.text;
        _textEditingFocusNode.requestFocus();
      }
    });
  }

  /// 保留正文焦点和选区，只切换平台键盘的可见性与同一区域的表情面板。
  void _toggleEmojiPanel() {
    if (_showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
      _keyboardPanel!.showSystem(_textEditingFocusNode);
    } else {
      setState(() {
        _inputMode = _InputMode.text;
        _showEmojiPanel = true;
        _showMorePanel = false;
      });
      _keyboardPanel!.showEmoji(_textEditingFocusNode);
    }
  }

  /// 构建与文本输入区同色的按住说话按钮。
  Widget _buildHoldToTalkButton(SemanticColorScheme colorsTheme) {
    return Semantics(
      identifier: 'chat.voice.hold',
      label: '按住说话',
      child: Listener(
        onPointerDown: _onStartRecording,
        onPointerUp: _onStopRecording,
        onPointerCancel: _onRecordingPointerCancel,
        onPointerMove: (PointerMoveEvent event) {
          _voicePreviewKey.currentState?.updatePointerPosition(event.position);
          _recordOverlayKey.currentState?.updatePointerPosition(event.position);
        },
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: colorsTheme.bgColorOperate,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              atomicLocale.holdToTalk,
              style: FontScheme.caption1Medium.copyWith(
                color: colorsTheme.textColorPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建空闲输入区；录音只由独立麦克风入口触发，避免与键盘焦点竞争。
  Widget _buildIdleInputArea(SemanticColorScheme colorsTheme) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showEmojiPanel = false;
          _showMorePanel = false;
          _inputMode = _InputMode.text;
        });
        // 文本框创建完成后再申请焦点，避免向已移除的输入连接发起键盘请求。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _textEditingFocusNode.requestFocus();
          }
        });
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: colorsTheme.bgColorOperate,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '发送给 ${widget.conversationDisplayName ?? _conversationInfo?.title ?? widget.conversationID}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FontScheme.caption1Regular.copyWith(
                  color: colorsTheme.textColorSecondary,
                ),
              ),
            ),
            _buildRichContentExpandButton(colorsTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildInputTextField({required SemanticColorScheme colorsTheme}) {
    return _MentionTextField(
      controller: _textEditingController,
      focusNode: _textEditingFocusNode,
      keyboardMode: _showEmojiPanel
          ? ExtendedKeyboardMode.custom
          : _keyboardPanel?.returningToSystem == true
              ? ExtendedKeyboardMode.returningToSystem
              : ExtendedKeyboardMode.system,
      inputFormatter: _inlineFormatInputFormatter,
      inlineAttachments: _inlineRichContentAttachments,
      videoPlayIcon: widget.config.videoPlayIcon,
      imageLoadingPlaceholder: widget.config.imageLoadingPlaceholder,
      videoLoadingPlaceholder: widget.config.videoLoadingPlaceholder,
      colorsTheme: colorsTheme,
      hintText:
          '发送给 ${widget.conversationDisplayName ?? _conversationInfo?.title ?? widget.conversationID}',
      onExpand: _openRichContentEditor,
      onTap: () {
        if (_showEmojiPanel ||
            _showMorePanel ||
            _inputMode != _InputMode.text) {
          setState(() {
            _showEmojiPanel = false;
            _showMorePanel = false;
            _inputMode = _InputMode.text;
          });
          _keyboardPanel!.showSystem(_textEditingFocusNode);
        }
      },
    );
  }

  Widget _buildRichContentExpandButton(SemanticColorScheme colorsTheme) {
    return Semantics(
      key: const Key('open_rich_content_editor'),
      container: true,
      identifier: 'tim.input.expand',
      label: '展开富文本编辑器',
      button: true,
      child: GestureDetector(
        onTap: _openRichContentEditor,
        child: SizedBox(
          width: 24,
          height: 22,
          child: Icon(
            AppIcons.expand1,
            size: 24,
            color: colorsTheme.textColorSecondary,
          ),
        ),
      ),
    );
  }

  /// 展开编辑器持有自身面板状态，普通输入区只读取它来安排共用键盘区域。
  bool get _isEmojiPanelVisible => _isRichContentEditorOpen
      ? _richContentEditorKey.currentState?.showEmojiPanel ?? _showEmojiPanel
      : _showEmojiPanel;

  /// 当前活动输入区的过渡几何，宿主不复制展开编辑器的键盘状态。
  InputKeyboardPanel? get _activeKeyboardPanel => _isRichContentEditorOpen
      ? _richContentEditorKey.currentState?.keyboardPanel ?? _keyboardPanel
      : _keyboardPanel;

  /// 自定义面板与系统遮挡合计只占一份键盘区域，更多面板保留既有高度。
  double _getBottomContainerHeight() {
    if (_showMorePanel) return 280;
    final keyboard = _activeKeyboardPanel;
    return keyboard?.hasReservedSpace == true
        ? keyboard!.remainingHeight
        : _bottomPadding;
  }
}

/// Custom TextEditingController that manages mention ranges
///
/// 管理提及范围的自定义 TextEditingController
class _MentionTextEditingController extends TextEditingController {
  final List<MentionInfo> _mentions = [];
  bool _isInternalUpdate = false;

  List<MentionInfo> get mentionList => List.unmodifiable(_mentions);

  void addMention(MentionInfo mention) {
    _mentions.add(mention);
    _mentions.sort((a, b) => a.startIndex.compareTo(b.startIndex));
  }

  void removeMention(MentionInfo mention) {
    _mentions.remove(mention);
    // Update positions of mentions after the removed one
    //
    // 移除某个提及后更新其他提及的位置
    final removedLength = mention.length;
    for (final m in _mentions) {
      if (m.startIndex > mention.startIndex) {
        m.startIndex -= removedLength;
      }
    }
  }

  void clearMentions() {
    _mentions.clear();
  }

  /// Get mention that ends at the given position
  ///
  /// 获取在指定位置结束的提及
  MentionInfo? getMentionEndingAt(int position) {
    for (final mention in _mentions) {
      if (mention.endIndex == position) {
        return mention;
      }
    }
    return null;
  }

  /// Get mention that contains the given position (exclusive of boundaries)
  ///
  /// 获取包含给定位置的提及（不包括边界）
  MentionInfo? getMentionContaining(int position) {
    for (final mention in _mentions) {
      if (position > mention.startIndex && position < mention.endIndex) {
        return mention;
      }
    }
    return null;
  }

  /// Get mention that the position is at or inside (for deletion detection)
  ///
  /// 获取位置处于或包含在内的提及（用于删除检测）
  MentionInfo? getMentionAt(int position) {
    for (final mention in _mentions) {
      if (position > mention.startIndex && position <= mention.endIndex) {
        return mention;
      }
    }
    return null;
  }

  /// Get the anchor position for a mention (jump to nearest boundary)
  ///
  /// 获取提及的锚点位置（跳到最近的边界）
  int getAnchorPosition(MentionInfo mention, int position) {
    final distanceToStart = position - mention.startIndex;
    final distanceToEnd = mention.endIndex - position;
    return distanceToStart <= distanceToEnd
        ? mention.startIndex
        : mention.endIndex;
  }

  @override
  set value(TextEditingValue newValue) {
    if (_isInternalUpdate) {
      super.value = newValue;
      return;
    }

    final oldText = text;
    final newText = newValue.text;

    // Skip if no text change
    //
    // 如果文本没有变化则跳过
    if (oldText == newText) {
      super.value = newValue;
      return;
    }

    final delta = newText.length - oldText.length;

    // Handle deletion
    //
    // 处理删除
    if (delta < 0) {
      final cursorPos = newValue.selection.baseOffset;
      // The deletion happened at cursorPos, and deleted (-delta) characters
      //
      // 删除发生在 cursorPos，删除了 (-delta) 个字符
      final deleteStart = cursorPos;
      final deleteEnd = cursorPos - delta; // This is the position in old text

      // Check if the deletion affects any mention
      // We need to find if any mention overlaps with [deleteStart, deleteEnd) in old text
      //
      // 检查删除是否影响任何提及 我们需要找出是否有任何提及与旧文本中的 [deleteStart, deleteEnd) 重叠
      MentionInfo? affectedMention;
      for (final mention in _mentions) {
        // Check if the deletion overlaps with this mention
        //
        // 检查删除是否与该提及重叠
        if (deleteStart < mention.endIndex && deleteEnd > mention.startIndex) {
          affectedMention = mention;
          break;
        }
      }

      if (affectedMention != null) {
        // Delete the entire mention
        //
        // 删除整条提及
        _isInternalUpdate = true;

        final beforeMention = oldText.substring(0, affectedMention.startIndex);
        final afterMention = oldText.substring(affectedMention.endIndex);
        final updatedText = '$beforeMention$afterMention';

        // Remove the mention from list
        //
        // 从列表中移除提及
        _mentions.remove(affectedMention);

        // Update positions of mentions after the removed one
        //
        // 更新被移除提及之后的提及位置
        final removedLength = affectedMention.length;
        for (final m in _mentions) {
          if (m.startIndex > affectedMention.startIndex) {
            m.startIndex -= removedLength;
          }
        }

        super.value = TextEditingValue(
          text: updatedText,
          selection: TextSelection.collapsed(
            offset: affectedMention.startIndex,
          ),
        );

        _isInternalUpdate = false;
        return;
      }

      // No mention affected, update mention positions normally
      //
      // 没有提及受影响，正常更新提及位置
      for (final mention in _mentions) {
        if (mention.startIndex >= deleteEnd) {
          mention.startIndex += delta;
        }
      }
    } else if (delta > 0) {
      // Handle insertion - update mention positions
      //
      // 处理插入 - 更新提及位置
      final insertPos = newValue.selection.baseOffset - delta;
      for (final mention in _mentions) {
        if (mention.startIndex >= insertPos) {
          mention.startIndex += delta;
        }
      }
    }

    super.value = newValue;
  }
}

/// 展示当前输入正文及展开入口，复用父输入区持有的控制器和焦点。
class _MentionTextField extends StatefulWidget {
  /// 父输入区持有的正文与提及范围，子组件只监听并修正选区。
  final _MentionTextEditingController controller;

  /// 由父输入区释放，切换编辑模式时保持同一焦点身份。
  final FocusNode focusNode;

  /// 表情面板仅抑制此输入框的系统键盘显示，不修改全局输入绑定。
  final ExtendedKeyboardMode keyboardMode;

  /// 当前宿主解析后的文字、占位和背景语义色。
  final SemanticColorScheme colorsTheme;

  /// 正文被点击时通知父输入区收起其他输入面板。
  final VoidCallback? onTap;

  /// 当前会话的空输入提示，不作为实际正文保存。
  final String? hintText;

  /// 展开编辑器时交回父输入区保留当前草稿。
  final VoidCallback? onExpand;

  /// 父输入区提供的格式同步约束，不在此截断超限正文。
  final TextInputFormatter? inputFormatter;

  /// 编辑态令牌对应的附件，用于按真实图片高度布局正文。
  final Map<int, RichContentDraftAttachmentBlock> inlineAttachments;

  /// 与展开编辑器共用的宿主播放图标。
  final ImageProvider? videoPlayIcon;

  /// 普通输入区与展开编辑器共用的图片加载占位图。
  final ImageProvider? imageLoadingPlaceholder;

  /// 普通输入区与展开编辑器共用的视频加载占位图。
  final ImageProvider? videoLoadingPlaceholder;

  const _MentionTextField({
    required this.controller,
    required this.focusNode,
    this.keyboardMode = ExtendedKeyboardMode.system,
    required this.colorsTheme,
    this.onTap,
    this.hintText,
    this.onExpand,
    this.inputFormatter,
    this.inlineAttachments = const {},
    this.videoPlayIcon,
    this.imageLoadingPlaceholder,
    this.videoLoadingPlaceholder,
  });

  @override
  State<_MentionTextField> createState() => _MentionTextFieldState();
}

/// 将提及选区修正为完整边界，并让正文在固定最大高度内独立滚动。
class _MentionTextFieldState extends State<_MentionTextField> {
  bool _isAdjustingSelection = false;

  /// 正文与右侧滚动条共用滚动位置，随当前输入组件创建和释放。
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSelectionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (_isAdjustingSelection) return;

    final selection = widget.controller.selection;
    if (!selection.isValid) return;

    final selStart = selection.start;
    final selEnd = selection.end;

    // Check if cursor is inside a mention
    //
    // 检查光标是否在提及内容内
    if (selStart == selEnd) {
      // Single cursor
      //
      // 单一光标
      final mention = widget.controller.getMentionContaining(selStart);
      if (mention != null) {
        // Jump to nearest boundary
        //
        // 跳到最近的边界
        final anchorPos = widget.controller.getAnchorPosition(
          mention,
          selStart,
        );

        // Only adjust if cursor is actually inside the mention (not at boundary)
        //
        // 只有当光标确实在提及内容内（而不是在边界）时才调整
        if (selStart != anchorPos) {
          _isAdjustingSelection = true;
          // Use microtask to ensure adjustment happens immediately but after current event
          //
          // 使用微任务确保调整立即发生，但在当前事件之后
          Future.microtask(() {
            if (mounted) {
              widget.controller.selection = TextSelection.collapsed(
                offset: anchorPos,
              );
            }
            _isAdjustingSelection = false;
          });
        }
      }
    } else {
      // Selection range - expand to include full mentions
      //
      // 选择范围 - 扩展以包含完整的提及内容
      int newStart = selStart;
      int newEnd = selEnd;
      bool needsUpdate = false;

      for (final mention in widget.controller.mentionList) {
        // If selection starts inside a mention, extend to mention start
        if (selStart > mention.startIndex && selStart < mention.endIndex) {
          newStart = mention.startIndex;
          needsUpdate = true;
        }
        // If selection ends inside a mention, extend to mention end
        if (selEnd > mention.startIndex && selEnd < mention.endIndex) {
          newEnd = mention.endIndex;
          needsUpdate = true;
        }
      }

      if (needsUpdate) {
        _isAdjustingSelection = true;
        Future.microtask(() {
          if (mounted) {
            widget.controller.selection = TextSelection(
              baseOffset: newStart,
              extentOffset: newEnd,
            );
          }
          _isAdjustingSelection = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = FontScheme.caption1Regular.copyWith(
          color: widget.colorsTheme.textColorPrimary,
          height: 1.5,
        );
        // 高度测量与实际输入使用同一行高，避免主题继承后五行正文被提前裁掉。
        final maxImageWidth = constraints.maxWidth;
        final lineHeight = TextPainter(
          text: TextSpan(text: ' ', style: style),
          textDirection: Directionality.of(context),
        ).preferredLineHeight;
        final maxInputHeight = lineHeight * 5 + 20;
        // 展开按钮独立于文本滚动区，输入内容只由 ExtendedTextField 自身滚动。
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxInputHeight),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // 上下留白放在轨道外侧，确保轨道长度与正文滚动视口完全一致。
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: ClipRect(
                    child: Semantics(
                      identifier: 'tim.input.scrollbar',
                      container: true,
                      explicitChildNodes: true,
                      child: RawScrollbar(
                        key: const Key('message_input_scrollbar'),
                        controller: _scrollController,
                        thumbColor: widget.colorsTheme.textColorTertiary,
                        thickness: 3,
                        radius: const Radius.circular(2),
                        scrollbarOrientation: ScrollbarOrientation.right,
                        interactive: true,
                        child: Semantics(
                          identifier: 'tim.input.text',
                          child: ExtendedTextField(
                            key: const Key('message_input_text_field'),
                            onTap: widget.onTap,
                            focusNode: widget.focusNode,
                            keyboardMode: widget.keyboardMode,
                            controller: widget.controller,
                            scrollController: _scrollController,
                            minLines: 1,
                            // 媒体段落的默认行高不同于正文，改用实际内容高度并由外层统一限制五行文字的高度。
                            maxLines:
                                widget.inlineAttachments.isEmpty ? 5 : null,
                            inputFormatters: [
                              if (widget.inputFormatter != null)
                                widget.inputFormatter!,
                            ],
                            style: style,
                            // 与展开编辑器一致，让图片参与真实行高而不被固定 strut 上移。
                            strutStyle: StrutStyle.disabled,
                            cursorHeight: richContentAttachmentCursorHeight(
                              context: context,
                              controller: widget.controller,
                              attachments: widget.inlineAttachments,
                              maxImageWidth: maxImageWidth,
                              textStyle: style,
                            ),
                            decoration: InputDecoration(
                              // 白色背景与圆角由父输入框承载，避免主题填充覆盖圆角。
                              filled: false,
                              isDense: true,
                              hintText: widget.hintText,
                              hintMaxLines: 1,
                              hintStyle: FontScheme.caption1Regular.copyWith(
                                color: widget.colorsTheme.textColorSecondary,
                                height: 1.5,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            specialTextSpanBuilder:
                                RichContentAttachmentSpanBuilder(
                              videoPlayIcon: widget.videoPlayIcon,
                              imageLoadingPlaceholder:
                                  widget.imageLoadingPlaceholder,
                              videoLoadingPlaceholder:
                                  widget.videoLoadingPlaceholder,
                              attachments: widget.inlineAttachments,
                              maxImageWidth: maxImageWidth,
                              devicePixelRatio:
                                  MediaQuery.devicePixelRatioOf(context),
                              colorScheme: widget.colorsTheme,
                              onTapUrl: (_) {},
                              mapMarkdownMarkers: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.onExpand != null)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Semantics(
                    identifier: 'tim.input.expand',
                    container: true,
                    child: material.IconButton(
                      key: const Key('open_rich_content_editor'),
                      tooltip: '展开富文本编辑器',
                      onPressed: widget.onExpand,
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        AppIcons.expand1,
                        size: 24,
                        color: widget.colorsTheme.textColorSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Data model for a "more" panel grid item
///
/// “更多”面板网格项的数据模型
class _MorePanelItem {
  final String icon;
  final String title;
  final VoidCallback onTap;

  const _MorePanelItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });
}

// MARK: - AlbumPickerMediaSendListener Implementation
//
// MARK: - AlbumPickerMediaSendListener 实现

class _AlbumPickerMediaSendListenerImpl
    implements AlbumPickerMediaSendListener {
  final MessageInputState _state;

  _AlbumPickerMediaSendListenerImpl(this._state);

  @override
  void onSendMessage(MessageInfo messageInfo) {
    _state._sendMessage(messageInfo).then((result) {
      if (!result.isSuccess) {
        debugPrint(
          "AlbumPicker onSendMessage failed: ${result.errorCode}, ${result.errorMessage}",
        );
      }
    });
  }

  @override
  void onSendPlaceholderMessage(MessageInfo placeholder) {
    _state._sendPlaceholderMessage(placeholder);
  }

  @override
  void onRemovePlaceholderMessage(MessageInfo placeholder) {
    _state._removePlaceholderMessage(placeholder);
  }
}
