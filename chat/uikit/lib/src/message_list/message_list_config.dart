import 'package:tuikit_atomic_x/base_component/utils/app_builder.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
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

  /// 用当前表情条组装气泡；无可见条目时传空，避免改变正文尺寸和背景。
  final Widget Function(
    BuildContext context,
    MessageInfo message,
    bool isLeft, {
    VoidCallback? showNativeDetails,
    Widget Function(Widget? reactionBar)? buildBubble,
  }) buildBar;
}

/// 约定消息列表的外观和可操作能力，具体默认值由聊天配置提供。
abstract class MessageListConfigProtocol {
  /// 宿主可渲染已识别的自定义正文；返回空值时继续用原有气泡。
  Widget? Function(BuildContext, MessageInfo, double)? get customContentBuilder;

  /// 双侧布局中，匹配的卡片保留发送侧头像，省略昵称和对侧头像留白。
  /// 发送侧头像沿用普通消息的位置和间距。
  bool Function(MessageInfo)? get useStandaloneCardLayout;

  /// 宿主可在真实消息正文外观察视口，不能借此替代普通消息已读回执。
  Widget Function(BuildContext, MessageInfo, Widget)? get messageContentWrapper;

  /// 宿主为消息昵称增加业务标记，默认沿用原有昵称布局。
  Widget Function(BuildContext, MessageInfo, Widget)? get senderNameWrapper;

  /// 宿主接管云端表情提交和对应展示，缺省时继续使用原生回应。
  ChatMessageReactionConfig? get reactionConfig;

  /// 建群与群资料变更通知中的个人名片由宿主打开。
  void Function(BuildContext, String)? get onGroupInfoOperatorTap;

  /// 点击手机号查看通知的姓名时，交给宿主按载荷中的用户 ID 打开名片。
  void Function(BuildContext context, String userId)? get onPhoneViewPersonTap;

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

  /// 宿主接管群消息头像点击，目标为头像所代表的本人或其他成员。
  void Function(BuildContext context, String userId)? get onGroupSenderAvatarTap;

  /// 宿主接管单聊消息头像点击，目标为头像所代表的本人或对方。
  void Function(BuildContext context, String userId)?
      get onDirectSenderAvatarTap;

  /// 宿主为消息中的单个提及成员提供行内回执指示。
  Widget? Function(MessageInfo message, String userId)?
      get mentionReceiptBuilder;

  /// 点击已校验当前群的公告卡片时，交给宿主打开详情。
  void Function(BuildContext, GroupAnnouncementMessage)?
      get onGroupAnnouncementTap;

  /// 通知详情入口只传公告业务 ID，由宿主在接口可用时查询详情。
  void Function(BuildContext, String id)? get onOaAnnouncementTap;

  /// 宿主提供公告业务阅读状态；为空或返回 null 表示尚无状态，不能用会话未读推断。
  bool? Function(String id)? get oaAnnouncementReadStatus;

  /// 本账号已确认的本机删除标识，阻止SDK窗口与进程快照重新呈现旧记录。
  Set<String> get hiddenMessageIDs;

  /// 当前 SDK 接通的多人呼叫标识，供匹配的发起气泡刷新正文。
  ValueListenable<String?>? get acceptedCallAttempt;

  /// 点击已校验的群通话气泡时打开原群的媒体选择。
  void Function(BuildContext)? get onGroupCallBubbleTap;

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

  /// 当前群已确认可长按头像提及的成员 ID。空集合关闭入口。
  Set<String> get avatarMentionMemberIds;

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
  /// 自定义正文仍由原消息行承载头像、菜单、状态和高亮。
  @override
  final Widget? Function(BuildContext, MessageInfo, double)? customContentBuilder;

  /// 由宿主匹配适用独立消息行的卡片正文。
  @override
  final bool Function(MessageInfo)? useStandaloneCardLayout;

  /// 仅包裹气泡正文，避免把头像、时间分组和整行空白误算为正文可见区域。
  @override
  final Widget Function(BuildContext, MessageInfo, Widget)? messageContentWrapper;

  /// 包装现有昵称内容，宿主负责标记语义与剩余宽度分配。
  @override
  final Widget Function(BuildContext, MessageInfo, Widget)? senderNameWrapper;

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

  /// 由宿主从当前群成员名单提供，成员资料未确认时保持为空。
  @override
  final Set<String> avatarMentionMemberIds;

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

  /// 公告会话可以隐藏普通头像，手机号查看通知仍独立使用此名片入口。
  @override
  final void Function(BuildContext context, String userId)?
      onPhoneViewPersonTap;

  @override
  final ChatForwardHandler? forwardHandler;
  @override
  final ChatLocalDeleteHandler? localDeleteHandler;

  /// 只在提及位置合法且绑定个人身份时交给宿主处理。
  @override
  final void Function(BuildContext context, String userId)? onMentionTap;

  /// 缺省时保留 UIKit 原有的头像点击行为。
  @override
  final void Function(BuildContext context, String userId)? onGroupSenderAvatarTap;

  /// 缺省时保留 UIKit 单聊头像的原有点击行为。
  @override
  final void Function(BuildContext context, String userId)?
      onDirectSenderAvatarTap;

  /// 缺省时正文只展示提及文字，不占用行内回执空间。
  @override
  final Widget? Function(MessageInfo message, String userId)?
      mentionReceiptBuilder;

  /// 空回调时卡片仅提供摘要展示。
  @override
  final void Function(BuildContext, GroupAnnouncementMessage)?
      onGroupAnnouncementTap;

  /// 接口未就绪时宿主可只展示暂不可用反馈，不能伪造详情请求成功。
  @override
  final void Function(BuildContext, String id)? onOaAnnouncementTap;

  /// 仅消费宿主已获取的阅读状态，UIKit 不发起业务请求或保存第二份状态。
  @override
  final bool? Function(String id)? oaAnnouncementReadStatus;
  @override
  final Set<String> hiddenMessageIDs;

  /// 未注入时，离线气泡按消息记录展示。
  @override
  final ValueListenable<String?>? acceptedCallAttempt;

  /// 旧消息详情没有宿主入口时保持只读。
  @override
  final void Function(BuildContext)? onGroupCallBubbleTap;
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
    this.messageContentWrapper,
    this.customContentBuilder,
    this.useStandaloneCardLayout,
    this.senderNameWrapper,
    this.showGroupDepartureNotices = true,
    this.groupMemberNoticeBuilder,
    this.groupSenderName,
    this.avatarMentionMemberIds = const {},
    this.groupReadReceiptBuilder,
    this.reactionConfig,
    this.onGroupInfoOperatorTap,
    this.onPhoneViewPersonTap,
    this.forwardHandler,
    this.localDeleteHandler,
    this.onMentionTap,
    this.onGroupSenderAvatarTap,
    this.onDirectSenderAvatarTap,
    this.mentionReceiptBuilder,
    this.onGroupAnnouncementTap,
    this.acceptedCallAttempt,
    this.onGroupCallBubbleTap,
    this.onOaAnnouncementTap,
    this.oaAnnouncementReadStatus,
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
