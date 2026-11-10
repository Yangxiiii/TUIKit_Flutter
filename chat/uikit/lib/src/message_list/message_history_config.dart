import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 宿主返回的一页归档历史，下一页游标为空表示已到末尾。
typedef ChatOlderMessagesPage = ({
  List<MessageInfo> messages,
  String? nextCursor,
});

/// 首次以 SDK 最早时间为边界，后续传回宿主上次返回的游标。
typedef ChatOlderMessagesLoader = Future<ChatOlderMessagesPage> Function({
  required int? beforeTimestamp,
  required String? cursor,
});

/// 由宿主提供与会话内搜索一致的入口外观；列表负责状态和触发时机。
typedef ChatOlderMessagesEntryBuilder = Widget Function(
  BuildContext context, {
  required AsyncValue<void> status,
  required VoidCallback onLoad,
});

/// 将应用的归档接口接到 SDK 消息列表，不要求 UIKit 依赖宿主网络层。
final class ChatMessageHistoryConfig {
  const ChatMessageHistoryConfig({
    required this.load,
    required this.buildEntry,
  });

  /// 分页请求必须绑定当前账号和会话；失败通过异常交给列表显示重试。
  final ChatOlderMessagesLoader load;

  /// 在最早一条消息上方绘制入口，支持加载、重试与继续查询。
  final ChatOlderMessagesEntryBuilder buildEntry;
}
