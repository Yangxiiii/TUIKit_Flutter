import 'package:app_ui/app_ui.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart' hide IconButton;

import '../contact_list.dart';
import 'package:tencent_chat_uikit/src/widgets/az_ordered_list.dart';

class Blacklist extends StatefulWidget {
  final OnContactClick? onContactClick;

  const Blacklist({
    super.key,
    this.onContactClick,
  });

  @override
  State<Blacklist> createState() => _BlacklistState();
}

class _BlacklistState extends State<Blacklist> {
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
    await _contactStore.loadBlackList();
  }

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);

    return Scaffold(
      backgroundColor: colorsTheme.bgColorOperate,
      appBar: AppBar(
        backgroundColor: colorsTheme.bgColorOperate,
        scrolledUnderElevation: 0,
        leading: IconButton.buttonContent(
          content: IconOnlyContent(Icon(Icons.arrow_back_ios,
              color: colorsTheme.buttonColorPrimaryDefault)),
          type: ButtonType.noBorder,
          size: ButtonSize.l,
          onClick: () => Navigator.of(context).pop(),
        ),
        title: Text(
          atomicLocale.blackList,
          style: FontScheme.caption1Medium.copyWith(
            color: colorsTheme.textColorPrimary,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: colorsTheme.strokeColorPrimary,
          ),
        ),
      ),
      body: ValueListenableBuilder<List<ContactInfo>>(
        valueListenable: _contactStore.state.blackList,
        builder: (context, blackList, child) {
          final dataSource = blackList
              .map((contact) => AZOrderedListItem(
                    key: contact.userID,
                    label: (contact.nickname?.isNotEmpty == true
                        ? contact.nickname!
                        : contact.userID),
                    avatarURL: contact.avatarURL,
                    extraData: contact,
                  ))
              .toList();

          return AZOrderedList(
            dataSource: dataSource,
            config: AZOrderedListConfig(
              emptyText: atomicLocale.noBlackList,
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
      ),
    );
  }
}
