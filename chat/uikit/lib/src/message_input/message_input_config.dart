import 'package:app_core/app_core.dart';
import 'package:flutter/painting.dart';
import 'package:tuikit_atomic_x/base_component/utils/app_builder.dart';
import 'chat_media_sender.dart';

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

  /// 相册提供的视频首帧封面本地路径；图片和普通文件不设置。
  final String? thumbnailPath;

  /// 相册返回的视频时长，单位为毫秒；旧草稿及非视频附件可以缺省。
  final int? durationMs;

  /// 视频沿用文件协议，通过 MIME 区分，不新增消息块类型。
  bool get isVideo =>
      type == RichContentAttachmentType.file && mimeType.startsWith('video/');

  /// 图片和视频均作为正文中的原子元素编辑；旧普通文件仍使用附件卡片。
  bool get isInlineMedia => type == RichContentAttachmentType.image || isVideo;

  /// 图片或视频封面宽度，单位为像素；普通文件附件为 null。
  final int? width;

  /// 图片或视频封面高度，单位为像素；普通文件附件为 null。
  final int? height;

  /// 图片及视频须在本地处理完成后取得正整数宽高，普通文件不要求尺寸。
  bool get hasRequiredDimensions =>
      !isInlineMedia || ((width ?? 0) > 0 && (height ?? 0) > 0);

  const RichContentLocalAttachment({
    required this.type,
    required this.localPath,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.thumbnailPath,
    this.durationMs,
    this.width,
    this.height,
  });
}

/// 宿主业务上传附件并返回可公开访问的 HTTP(S) URL。
typedef RichContentAttachmentUploader = Future<String> Function(
    RichContentLocalAttachment attachment);

/// 定义 MessageInput 的可见能力和宿主业务扩展入口。
abstract class MessageInputConfigProtocol {
  /// 宿主提供的视频播放图标；缺省时使用 UIKit 字体图标。
  ImageProvider? get videoPlayIcon;

  /// 图片导出或预览图加载期间使用的宿主占位图。
  ImageProvider? get imageLoadingPlaceholder;

  /// 视频导出及封面加载期间使用的宿主占位图。
  ImageProvider? get videoLoadingPlaceholder;

  /// 宿主统一媒体大小分流；为空时保留UIKit原生发送。
  ChatMediaSender? get mediaSender;

  /// 宿主文件选择页；为空时使用UIKit原生文件选择器。
  ChatFileSelector? get fileSelector;

  /// 宿主注册的全局异步操作守卫；未注入时输入组件使用独立的同类型守卫。
  ActionGuard? get actionGuard;

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

  /// 富文本附件上传入口，只在点击发送后调用；未配置时本地附件不能发送。
  RichContentAttachmentUploader? get richContentAttachmentUploader;
}

/// 提供聊天输入区的默认配置，并允许宿主按会话覆盖单项能力。
class ChatMessageInputConfig implements MessageInputConfigProtocol {
  @override
  final ImageProvider? videoPlayIcon;
  @override
  final ImageProvider? imageLoadingPlaceholder;
  @override
  final ImageProvider? videoLoadingPlaceholder;
  @override
  final ChatMediaSender? mediaSender;
  @override
  final ChatFileSelector? fileSelector;

  /// 保持与宿主其他文字发送入口共用同一并发边界。
  @override
  final ActionGuard? actionGuard;

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
    this.videoPlayIcon,
    this.imageLoadingPlaceholder,
    this.videoLoadingPlaceholder,
    this.mediaSender,
    this.fileSelector,
    this.actionGuard,
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
  })  : _userIsShowAudioRecorder = isShowAudioRecorder,
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
