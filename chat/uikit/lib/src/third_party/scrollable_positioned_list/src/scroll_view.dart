// Copyright 2019 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'wrapping.dart';
import 'viewport.dart';

/// 构建支持扩展锚点范围的滚动视口，普通和按内容收缩两种布局共用裁剪配置。
class UnboundedCustomScrollView extends CustomScrollView {
  /// 保留宿主的收缩选项，由自定义视口处理带中心锚点的收缩布局。
  final bool _shrinkWrap;

  const UnboundedCustomScrollView({
    Key? key,
    Axis scrollDirection = Axis.vertical,
    bool reverse = false,
    ScrollController? controller,
    bool? primary,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    super.clipBehavior,
    Key? center,
    double anchor = 0.0,
    double? cacheExtent,
    List<Widget> slivers = const <Widget>[],
    int? semanticChildCount,
    DragStartBehavior dragStartBehavior = DragStartBehavior.start,
  })  : _shrinkWrap = shrinkWrap,
        _anchor = anchor,
        super(
          key: key,
          scrollDirection: scrollDirection,
          reverse: reverse,
          controller: controller,
          primary: primary,
          physics: physics,
          shrinkWrap: false,
          center: center,
          cacheExtent: cacheExtent,
          semanticChildCount: semanticChildCount,
          dragStartBehavior: dragStartBehavior,
          slivers: slivers,
        );

  // [CustomScrollView] enforces constraints on [CustomScrollView.anchor], so
  // we need our own version.
  final double _anchor;

  @override
  double get anchor => _anchor;

  /// 按内容是否收缩选择视口，并传递同一套裁剪配置。
  @override
  @protected
  Widget buildViewport(
    BuildContext context,
    ViewportOffset offset,
    AxisDirection axisDirection,
    List<Widget> slivers,
  ) {
    if (_shrinkWrap) {
      return CustomShrinkWrappingViewport(
        axisDirection: axisDirection,
        offset: offset,
        clipBehavior: clipBehavior,
        slivers: slivers,
        cacheExtent: cacheExtent,
        center: center,
        anchor: anchor,
      );
    }
    return UnboundedViewport(
      axisDirection: axisDirection,
      offset: offset,
      clipBehavior: clipBehavior,
      slivers: slivers,
      cacheExtent: cacheExtent,
      center: center,
      anchor: anchor,
    );
  }
}
