import 'package:flutter/foundation.dart';

/// 保存全屏预览资源及用于分页重新定位的稳定标识。
class ImageElement {
  /// 预览器内部类型：0为图片，1为视频。
  final int type;

  /// 图片或视频封面的本地路径，也可为富文本协议校验过的HTTP(S)地址。
  final String imagePath;

  /// 主图下载或解码失败时，按顺序尝试剩余地址。
  final List<String> fallbackImagePaths;

  /// 已下载视频的本地路径，未下载时为空并展示下载入口。
  final String? videoPath;

  /// 富文本媒体的稳定资源标识，区分缺少封面或共用封面的不同视频；普通消息可缺省。
  final String? mediaId;

  /// 下载状态和结果回填使用的标识，兼容普通消息沿用本地封面路径。
  String get resourceKey => mediaId ?? imagePath;

  const ImageElement({
    required this.type,
    required this.imagePath,
    this.videoPath,
    this.mediaId,
    this.fallbackImagePaths = const [],
  });

  bool get isImage => type == 0;

  bool get isVideo => type == 1;

  bool get hasVideoFile => videoPath != null && videoPath!.isNotEmpty;

  /// 还原预览器内部Map，缺少资源标识时兼容普通媒体；此结构不是富文本消息协议。
  factory ImageElement.fromMap(Map<String, dynamic> map) {
    return ImageElement(
      type: map['type'] as int,
      imagePath: map['imagePath'] as String,
      videoPath: map['videoPath'] as String?,
      mediaId: map['mediaId'] as String?,
      fallbackImagePaths:
          (map['fallbackImagePaths'] as List?)?.cast<String>() ?? const [],
    );
  }

  /// 导出预览组件内部字段，普通媒体不额外写入富文本资源标识。
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'imagePath': imagePath,
      'videoPath': videoPath,
      if (mediaId != null) 'mediaId': mediaId,
      if (fallbackImagePaths.isNotEmpty)
        'fallbackImagePaths': fallbackImagePaths,
    };
  }

  @override
  String toString() {
    return 'ImageElement(type: $type, imagePath: $imagePath, videoPath: $videoPath)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ImageElement &&
        other.type == type &&
        other.imagePath == imagePath &&
        other.videoPath == videoPath &&
        other.mediaId == mediaId &&
        listEquals(other.fallbackImagePaths, fallbackImagePaths);
  }

  @override
  int get hashCode {
    return type.hashCode ^
        imagePath.hashCode ^
        videoPath.hashCode ^
        mediaId.hashCode ^
        Object.hashAll(fallbackImagePaths);
  }
}
