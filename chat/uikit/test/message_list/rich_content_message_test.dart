import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_chat_uikit/src/message_input/message_input_config.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_markdown_format.dart';

void main() {
  test('草稿视频时长可缺省并拒绝负数及错误类型', () {
    const draft = RichContentDraft(blocks: [
      RichContentDraftAttachmentBlock(1,
          attachment: RichContentLocalAttachment(
            type: RichContentAttachmentType.file,
            localPath: '/tmp/video.mp4',
            fileName: 'video.mp4',
            fileSize: 1,
            mimeType: 'video/mp4',
            durationMs: 232000,
          )),
    ]);
    final encoded = draft.toPersistedString();
    const prefix = 'oa-rich-content-draft-v1:';
    final json =
        jsonDecode(encoded.substring(prefix.length)) as Map<String, dynamic>;
    final attachment = (json['blocks'] as List).single as Map<String, dynamic>;
    RichContentDraft? parse() =>
        RichContentDraft.tryParsePersisted('$prefix${jsonEncode(json)}');
    for (final invalid in [-1, '232000', 1.5]) {
      attachment['durationMs'] = invalid;
      expect(parse(), isNull);
    }
    attachment.remove('durationMs');
    final restored = parse()!.blocks.single as RichContentDraftAttachmentBlock;
    expect(restored.attachment.durationMs, isNull);
  });

  test('视频封面协议往返和草稿回填，旧消息可缺省且拒绝非法封面地址', () {
    const video = RichFileBlock(
        'https://example.com/video.mp4', '视频.mp4', 12, 'video/mp4',
        thumbnailUrl: 'https://example.com/cover.jpg');
    const message = RichContentMessage([video]);
    final parsed = RichContentMessage.tryParse(message.toCustomData())!;
    expect((parsed.blocks.single as RichFileBlock).thumbnailUrl,
        video.thumbnailUrl);
    final draft = RichContentDraft.fromMessage(parsed);
    final restored =
        RichContentDraft.tryParsePersisted(draft.toPersistedString())!;
    expect(restored.canSend, isTrue);
    expect(restored.toMessage()!.toCustomData(), message.toCustomData());
    final base = <String, Object?>{
      'type': 'file',
      'url': video.url,
      'name': video.name,
      'size': video.size,
      'mimeType': video.mimeType
    };
    String encode(Map<String, Object?> block) => jsonEncode({
          'businessID': RichContentMessage.businessID,
          'version': 1,
          'payload': {
            'blocks': [block]
          }
        });
    expect(RichContentMessage.tryParse(encode(base)), isNotNull);
    for (final value in [
      'file:///tmp/a.jpg',
      'javascript:alert(1)',
      '',
      1,
      false
    ]) {
      expect(
          RichContentMessage.tryParse(encode({...base, 'thumbnailUrl': value})),
          isNull);
    }
  });

  test('光标在格式正文前不选中，仅中间及末尾选中，内层起点保留外层样式', () {
    for (final marker in richContentMarkdownFormatOrder) {
      final source = '普通$marker甲乙$marker';
      final start = source.indexOf('甲');
      for (var offset = 2; offset <= start; offset++) {
        expect(richContentMarkdownFormatsAt(source, offset), isEmpty,
            reason: '$marker 起点 $offset');
      }
      for (var offset = start + 1; offset <= source.length; offset++) {
        expect(richContentMarkdownFormatsAt(source, offset), {marker},
            reason: '$marker 中间及末尾 $offset');
      }
    }
    const nested = '**前*内文*后**';
    expect(richContentMarkdownFormatsAt(nested, nested.indexOf('前')), isEmpty);
    expect(richContentMarkdownFormatsAt(nested, nested.indexOf('内')), {'**'});
    const combined = '~**~~*组合*~~**~';
    expect(
        richContentMarkdownFormatsAt(combined, combined.indexOf('组')), isEmpty);
    const link = '[**链接**](https://example.com)';
    expect(richContentMarkdownFormatsAt(link, link.indexOf('链')), isEmpty);
  });

  test('光标识别共享格式边界，正文中间及末尾选中左侧样式，进入普通文字清除', () {
    const source = '**前*内文*后**普通';
    expect(richContentMarkdownFormatsAt(source, source.indexOf('内') + 1),
        {'**', '*'});
    expect(richContentMarkdownFormatsAt(source, source.indexOf('文') + 1),
        {'**', '*'});
    expect(
        richContentMarkdownFormatsAt(source, source.indexOf('后')), {'**', '*'});
    expect(
        richContentMarkdownFormatsAt(source, source.indexOf('后') + 1), {'**'});
    expect(richContentMarkdownFormatsAt(source, source.indexOf('普')), {'**'});
    expect(
        richContentMarkdownFormatsAt(source, source.indexOf('普') + 1), isEmpty);
    const adjacent = '**粗***斜*';
    expect(richContentMarkdownFormatsAt(adjacent, 5), {'**'});
    expect(richContentMarkdownFormatsAt(adjacent, 7), {'*'});
    const nested = '~**~~*组合*~~**~';
    expect(richContentMarkdownFormatsAt(nested, nested.indexOf('组') + 1),
        {'**', '~~', '*', '~'});
    expect(richContentMarkdownFormatsAt(nested, nested.length),
        {'**', '~~', '*', '~'});
    expect(richContentMarkdownFormatsAt('**粗**\n普通', 6), isEmpty);
  });

  test('光标格式不误读转义、代码及链接地址，链接正文仍支持嵌套格式', () {
    for (final source in [r'\*\*文字\*\*', '`**文字**`', '```\n**文字**\n```']) {
      expect(
          richContentMarkdownFormatsAt(source, source.indexOf('字')), isEmpty);
    }
    const link = '[**链接**](https://example.com/~路径~)';
    expect(richContentMarkdownFormatsAt(link, link.indexOf('链') + 1), {'**'});
    expect(richContentMarkdownFormatsAt(link, link.indexOf('路') + 1), isEmpty);
    expect(richContentMarkdownFormatsAt(link, link.length), {'**'});
    expect(richContentMarkdownFormatsAt('**文字**', -1), isEmpty);
    expect(richContentMarkdownFormatsAt('**文字**', 99), isEmpty);
  });

  test('已有格式在未选中工具条时回车仍保持，支持嵌套及替换选区', () {
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{});
    for (final lineBreak in ['\n', '\r\n', '\r']) {
      const source = '**甲乙**';
      final result = formatter.formatEditUpdate(
        const TextEditingValue(
            text: source, selection: TextSelection.collapsed(offset: 3)),
        TextEditingValue(
            text: '**甲$lineBreak乙**',
            selection: TextSelection.collapsed(offset: 3 + lineBreak.length)),
      );
      expect(result.text, '**甲**$lineBreak**乙**');
      expect(result.selection.extentOffset, 5 + lineBreak.length + 2);
    }
    const nested = '**前*甲乙*后**';
    final offset = nested.indexOf('乙');
    final split = formatter.formatEditUpdate(
      TextEditingValue(
          text: nested, selection: TextSelection.collapsed(offset: offset)),
      TextEditingValue(
          text: nested.replaceRange(offset, offset, '\n'),
          selection: TextSelection.collapsed(offset: offset + 1)),
    );
    expect(split.text, '**前*甲***\n***乙*后**');
    const source = '**甲乙丙丁**';
    final replaced = formatter.formatEditUpdate(
      const TextEditingValue(
          text: source,
          selection: TextSelection(baseOffset: 3, extentOffset: 5)),
      const TextEditingValue(
          text: '**甲\n丁**', selection: TextSelection.collapsed(offset: 4)),
    );
    expect(replaced.text, '**甲**\n**丁**');
  });

  test('批量输入多行和连续回车不生成跨行格式或空格式段', () {
    final formatter = activeMarkdownFormatInputFormatter(
        () => <String>{'**', '~~', '*', '~'});
    final value = formatter.formatEditUpdate(
        const TextEditingValue(),
        const TextEditingValue(
          text: '第一行\n\n第二行',
          selection: TextSelection.collapsed(offset: 8),
        ));
    expect(value.text, '**~~*~第一行~*~~**\n\n**~~*~第二行~*~~**');
    expect(value.selection.extentOffset, value.text.length - 6);
  });

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
      (message.blocks[1] as RichImageBlock).url,
      'https://example.com/a.png',
    );
    expect((message.blocks[2] as RichTextBlock).text, '第二段');
    expect((message.blocks[3] as RichFileBlock).name, '报价单.pdf');
  });

  test('其他业务类型、未知版本和损坏的图文消息交给通用气泡兜底', () {
    expect(RichContentMessage.tryParse('not-json'), isNull);
    expect(
      RichContentMessage.tryParse(
        jsonEncode({
          'businessID': 'group_create',
          'version': 1,
          'payload': {'blocks': []},
        }),
      ),
      isNull,
    );
    expect(
      RichContentMessage.tryParse(
        jsonEncode({
          'businessID': 'oa_rich_content',
          'version': 2,
          'payload': {'blocks': []},
        }),
      ),
      isNull,
    );
    expect(
      RichContentMessage.tryParse(
        jsonEncode({
          'businessID': 'oa_rich_content',
          'version': 1,
          'payload': {
            'blocks': [
              {'type': 'text', 'text': '有效文字'},
              {
                'type': 'image',
                'url': 'javascript:alert(1)',
                'width': 1,
                'height': 1,
              },
            ],
          },
        }),
      ),
      isNull,
    );
  });

  test('编辑草稿仅在附件上传完成后编码为可解析的自定义消息', () {
    const attachment = RichContentLocalAttachment(
      type: RichContentAttachmentType.image,
      localPath: '/tmp/a.png',
      fileName: 'a.png',
      fileSize: 12,
      mimeType: 'image/png',
      width: 20,
      height: 10,
    );
    const pending = RichContentDraft(
      title: '周报 *草稿*',
      blocks: [
        RichContentDraftTextBlock(1, '正文'),
        RichContentDraftAttachmentBlock(2, attachment: attachment),
      ],
    );
    expect(pending.canSend, isFalse);
    expect(pending.canSubmit, isTrue);
    expect(pending.toMessage(), isNull);

    const uploaded = RichContentDraft(
      title: '周报 *草稿*',
      blocks: [
        RichContentDraftTextBlock(1, '正文'),
        RichContentDraftAttachmentBlock(
          2,
          attachment: attachment,
          remoteUrl: 'https://example.com/a.png',
          status: RichContentAttachmentStatus.uploaded,
        ),
      ],
    );
    final encoded = uploaded.toMessage()!.toCustomData();
    expect(uploaded.hasSameContentAs(pending), isTrue);
    expect(const RichContentDraft().hasSameContentAs(pending), isFalse);
    final parsed = RichContentMessage.tryParse(encoded);
    expect(parsed, isNotNull);
    expect(
      (parsed!.blocks.first as RichTextBlock).text,
      r'**周报 \*草稿\***'
      '\n\n正文',
    );
    expect(parsed.blocks[1], isA<RichImageBlock>());
  });

  test('富文本草稿持久化后保留图片本地路径和块顺序', () {
    const draft = RichContentDraft(
      title: '标题',
      blocks: [
        RichContentDraftTextBlock(1, '图片前'),
        RichContentDraftAttachmentBlock(
          2,
          attachment: RichContentLocalAttachment(
            type: RichContentAttachmentType.image,
            localPath: '/data/user/0/app/files/draft.png',
            fileName: 'draft.png',
            fileSize: 128,
            mimeType: 'image/png',
            width: 640,
            height: 480,
          ),
        ),
        RichContentDraftTextBlock(3, '图片后'),
      ],
    );

    final restored = RichContentDraft.tryParsePersisted(
      draft.toPersistedString(),
    );

    expect(restored, isNotNull);
    expect(restored!.title, '标题');
    expect(restored.blocks.map((block) => block.id), [1, 2, 3]);
    final image = restored.blocks[1] as RichContentDraftAttachmentBlock;
    expect(image.attachment.localPath, '/data/user/0/app/files/draft.png');
    expect(image.attachment.width, 640);
    expect(image.attachment.height, 480);
    expect(restored.plainTextPreview, '标题 图片前 [图片] 图片后');
    expect(restored.hasContent, isTrue);
    expect(
      RichContentDraft.tryParsePersisted('oa-rich-content-draft-v1:broken'),
      isNull,
    );
  });

  test('富文本草稿摘要隐藏相邻和多层 Markdown 标签', () {
    const draft = RichContentDraft(
      title: '标题 *保持原样*',
      blocks: [
        RichContentDraftTextBlock(
          1,
          '普通 **粗体****斜体** ~下划线~ '
          '~**~~*四层格式*~~**~ [链接](https://example.com) ```代码```',
        ),
      ],
    );

    expect(
      draft.plainTextPreview,
      '标题 *保持原样* 普通 粗体斜体 下划线 四层格式 链接 代码',
    );
  });

  test('空富文本不作为草稿，纯图片草稿显示图片摘要', () {
    expect(const RichContentDraft().hasContent, isFalse);
    expect(
      const RichContentDraft(
        blocks: [RichContentDraftTextBlock(1, '  \n')],
      ).hasContent,
      isFalse,
    );
    const imageDraft = RichContentDraft(
      blocks: [
        RichContentDraftAttachmentBlock(
          1,
          attachment: RichContentLocalAttachment(
            type: RichContentAttachmentType.image,
            localPath: '/tmp/image.png',
            fileName: 'image.png',
            fileSize: 1,
            mimeType: 'image/png',
            width: 1,
            height: 1,
          ),
        ),
      ],
    );
    expect(imageDraft.hasContent, isTrue);
    expect(imageDraft.plainTextPreview, '[图片]');
  });

  test('选中格式后只在实际输入时写入 Markdown 标记', () {
    final activeMarkers = <String>{'**'};
    final formatter = activeMarkdownFormatInputFormatter(() => activeMarkers);
    final first = formatter.formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(
        text: '正文',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(first.text, '**正文**');
    expect(first.selection, const TextSelection.collapsed(offset: 4));

    final continued = formatter.formatEditUpdate(
      first,
      const TextEditingValue(
        text: '**正文补**',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    expect(continued.text, '**正文补**');

    final replaced = formatter.formatEditUpdate(
      const TextEditingValue(
        text: '原内容',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
      ),
      const TextEditingValue(
        text: '新',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    expect(replaced.text, '**新**');
  });

  test('多个选中格式按固定顺序嵌套并支持连续输入', () {
    final formatter = activeMarkdownFormatInputFormatter(
      () => <String>{'~', '**', '*', '~~'},
    );
    final first = formatter.formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(
        text: '组合',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(first.text, '**~~*~组合~*~~**');

    final continued = formatter.formatEditUpdate(
      first,
      const TextEditingValue(
        text: '**~~*~组合格式~*~~**',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    expect(continued.text, '**~~*~组合格式~*~~**');
  });

  test('删除格式内全部文字时清理空标签，部分删除仍保留格式', () {
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{});
    final bold = formatter.formatEditUpdate(
      const TextEditingValue(text: '**文字**'),
      const TextEditingValue(
        text: '****',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(bold.text, isEmpty);
    expect(bold.selection, const TextSelection.collapsed(offset: 0));

    final combined = formatter.formatEditUpdate(
      const TextEditingValue(text: '**~~*~组合~*~~**'),
      const TextEditingValue(
        text: '**~~*~~*~~**',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    expect(combined.text, isEmpty);

    final partial = formatter.formatEditUpdate(
      const TextEditingValue(text: '**文字**'),
      const TextEditingValue(
        text: '**文**',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    expect(partial.text, '**文**');
  });

  test('任意顺序的多层标签删除正文后会清理全部标签', () {
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{});
    final result = formatter.formatEditUpdate(
      const TextEditingValue(text: '~**~~*组合*~~**~'),
      const TextEditingValue(
        text: '~**~~**~~**~',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    expect(result.text, isEmpty);
  });

  test('连续删除相邻格式段时光标回到上一段正文', () {
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{});
    final firstDeletion = formatter.formatEditUpdate(
      const TextEditingValue(
        text: '**第一段****第二段**',
        selection: TextSelection.collapsed(offset: 12),
      ),
      const TextEditingValue(
        text: '**第一段******',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    expect(firstDeletion.text, '**第一段**');
    expect(firstDeletion.selection, const TextSelection.collapsed(offset: 5));

    final secondDeletion = formatter.formatEditUpdate(
      firstDeletion,
      const TextEditingValue(
        text: '**第一**',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    expect(secondDeletion.text, '**第一**');
  });

  test('连续删除不同格式的相邻文本时光标不跳转', () {
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{});
    var value = const TextEditingValue(
      text: '**甲***乙*~~丙~~~丁~',
      selection: TextSelection.collapsed(offset: 16),
    );

    value = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '**甲***乙*~~丙~~~丁',
        selection: TextSelection.collapsed(offset: 15),
      ),
    );
    expect(value.text, '**甲***乙*~~丙~~');
    expect(value.selection, const TextSelection.collapsed(offset: 11));

    value = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '**甲***乙*~~~~',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    expect(value.text, '**甲***乙*');
    expect(value.selection, const TextSelection.collapsed(offset: 7));
  });

  test('连续删除相邻的多层格式段时光标回到上一段正文', () {
    const first = '**~~甲~~**';
    const firstAndSecond = '$first*~乙~*';
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{});
    var value = const TextEditingValue(
      text: '$firstAndSecond~**丙**~',
      selection: TextSelection.collapsed(offset: 22),
    );

    value = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '$firstAndSecond~**丙**',
        selection: TextSelection.collapsed(offset: 21),
      ),
    );
    expect(value.text, firstAndSecond);
    expect(value.selection, const TextSelection.collapsed(offset: 12));

    value = formatter.formatEditUpdate(
      value,
      const TextEditingValue(
        text: '$first*~~*',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );
    expect(value.text, first);
    expect(value.selection, const TextSelection.collapsed(offset: 5));
  });

  test('光标位于视觉末尾时退格直接删除正文而不是隐藏标签', () {
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{});
    final partial = formatter.formatEditUpdate(
      const TextEditingValue(
        text: '**第一段**',
        selection: TextSelection.collapsed(offset: 7),
      ),
      const TextEditingValue(
        text: '**第一段*',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    expect(partial.text, '**第一**');
    expect(partial.selection, const TextSelection.collapsed(offset: 4));

    final emptied = formatter.formatEditUpdate(
      const TextEditingValue(
        text: '**一**',
        selection: TextSelection.collapsed(offset: 5),
      ),
      const TextEditingValue(
        text: '**一*',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    expect(emptied.text, isEmpty);
  });

  test('输入法批量删除正文和闭合标签时保留完整格式', () {
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{});
    final result = formatter.formatEditUpdate(
      const TextEditingValue(
        text: '普通文字 **粗体文字** **~~粗体+删除线文字~~**',
        selection: TextSelection.collapsed(offset: 30),
      ),
      const TextEditingValue(
        text: '普通文字 **粗体文字** **~~粗体+删除线文',
        selection: TextSelection.collapsed(offset: 25),
      ),
    );
    expect(result.text, '普通文字 **粗体文字** **~~粗体+删除线文~~**');
  });

  test('切换格式组合会结束上一段并让下次输入使用完整新组合', () {
    final activeMarkers = <String>{'**'};
    final formatter = activeMarkdownFormatInputFormatter(() => activeMarkers);
    final bold = formatter.formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(
        text: '粗体',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    final nextRun = exitActiveMarkdownFormats(bold, activeMarkers);
    activeMarkers.add('*');

    final combined = formatter.formatEditUpdate(
      nextRun,
      TextEditingValue(
        text: '${nextRun.text}叠加',
        selection: TextSelection.collapsed(offset: nextRun.text.length + 2),
      ),
    );
    expect(combined.text, '**粗体*****叠加***');
  });

  test('中文输入法提交候选文字后再写入 Markdown 标记', () {
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{'**'});
    const composing = TextEditingValue(
      text: '中文',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    expect(
      formatter.formatEditUpdate(const TextEditingValue(), composing),
      composing,
    );

    final committed = formatter.formatEditUpdate(
      composing,
      const TextEditingValue(
        text: '中文',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(committed.text, '**中文**');
  });
}
