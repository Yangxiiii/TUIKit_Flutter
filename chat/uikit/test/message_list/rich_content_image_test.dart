import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/src/conversation_list/rich_content_preview.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

const _url = 'https://example.com/rich-content.png';

/// 复现接收到的文字、换行、无尺寸图片和后续文字结构，资源地址使用测试值。
String _customData({Map<String, Object?> dimensions = const {}}) => jsonEncode({
      'businessID': 'oa_rich_content',
      'version': 1,
      'payload': {
        'blocks': [
          {'type': 'text', 'text': '空行验证文字A'},
          {'type': 'text', 'text': '\n'},
          {'type': 'image', 'url': _url, ...dimensions},
          {'type': 'text', 'text': '\n'},
          {'type': 'text', 'text': '\n'},
          {'type': 'text', 'text': '空行验证文字B'},
        ],
      },
    });

void main() {
  test('无尺寸图片完整解析且可回填、持久化及再次发送，发送协议仅包含地址', () {
    final content = RichContentMessage.tryParse(_customData())!;
    expect(content.blocks, hasLength(6));
    final image = content.blocks[2] as RichImageBlock;
    expect(image.width, isNull);
    expect(image.height, isNull);
    expect(content.blocks.whereType<RichTextBlock>().map((b) => b.text),
        ['空行验证文字A', '\n', '\n', '\n', '空行验证文字B']);

    final draft = RichContentDraft.fromMessage(content);
    expect(draft.canSend, isTrue);
    final restored =
        RichContentDraft.tryParsePersisted(draft.toPersistedString())!;
    expect(restored.canSend, isTrue);
    expect(restored.toMessage()!.toCustomData(), _customData());
    final encoded = jsonDecode(const RichContentMessage([
      RichImageBlock(_url, 640, 360),
    ]).toCustomData());
    expect(encoded['payload']['blocks'], [
      {'type': 'image', 'url': _url},
    ]);
  });

  test('兼容旧图片尺寸和空尺寸，仍拒绝非法地址及错误尺寸类型', () {
    for (final dimensions in <Map<String, Object?>>[
      {'width': 640, 'height': 360},
      {'width': 640},
      {'width': null, 'height': null},
    ]) {
      expect(RichContentMessage.tryParse(_customData(dimensions: dimensions)),
          isNotNull);
    }
    for (final dimensions in <Map<String, Object?>>[
      {'width': 0},
      {'height': -1},
      {'width': '640'},
      {'height': []},
    ]) {
      expect(RichContentMessage.tryParse(_customData(dimensions: dimensions)),
          isNull);
    }
    expect(
        RichContentMessage.tryParse(
            _customData().replaceAll(_url, 'javascript:alert(1)')),
        isNull);
  });

  testWidgets('无尺寸图文显示正文及图片，列表展示图片占位，长图保持比例且限制高度', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cache = PaintingBinding.instance.imageCache;
    addTearDown(() {
      cache.clear();
      cache.clearLiveImages();
    });
    final message = MessageInfo(
      messageType: MessageType.custom,
      messagePayload: CustomMessagePayload(customData: _customData()),
    );
    for (final size in [const Size(400, 200), const Size(100, 600)]) {
      await tester.pumpWidget(const SizedBox());
      cache.clear();
      cache.clearLiveImages();
      final image = await tester.runAsync(() => createTestImage(
          width: size.width.toInt(), height: size.height.toInt()));
      // 使用已解码的内存图片验证真实布局，测试不请求网络资源。
      cache.putIfAbsent(
        const CachedNetworkImageProvider(_url),
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image!))),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: CustomMessageWidget(
          message: message,
          isSelf: false,
          maxWidth: 400,
        ))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('空行验证文字A', findRichText: true), findsOneWidget);
      expect(find.text('空行验证文字B', findRichText: true), findsOneWidget);
      final cached =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(cached.height, isNull);
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.image!.width, size.width.toInt());
      expect(raw.fit, BoxFit.contain);
      final displayed = tester.getSize(find.byType(RawImage));
      expect(displayed.height, lessThanOrEqualTo(240));
      if (size.width > size.height) {
        expect(displayed.width / displayed.height,
            closeTo(size.width / size.height, 0.01));
      }
      final context = tester.element(find.byType(CustomMessageWidget));
      final preview =
          richContentConversationPreview(context, message, const TextStyle())!
              .toPlainText();
      expect(preview, contains('[图片]'));
      expect(preview, contains('空行验证文字B'));
      expect(tester.takeException(), isNull);
    }
    // 失败占位不依赖图片尺寸，也不能使气泡布局抛出异常。
    final cached =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    final context = tester.element(find.byType(CustomMessageWidget));
    final error = cached.errorWidget!(context, _url, StateError('测试图片不可用'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: error)));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
