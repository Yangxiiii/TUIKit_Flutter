import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/navigation/chat_uikit_navigation.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';

import 'search_page.dart';

typedef OnContactSelect = void Function(FriendSearchInfo friendSearchInfo);
typedef OnGroupSelect = void Function(GroupSearchInfo groupSearchInfo);
typedef OnConversationSelect = void Function(
    MessageSearchResultItem messageSearchResultItem);
typedef OnMessageSelect = void Function(MessageInfo messageInfo);

class SearchBar extends StatelessWidget {
  final OnContactSelect? onContactSelect;
  final OnGroupSelect? onGroupSelect;
  final OnConversationSelect? onConversationSelect;
  final OnMessageSelect? onMessageSelect;

  const SearchBar({
    super.key,
    this.onContactSelect,
    this.onGroupSelect,
    this.onConversationSelect,
    this.onMessageSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);
    final atomicLocale = AppLocalization.of(context);
    return Container(
      color: colorsTheme.bgColorOperate,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          context.pushChatUIKitPage(
            SearchPage(
              onContactSelect: onContactSelect,
              onGroupSelect: onGroupSelect,
              onConversationSelect: onConversationSelect,
              onMessageSelect: onMessageSelect,
            ),
          );
        },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: colorsTheme.bgColorInput,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(
                Icons.search,
                color: colorsTheme.textColorSecondary,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                atomicLocale.search,
                style: TextStyle(
                  fontSize: 16,
                  color: colorsTheme.textColorSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
