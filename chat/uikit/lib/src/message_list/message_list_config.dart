import 'package:tuikit_atomic_x/base_component/utils/app_builder.dart';
import '../message_input/chat_media_sender.dart';

/// 约定消息列表的外观和可操作能力，具体默认值由聊天配置提供。
abstract class MessageListConfigProtocol {
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
  bool get isSupportForward;
  bool get isSupportMultiSelect;
  bool get isSupportReaction;
  bool get isSupportTranslate;
  bool get isSupportTongue;
  bool get isSupportQuote;
}

/// 提供消息列表默认外观，并保留宿主显式传入的单项覆盖。
class ChatMessageListConfig implements MessageListConfigProtocol {
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
