import 'package:app_ui/app_ui.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:flutter/material.dart' hide IconButton;

import '../widgets/avatar_selector.dart';

class ChooseGroupAvatar extends StatefulWidget {
  final String groupID;
  final String groupType;
  final String selectedAvatarURL;

  const ChooseGroupAvatar({
    super.key,
    required this.groupID,
    required this.groupType,
    required this.selectedAvatarURL,
  });

  @override
  State<StatefulWidget> createState() => ChooseGroupAvatarState();
}

class ChooseGroupAvatarState extends State<ChooseGroupAvatar> {
  late SemanticColorScheme colorsTheme;
  late AppLocalizedText atomicLocale;

  final String _groupFaceURL =
      "https://im.sdk.qcloud.com/download/tuikit-resource/group-avatar/group_avatar_%s.png";
  final int _groupFaceCount = 24;
  List<String> groupAvatars = [];
  String selectedAvatarUrl = '';

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _groupFaceCount; i++) {
      groupAvatars.add(_groupFaceURL.replaceAll('%s', (i + 1).toString()));
    }

    selectedAvatarUrl = widget.selectedAvatarURL;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    atomicLocale = AppLocalization.of(context);
    colorsTheme = SemanticColorScheme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorsTheme.listColorDefault,
      appBar: AppBar(
        backgroundColor: colorsTheme.bgColorTopBar,
        scrolledUnderElevation: 0,
        leading: IconButton.buttonContent(
          content: IconOnlyContent(Icon(Icons.arrow_back_ios,
              color: colorsTheme.buttonColorPrimaryDefault)),
          type: ButtonType.noBorder,
          size: ButtonSize.l,
          onClick: () => Navigator.of(context).pop(),
        ),
        title: Text(
          atomicLocale.chooseAvatar,
          style: FontScheme.caption1Medium.copyWith(
            color: colorsTheme.textColorPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _submitAvatar,
            child: Text(
              atomicLocale.confirm,
              style: FontScheme.caption1Medium.copyWith(
                color: colorsTheme.buttonColorPrimaryDefault,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: colorsTheme.strokeColorPrimary,
          ),
        ),
      ),
      body: AvatarSelector(
        avatarURLs: groupAvatars,
        selectedAvatarURL: selectedAvatarUrl,
        onAvatarSelected: (url) {
          setState(() {
            selectedAvatarUrl = url;
          });
        },
        config: const AvatarSelectorConfig(
          scrollDirection: Axis.vertical,
          crossAxisCount: 4,
          childAspectRatio: 1.0,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          padding: EdgeInsets.all(16),
        ),
      ),
    );
  }

  Future<void> _submitAvatar() async {
    if (selectedAvatarUrl.isNotEmpty &&
        selectedAvatarUrl != widget.selectedAvatarURL) {
      if (mounted) {
        Navigator.of(context).pop(selectedAvatarUrl);
      }
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}
