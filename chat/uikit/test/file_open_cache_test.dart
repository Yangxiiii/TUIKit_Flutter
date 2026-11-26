import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/file_picker/file_open_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chat-file-open-');
    final cache = await Directory('${root.path}/cache').create();
    messenger.setMockMethodCallHandler(pathProvider, (_) async => cache.path);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProvider, null);
    await root.delete(recursive: true);
  });

  test('外部打开保留中文和扩展名，同名附件各自缓存', () async {
    final sdkFile = await File('${root.path}/uuid').writeAsString('first');
    final bigFile = await File('${root.path}/hash.docx').writeAsString('other');
    const name = '项目计划 #2.docx';

    final paths = await Future.wait([
      prepareFileForOpen(sdkFile.path, name),
      prepareFileForOpen(sdkFile.path, name),
      prepareFileForOpen(bigFile.path, name),
    ]);
    expect(paths.every((path) => File(path).uri.pathSegments.last == name),
        isTrue);
    expect(paths[0], paths[1]);
    expect(paths[0], isNot(paths[2]));
    expect(await File(paths[0]).readAsString(), 'first');
    expect(await File(paths[2]).readAsString(), 'other');
    expect(await sdkFile.readAsString(), 'first');

    await sdkFile.writeAsString('newer');
    await sdkFile.setLastModified(DateTime(2023));
    expect(await prepareFileForOpen(sdkFile.path, name), paths[0]);
    expect(await File(paths[0]).readAsString(), 'newer');
  });

  test('消息文件名始终限制在单个路径段，超长时保留扩展名', () async {
    final source = await File('${root.path}/uuid').writeAsString('content');
    final path = await prepareFileForOpen(source.path, '../子目录\\报告\u0000.pdf');
    expect(File(path).uri.pathSegments.last, '.._子目录_报告_.pdf');
    expect(await File(path).readAsString(), 'content');

    final longName = '${'文' * 100}.pdf';
    final longPath = await prepareFileForOpen(source.path, longName);
    final name = File(longPath).uri.pathSegments.last;
    expect(name, '${'文' * 83}.pdf');
    expect(utf8.encode(name).length, lessThanOrEqualTo(255));
  });

  test('已有原名、缺少消息名和系统 URI 时直接使用已有路径', () async {
    final source = await File('${root.path}/原名.txt').writeAsString('content');
    expect(await prepareFileForOpen(source.path, '原名.txt'), source.path);
    expect(await prepareFileForOpen(source.path, null), source.path);
    const uri = 'file://docs/document';
    expect(await prepareFileForOpen(uri, '原名.txt'), uri);
  });
}
