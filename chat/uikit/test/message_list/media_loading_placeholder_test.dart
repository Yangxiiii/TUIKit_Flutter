import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/chat_media_placeholder.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/custom_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/image_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/video_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/rich_content_editor_sheet.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart';
import 'package:tuikit_atomic_x/album_picker/album_picker.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('编辑器按媒体类型显示宿主占位图并保留 loading 和整体删除', (tester) async {
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOQcHnxHwAEAAJEfJjuTwAAAABJRU5ErkJggg==');
    final image = MemoryImage(bytes);
    final video = MemoryImage(bytes, scale: 2);
    for (final type in AlbumMediaType.values) {
      final key = GlobalKey<RichContentEditorSheetState>();
      await tester.pumpWidget(MaterialApp(
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        home: Scaffold(
            body: RichContentEditorSheet(
                key: key,
                conversationName: '测试',
                initialDraft: const RichContentDraft(),
                canUploadAttachments: true,
                imageLoadingPlaceholder: image,
                videoLoadingPlaceholder: video,
                onSend: (_) async => false)),
      ));
      await tester.pump();
      key.currentState!
          .beginMediaPreparation(AlbumMedia(id: 1, mediaType: type));
      await tester.pump();
      final placeholder = find.byType(ChatMediaPlaceholder);
      expect(placeholder, findsOneWidget);
      expect(tester.widget<ChatMediaPlaceholder>(placeholder).image,
          type == AlbumMediaType.image ? image : video);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(key.currentState!.canSend, isFalse);
      final rect = tester.getRect(placeholder);
      expect(rect.width, lessThanOrEqualTo(120));
      expect(rect.height, lessThanOrEqualTo(160));
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField))
          .controller!
          .clear();
      await tester.pump();
      expect(placeholder, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('普通及富文本媒体等待首帧时使用各自占位，首帧完成后移除且播放入口保留', (tester) async {
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOQcHnxHwAEAAJEfJjuTwAAAABJRU5ErkJggg==');
    final imagePlaceholder = MemoryImage(bytes);
    final videoPlaceholder = MemoryImage(bytes, scale: 2);
    final decoded =
        (await tester.runAsync(() => createTestImage(width: 64, height: 32)))!;
    final cache = PaintingBinding.instance.imageCache;
    addTearDown(() {
      cache.clear();
      cache.clearLiveImages();
      decoded.dispose();
    });
    for (final placeholder in [imagePlaceholder, videoPlaceholder]) {
      cache.putIfAbsent(
          placeholder,
          () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: decoded.clone()))));
    }
    final config = ChatMessageListConfig(
        alignment: 'right',
        enableReadReceipt: false,
        imageLoadingPlaceholder: imagePlaceholder,
        videoLoadingPlaceholder: videoPlaceholder);
    for (final kind in [
      'plain_image',
      'plain_video',
      'rich_image',
      'rich_video'
    ]) {
      final video = kind.endsWith('video');
      final rich = kind.startsWith('rich');
      final url = 'https://example.com/$kind.png';
      final path = '/tmp/$kind.png';
      final scale = tester.view.devicePixelRatio * 1.5;
      final ImageProvider provider = rich
          ? ResizeImage(CachedNetworkImageProvider(url),
              width: (256 * scale).ceil(),
              height: (128 * scale).ceil(),
              policy: ResizeImagePolicy.fit)
          : video
              ? NetworkImage(url)
              : FileImage(File(path));
      final frame = Completer<ImageInfo>();
      // 缓存中预置尚未完成的首帧，避免真实网络或文件 IO 干扰加载状态。
      cache.putIfAbsent(await provider.obtainKey(ImageConfiguration.empty),
          () => OneFrameImageStreamCompleter(frame.future));
      final message = MessageInfo(
          msgID: kind,
          messageType: rich
              ? MessageType.custom
              : video
                  ? MessageType.video
                  : MessageType.image,
          messagePayload: rich
              ? CustomMessagePayload(
                  customData: RichContentMessage([
                  if (video)
                    RichFileBlock('https://example.com/video.mp4', 'video.mp4',
                        1, 'video/mp4',
                        thumbnailUrl: url, width: 64, height: 32)
                  else
                    RichImageBlock(url, 64, 32),
                ]).toCustomData())
              : video
                  ? VideoMessagePayload(
                      videoSnapshotURL: url,
                      videoSnapshotWidth: 64,
                      videoSnapshotHeight: 32)
                  : ImageMessagePayload(
                      originalImagePath: path,
                      originalImageWidth: 64,
                      originalImageHeight: 32));
      final Widget bubble = rich
          ? CustomMessageWidget(
              message: message, isSelf: false, maxWidth: 400, config: config)
          : video
              ? VideoMessageWidget(
                  message: message,
                  conversationID: 'c2c_test',
                  isSelf: false,
                  maxWidth: 400,
                  config: config)
              : ImageMessageWidget(
                  message: message,
                  conversationID: 'c2c_test',
                  isSelf: false,
                  maxWidth: 400,
                  config: config);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: bubble)));
      await tester.pump();
      final loading = find.byType(ChatMediaPlaceholder);
      expect(loading, findsOneWidget, reason: kind);
      expect(tester.widget<ChatMediaPlaceholder>(loading).image,
          video ? videoPlaceholder : imagePlaceholder,
          reason: kind);
      final rect = tester.getRect(loading);
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      frame.complete(ImageInfo(image: decoded.clone()));
      await tester.pumpAndSettle();
      expect(loading, findsNothing, reason: kind);
      expect(find.byType(RawImage), findsWidgets);
      if (video) {
        expect(find.byIcon(rich ? AppIcons.videoPlay : Icons.play_arrow),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: kind);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
