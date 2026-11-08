import 'dart:convert';
import 'dart:io';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/album_picker_media_send_manager.dart';
import 'package:tencent_chat_uikit/src/message_input/chat_media_sender.dart';
import 'package:tuikit_atomic_x/album_picker/album_picker.dart';
import 'package:tuikit_atomic_x/album_picker/album_picker_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('压缩时先显示文件占位，导出后按实际大小移交或清理', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const method = MethodChannel('atomic_x/album_picker');
    const events = MethodChannel('atomic_x/album_picker_events');
    const codec = StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    addTearDown(() async {
      await AlbumPickerPlatform.dispose();
      messenger.setMockMethodCallHandler(method, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    final directory = await Directory.systemTemp.createTemp('album-original-');
    addTearDown(() => directory.delete(recursive: true));
    final small = await File('${directory.path}/small.mp4').writeAsBytes([1]);
    final large = await File('${directory.path}/export.mp4').writeAsBytes([2]);
    final cover = await File('${directory.path}/portrait.png').writeAsBytes(
      base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAAECAYAAACk7+45AAAAEUlE'
          'QVR4nGP4z8DwH4QZcDMAHxMP8b9IbMkAAAAASUVORK5CYII='),
    );
    final limit = ChatMediaKind.video.nativeLimitBytes;
    final compressedAboveLimit = File('${directory.path}/above.mp4');
    final handle = await compressedAboveLimit.open(mode: FileMode.write);
    await handle.truncate(limit + 1);
    await handle.close();
    final listener = _Listener();

    messenger.setMockMethodCallHandler(method, (call) async {
      final args = call.arguments as Map;
      expect(args['includeSourceMetadata'], isTrue);
      expect(args.containsKey('exportOriginalFiles'), isFalse);
      Future<void> emit(String type, Map<String, Object?> fields) =>
          messenger.handlePlatformMessage(
            events.name,
            codec.encodeSuccessEnvelope({
              'sessionId': args['sessionId'],
              'type': type,
              ...fields,
            }),
            (_) {},
          );

      await emit('onPickConfirm', {
        'pickedAlbumMedias': [
          {
            'id': 1,
            'mediaType': 1,
            'isOriginal': true,
            'sourceFileName': '原视频.mp4',
            'sourceFileSize': limit + 1,
          },
          {
            'id': 2,
            'mediaType': 1,
            'isOriginal': true,
            'sourceFileSize': limit,
            'videoThumbnailPath': '/cover.jpg',
          },
          {
            'id': 3,
            'mediaType': 1,
            'isOriginal': false,
            'sourceFileSize': limit + 1,
            'fileSize': limit + 1,
          },
          {'id': 4, 'mediaType': 1, 'sourceFileSize': limit + 1},
          {'id': 5, 'mediaType': 1, 'isOriginal': false},
        ],
      });
      // 压缩占位立即可见，原文件大小不能提前锁定压缩后的上传通道。
      expect(listener.messages, isEmpty);
      expect(listener.placeholders.map((m) => m.messageType), [
        MessageType.file,
        MessageType.video,
        MessageType.file,
        MessageType.file,
        MessageType.file,
      ]);
      final file =
          listener.placeholders.first.messagePayload as FileMessagePayload;
      expect(file.fileName, '原视频.mp4');
      expect(file.fileSize, limit + 1);
      expect(
          (listener.placeholders[2].messagePayload as FileMessagePayload)
              .fileSize,
          0);
      await emit('onMediaProcessing', {
        'data': {'id': 3, 'mediaType': 1},
        'progress': .5,
      });
      expect(listener.messages, isEmpty);
      expect(listener.removed, isEmpty);
      for (final (id, file, size, thumbnail) in [
        (1, large, 1, null),
        (2, small, 1, cover.path),
        (3, small, 1, cover.path),
        (4, compressedAboveLimit, limit + 1, null),
      ]) {
        await emit('onMediaProcessing', {
          'data': {
            'id': id,
            'mediaType': 1,
            'mediaPath': file.path,
            'fileSize': size,
            'videoThumbnailPath': thumbnail,
          },
          'progress': 1.0,
        });
      }
      await emit('onMediaProcessing', {
        'data': {'id': 5, 'mediaType': 1},
        'progress': 1.0,
        'error': true,
      });
      await emit('onMediaProcessed', {});
      return null;
    });

    await AlbumPickerMediaSendManager.shared.pickAlbumMedia(
      conversationID: 'c2c_peer',
      listener: listener,
      config: const AlbumPickerConfig(includeSourceMetadata: true),
    );
    final videos = listener.messages
        .map((message) => message.messagePayload as VideoMessagePayload)
        .toList();
    expect(videos.map((video) => video.videoPath),
        [large.path, small.path, small.path, compressedAboveLimit.path]);
    expect(videos.first.videoSnapshotPath, isEmpty);
    for (final video in videos.sublist(1, 3)) {
      expect(video.videoSnapshotPath, cover.path);
      expect(video.videoSnapshotWidth, 2);
      expect(video.videoSnapshotHeight, 4);
    }
    expect(videos.last.videoSnapshotPath, isEmpty);
    expect(listener.uploadPlaceholders, [
      same(listener.placeholders.first),
      isNull,
      isNull,
      same(listener.placeholders[3]),
    ]);
    expect((await ChatLocalMedia.read(videos[2]))!.needsDirectUpload, isFalse);
    expect((await ChatLocalMedia.read(videos[3]))!.needsDirectUpload, isTrue);
    expect(
        listener.removed,
        unorderedEquals([
          same(listener.placeholders[1]),
          same(listener.placeholders[2]),
          same(listener.placeholders[4]),
        ]));
    expect(listener.preparationFailures, 1);
  });
}

final class _Listener implements AlbumPickerMediaSendListener {
  final messages = <MessageInfo>[];
  final placeholders = <MessageInfo>[];
  final uploadPlaceholders = <MessageInfo?>[];
  final removed = <MessageInfo>[];
  int preparationFailures = 0;

  @override
  void onSendMessage(MessageInfo messageInfo,
      {MessageInfo? albumUploadPlaceholder}) {
    messages.add(messageInfo);
    uploadPlaceholders.add(albumUploadPlaceholder);
  }

  @override
  void onSendPlaceholderMessage(MessageInfo placeholder) =>
      placeholders.add(placeholder);

  @override
  void onRemovePlaceholderMessage(MessageInfo placeholder) =>
      removed.add(placeholder);

  @override
  void onMediaPreparationFailed() => preparationFailures++;
}
