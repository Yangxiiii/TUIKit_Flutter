import 'dart:async';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart' show Toast;
import 'package:tencent_chat_uikit/src/image_viewer/image_element.dart';
import 'package:tencent_chat_uikit/src/image_viewer/image_viewer_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/big_file_message.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/custom_message_widget.dart';
import 'package:tencent_chat_uikit/src/video_player/video_player_widget.dart';

const image1 = 'https://example.com/one.png';
const image2 = 'https://example.com/two.png';
const cover = 'https://example.com/cover.png';
const video = 'https://example.com/movie.mp4';
const content = RichContentMessage([
  RichTextBlock('媒体说明'),
  RichImageBlock(image1, 160, 90),
  RichFileBlock(video, 'movie.mp4', 123, 'video/mp4', thumbnailUrl: cover),
  RichFileBlock('https://example.com/a.pdf', 'a.pdf', 12, 'application/pdf'),
  RichImageBlock(image2, 160, 90),
]);

void main() {
  Future<void> mount(WidgetTester tester,
      {Future<String> Function(BigFileMessage)? download,
      RichContentMessage messageContent = content}) async {
    final cache = PaintingBinding.instance.imageCache;
    addTearDown(() {
      cache.clear();
      cache.clearLiveImages();
    });
    for (final url in [image1, image2, cover]) {
      final image =
          await tester.runAsync(() => createTestImage(width: 160, height: 90));
      cache.putIfAbsent(
          CachedNetworkImageProvider(url),
          () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: image!))));
    }
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomMessageWidget(
      message: MessageInfo(
          msgID: 'rich',
          messageType: MessageType.custom,
          messagePayload:
              CustomMessagePayload(customData: messageContent.toCustomData())),
      isSelf: false,
      maxWidth: 320,
      config: ChatMessageListConfig(fileDownloader: download),
    ))));
    await tester.pumpAndSettle();
  }

  test('预览资源标识往返兼容普通媒体，缺省时仍按原封面路径处理', () {
    const original = ImageElement(type: 1, imagePath: '/tmp/cover.jpg');
    expect(original.toMap().containsKey('mediaId'), isFalse);
    expect(
        ImageElement.fromMap(original.toMap()).resourceKey, '/tmp/cover.jpg');
    const rich = ImageElement(type: 1, imagePath: '', mediaId: video);
    final restored = ImageElement.fromMap(rich.toMap());
    expect(restored, rich);
    expect(restored.resourceKey, video);
  });

  testWidgets('多个无封面视频按资源区分，下载失败可重试且关闭后的失败不再提示', (tester) async {
    const second = 'https://example.com/second.mp4';
    final requested = <String>[];
    final pending = Completer<String>();
    await mount(tester,
        messageContent: const RichContentMessage([
          RichFileBlock(video, 'one.mp4', 1, 'video/mp4'),
          RichFileBlock(second, 'second.mp4', 2, 'video/mp4'),
        ]), download: (file) {
      requested.add(file.url);
      if (requested.length == 1) return Future.error(StateError('下载失败'));
      return pending.future;
    });
    await tester.tap(
        find.bySemanticsIdentifier('tim.rich.video.rich.${second.hashCode}'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.download).hitTestable());
    await tester.pumpAndSettle();
    expect(requested, [second]);
    expect(find.text('视频下载失败，请重试'), findsOneWidget);
    Toast.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.download).hitTestable());
    await tester.pump();
    expect(requested, [second, second]);
    Navigator.of(tester.element(find.byType(ImageViewerWidget))).pop();
    await tester.pumpAndSettle();
    pending.completeError(StateError('迟到的失败'));
    await tester.pump();
    expect(find.text('视频下载失败，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击富文本中的第二张图片进入共用预览器，顺序忽略文字文件且支持双击缩放', (tester) async {
    await mount(tester);
    await tester.tap(
        find.bySemanticsIdentifier('tim.rich.image.rich.${image2.hashCode}'));
    await tester.pumpAndSettle();
    final viewer =
        tester.widget<ImageViewerWidget>(find.byType(ImageViewerWidget));
    expect(viewer.initialIndex, 2);
    expect(viewer.imageElements.map((e) => e.type), [0, 1, 0]);
    expect(
        viewer.imageElements.map((e) => e.imagePath), [image1, cover, image2]);
    final picture = find.descendant(
        of: find.byType(ImageViewerWidget),
        matching: find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.image == const CachedNetworkImageProvider(image2)));
    expect(picture, findsOneWidget);
    final before = tester.getRect(picture).width;
    await tester.tap(picture);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(picture);
    await tester.pumpAndSettle();
    expect(tester.getRect(picture).width, greaterThan(before));
    Navigator.of(tester.element(find.byType(ImageViewerWidget))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerWidget), findsNothing);
    expect(find.text('媒体说明', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击富文本视频进入同一预览器，下载成功交给单独视频消息的播放器', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final pending = Completer<String>();
    BigFileMessage? requested;
    await mount(tester, download: (file) {
      requested = file;
      return pending.future;
    });
    await tester.tap(
        find.bySemanticsIdentifier('tim.rich.video.rich.${video.hashCode}'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ImageViewerWidget>(find.byType(ImageViewerWidget))
            .initialIndex,
        1);
    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    expect((requested!.url, requested!.name, requested!.size),
        (video, 'movie.mp4', 123));
    pending.complete('/tmp/downloaded-video.mp4');
    await tester.pumpAndSettle();
    final player =
        tester.widget<VideoPlayerWidget>(find.byType(VideoPlayerWidget));
    expect(player.video.localPath, '/tmp/downloaded-video.mp4');
    expect(player.video.snapshotUrl, cover);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('下载过程中关闭预览，迟到结果不得触发已销毁页面更新', (tester) async {
    final pending = Completer<String>();
    await mount(tester, download: (_) => pending.future);
    await tester.tap(
        find.bySemanticsIdentifier('tim.rich.video.rich.${video.hashCode}'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    Navigator.of(tester.element(find.byType(ImageViewerWidget))).pop();
    await tester.pumpAndSettle();
    pending.complete('/tmp/late.mp4');
    await tester.pump();
    expect(find.byType(ImageViewerWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
