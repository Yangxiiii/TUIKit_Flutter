import 'dart:ui';

import 'album_picker_platform.dart';

enum AlbumPickerMediaFilter {
  imageOnly,
  videoOnly,
  imageAndVideo,
}

enum AlbumMediaType {
  image,
  video,
}

enum AlbumPickerStyle {
  likeWeChat,
  likeWhatsApp,
}

enum AlbumPickerLanguage {
  system,
  en,
  zhHans,
  zhHant,
  ar,
}

enum AlbumPickerCompressQuality {
  standard,
  high,
}

class AlbumPickerTheme {
  final Color? primaryColor;
  final Color? backgroundColor;
  final Color? backgroundColorSecondary;
  final Color? textColor;
  final Color? textColorSecondary;
  final String? confirmButtonIconAsset;
  final double? bigFontSize;
  final double? normalFontSize;
  final double? smallFontSize;
  final double? bigRadius;
  final double? normalRadius;
  final double? smallRadius;

  const AlbumPickerTheme({
    this.primaryColor,
    this.backgroundColor,
    this.backgroundColorSecondary,
    this.textColor,
    this.textColorSecondary,
    this.confirmButtonIconAsset,
    this.bigFontSize,
    this.normalFontSize,
    this.smallFontSize,
    this.bigRadius,
    this.normalRadius,
    this.smallRadius,
  });
}

/// 相册返回的媒体资料，分别记录选择时的原件和处理后的本地文件。
class AlbumMedia {
  final int id;
  final String uri;
  final AlbumMediaType mediaType;
  final String mediaPath;
  final String fileExtension;
  final int fileSize;
  final String? videoThumbnailPath;
  final int duration;

  /// 发送原件或平台直接复制原件时为真，未知时由导出结果决定上传通道。
  final bool isOriginal;

  /// 选择时原件的文件名，提供者未返回时为空。
  final String? sourceFileName;

  /// 选择时原件的字节数，未知时以导出结果分流。
  final int? sourceFileSize;

  AlbumMedia({
    required this.id,
    this.uri = '',
    required this.mediaType,
    this.mediaPath = '',
    this.fileExtension = '',
    this.fileSize = 0,
    this.videoThumbnailPath,
    this.duration = 0,
    this.isOriginal = false,
    this.sourceFileName,
    this.sourceFileSize,
  });

  @override
  String toString() {
    return 'AlbumMedia(id: $id, uri: $uri, mediaType: $mediaType, mediaPath: $mediaPath, '
        'fileExtension: $fileExtension, fileSize: $fileSize, '
        'videoThumbnailPath: $videoThumbnailPath, duration: $duration)';
  }
}

/// 配置腾讯相册的选择界面和本地导出。
class AlbumPickerConfig {
  /// 原生接收的最大正整数，将实际大小限制交给发送层。
  static const unrestrictedOutputFileSizeInMB = 0x7fffffff;

  final AlbumPickerMediaFilter? mediaFilter;
  final int? maxSelectionCount;
  final int? itemsPerRow;
  final bool? showsCameraItem;
  final AlbumPickerStyle? style;
  final AlbumPickerLanguage? language;
  final AlbumPickerCompressQuality? compressQuality;
  final int? maxVideoDurationInSeconds;
  final int? maxOutputFileSizeInMB;

  /// 在选择确认事件补充原件资料，供聊天在创建占位前分流。
  final bool includeSourceMetadata;

  const AlbumPickerConfig({
    this.mediaFilter,
    this.maxSelectionCount,
    this.itemsPerRow,
    this.showsCameraItem,
    this.style,
    this.language,
    this.compressQuality,
    this.maxVideoDurationInSeconds,
    this.maxOutputFileSizeInMB,
    this.includeSourceMetadata = false,
  });
}

/// 提供腾讯原生相册选择和单张本地图片编辑。
class AlbumPicker {
  static final AlbumPicker instance = AlbumPicker._internal();

  AlbumPicker._internal();

  /// 直接编辑当前本地图片，原文件由调用方持有，返回的临时副本由调用方清理。
  static Future<String?> editImage({required String imagePath}) =>
      AlbumPickerPlatform.editImageNative(imagePath);

  /// Callbacks mirror native AlbumPickerDelegate / AlbumPickerListener:
  /// - [onPickConfirm]: User confirmed selection. Provides all selected media.
  /// - [onMediaProcessing]: A media item is being processed (export/compress).
  /// - [onMediaProcessed]: All media items have finished processing.
  /// - [onCancel]: User cancelled the picker.
  static Future<void> pickMedia({
    AlbumPickerConfig? config,
    AlbumPickerTheme? theme,
    Function(List<AlbumMedia> pickedAlbumMedias, String? textMessage)?
        onPickConfirm,
    Function(AlbumMedia albumMedia, double progress, bool error)?
        onMediaProcessing,
    Function()? onMediaProcessed,
    Function()? onCancel,
  }) async {
    return AlbumPickerPlatform.pickMediaNative(
      config: config,
      theme: theme,
      onPickConfirm: onPickConfirm,
      onMediaProcessing: onMediaProcessing,
      onMediaProcessed: onMediaProcessed,
      onCancel: onCancel,
    );
  }
}
