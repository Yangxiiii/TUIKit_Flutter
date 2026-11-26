import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 为系统预览准备按消息命名的本地文件，保留源文件供下载缓存继续复用。
Future<String> prepareFileForOpen(String path, String? fileName) async {
  if (fileName == null || fileName.trim().isEmpty || !path.startsWith('/')) {
    return path;
  }
  final name = _safeFileName(fileName);
  final source = File(path);
  if (source.uri.pathSegments.last == name) return path;

  final sourceStat = await source.stat();
  if (sourceStat.type != FileSystemEntityType.file) {
    throw FileSystemException('文件不可用', path);
  }
  // 使用源路径摘要隔离同名附件，副本放入系统缓存，供接收应用稍后读取。
  final cache = await getTemporaryDirectory();
  final sourceKey = sha256.convert(utf8.encode(path));
  final directory = Directory('${cache.path}/chat_file_open/$sourceKey');
  final target = File('${directory.path}/$name');
  final cached = await target.stat();
  if (cached.type == FileSystemEntityType.file &&
      cached.size == sourceStat.size &&
      cached.modified == sourceStat.modified) {
    return target.path;
  }

  // 聊天和历史可以同时打开同一附件，完整复制后才原子发布目标路径。
  await directory.create(recursive: true);
  final staging = await directory.createTemp('.open-');
  try {
    final copy = await source.copy('${staging.path}/attachment');
    await copy.setLastModified(sourceStat.modified);
    await copy.rename(target.path);
  } finally {
    await staging.delete(recursive: true);
  }
  return target.path;
}

/// 将消息文件名约束为一个安全的路径段，限制 UTF-8 长度并尽量保留扩展名。
String _safeFileName(String fileName) {
  final name = fileName.replaceAll(RegExp(r'[/\\\x00-\x1f\x7f]'), '_');
  if (name == '.' || name == '..') return 'file';
  if (utf8.encode(name).length <= 255) return name;

  final suffix = RegExp(r'\.[a-zA-Z0-9]{1,16}$').stringMatch(name) ?? '';
  final stem = name.substring(0, name.length - suffix.length);
  final shortened = StringBuffer();
  var bytesLeft = 255 - suffix.length;
  // 按码点截断，避免切断中文或表情的 UTF-8 序列。
  for (final rune in stem.runes) {
    final character = String.fromCharCode(rune);
    bytesLeft -= utf8.encode(character).length;
    if (bytesLeft < 0) break;
    shortened.write(character);
  }
  return '$shortened$suffix';
}
