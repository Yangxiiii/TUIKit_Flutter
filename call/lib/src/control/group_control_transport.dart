/// 已登录 IM 实例收到的原始控制消息，身份必须取 SDK 的实际发送者。
class GroupControlInbound {
  const GroupControlInbound({required this.senderId, required this.payload});

  /// 腾讯 IM 消息实际发送者，禁止使用消息体中的自报身份。
  final String senderId;

  /// 在线自定义消息正文，由会控控制器校验协议、目标及有效期。
  final String payload;
}

/// 复用宿主 IM 登录的在线控制通道，不经过聊天发送、历史或普通通知编排。
abstract interface class GroupControlTransport {
  /// 已过滤到本协议的真实 IM 接收事件，仍由控制器做身份和场次鉴权。
  Stream<GroupControlInbound> get messages;

  /// 定向在线发送；必须禁用消息前后云回调，不附加聊天回执或漫游扩展。
  /// 成功仅表示 IM 发送成功，不能据此认定设备操作已完成。
  Future<void> send(String targetUserId, String payload);

  /// 从可信群成员接口读取剩余管理员；临时多人或没有管理员时返回空集合。
  Future<Set<String>> loadAdministrators(
      String groupId, List<String> memberIds);
}
