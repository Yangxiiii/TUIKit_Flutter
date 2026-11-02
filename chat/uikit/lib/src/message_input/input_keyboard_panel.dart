import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../third_party/extended_text_field/extended_text_field.dart';

/// 在同一底部区域切换系统键盘与业务面板，不关闭输入连接或修改正文选区。
///
/// 面板是否展开仍由输入区持有；这里只维护底部占位、平台显示请求和过渡生命周期。
final class InputKeyboardPanel with WidgetsBindingObserver {
  InputKeyboardPanel(
      {required FlutterView view, required VoidCallback onChanged})
      : _view = view,
        _onChanged = onChanged {
    WidgetsBinding.instance.addObserver(this);
  }

  /// 当前输入区所属窗口，尺寸监听不能读取其他窗口的键盘遮挡。
  final FlutterView _view;

  /// 几何改变时只通知当前输入区重排，由宿主继续更新覆盖层锚点。
  final VoidCallback _onChanged;

  /// 尚未显示系统键盘时使用280逻辑像素，之后沿用最近可用的系统键盘高度。
  double _keyboardHeight = 280;

  /// 本次切换固定的总高度；系统键盘遮挡与面板占位共同填满这一区域。
  double? _reservedHeight;

  /// 系统键盘重新出现前继续绘制原面板，避免中间帧只剩空白。
  bool _returningToSystem = false;

  /// 尺寸通知停止80毫秒后接受新的系统键盘高度，兼容输入法高度发生变化。
  Timer? _settleTimer;

  /// 使已经排队的显示请求失效，防止快速往返切换后迟到的hide覆盖show。
  int _requestRevision = 0;

  /// 销毁后所有排队请求与延迟回调均失效，不作用于后续页面。
  bool _disposed = false;

  double get _inset => _view.viewInsets.bottom / _view.devicePixelRatio;

  /// 当前表情面板的完整逻辑高度，不随系统键盘动画逐帧改变。
  double get height => _reservedHeight ?? _keyboardHeight;

  /// 只补足系统键盘未遮挡的高度，不能再叠加一整份面板高度。
  double get remainingHeight =>
      _reservedHeight == null ? 0 : math.max(0, height - _inset);

  /// 切换期间仍需由输入区保留的底部区域。
  bool get hasReservedSpace => _reservedHeight != null;

  /// 系统键盘显示完成前保持原面板作为过渡背景。
  bool get returningToSystem => _returningToSystem;

  /// 打开业务面板时只隐藏系统键盘；编辑区交接可显式沿用上一面板的逻辑高度。
  void showEmoji(FocusNode focus, {double? previousHeight}) {
    assert(previousHeight == null || previousHeight > 0);
    _settleTimer?.cancel();
    _returningToSystem = false;
    _reservedHeight = previousHeight ?? (_inset > 0 ? _inset : height);
    _keyboardHeight = height;
    _requestKeyboard(focus, show: false);
  }

  /// 切回系统键盘，原占位随系统遮挡增长逐步缩小，避免输入区先落到底部。
  void showSystem(FocusNode focus) {
    _returningToSystem = _reservedHeight != null;
    _requestKeyboard(focus, show: true);
    if (_reservedHeight != null) didChangeMetrics();
  }

  /// 等本帧输入框挂载并接管焦点后请求显示或隐藏，不调用clearClient或unfocus。
  void _requestKeyboard(FocusNode focus, {required bool show}) {
    final revision = ++_requestRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || revision != _requestRevision) return;
      // 编辑区交接必须先更新接收方的键盘模式，再获取焦点，避免旧system模式闪现IME。
      focus.requestFocus();
      scheduleMicrotask(() {
        if (_disposed || revision != _requestRevision || !focus.hasFocus) {
          return;
        }
        if (show) {
          // 平台可能在隐藏时结束了原生客户端，显式请求编辑器恢复连接，而非只发show。
          final editable = focus.context
              ?.findAncestorStateOfType<ExtendedEditableTextState>();
          if (editable != null) {
            editable.requestKeyboard();
            return;
          }
        }
        unawaited(SystemChannels.textInput
            .invokeMethod<void>(show ? 'TextInput.show' : 'TextInput.hide'));
      });
    });
  }

  @override
  void didChangeMetrics() {
    if (_disposed) return;
    if (_reservedHeight == null) {
      // 系统收起期间的小高度不能覆盖最近的完整键盘高度。
      if (_inset > 0) _keyboardHeight = math.max(_keyboardHeight, _inset);
      return;
    }
    if (_returningToSystem && _inset >= height - 0.5) {
      _settleTimer?.cancel();
      _keyboardHeight = _inset;
      _reservedHeight = null;
      _returningToSystem = false;
    } else if (_returningToSystem && _inset > 0) {
      _settleTimer?.cancel();
      _settleTimer = Timer(const Duration(milliseconds: 80), () {
        if (_disposed || !_returningToSystem || _inset <= 0) return;
        _keyboardHeight = _inset;
        _reservedHeight = null;
        _returningToSystem = false;
        _onChanged();
      });
    }
    _onChanged();
  }

  /// 输入区失去焦点或关闭时撤销过渡，不留下空白占位或迟到的平台请求。
  void clear() {
    _requestRevision++;
    _settleTimer?.cancel();
    _reservedHeight = null;
    _returningToSystem = false;
  }

  /// 随输入区销毁尺寸监听和定时器，排队的显示请求不再作用于其他页面。
  void dispose() {
    _disposed = true;
    clear();
    WidgetsBinding.instance.removeObserver(this);
  }
}
