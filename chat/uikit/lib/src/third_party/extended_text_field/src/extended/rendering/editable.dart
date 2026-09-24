part of 'package:tencent_chat_uikit/src/third_party/extended_text_field/src/extended/widgets/text_field.dart';

/// [RenderEditable]
class ExtendedRenderEditable extends _RenderEditable {
  ExtendedRenderEditable({
    super.text,
    required super.textDirection,
    super.textAlign = TextAlign.start,
    super.cursorColor,
    super.backgroundCursorColor,
    super.showCursor,
    super.hasFocus,
    required super.startHandleLayerLink,
    required super.endHandleLayerLink,
    super.maxLines = 1,
    super.minLines,
    super.expands = false,
    super.strutStyle,
    super.selectionColor,
    super.textScaler = TextScaler.noScaling,
    super.selection,
    required super.offset,
    super.ignorePointer = false,
    super.readOnly = false,
    super.forceLine = true,
    super.textHeightBehavior,
    super.textWidthBasis = TextWidthBasis.parent,
    super.obscuringCharacter = '•',
    super.obscureText = false,
    super.locale,
    super.cursorWidth = 1.0,
    super.cursorHeight,
    super.cursorRadius,
    super.paintCursorAboveText = false,
    super.cursorOffset = Offset.zero,
    super.devicePixelRatio = 1.0,
    super.selectionHeightStyle = ui.BoxHeightStyle.tight,
    super.selectionWidthStyle = ui.BoxWidthStyle.tight,
    super.enableInteractiveSelection,
    super.floatingCursorAddedMargin = const EdgeInsets.fromLTRB(4, 4, 4, 5),
    super.promptRectRange,
    super.promptRectColor,
    super.clipBehavior = Clip.hardEdge,
    required super.textSelectionDelegate,
    super.painter,
    super.foregroundPainter,
    super.children,
    this.supportSpecialText = false,
  }) {
    _findSpecialInlineSpanBase(text);
  }

  bool supportSpecialText = false;
  bool _hasSpecialInlineSpanBase = false;
  bool get hasSpecialInlineSpanBase =>
      supportSpecialText && _hasSpecialInlineSpanBase;

  void _findSpecialInlineSpanBase(InlineSpan? span) {
    _hasSpecialInlineSpanBase = false;
    span?.visitChildren((InlineSpan span) {
      if (span is SpecialInlineSpanBase) {
        _hasSpecialInlineSpanBase = true;
        return false;
      }
      return true;
    });
  }

  @override
  set text(InlineSpan? value) {
    if (_textPainter.text == value) {
      return;
    }
    _findSpecialInlineSpanBase(value);
    super.text = value;
  }

  @override
  String get plainText {
    return ExtendedTextLibraryUtils.textSpanToActualText(_textPainter.text!);
  }

  /// 按实际视觉行校准光标：图片行居中到最高占位元素，其余折行恢复普通文字高度。
  @override
  Rect getLocalRectForCaret(TextPosition caretPosition) {
    final caretRect = super.getLocalRectForCaret(caretPosition);
    final displayedText = text?.toPlainText() ?? '';
    final followsHardBreak = caretPosition.offset > 0 &&
        caretPosition.offset <= displayedText.length &&
        displayedText.codeUnitAt(caretPosition.offset - 1) == 0x0A;
    // 段落引擎会把图片行高重复计入末尾空行，直接从上一视觉行底部开始新行。
    if (followsHardBreak) {
      final previousLine = _textPainter.getLineBoundary(
        TextPosition(
          offset: caretPosition.offset - 1,
          affinity: TextAffinity.upstream,
        ),
      );
      final previousBoxes = super.getBoxesForSelection(
        TextSelection(
          baseOffset: previousLine.start,
          extentOffset: previousLine.end,
        ),
      );
      if (previousBoxes.any(
        (box) => box.bottom - box.top > preferredLineHeight,
      )) {
        final previousBottom =
            previousBoxes.map((box) => box.bottom).reduce(math.max);
        return Rect.fromLTWH(
          caretRect.left,
          previousBottom,
          caretRect.width,
          preferredLineHeight,
        );
      }
    }
    if (cursorHeight <= preferredLineHeight) return caretRect;
    final line = _textPainter.getLineBoundary(caretPosition);
    if (line.isCollapsed) {
      final defaultPrototype = Rect.fromLTWH(
        0,
        _kCaretHeightOffset,
        cursorWidth,
        preferredLineHeight - 2 * _kCaretHeightOffset,
      );
      final offset = _textPainter.getOffsetForCaret(
            caretPosition,
            defaultPrototype,
          ) +
          cursorOffset +
          _paintOffset;
      final rect = Rect.fromLTWH(
        caretRect.left,
        offset.dy - 2 * _kCaretHeightOffset,
        caretRect.width,
        preferredLineHeight,
      );
      return rect.shift(_snapToPhysicalPixel(rect.topLeft));
    }
    final boxes = super.getBoxesForSelection(
      TextSelection(baseOffset: line.start, extentOffset: line.end),
    );
    if (boxes.isEmpty) return caretRect;
    final tallest = boxes.reduce(
      (current, box) =>
          box.bottom - box.top > current.bottom - current.top ? box : current,
    );
    final boxHeight = tallest.bottom - tallest.top;
    final targetHeight =
        boxHeight >= caretRect.height ? caretRect.height : preferredLineHeight;
    return Rect.fromLTWH(
      caretRect.left,
      tallest.top + (boxHeight - targetHeight) / 2,
      caretRect.width,
      targetHeight,
    );
  }

  /// Move the selection to the beginning or end of a word.
  ///
  /// {@macro flutter.rendering.RenderEditable.selectPosition}
  @override
  void selectWordEdge({required SelectionChangedCause cause}) {
    _computeTextMetricsIfNeeded();
    assert(_lastTapDownPosition != null);
    final TextPosition position = _textPainter.getPositionForOffset(
        globalToLocal(_lastTapDownPosition!) - _paintOffset);
    final TextRange word = _textPainter.getWordBoundary(position);
    late TextSelection newSelection;
    if (position.offset <= word.start) {
      newSelection = TextSelection.collapsed(offset: word.start);
    } else {
      newSelection = TextSelection.collapsed(
          offset: word.end, affinity: TextAffinity.upstream);
    }

    /// zmtzawqlp
    newSelection = hasSpecialInlineSpanBase
        ? ExtendedTextLibraryUtils
            .convertTextPainterSelectionToTextInputSelection(
                text!, newSelection)
        : newSelection;
    _setSelection(newSelection, cause);
  }

  @override

  /// Select text between the global positions [from] and [to].
  ///
  /// [from] corresponds to the [TextSelection.baseOffset], and [to] corresponds
  /// to the [TextSelection.extentOffset].
  void selectPositionAt(
      {required Offset from,
      Offset? to,
      required SelectionChangedCause cause}) {
    _computeTextMetricsIfNeeded();
    TextPosition fromPosition =
        _textPainter.getPositionForOffset(globalToLocal(from) - _paintOffset);
    TextPosition? toPosition = to == null
        ? null
        : _textPainter.getPositionForOffset(globalToLocal(to) - _paintOffset);
    // zmtzawqlp
    if (hasSpecialInlineSpanBase) {
      fromPosition =
          ExtendedTextLibraryUtils.convertTextPainterPostionToTextInputPostion(
              text!, fromPosition)!;
      toPosition =
          ExtendedTextLibraryUtils.convertTextPainterPostionToTextInputPostion(
              text!, toPosition);
    }
    final int baseOffset = fromPosition.offset;
    final int extentOffset = toPosition?.offset ?? fromPosition.offset;

    final TextSelection newSelection = TextSelection(
      baseOffset: baseOffset,
      extentOffset: extentOffset,
      affinity: fromPosition.affinity,
    );

    _setSelection(newSelection, cause);
  }

  @override
  TextSelection getWordAtOffset(TextPosition position) {
    final TextSelection selection = super.getWordAtOffset(position);

    /// zmt
    return hasSpecialInlineSpanBase
        ? ExtendedTextLibraryUtils
            .convertTextPainterSelectionToTextInputSelection(text!, selection,
                selectWord: true)
        : selection;
  }

  @override
  List<TextSelectionPoint> getEndpointsForSelection(TextSelection selection) {
    // zmtzawqlp
    if (hasSpecialInlineSpanBase) {
      selection = ExtendedTextLibraryUtils
          .convertTextInputSelectionToTextPainterSelection(text!, selection);
    }

    return super.getEndpointsForSelection(selection);
  }

  @override
  set selection(TextSelection? value) {
    if (_selection == value) {
      return;
    }
    _selection = value;
    _selectionPainter.highlightedRange = getActualSelection();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void setPromptRectRange(TextRange? newRange) {
    _autocorrectHighlightPainter.highlightedRange =
        getActualSelection(newRange: newRange);
  }

  TextSelection? getActualSelection({TextRange? newRange}) {
    TextSelection? value = selection;
    if (newRange != null) {
      value =
          TextSelection(baseOffset: newRange.start, extentOffset: newRange.end);
    }

    return hasSpecialInlineSpanBase
        ? ExtendedTextLibraryUtils
            .convertTextInputSelectionToTextPainterSelection(text!, value!)
        : value;
  }
}
