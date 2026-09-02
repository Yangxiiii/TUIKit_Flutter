import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';

import 'listen_from_here_controller.dart';

/// Floating playback status bar for "listen from here". Collapsed by default
/// (a small pill); tap to expand and show the currently spoken text; the close
/// button stops playback.
///
/// "从这里开始听" 的悬浮播放状态栏。默认折叠（一个小膠囊按钮）；点击展开显示当前播放的文字；关闭按钮停止播放。
class ListenPlaybackBar extends StatefulWidget {
  const ListenPlaybackBar({super.key, this.controller});

  /// Defaults to the shared singleton; injectable for tests.
  ///
  /// 默认使用共享单例；可注入测试。
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
          //
          // 播放结束时重置展开状态，这样下次会话打开时是折叠的。
          if (_expanded) _expanded = false;
          // Empty box does not absorb taps, so the chat below stays
          // interactive. (Placed inside a Positioned.fill in ChatPage.)
          //
          // 空盒子不会阻止点击，因此下面的聊天仍然可以互动。（放在 ChatPage 的 Positioned.fill 里。）
          return const SizedBox.shrink();
        }

        // The pill floats mid-right over the message area. Collapsed hugs the
        // screen edge; expanded floats with its own built-in right margin.
        //
        // 这个小组件浮在消息区域的中右侧。收起来时贴着屏幕边缘；展开时有自带的右边距浮动。
        final pill = Align(
          alignment: const Alignment(1.0, -0.2),
          child: _expanded ? _buildExpanded(colors) : _buildCollapsed(colors),
        );

        if (!_expanded) {
          // Collapsed: only the pill is tappable; empty area passes taps
          // through to the chat.
          //
          // 收起：只有小组件本身可以点击；空白区域的点击会穿透到聊天窗口。
          return pill;
        }

        // Expanded: a full-screen transparent barrier collapses the bar when
        // tapping anywhere outside the pill (WeChat-like behavior).
        //
        // 展开：一个全屏透明屏障，在点击小组件之外的任意地方时会收起栏（像微信的行为）。
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
  ///
  /// 圆角白色“卡片”装饰，两个状态都通用：浅色背景、细边框和柔和的投影。
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
  ///
  /// 蓝色TTS图标（通过主题链接颜色着色，可适配暗黑模式），或者在当前条目准备过程中显示加载旋转图标。
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
      //
      // 贴着屏幕右边缘：只有左侧角是圆角，右边是平的。垂直内边距让图标/旋转器垂直居中，无需固定高度（避免旋转器顶部被裁剪）。
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
