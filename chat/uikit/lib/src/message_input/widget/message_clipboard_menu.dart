import 'package:flutter/material.dart';

import '../../third_party/extended_text_field/extended_text_field.dart';

/// 保留平台风格的选区菜单，仅把显式点击粘贴交给聊天输入区处理。
Widget buildMessageClipboardMenu(
  BuildContext context,
  ExtendedEditableTextState editor,
  VoidCallback onPaste,
) {
  final items = [
    for (final item in editor.contextMenuButtonItems)
      if (item.type == ContextMenuButtonType.paste)
        ContextMenuButtonItem(type: item.type, onPressed: onPaste)
      else
        item,
  ];
  final buttons =
      AdaptiveTextSelectionToolbar.getAdaptiveButtons(context, items).toList();
  return AdaptiveTextSelectionToolbar(
    anchors: editor.contextMenuAnchors,
    children: [
      for (var i = 0; i < buttons.length; i++)
        if (items[i].type == ContextMenuButtonType.paste)
          // 浮层位于输入框外，粘贴点击属于同一输入区，不能先丢失焦点。
          TextFieldTapRegion(
            groupId: editor.widget.groupId,
            child: Semantics(
              container: true,
              identifier: 'tim.input.clipboard.paste',
              child: buttons[i],
            ),
          )
        else
          buttons[i],
    ],
  );
}
