import 'package:app_ui/app_ui.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/contact_list/pages/group_application_list.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/api/group/group_store.dart' as group_api;
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/navigation/chat_uikit_navigation.dart';

import 'pages/blacklist.dart';
import 'pages/friend_application_list.dart';
import 'pages/group_list.dart';
import 'package:tencent_chat_uikit/src/widgets/az_ordered_list.dart';

typedef OnGroupClick = void Function(ContactInfo contactInfo);
typedef OnContactClick = void Function(ContactInfo contactInfo);

class ContactList extends StatefulWidget {
  final Function(ContactInfo contactInfo)? onGroupClick;
  final Function(ContactInfo contactInfo)? onContactClick;

  const ContactList({
    super.key,
    this.onGroupClick,
    this.onContactClick,
  });

  @override
  State<ContactList> createState() => _ContactListState();
}

class _ContactListState extends State<ContactList> {
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

  final group_api.GroupStore _groupStore = group_api.GroupStore.shared;

  Future<void> _loadData() async {
    await Future.wait([
      _contactStore.loadFriends(),
      _contactStore.loadFriendApplications(),
      _groupStore.loadApplications(),
    ]);
  }

  Widget _buildMenuTile({
    required String title,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Container(
      color: colorsTheme.bgColorInput,
      child: ListTile(
        title: Text(
          title,
          style: FontScheme.body4Regular.copyWith(
            color: colorsTheme.textColorPrimary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorsTheme.textColorError,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: FontScheme.caption3Medium.copyWith(
                    color: colorsTheme.textColorButton,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: colorsTheme.scrollbarColorHover),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  static Widget buildDivider(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);

    return Container(
      height: 1,
      color: colorsTheme.listColorDefault,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ContactInfo>>(
      valueListenable: _contactStore.state.friendList,
      builder: (context, friendList, _) {
        return ValueListenableBuilder<int>(
          valueListenable: _contactStore.state.friendApplicationUnreadCount,
          builder: (context, friendAppUnread, _) {
            return ValueListenableBuilder<int>(
              valueListenable: _groupStore.state.unreadApplicationCount,
              builder: (context, groupAppUnread, _) {
                final dataSource = friendList
                    .map((contact) => AZOrderedListItem(
                          key: contact.userID,
                          label: (contact.nickname?.isNotEmpty == true
                              ? contact.nickname!
                              : contact.userID),
                          avatarURL: contact.avatarURL,
                        ))
                    .toList();

                final header = Column(
                  children: [
                    _buildMenuTile(
                      title: atomicLocale.newFriend,
                      badge: friendAppUnread > 0
                          ? friendAppUnread.toString()
                          : null,
                      onTap: () {
                        context.pushChatUIKitPage(
                          const FriendApplicationList(),
                        );
                      },
                    ),
                    buildDivider(context),
                    _buildMenuTile(
                      title: atomicLocale.groupChatNotifications,
                      badge:
                          groupAppUnread > 0 ? groupAppUnread.toString() : null,
                      onTap: () {
                        context.pushChatUIKitPage(
                          const GroupApplicationList(),
                        );
                      },
                    ),
                    buildDivider(context),
                    _buildMenuTile(
                      title: atomicLocale.myGroups,
                      onTap: () {
                        context.pushChatUIKitPage(
                          GroupList(
                            onGroupClick: widget.onGroupClick,
                          ),
                        );
                      },
                    ),
                    buildDivider(context),
                    _buildMenuTile(
                      title: atomicLocale.blackList,
                      onTap: () {
                        context.pushChatUIKitPage(
                          Blacklist(
                            onContactClick: widget.onContactClick,
                          ),
                        );
                      },
                    ),
                  ],
                );

                return AZOrderedList(
                  dataSource: dataSource,
                  header: header,
                  config: AZOrderedListConfig(
                    showIndexBar: true,
                    emptyText: '',
                    onItemClick: (item) {
                      if (widget.onContactClick != null) {
                        ContactInfo contactInfo = ContactInfo(
                          userID: item.key,
                          nickname: item.label,
                          avatarURL: item.avatarURL,
                        );

                        widget.onContactClick!(contactInfo);
                      }
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
