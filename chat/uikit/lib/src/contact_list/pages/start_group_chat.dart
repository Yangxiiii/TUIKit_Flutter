import 'package:app_ui/app_ui.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/navigation/chat_uikit_navigation.dart';

import '../../user_picker/user_picker.dart';
import 'create_group.dart';

class StartGroupChat extends StatefulWidget {
  final Function(String groupID, String groupName, String? avatar)?
      onGroupCreated;

  const StartGroupChat({
    super.key,
    this.onGroupCreated,
  });

  @override
  State<StartGroupChat> createState() => _StartGroupChatState();
}

class _StartGroupChatState extends State<StartGroupChat> {
  final ContactStore _contactStore = ContactStore.shared;
  late SemanticColorScheme colorsTheme;
  late AppLocalizedText atomicLocale;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorsTheme = SemanticColorScheme.of(context);
    atomicLocale = AppLocalization.of(context);
  }

  Future<void> _loadData() async {
    await _contactStore.loadFriends();
  }

  Future<void> _createGroupChat(List<UserPickerData> selectedItems) async {
    List<ContactInfo> selectedMembers = [];
    for (final item in selectedItems) {
      final contactInfo = _contactStore.state.friendList.value.firstWhere(
        (contact) => contact.userID == item.key,
        orElse: () => ContactInfo(
          userID: item.key,
          nickname: item.label,
          avatarURL: item.avatarURL,
        ),
      );
      selectedMembers.add(contactInfo);
    }

    context.pushChatUIKitPage(
      CreateGroup(
        selectedMembers: selectedMembers,
        onGroupCreated: (groupID, groupName, avatar) {
          context.popChatUIKitPage();
          context.popChatUIKitPage();

          if (widget.onGroupCreated != null) {
            widget.onGroupCreated!(groupID, groupName, avatar);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ContactInfo>>(
      valueListenable: _contactStore.state.friendList,
      builder: (context, friendList, child) {
        final dataSource = friendList
            .map((contact) => UserPickerData(
                  key: contact.userID,
                  label: (contact.nickname?.isNotEmpty == true
                      ? contact.nickname!
                      : contact.userID),
                  avatarURL: contact.avatarURL,
                ))
            .toList();

        return UserPicker(
          dataSource: dataSource,
          title: atomicLocale.createGroupChat,
          showSelectedList: true,
          maxCount: 20,
          confirmText: atomicLocale.next,
          onConfirm: _createGroupChat,
        );
      },
    );
  }
}
