import 'dart:convert';
import 'dart:io';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/message_input/message_input.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/rich_content_editor_sheet.dart';
import 'package:tencent_chat_uikit/src/message_input/utils/image_size_reader.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart'
    show SemanticColorScheme;
import 'package:tuikit_atomic_x/album_picker/album_picker.dart';

void main() {
  testWidgets('编辑器展开后普通输入行保留但隐藏', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.create(
          const AppNormalColorScheme(),
          Brightness.light,
        ),
        home: const Scaffold(
          body: MessageInput(conversationID: 'c2c_rich_content_test'),
        ),
      ),
    );
    await tester.pump();

    const normalInputRowKey = Key('message_input_normal_input_row');
    const normalInputOffstageKey = Key('message_input_normal_input_offstage');
    final normalInputRow = tester.element(find.byKey(normalInputRowKey));
    expect(tester.widget<Offstage>(find.byKey(normalInputOffstageKey)).offstage,
        isFalse);
    await tester.tap(find.byKey(const Key('open_rich_content_editor')));
    await tester.pump();
    expect(find.byKey(normalInputRowKey), findsNothing);
    expect(find.byKey(normalInputRowKey, skipOffstage: false), findsOneWidget);
    expect(
      tester.element(find.byKey(normalInputRowKey, skipOffstage: false)),
      same(normalInputRow),
    );
    expect(
      tester
          .widget<Offstage>(
            find.byKey(normalInputOffstageKey, skipOffstage: false),
          )
          .offstage,
      isTrue,
    );
  });

  testWidgets('普通输入框保持单行高度并按换行增长到五行', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.create(
          const AppNormalColorScheme(),
          Brightness.light,
        ),
        home: const Scaffold(
          body: MessageInput(
            conversationID: 'c2c_dynamic_input_height_test',
          ),
        ),
      ),
    );
    await tester.tap(find.text('发送给 c2c_dynamic_input_height_test'));
    await tester.pump();

    const inputRow = Key('message_input_normal_input_row');
    final input = tester.widget<ExtendedTextField>(
      find.byKey(const Key('message_input_text_field')),
    );
    expect(tester.getSize(find.byKey(inputRow)).height, 36);

    input.controller!.text = '1\n2\n3';
    await tester.pump();
    final threeLineHeight = tester.getSize(find.byKey(inputRow)).height;
    expect(threeLineHeight, greaterThan(36));

    input.controller!.text = '1\n2\n3\n4\n5';
    await tester.pump();
    final fiveLineHeight = tester.getSize(find.byKey(inputRow)).height;
    expect(fiveLineHeight, greaterThan(threeLineHeight));

    input.controller!.text = '1\n2\n3\n4\n5\n6\n7';
    await tester.pump();
    expect(tester.getSize(find.byKey(inputRow)).height, fiveLineHeight);
  });

  testWidgets('收起编辑器后普通输入框保留富文本图片', (tester) async {
    late Directory directory;
    late File image;
    late int imageLength;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('inline_rich_image_');
      image = File('${directory.path}/selected.png');
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      imageLength = bytes.length;
      await image.writeAsBytes(bytes);
    });
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.create(
          const AppNormalColorScheme(),
          Brightness.light,
        ),
        home: const Scaffold(
          body: Column(
            children: [
              Spacer(),
              SizedBox(
                height: 220,
                child: MessageInput(
                  conversationID: 'c2c_inline_rich_image_test',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_rich_content_editor')));
    await tester.pump();
    await tester.pumpAndSettle();
    final editor = tester.state<RichContentEditorSheetState>(
      find.byType(RichContentEditorSheet),
    );
    final editorInput = tester.widget<ExtendedTextField>(
      find.byKey(const Key('rich_content_text_1')),
    );
    editorInput.controller!.value = const TextEditingValue(
      text: '前后',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(
      await editor.insertProcessedImage(
        AlbumMedia(
          id: 8,
          mediaType: AlbumMediaType.image,
          mediaPath: image.path,
          fileExtension: 'png',
          fileSize: imageLength,
        ),
        readSize: (_) async => const ImageSize(100, 200),
      ),
      isTrue,
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_fullscreen));
    await tester.pumpAndSettle();

    const token = '\uFFF92\uFFFA';
    final normalInput = tester.widget<ExtendedTextField>(
      find.byType(ExtendedTextField),
    );
    expect(normalInput.controller!.text, '前\n$token后');
    expect(
        find.byKey(const Key('rich_content_inline_image_2')), findsOneWidget);
    final inputField = find.byKey(const Key('message_input_text_field'));
    final expandButton = find.byKey(const Key('open_rich_content_editor'));
    final inputScrollable = tester.state<ScrollableState>(
      find.descendant(
        of: inputField,
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.descendant(
        of: inputField,
        matching: expandButton,
      ),
      findsNothing,
    );
    expect(
      tester.getCenter(expandButton).dy,
      closeTo(tester.getCenter(inputField).dy, 0.1),
    );
    final buttonCenter = tester.getCenter(expandButton);
    expect(inputScrollable.position.maxScrollExtent, greaterThan(0));
    inputScrollable.position.jumpTo(0);
    await tester.drag(inputField, const Offset(0, -60));
    await tester.pump();
    expect(inputScrollable.position.pixels, greaterThan(0));
    expect(tester.getCenter(expandButton), buttonCenter);

    await tester.tap(find.byKey(const Key('open_rich_content_editor')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('rich_content_inline_image_2')), findsOneWidget);
  });

  testWidgets('覆盖层按普通输入框、编辑器、共享工具条的顺序绘制', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RichContentEditorOverlayLayout(
          editorBottom: 600,
          toolbarRect: Rect.fromLTWH(10, 600, 380, 38),
          editor: ColoredBox(
            key: Key('test_editor'),
            color: Colors.white,
          ),
          toolbar: ColoredBox(
            key: Key('test_toolbar'),
            color: Colors.blue,
          ),
        ),
      ),
    );

    final stack = tester.widget<Stack>(
      find.descendant(
        of: find.byType(RichContentEditorOverlayLayout),
        matching: find.byType(Stack),
      ),
    );
    expect(stack.children.first.key, const Key('rich_content_editor_layer'));
    expect(stack.children.last.key, const Key('rich_content_toolbar_layer'));
    expect(
      tester.getSize(find.byKey(const Key('rich_content_editor_layer'))).height,
      600,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: RichContentEditorOverlayLayout(
          editorBottom: 520,
          toolbarRect: Rect.fromLTWH(10, 520, 380, 44),
          editor: ColoredBox(color: Colors.white),
          toolbar: ColoredBox(color: Colors.blue),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('rich_content_editor_layer'))).height,
      520,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('rich_content_toolbar_layer'))).dy,
      520,
    );
  });

  testWidgets('编辑器打开后默认聚焦正文', (tester) async {
    await tester.pumpWidget(
      _testApp(const RichContentDraft(), onSend: (_) async => false),
    );
    await tester.pump();

    final input = tester.widget<ExtendedTextField>(
      find.byKey(const Key('rich_content_text_1')),
    );
    expect(input.focusNode!.hasFocus, isTrue);
    expect(find.byType(RichContentInputToolbar), findsOneWidget);
  });

  testWidgets('外部工具条模式不在编辑器内重复构建工具条', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const RichContentDraft(),
        onSend: (_) async => false,
        showToolbar: false,
      ),
    );
    await tester.pump();

    expect(find.byType(RichContentInputToolbar), findsNothing);
    final input = tester.widget<ExtendedTextField>(
      find.byKey(const Key('rich_content_text_1')),
    );
    expect(input.focusNode!.hasFocus, isTrue);
  });

  testWidgets('外部工具条模式下编辑器输入区域不显示边框', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const RichContentDraft(),
        onSend: (_) async => false,
        showToolbar: false,
      ),
    );

    expect(find.byType(Divider), findsNothing);
    final title = tester.widget<TextField>(
      find.byKey(const Key('rich_content_title')),
    );
    final body = tester.widget<ExtendedTextField>(
      find.byKey(const Key('rich_content_text_1')),
    );
    expect(title.decoration?.focusedBorder, InputBorder.none);
    expect(body.decoration?.focusedBorder, InputBorder.none);
    expect(
      tester
          .widget<ListView>(find.byKey(const Key('rich_content_body')))
          .padding,
      const EdgeInsets.fromLTRB(16, 12, 16, 20),
    );
  });

  testWidgets('外部工具条模式沿用切换前的 Markdown 状态', (tester) async {
    final editorKey = GlobalKey<RichContentEditorSheetState>();
    await tester.pumpWidget(
      _testApp(
        const RichContentDraft(),
        onSend: (_) async => false,
        showToolbar: false,
        editorKey: editorKey,
        initialShowFormatting: true,
        initialActiveFormats: const {'**', '*'},
      ),
    );

    expect(editorKey.currentState!.showFormatting, isTrue);
    expect(editorKey.currentState!.activeFormats, {'**', '*'});
  });

  testWidgets('外部工具条模式下面板上升且遮罩同步渐入', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const RichContentDraft(),
        onSend: (_) async => false,
        showToolbar: false,
      ),
    );

    FractionalTranslation transition() => tester.widget<FractionalTranslation>(
          find.descendant(
            of: find.byKey(const Key('rich_content_editor_entrance')),
            matching: find.byType(FractionalTranslation),
          ),
        );
    Opacity backdrop() => tester.widget<Opacity>(
          find.byKey(const Key('rich_content_editor_backdrop_opacity')),
        );
    final panelPosition = tester.widget<Positioned>(
      find.byKey(const Key('rich_content_editor_panel_position')),
    );
    final backdropPosition = tester.widget<Positioned>(
      find.byKey(const Key('rich_content_editor_backdrop')),
    );

    expect(panelPosition.top, 57);
    expect(panelPosition.bottom, 0);
    expect(backdropPosition.top, 0);
    expect(backdropPosition.bottom, 0);
    expect(transition().translation.dy, 1);
    expect(backdrop().opacity, 0);
    await tester.pump(const Duration(milliseconds: 90));
    expect(transition().translation.dy, inExclusiveRange(0, 1));
    expect(backdrop().opacity, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(transition().translation.dy, 0);
    expect(backdrop().opacity, 1);
  });

  testWidgets('编辑器展示空态并可切换格式栏', (tester) async {
    await tester.pumpWidget(
      _testApp(const RichContentDraft(), onSend: (_) async => false),
    );

    expect(find.text('无标题'), findsOneWidget);
    expect(find.text('发送给 杨洋阳 (一只羊)'), findsOneWidget);
    await tester.tap(find.byTooltip('文字格式'));
    await tester.pump();
    expect(find.byTooltip('粗体'), findsOneWidget);
    final toolbarTransitions = find.descendant(
      of: find.byKey(const Key('rich_content_toolbar_switcher')),
      matching: find.byType(SlideTransition),
    );
    expect(toolbarTransitions, findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(toolbarTransitions, findsOneWidget);

    await tester.tap(find.byTooltip('关闭文字格式'));
    await tester.pump();
    expect(toolbarTransitions, findsNWidgets(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('文字格式'));
    await tester.pumpAndSettle();

    await _enterExtendedText(
      tester,
      find.byKey(const Key('rich_content_text_1')),
      '正文',
    );
    await tester.pump();
    final sendButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('发送富文本消息'),
        matching: find.byType(IconButton),
      ),
    );
    expect(sendButton.onPressed, isNotNull);
  });

  testWidgets('存在未上传附件时发送按钮保持禁用', (tester) async {
    const attachment = RichContentLocalAttachment(
      type: RichContentAttachmentType.file,
      localPath: '/tmp/test.pdf',
      fileName: 'test.pdf',
      fileSize: 12,
      mimeType: 'application/pdf',
    );
    await tester.pumpWidget(
      _testApp(
        const RichContentDraft(
          blocks: [
            RichContentDraftTextBlock(1, '正文'),
            RichContentDraftAttachmentBlock(2, attachment: attachment),
          ],
        ),
        onSend: (_) async => true,
      ),
    );

    expect(find.text('等待上传'), findsOneWidget);
    final sendButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('发送富文本消息'),
        matching: find.byType(IconButton),
      ),
    );
    expect(sendButton.onPressed, isNull);
  });

  testWidgets('图片单行排版且尺寸不随编辑器高度变化', (tester) async {
    tester.view.physicalSize = const Size(390, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Directory directory;
    late File image;
    late int imageLength;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('rich_image_test_');
      image = File('${directory.path}/selected.png');
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      imageLength = bytes.length;
      await image.writeAsBytes(bytes);
    });
    addTearDown(() => directory.deleteSync(recursive: true));
    final editorKey = GlobalKey<RichContentEditorSheetState>();
    await tester.pumpWidget(
      _testApp(
        const RichContentDraft(
          blocks: [RichContentDraftTextBlock(1, '前后')],
        ),
        onSend: (_) async => false,
        editorKey: editorKey,
      ),
    );
    final firstInput = tester.widget<ExtendedTextField>(
      find.byKey(const Key('rich_content_text_1')),
    );
    firstInput.controller!.selection = const TextSelection.collapsed(offset: 1);
    final media = AlbumMedia(
      id: 7,
      mediaType: AlbumMediaType.image,
      mediaPath: image.path,
      fileExtension: 'png',
      fileSize: imageLength,
    );

    expect(
      await editorKey.currentState!.insertProcessedImage(
        media,
        readSize: (_) async => const ImageSize(100, 250),
      ),
      isTrue,
    );
    await tester.pump();
    final imageFinder = find.byKey(const Key('rich_content_inline_image_2'));
    expect(imageFinder, findsOneWidget);
    expect(find.byType(ExtendedTextField), findsOneWidget);
    final bodyWidth =
        tester.getSize(find.byKey(const Key('rich_content_body'))).width;
    expect(tester.getSize(imageFinder).width, lessThanOrEqualTo(bodyWidth / 2));
    final initialImageSize = tester.getSize(imageFinder);
    tester.view.physicalSize = const Size(390, 800);
    await tester.pump();
    expect(tester.getSize(imageFinder), initialImageSize);

    final field = find.byKey(const Key('rich_content_text_1'));
    final input = tester.widget<ExtendedTextField>(field);
    const token = '\uFFF92\uFFFA';
    expect(input.controller!.text, '前\n$token后');
    final rendered = input.specialTextSpanBuilder!.build(
      input.controller!.text,
      textStyle: input.style,
    );
    expect(
      _flattenInlineSpans(rendered).whereType<WidgetSpan>().single.alignment,
      PlaceholderAlignment.bottom,
    );
    await tester.pumpAndSettle();
    final imageRect = tester.getRect(imageFinder);
    final bodyRect = tester.getRect(find.byKey(const Key('rich_content_body')));
    final bodyScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('rich_content_body')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(bodyScrollable.position.pixels, 0);
    final fieldRect = tester.getRect(field);
    expect(imageRect.top, greaterThanOrEqualTo(fieldRect.top));
    await tester.tapAt(Offset(imageRect.right + 4, imageRect.center.dy));
    await tester.pump();
    expect(input.focusNode!.hasFocus, isTrue);
    expect(input.controller!.selection.extentOffset, greaterThan(token.length));
    final insertionOffset = input.controller!.selection.extentOffset;
    input.controller!.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    expect(
      tester.widget<ExtendedTextField>(field).cursorHeight,
      closeTo(imageRect.height, 0.01),
    );
    final renderEditable =
        tester.allRenderObjects.whereType<ExtendedRenderEditable>().single;
    Rect globalCaretRect() {
      final localRect = renderEditable.getLocalRectForCaret(
        renderEditable.getActualSelection()!.extent,
      );
      return localRect.shift(renderEditable.localToGlobal(Offset.zero));
    }

    expect(
      globalCaretRect().center.dy,
      closeTo(imageRect.center.dy, 1),
    );
    input.controller!.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();
    expect(globalCaretRect().center.dy, closeTo(imageRect.center.dy, 1));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '前\n$token后\n',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.pump();
    expect(tester.widget<ExtendedTextField>(field).cursorHeight, isNull);
    expect(renderEditable.getActualSelection()!.extentOffset, 5);
    expect(globalCaretRect().top, greaterThanOrEqualTo(imageRect.bottom));
    expect(
      globalCaretRect().top - imageRect.bottom,
      lessThan(renderEditable.preferredLineHeight),
    );
    expect(
      globalCaretRect().height,
      closeTo(renderEditable.preferredLineHeight, 0.01),
    );
    final wrappedText = '前\n$token${List.filled(80, '换').join()}';
    input.controller!.value = TextEditingValue(
      text: wrappedText,
      selection: TextSelection.collapsed(offset: wrappedText.length),
    );
    await tester.pump();
    expect(
        globalCaretRect().top, greaterThan(tester.getRect(imageFinder).bottom));
    expect(globalCaretRect().height,
        closeTo(renderEditable.preferredLineHeight, 0.01));
    input.controller!.value = const TextEditingValue(
      text: '前\n$token后\n尾',
      selection: TextSelection.collapsed(offset: 7),
    );
    await tester.pump();
    expect(tester.widget<ExtendedTextField>(field).cursorHeight, isNull);
    expect(
      globalCaretRect().height,
      closeTo(renderEditable.preferredLineHeight, 0.01),
    );
    input.controller!.value = const TextEditingValue(
      text: '前\n$token后',
      selection: TextSelection.collapsed(offset: 5),
    );
    await tester.pump();
    expect(globalCaretRect().center.dy, closeTo(imageRect.center.dy, 1));
    input.controller!.selection = TextSelection.collapsed(
      offset: insertionOffset,
    );
    await tester.pump();
    final current = input.controller!.value;
    tester.testTextInput.updateEditingValue(
      current.copyWith(
        text: current.text.replaceRange(insertionOffset, insertionOffset, '新增'),
        selection: TextSelection.collapsed(offset: insertionOffset + 2),
        composing: TextRange.empty,
      ),
    );
    await tester.pump();
    expect(input.controller!.text, '前\n$token新增后');

    final longText = List.filled(30, '滚动正文').join('\n');
    input.controller!.value = TextEditingValue(
      text: '$longText\n$token\n$longText',
      selection: const TextSelection.collapsed(offset: 0),
    );
    await tester.pump();
    expect(bodyScrollable.position.maxScrollExtent, greaterThan(0));
    await tester.dragFrom(bodyRect.center, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(bodyScrollable.position.pixels, greaterThan(0));

    input.controller!.value = const TextEditingValue(
      text: '前\n$token后',
      selection: TextSelection.collapsed(offset: 5),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '前\n\uFFF92后',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump();
    expect(imageFinder, findsNothing);
    expect(find.byType(ExtendedTextField), findsOneWidget);
    expect(input.controller!.text, '前\n后');

    expect(await editorKey.currentState!.insertProcessedImage(media), isFalse);
  });

  testWidgets('持久化图片草稿通过本地路径恢复渲染', (tester) async {
    late Directory directory;
    late File image;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('draft_image_test_');
      image = File('${directory.path}/draft.png');
      await image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    });
    addTearDown(() => directory.deleteSync(recursive: true));
    final stored = RichContentDraft(
      blocks: [
        const RichContentDraftTextBlock(1, '正文\n'),
        RichContentDraftAttachmentBlock(
          2,
          attachment: RichContentLocalAttachment(
            type: RichContentAttachmentType.image,
            localPath: image.path,
            fileName: 'draft.png',
            fileSize: image.lengthSync(),
            mimeType: 'image/png',
            width: 100,
            height: 100,
          ),
        ),
      ],
    ).toPersistedString();

    await tester.pumpWidget(
      _testApp(
        RichContentDraft.tryParsePersisted(stored)!,
        onSend: (_) async => false,
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const Key('rich_content_inline_image_2')), findsOneWidget);
    final input = tester.widget<ExtendedTextField>(
      find.byKey(const Key('rich_content_text_1')),
    );
    expect(input.controller!.text, '正文\n\uFFF92\uFFFA');
  });

  testWidgets('格式按钮切换选中态并在输入时应用 Markdown', (tester) async {
    await tester.pumpWidget(
      _testApp(const RichContentDraft(), onSend: (_) async => false),
    );

    await tester.tap(find.byTooltip('文字格式'));
    await tester.pumpAndSettle();
    await _enterExtendedText(
      tester,
      find.byKey(const Key('rich_content_text_1')),
      '已有文字',
    );
    final input = tester.widget<ExtendedTextField>(
      find.byKey(const Key('rich_content_text_1')),
    );
    input.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    await tester.tap(find.byTooltip('粗体'));
    await tester.tap(find.byTooltip('斜体'));
    await tester.pump();

    final boldButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('粗体'),
        matching: find.byType(IconButton),
      ),
    );
    final italicButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('斜体'),
        matching: find.byType(IconButton),
      ),
    );
    expect(boldButton.isSelected, isTrue);
    expect(italicButton.isSelected, isTrue);
    expect(input.controller!.text, '已有文字');
    expect(
      input.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );

    await _enterExtendedText(
      tester,
      find.byKey(const Key('rich_content_text_1')),
      '正文',
    );
    await tester.pump();
    expect(input.controller!.text, '***正文***');
  });

  test('格式选中态换行时结束当前段并在下一次输入恢复格式', () {
    final formatter = activeMarkdownFormatInputFormatter(
      () => <String>{'**', '*'},
    );
    const formatted = TextEditingValue(
      text: '***正文***',
      selection: TextSelection.collapsed(offset: 5),
    );
    final newline = formatter.formatEditUpdate(
      formatted,
      const TextEditingValue(
        text: '***正文\n***',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    expect(newline.text, '***正文***\n');
    expect(newline.selection, const TextSelection.collapsed(offset: 9));

    final continued = formatter.formatEditUpdate(
      newline,
      const TextEditingValue(
        text: '***正文***\n下一行',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    expect(continued.text, '***正文***\n***下一行***');
  });

  testWidgets('Markdown 在输入框中渲染样式并保留原文', (tester) async {
    late TextSpan rendered;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.create(
          const AppNormalColorScheme(),
          Brightness.light,
        ),
        home: Builder(
          builder: (context) {
            rendered = ChatSpecialTextSpanBuilder(
              onTapUrl: (_) {},
              colorScheme: SemanticColorScheme.of(context),
            ).build(
              '**粗体** ~~删除~~ *斜体* ~下划线~ [链接](https://example.com) ```code```',
              textStyle: const TextStyle(fontSize: 16),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      rendered.toPlainText(),
      '**粗体** ~~删除~~ *斜体* ~下划线~ [链接](https://example.com) ```code```',
    );
    final spans = _flattenTextSpans(rendered).toList();
    expect(
      spans.singleWhere((span) => span.text == '粗体').style?.fontWeight,
      FontWeight.bold,
    );
    expect(
      spans.singleWhere((span) => span.text == '删除').style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(
      spans.singleWhere((span) => span.text == '斜体').style?.fontStyle,
      FontStyle.italic,
    );
    expect(
      spans.singleWhere((span) => span.text == '下划线').style?.decoration,
      TextDecoration.underline,
    );
    expect(
      spans.singleWhere((span) => span.text == 'code').style?.fontFamily,
      'monospace',
    );
  });

  testWidgets('普通文字沿用 ExtendedTextField 原始 span 结构', (tester) async {
    late TextSpan rendered;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.create(
          const AppNormalColorScheme(),
          Brightness.light,
        ),
        home: Builder(
          builder: (context) {
            rendered = ChatSpecialTextSpanBuilder(
              onTapUrl: (_) {},
              colorScheme: SemanticColorScheme.of(context),
              mapMarkdownMarkers: true,
            ).build('普通文字');
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(rendered.toPlainText(), '普通文字');
    expect(
        _flattenTextSpans(rendered).map((span) => span.text), contains('普通文字'));
  });

  testWidgets('Markdown 在输入框中叠加渲染多选格式', (tester) async {
    late TextSpan rendered;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.create(
          const AppNormalColorScheme(),
          Brightness.light,
        ),
        home: Builder(
          builder: (context) {
            rendered = ChatSpecialTextSpanBuilder(
              onTapUrl: (_) {},
              colorScheme: SemanticColorScheme.of(context),
            ).build(
              '**~~*~组合格式~*~~**',
              textStyle: const TextStyle(fontSize: 16),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(rendered.toPlainText(), '**~~*~组合格式~*~~**');
    final style = _flattenTextSpans(
      rendered,
    ).singleWhere((span) => span.text == '组合格式').style!;
    expect(style.fontWeight, FontWeight.bold);
    expect(style.fontStyle, FontStyle.italic);
    expect(style.decoration!.contains(TextDecoration.lineThrough), isTrue);
    expect(style.decoration!.contains(TextDecoration.underline), isTrue);
  });

  testWidgets('Markdown 多层标签按任意顺序嵌套均能识别', (tester) async {
    late ChatSpecialTextSpanBuilder spanBuilder;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.create(
          const AppNormalColorScheme(),
          Brightness.light,
        ),
        home: Builder(
          builder: (context) {
            spanBuilder = ChatSpecialTextSpanBuilder(
              onTapUrl: (_) {},
              colorScheme: SemanticColorScheme.of(context),
              mapMarkdownMarkers: true,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    for (final markers in _permutations(['**', '~~', '*', '~'])) {
      final source = '${markers.join()}任意顺序${markers.reversed.join()}';
      final rendered = spanBuilder.build(source);
      expect(rendered.toPlainText(), '任意顺序', reason: source);
      final style = _flattenTextSpans(
        rendered,
      ).singleWhere((span) => span.text == '任意顺序').style!;
      expect(style.fontWeight, FontWeight.bold, reason: source);
      expect(style.fontStyle, FontStyle.italic, reason: source);
      expect(
        style.decoration!.contains(TextDecoration.lineThrough),
        isTrue,
        reason: source,
      );
      expect(
        style.decoration!.contains(TextDecoration.underline),
        isTrue,
        reason: source,
      );
    }
  });

  testWidgets('连续退格跨格式段时直接删除可见正文', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const RichContentDraft(
          blocks: [RichContentDraftTextBlock(1, '**甲****乙**')],
        ),
        onSend: (_) async => false,
      ),
    );
    final field = find.byKey(const Key('rich_content_text_1'));
    await tester.tap(field);
    await tester.pump();
    final controller = tester.widget<ExtendedTextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 10);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '**甲****乙*',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    await tester.pump();
    expect(controller.text, '**甲**');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '**甲*',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump();
    expect(controller.text, isEmpty);
  });

  testWidgets('四段混合内容从末尾删除时不显示 Markdown 标签', (tester) async {
    const source = '普通文字 **粗体文字** **~~粗体+删除线文字~~** 普通文字';
    await tester.pumpWidget(
      _testApp(
        const RichContentDraft(blocks: [RichContentDraftTextBlock(1, source)]),
        onSend: (_) async => false,
      ),
    );
    final field = find.byKey(const Key('rich_content_text_1'));
    await tester.tap(field);
    await tester.pump();
    final controller = tester.widget<ExtendedTextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: source.length);

    for (var remaining = ' 普通文字'.length; remaining > 0; remaining--) {
      final current = controller.value;
      tester.testTextInput.updateEditingValue(
        current.copyWith(
          text: current.text.substring(0, current.text.length - 1),
          selection: TextSelection.collapsed(offset: current.text.length - 1),
          composing: TextRange.empty,
        ),
      );
      await tester.pump();
    }
    expect(controller.text, '普通文字 **粗体文字** **~~粗体+删除线文字~~**');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '普通文字 **粗体文字** **~~粗体+删除线文',
        selection: TextSelection.collapsed(offset: 25),
      ),
    );
    await tester.pump();
    expect(controller.text, '普通文字 **粗体文字** **~~粗体+删除线文~~**');
  });

  testWidgets('普通输入框使用原文映射隐藏叠加格式标签', (tester) async {
    const source = '普通文字 **粗体文字** **~~粗体+删除线文字~~** 普通文字';
    final controller = TextEditingController(text: source);
    addTearDown(controller.dispose);
    final formatter = activeMarkdownFormatInputFormatter(() => <String>{});
    late TextSpan mappedText;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.create(
          const AppNormalColorScheme(),
          Brightness.light,
        ),
        home: Builder(
          builder: (context) {
            final spanBuilder = ChatSpecialTextSpanBuilder(
              onTapUrl: (_) {},
              colorScheme: SemanticColorScheme.of(context),
              mapMarkdownMarkers: true,
            );
            mappedText = spanBuilder.build(source);
            return Scaffold(
              body: ExtendedTextField(
                key: const Key('mapped_markdown_input'),
                controller: controller,
                inputFormatters: [formatter],
                specialTextSpanBuilder: spanBuilder,
              ),
            );
          },
        ),
      ),
    );
    final field = find.byKey(const Key('mapped_markdown_input'));
    await tester.tap(field);
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: source.length);

    for (var remaining = ' 普通文字'.length; remaining > 0; remaining--) {
      final current = controller.value;
      tester.testTextInput.updateEditingValue(
        current.copyWith(
          text: current.text.substring(0, current.text.length - 1),
          selection: TextSelection.collapsed(offset: current.text.length - 1),
          composing: TextRange.empty,
        ),
      );
      await tester.pump();
    }
    final current = controller.value;
    tester.testTextInput.updateEditingValue(
      current.copyWith(
        text: current.text.substring(0, current.text.length - 1),
        selection: TextSelection.collapsed(offset: current.text.length - 1),
        composing: TextRange.empty,
      ),
    );
    await tester.pump();

    expect(controller.text, '普通文字 **粗体文字** **~~粗体+删除线文~~**');
    expect(mappedText.toPlainText(), '普通文字 粗体文字 粗体+删除线文字 普通文字');
  });

  testWidgets('展开编辑器使用原文映射保持多层格式光标稳定', (tester) async {
    const source = '~**~~*四层格式*~~**~';
    await tester.pumpWidget(
      _testApp(
        const RichContentDraft(
          blocks: [RichContentDraftTextBlock(1, source)],
        ),
        onSend: (_) async => false,
      ),
    );

    final field = find.byKey(const Key('rich_content_text_1'));
    final input = tester.widget<ExtendedTextField>(field);
    final rendered = input.specialTextSpanBuilder!.build(source);
    expect(rendered.toPlainText(), '四层格式');

    await tester.tap(field);
    await tester.pump();
    input.controller!.selection = const TextSelection.collapsed(offset: 9);
    await tester.pump();
    expect(input.controller!.selection.extentOffset, 9);
  });
}

Iterable<List<String>> _permutations(List<String> values) sync* {
  if (values.isEmpty) {
    yield const [];
    return;
  }
  for (var index = 0; index < values.length; index++) {
    final remaining = [...values]..removeAt(index);
    for (final suffix in _permutations(remaining)) {
      yield [values[index], ...suffix];
    }
  }
}

Future<void> _enterExtendedText(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  await tester.tap(field);
  await tester.pump();
  tester.testTextInput.enterText(text);
  await tester.pump();
}

Iterable<TextSpan> _flattenTextSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _flattenTextSpans(child);
  }
}

Iterable<InlineSpan> _flattenInlineSpans(InlineSpan span) sync* {
  yield span;
  if (span is! TextSpan) return;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _flattenInlineSpans(child);
  }
}

Widget _testApp(
  RichContentDraft draft, {
  required Future<bool> Function(RichContentDraft) onSend,
  bool showToolbar = true,
  GlobalKey<RichContentEditorSheetState>? editorKey,
  bool initialShowFormatting = false,
  Set<String> initialActiveFormats = const {},
}) {
  return MaterialApp(
    theme: AppThemeFactory.create(
      const AppNormalColorScheme(),
      Brightness.light,
    ),
    home: Scaffold(
      body: RichContentEditorSheet(
        key: editorKey,
        conversationName: '杨洋阳 (一只羊)',
        initialDraft: draft,
        onSend: onSend,
        showToolbar: showToolbar,
        initialShowFormatting: initialShowFormatting,
        initialActiveFormats: initialActiveFormats,
      ),
    ),
  );
}
