import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';

void main() {
  test('图文自定义消息按原顺序解析文字、图片和文件', () {
    final raw = jsonEncode({
      'businessID': 'oa_rich_content',
      'version': 1,
      'payload': {
        'blocks': [
          {'type': 'text', 'text': '第一段\n文字'},
          {
            'type': 'image',
            'url': 'https://example.com/a.png',
            'width': 1080,
            'height': 720,
          },
          {'type': 'text', 'text': '第二段'},
          {
            'type': 'file',
            'url': 'https://example.com/a.pdf',
            'name': '报价单.pdf',
            'size': 182340,
            'mimeType': 'application/pdf',
          },
        ],
      },
    });

    final message = RichContentMessage.tryParse(raw);
    expect(message, isNotNull);
    expect(message!.blocks, hasLength(4));
    expect((message.blocks[0] as RichTextBlock).text, '第一段\n文字');
    expect(
        (message.blocks[1] as RichImageBlock).url, 'https://example.com/a.png');
    expect((message.blocks[2] as RichTextBlock).text, '第二段');
    expect((message.blocks[3] as RichFileBlock).name, '报价单.pdf');
  });

  test('其他业务类型、未知版本和损坏的图文消息交给通用气泡兜底', () {
    expect(RichContentMessage.tryParse('not-json'), isNull);
    expect(
      RichContentMessage.tryParse(jsonEncode({
        'businessID': 'group_create',
        'version': 1,
        'payload': {'blocks': []},
      })),
      isNull,
    );
    expect(
      RichContentMessage.tryParse(jsonEncode({
        'businessID': 'oa_rich_content',
        'version': 2,
        'payload': {'blocks': []},
      })),
      isNull,
    );
    expect(
      RichContentMessage.tryParse(jsonEncode({
        'businessID': 'oa_rich_content',
        'version': 1,
        'payload': {
          'blocks': [
            {'type': 'text', 'text': '有效文字'},
            {
              'type': 'image',
              'url': 'javascript:alert(1)',
              'width': 1,
              'height': 1
            },
          ],
        },
      })),
      isNull,
    );
  });
}
