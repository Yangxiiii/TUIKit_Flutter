import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Chat UIKit 内部临时页面使用的稳定路由名称。
const chatUIKitPageRouteName = 'tim.uikit.page';

/// Chat UIKit 内部临时页面使用的统一路径。
const chatUIKitPageRoutePath = '/tim/uikit/page';

/// 将 UIKit 内部页面压入宿主 GoRouter，并把返回值传回调用方。
extension ChatUIKitNavigation on BuildContext {
  Future<T?> pushChatUIKitPage<T>(Widget page) => pushNamed<T>(
        chatUIKitPageRouteName,
        extra: page,
      );

  /// 关闭当前 UIKit 页面，并把可选结果交还上一层路由。
  void popChatUIKitPage<T>([T? result]) => pop<T>(result);
}
