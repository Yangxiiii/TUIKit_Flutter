import 'package:flutter/cupertino.dart';
import 'package:tencent_live_uikit/component/beauty/base/base_beauty_panel_widget.dart';
import 'package:tencent_live_uikit/component/beauty/live_beauty_store.dart';
import 'package:tuikit_atomic_x/base_component/theme/color_scheme.dart';

class BeautyPanelWidget extends StatefulWidget {
  const BeautyPanelWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return _BeautyPanelWidgetState();
  }
}

class _BeautyPanelWidgetState extends State<BeautyPanelWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    Color backgroundColor = SemanticColorScheme.of(context).bgColorDialog;
    return LiveBeautyStore.shared.getTEBeautyPanel(backgroundColor) ?? const BaseBeautyPanelWidget();
  }
}
