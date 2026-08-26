class ImageElement {
  final int type;

  final String imagePath;

  final String? videoPath;

  const ImageElement({
    required this.type,
    required this.imagePath,
    this.videoPath,
  });

  bool get isImage => type == 0;

  bool get isVideo => type == 1;

  bool get hasVideoFile => videoPath != null && videoPath!.isNotEmpty;

  factory ImageElement.fromMap(Map<String, dynamic> map) {
    return ImageElement(
      type: map['type'] as int,
      imagePath: map['imagePath'] as String,
      videoPath: map['videoPath'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'imagePath': imagePath,
      'videoPath': videoPath,
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
        other.videoPath == videoPath;
  }

  @override
  int get hashCode {
    return type.hashCode ^ imagePath.hashCode ^ videoPath.hashCode;
  }
}
