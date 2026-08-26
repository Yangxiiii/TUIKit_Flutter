import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';

import 'listen_from_here_controller.dart';

/// Floating playback status bar for "listen from here". Collapsed by default
/// (a small pill); tap to expand and show the currently spoken text; the close
/// button stops playback.
class ListenPlaybackBar extends StatefulWidget {
  const ListenPlaybackBar({super.key, this.controller});

  /// Defaults to the shared singleton; injectable for tests.
  final ListenFromHereController? controller;

  @override
  State<ListenPlaybackBar> createState() => _ListenPlaybackBarState();
}

class _ListenPlaybackBarState extends State<ListenPlaybackBar> {
  bool _expanded = false;

  ListenFromHereController get _controller =>
      widget.controller ?? ListenFromHereController.instance;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (!_controller.isActive) {
          // Reset expansion when playback ends so the next session opens
          // collapsed.
          if (_expanded) _expanded = false;
          // Empty box does not absorb taps, so the chat below stays
          // interactive. (Placed inside a Positioned.fill in ChatPage.)
          return const SizedBox.shrink();
        }

        // The pill floats mid-right over the message area. Collapsed hugs the
        // screen edge; expanded floats with its own built-in right margin.
        final pill = Align(
          alignment: const Alignment(1.0, -0.2),
          child: _expanded ? _buildExpanded(colors) : _buildCollapsed(colors),
        );

        if (!_expanded) {
          // Collapsed: only the pill is tappable; empty area passes taps
          // through to the chat.
          return pill;
        }

        // Expanded: a full-screen transparent barrier collapses the bar when
        // tapping anywhere outside the pill (WeChat-like behavior).
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = false),
              ),
            ),
            pill,
          ],
        );
      },
    );
  }

  /// Rounded white "card" decoration shared by both states: light background,
  /// hairline border and a soft drop shadow.
  BoxDecoration _cardDecoration(
    SemanticColorScheme colors,
    BorderRadius borderRadius,
  ) {
    return BoxDecoration(
      color: colors.bgColorOperate,
      borderRadius: borderRadius,
      border: Border.all(color: colors.strokeColorPrimary, width: 0.5),
      boxShadow: [
        BoxShadow(
          color: colors.shadowColor,
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// Blue TTS icon (tinted via theme link color so it adapts to dark mode),
  /// or a spinner while the current item is being prepared.
  Widget _ttsIcon(SemanticColorScheme colors, double size) {
    if (_controller.isLoading) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(colors.textColorLink),
        ),
      );
    }
    return SvgPicture.asset(
      'chat_assets/icon/tts_play.svg',
      package: 'tencent_chat_uikit',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(colors.textColorLink, BlendMode.srcIn),
    );
  }

  Widget _buildCollapsed(SemanticColorScheme colors) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = true),
      // Hugs the right screen edge: only the left corners are rounded, the
      // right side is flush (square). Vertical padding keeps the icon/spinner
      // centred without a fixed height (avoids the spinner clipping the top).
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: _cardDecoration(
          colors,
          const BorderRadius.only(
            topLeft: Radius.circular(10),
            bottomLeft: Radius.circular(10),
          ),
        ),
        child: _ttsIcon(colors, 20),
      ),
    );
  }

  Widget _buildExpanded(SemanticColorScheme colors) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _cardDecoration(colors, BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ttsIcon(colors, 18),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onTap: () => setState(() => _expanded = false),
              child: Text(
                _controller.currentText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FontScheme.caption2Regular.copyWith(
                  color: colors.textColorSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              _controller.stop();
              setState(() => _expanded = false);
            },
            child: Icon(
              Icons.close,
              color: colors.textColorPrimary,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }
}
