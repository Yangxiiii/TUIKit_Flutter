import 'package:flutter/material.dart';

import 'package:tuikit_atomic_x/base_component/theme/color_scheme.dart';

class AvatarSelectorConfig {
  final Axis scrollDirection;
  final int crossAxisCount;
  final double childAspectRatio;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final EdgeInsets padding;
  final double? height;

  const AvatarSelectorConfig({
    this.scrollDirection = Axis.vertical,
    this.crossAxisCount = 4,
    this.childAspectRatio = 1.0,
    this.mainAxisSpacing = 12,
    this.crossAxisSpacing = 12,
    this.padding = const EdgeInsets.all(16),
    this.height,
  });
}

class AvatarSelector extends StatefulWidget {
  final List<String> avatarURLs;
  final String? selectedAvatarURL;
  final Function(String selectedUrl)? onAvatarSelected;
  final AvatarSelectorConfig config;

  const AvatarSelector({
    super.key,
    required this.avatarURLs,
    this.selectedAvatarURL,
    this.onAvatarSelected,
    this.config = const AvatarSelectorConfig(),
  });

  @override
  State<AvatarSelector> createState() => _AvatarSelectorState();
}

class _AvatarSelectorState extends State<AvatarSelector> {
  late SemanticColorScheme colorsTheme;
  String? _selectedAvatarURL;

  @override
  void initState() {
    super.initState();
    _selectedAvatarURL = widget.selectedAvatarURL;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorsTheme = SemanticColorScheme.of(context);
  }

  @override
  void didUpdateWidget(AvatarSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedAvatarURL != oldWidget.selectedAvatarURL) {
      _selectedAvatarURL = widget.selectedAvatarURL;
    }
  }

  void _selectAvatar(String avatarUrl) {
    setState(() {
      _selectedAvatarURL = avatarUrl;
    });
    widget.onAvatarSelected?.call(avatarUrl);
  }

  Widget _buildAvatarItem(String avatarURL, int index) {
    final isSelected = _selectedAvatarURL == avatarURL;

    return GestureDetector(
      onTap: () => _selectAvatar(avatarURL),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected
                    ? colorsTheme.checkboxColorSelected
                    : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                avatarURL,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: colorsTheme.listColorHover,
                    child: Icon(
                      Icons.image_not_supported,
                      color: colorsTheme.textColorSecondary,
                      size: 24,
                    ),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: colorsTheme.listColorHover,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorsTheme.buttonColorPrimaryDefault,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (isSelected)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: colorsTheme.checkboxColorSelected,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  color: colorsTheme.textColorButton,
                  size: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.avatarURLs.isEmpty) {
      return Container();
    }

    Widget gridView = GridView.builder(
      scrollDirection: widget.config.scrollDirection,
      padding: widget.config.padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.config.crossAxisCount,
        childAspectRatio: widget.config.childAspectRatio,
        mainAxisSpacing: widget.config.mainAxisSpacing,
        crossAxisSpacing: widget.config.crossAxisSpacing,
      ),
      itemCount: widget.avatarURLs.length,
      itemBuilder: (context, index) {
        return _buildAvatarItem(widget.avatarURLs[index], index);
      },
    );

    if (widget.config.scrollDirection == Axis.horizontal &&
        widget.config.height != null) {
      return SizedBox(
        height: widget.config.height,
        child: gridView,
      );
    }

    return gridView;
  }
}
