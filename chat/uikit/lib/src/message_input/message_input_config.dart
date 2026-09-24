import 'package:tuikit_atomic_x/base_component/utils/app_builder.dart';

/// 富文本编辑器支持插入的本地附件类型。
enum RichContentAttachmentType { image, file }

/// 交给宿主业务上传的本地附件信息。
final class RichContentLocalAttachment {
  /// 附件类型，用于选择对应的业务上传策略。
  final RichContentAttachmentType type;

  /// 选择器返回的本地文件绝对路径。
  final String localPath;

  /// 展示和上传时使用的原始文件名。
  final String fileName;

  /// 文件大小，单位为字节。
  final int fileSize;

  /// 文件 MIME 类型；选择器无法确定时使用 `application/octet-stream`。
  final String mimeType;

  /// 图片原始宽度，单位为像素；文件附件为 null。
  final int? width;

  /// 图片原始高度，单位为像素；文件附件为 null。
  final int? height;

  const RichContentLocalAttachment({
    required this.type,
    required this.localPath,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.width,
    this.height,
  });
}

/// 宿主业务上传附件并返回可公开访问的 HTTP(S) URL。
typedef RichContentAttachmentUploader =
    Future<String> Function(RichContentLocalAttachment attachment);

/// 定义 MessageInput 的可见能力和宿主业务扩展入口。
abstract class MessageInputConfigProtocol {
  bool get isShowAudioRecorder;
  bool get isShowMore;
  bool get enableReadReceipt;
  bool get enableMention;
  bool get enableVoiceToTextOnRecord;

  /// More panel items (order matches the more panel UI)
  ///
  /// 更多面板项（顺序与更多面板 UI 一致）
  bool get isShowAlbum;
  bool get isShowPhotoTaker;
  bool get isShowVideoRecorder;
  bool get isShowFile;
  bool get isShowVideoCall;
  bool get isShowAudioCall;

  /// 富文本附件上传入口；未配置时允许插入附件，但不允许发送。
  RichContentAttachmentUploader? get richContentAttachmentUploader;
}

/// 提供聊天输入区的默认配置，并允许宿主按会话覆盖单项能力。
class ChatMessageInputConfig implements MessageInputConfigProtocol {
  final bool? _userIsShowAudioRecorder;
  final bool? _userIsShowMore;
  final bool? _userEnableReadReceipt;
  final bool? _userEnableMention;
  final bool? _userEnableVoiceToTextOnRecord;
  final bool? _userIsShowAlbum;
  final bool? _userIsShowPhotoTaker;
  final bool? _userIsShowVideoRecorder;
  final bool? _userIsShowFile;
  final bool? _userIsShowVideoCall;
  final bool? _userIsShowAudioCall;
  final RichContentAttachmentUploader? _richContentAttachmentUploader;

  @override
  bool get isShowAudioRecorder => _userIsShowAudioRecorder ?? true;

  @override
  bool get isShowMore => _userIsShowMore ?? true;

  @override
  bool get enableReadReceipt {
    if (_userEnableReadReceipt != null) {
      return _userEnableReadReceipt;
    } else {
      return AppBuilder.getInstance().messageListConfig.enableReadReceipt;
    }
  }

  @override
  bool get enableMention => _userEnableMention ?? true;

  @override
  bool get enableVoiceToTextOnRecord => _userEnableVoiceToTextOnRecord ?? true;

  @override
  bool get isShowAlbum => _userIsShowAlbum ?? true;

  @override
  bool get isShowPhotoTaker => _userIsShowPhotoTaker ?? true;

  @override
  bool get isShowVideoRecorder => _userIsShowVideoRecorder ?? true;

  @override
  bool get isShowFile => _userIsShowFile ?? true;

  @override
  bool get isShowVideoCall => _userIsShowVideoCall ?? false;

  @override
  bool get isShowAudioCall => _userIsShowAudioCall ?? false;

  @override
  RichContentAttachmentUploader? get richContentAttachmentUploader =>
      _richContentAttachmentUploader;

  const ChatMessageInputConfig({
    bool? isShowAudioRecorder,
    bool? isShowMore,
    bool? enableReadReceipt,
    bool? enableMention,
    bool? enableVoiceToTextOnRecord,
    bool? isShowAlbum,
    bool? isShowPhotoTaker,
    bool? isShowVideoRecorder,
    bool? isShowFile,
    bool? isShowVideoCall,
    bool? isShowAudioCall,
    RichContentAttachmentUploader? richContentAttachmentUploader,
  }) : _userIsShowAudioRecorder = isShowAudioRecorder,
       _userIsShowMore = isShowMore,
       _userEnableReadReceipt = enableReadReceipt,
       _userEnableMention = enableMention,
       _userEnableVoiceToTextOnRecord = enableVoiceToTextOnRecord,
       _userIsShowAlbum = isShowAlbum,
       _userIsShowPhotoTaker = isShowPhotoTaker,
       _userIsShowVideoRecorder = isShowVideoRecorder,
       _userIsShowFile = isShowFile,
       _userIsShowVideoCall = isShowVideoCall,
       _userIsShowAudioCall = isShowAudioCall,
       _richContentAttachmentUploader = richContentAttachmentUploader;
}
