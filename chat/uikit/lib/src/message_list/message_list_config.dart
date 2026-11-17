import 'package:tuikit_atomic_x/base_component/utils/app_builder.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';
import '../message_input/chat_media_sender.dart';
import 'message_forward_config.dart';
import 'utils/group_announcement_message.dart';
import 'utils/conversation_notice.dart';
export 'message_forward_config.dart';

/// 宿主接管表情写入和条目渲染，UIKit 继续管理既有表情选择入口。
final class ChatMessageReactionConfig {
  const ChatMessageReactionConfig({
    required this.select,
    required this.buildBar,
  });

  /// 接收当前消息与跨端表情编码，提交后由宿主发布确认状态。
  final Future<void> Function(MessageInfo message, String code) select;

  /// 使用消息列的可用宽度渲染表情条，旧群聊回应可沿用原生明细入口。
  final Widget Function(BuildContext context, MessageInfo message, bool isLeft,
      {VoidCallback? showNativeDetails}) buildBar;
}

/// 约定消息列表的外观和可操作能力，具体默认值由聊天配置提供。
abstract class MessageListConfigProtocol {
  /// 宿主接管云端表情提交和对应展示，缺省时继续使用原生回应。
  ChatMessageReactionConfig? get reactionConfig;

  /// 建群与群资料变更通知中的个人名片由宿主打开。
  void Function(BuildContext, String)? get onGroupInfoOperatorTap;

  /// 宿主当前群角色是否允许显示退群与移出通知。
  bool get showGroupDepartureNotices;

  /// 成员进退群及管理员变更通知共用宿主的姓名样式和名片入口。
  Widget Function(BuildContext, ConversationNotice)?
      get groupMemberNoticeBuilder;

  /// 宿主统一转发入口；为空时保留UIKit默认流程。
  ChatForwardHandler? get forwardHandler;

  /// 宿主只删除当前用户本地记录，不借用会删除云端漫游的SDK批量接口。
  ChatLocalDeleteHandler? get localDeleteHandler;

  /// 由宿主复核群权限后按提及 ID 打开名片。
  void Function(BuildContext context, String userId)? get onMentionTap;

  /// 宿主为消息中的单个提及成员提供行内回执指示。
  Widget? Function(MessageInfo message, String userId)?
      get mentionReceiptBuilder;

  /// 点击已校验当前群的公告卡片时，交给宿主打开详情。
  void Function(BuildContext, GroupAnnouncementMessage)?
      get onGroupAnnouncementTap;

  /// 本账号已确认的本机删除标识，阻止SDK窗口与进程快照重新呈现旧记录。
  Set<String> get hiddenMessageIDs;

  /// 宿主提供的视频播放图标；缺省时使用 UIKit 字体图标。
  ImageProvider? get videoPlayIcon;

  /// 图片资源尚未取得或首帧尚未解码时使用的宿主占位图。
  ImageProvider? get imageLoadingPlaceholder;

  /// 视频封面加载期间使用的宿主占位图，不替代播放按钮。
  ImageProvider? get videoLoadingPlaceholder;

  /// 普通失败消息的重发也必须通过同一媒体大小分流入口。
  ChatMediaSender? get mediaSender;

  /// 上传占位的不可变状态，由宿主Controller维护。
  Map<String, ChatFileTransferView> get fileTransfers;

  /// 用户提供的文件类型真实图片构建入口。
  ChatFileIconBuilder? get fileIconBuilder;

  /// 大文件下载由宿主提供账号隔离存储与资源失效判定。
  ChatFileDownloader? get fileDownloader;
  double get textBubbleCornerRadius;
  String get alignment;
  bool get isShowTimeMessage;
  bool get isShowLeftAvatar;
  bool get isShowLeftNickname;
  bool get isShowRightAvatar;
  bool get isShowRightNickname;
  bool get isShowTimeInBubble;

  /// 同一时间组内消息项的间隔，单位为逻辑像素；新时间组独立留出分组间隔。
  double get cellSpacing;
  bool get isShowSystemMessage;
  bool get isShowUnsupportMessage;
  double get horizontalPadding;
  double get avatarSpacing;
  bool get isSupportCopy;
  bool get isSupportDelete;
  bool get isSupportRecall;
  bool get enableReadReceipt;

  /// 由群聊宿主提供气泡标题；空回调时使用 UIKit 的发送者名称。
  String Function(MessageInfo)? get groupSenderName;

  /// 宿主可替换群回执的展示与导航，默认沿用 UIKit。
  Widget? Function(BuildContext, MessageInfo, MessageListStore)?
      get groupReadReceiptBuilder;
  bool get isSupportForward;
  bool get isSupportMultiSelect;
  bool get isSupportReaction;
  bool get isSupportTranslate;
  bool get isSupportTongue;
  bool get isSupportQuote;
}

/// 提供消息列表默认外观，并保留宿主显式传入的单项覆盖。
class ChatMessageListConfig implements MessageListConfigProtocol {
  /// 群聊宿主按已确认的群角色设置，独立 UIKit 实例沿用已有显示方式。
  @override
  final bool showGroupDepartureNotices;

  /// 宿主负责成员变动通知的姓名格式和名片动作，UIKit 继续处理事件受众。
  @override
  final Widget Function(BuildContext, ConversationNotice)?
      groupMemberNoticeBuilder;

  /// 按当前群的名称策略生成发送者标题。
  @override
  final String Function(MessageInfo)? groupSenderName;

  /// 仅在消息满足群回执条件且有实时列表时调用。
  @override
  final Widget? Function(BuildContext, MessageInfo, MessageListStore)?
      groupReadReceiptBuilder;

  /// 宿主提供的云表情回复写入及展示适配。
  @override
  final ChatMessageReactionConfig? reactionConfig;

  /// 按建群或群资料变更通知中的用户 ID 打开名片。
  @override
  final void Function(BuildContext, String)? onGroupInfoOperatorTap;

  @override
  final ChatForwardHandler? forwardHandler;
  @override
  final ChatLocalDeleteHandler? localDeleteHandler;

  /// 只在提及位置合法且绑定个人身份时交给宿主处理。
  @override
  final void Function(BuildContext context, String userId)? onMentionTap;

  /// 缺省时正文只展示提及文字，不占用行内回执空间。
  @override
  final Widget? Function(MessageInfo message, String userId)?
      mentionReceiptBuilder;

  /// 空回调时卡片仅提供摘要展示。
  @override
  final void Function(BuildContext, GroupAnnouncementMessage)?
      onGroupAnnouncementTap;
  @override
  final Set<String> hiddenMessageIDs;
  @override
  final ImageProvider? videoPlayIcon;
  @override
  final ImageProvider? imageLoadingPlaceholder;
  @override
  final ImageProvider? videoLoadingPlaceholder;
  @override
  final ChatMediaSender? mediaSender;
  @override
  final Map<String, ChatFileTransferView> fileTransfers;
  @override
  final ChatFileIconBuilder? fileIconBuilder;
  @override
  final ChatFileDownloader? fileDownloader;
  final double? _userTextBubbleCornerRadius;
  final String? _userAlignment;
  final bool? _userIsShowTimeMessage;
  final bool? _userIsShowLeftAvatar;
  final bool? _userIsShowLeftNickname;
  final bool? _userIsShowRightAvatar;
  final bool? _userIsShowRightNickname;
  final bool? _userIsShowTimeInBubble;

  /// 宿主指定的组内间距；为空时使用设计中的16逻辑像素。
  final double? _userCellSpacing;
  final bool? _userIsShowSystemMessage;
  final bool? _userIsShowUnsupportMessage;
  final bool? _userIsSupportCopy;
  final bool? _userIsSupportDelete;
  final bool? _userIsSupportRecall;
  final double? _userHorizontalPadding;
  final double? _userAvatarSpacing;
  final bool? _userEnableReadReceipt;
  final bool _isSupportForward;
  final bool _isSupportMultiSelect;
  final bool _isSupportReaction;
  final bool _isSupportTranslate;
  final bool _isSupportTongue;
  final bool _isSupportQuote;

  @override
  double get textBubbleCornerRadius => _userTextBubbleCornerRadius ?? 18.0;

  @override
  String get alignment {
    if (_userAlignment != null) {
      return _userAlignment;
    } else {
      final config = AppBuilder.getInstance();
      return config.messageListConfig.alignment;
    }
  }

  @override
  bool get isShowTimeMessage => _userIsShowTimeMessage ?? true;

  @override
  bool get isShowLeftAvatar => _userIsShowLeftAvatar ?? true;

  @override
  bool get isShowLeftNickname => _userIsShowLeftNickname ?? false;

  @override
  bool get isShowRightAvatar => _userIsShowRightAvatar ?? false;

  @override
  bool get isShowRightNickname => _userIsShowRightNickname ?? false;

  @override
  bool get isShowTimeInBubble => _userIsShowTimeInBubble ?? false;

  @override
  double get cellSpacing => _userCellSpacing ?? 16;

  @override
  bool get isShowSystemMessage => _userIsShowSystemMessage ?? true;

  @override
  bool get isShowUnsupportMessage => _userIsShowUnsupportMessage ?? true;

  @override
  bool get isSupportCopy {
    if (_userIsSupportCopy != null) {
      return _userIsSupportCopy;
    } else {
      final config = AppBuilder.getInstance();
      return config.messageListConfig.messageActionList
          .contains(AppBuilder.MESSAGE_ACTION_COPY);
    }
  }

  @override
  bool get isSupportDelete {
    if (_userIsSupportDelete != null) {
      return _userIsSupportDelete;
    } else {
      final config = AppBuilder.getInstance();
      return config.messageListConfig.messageActionList
          .contains(AppBuilder.MESSAGE_ACTION_DELETE);
    }
  }

  @override
  bool get isSupportRecall {
    if (_userIsSupportRecall != null) {
      return _userIsSupportRecall;
    } else {
      final config = AppBuilder.getInstance();
      return config.messageListConfig.messageActionList
          .contains(AppBuilder.MESSAGE_ACTION_RECALL);
    }
  }

  @override
  double get horizontalPadding => _userHorizontalPadding ?? 16.0;

  @override
  double get avatarSpacing => _userAvatarSpacing ?? 8.0;

  @override
  bool get enableReadReceipt {
    if (_userEnableReadReceipt != null) {
      return _userEnableReadReceipt;
    } else {
      return AppBuilder.getInstance().messageListConfig.enableReadReceipt;
    }
  }

  @override
  bool get isSupportForward => _isSupportForward;

  @override
  bool get isSupportMultiSelect => _isSupportMultiSelect;

  @override
  bool get isSupportReaction => _isSupportReaction;

  @override
  bool get isSupportTranslate => _isSupportTranslate;

  @override
  bool get isSupportTongue => _isSupportTongue;

  @override
  bool get isSupportQuote => _isSupportQuote;

  const ChatMessageListConfig({
    this.showGroupDepartureNotices = true,
    this.groupMemberNoticeBuilder,
    this.groupSenderName,
    this.groupReadReceiptBuilder,
    this.reactionConfig,
    this.onGroupInfoOperatorTap,
    this.forwardHandler,
    this.localDeleteHandler,
    this.onMentionTap,
    this.mentionReceiptBuilder,
    this.onGroupAnnouncementTap,
    this.hiddenMessageIDs = const {},
    this.videoPlayIcon,
    this.imageLoadingPlaceholder,
    this.videoLoadingPlaceholder,
    this.mediaSender,
    this.fileTransfers = const {},
    this.fileIconBuilder,
    this.fileDownloader,
    double? textBubbleCornerRadius,
    String? alignment,
    bool? isShowTimeMessage,
    bool? isShowLeftAvatar,
    bool? isShowLeftNickname,
    bool? isShowRightAvatar,
    bool? isShowRightNickname,
    bool? isShowTimeInBubble,
    double? cellSpacing,
    bool? isShowSystemMessage,
    bool? isShowUnsupportMessage,
    bool? isSupportCopy,
    bool? isSupportDelete,
    bool? isSupportRecall,
    double? horizontalPadding,
    double? avatarSpacing,
    bool? enableReadReceipt,
    bool isSupportForward = true,
    bool isSupportMultiSelect = true,
    bool isSupportReaction = true,
    bool isSupportTranslate = true,
    bool isSupportTongue = true,
    bool isSupportQuote = true,
  })  : _userTextBubbleCornerRadius = textBubbleCornerRadius,
        _userAlignment = alignment,
        _userIsShowTimeMessage = isShowTimeMessage,
        _userIsShowLeftAvatar = isShowLeftAvatar,
        _userIsShowLeftNickname = isShowLeftNickname,
        _userIsShowRightAvatar = isShowRightAvatar,
        _userIsShowRightNickname = isShowRightNickname,
        _userIsShowTimeInBubble = isShowTimeInBubble,
        _userCellSpacing = cellSpacing,
        _userIsShowSystemMessage = isShowSystemMessage,
        _userIsShowUnsupportMessage = isShowUnsupportMessage,
        _userIsSupportCopy = isSupportCopy,
        _userIsSupportDelete = isSupportDelete,
        _userIsSupportRecall = isSupportRecall,
        _userHorizontalPadding = horizontalPadding,
        _userAvatarSpacing = avatarSpacing,
        _userEnableReadReceipt = enableReadReceipt,
        _isSupportForward = isSupportForward,
        _isSupportMultiSelect = isSupportMultiSelect,
        _isSupportReaction = isSupportReaction,
        _isSupportTranslate = isSupportTranslate,
        _isSupportTongue = isSupportTongue,
        _isSupportQuote = isSupportQuote;
}
