import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'group_control_message.g.dart';

/// 在线会控消息类型；策略同步与设备执行分开，不能将授权等同于设备开启。
enum GroupControlMessageKind { hello, sync, command, policy, ack, transfer }

/// 本项目正式在线会控信封，序列化由生成器完成，控制器负责业务鉴权。
@JsonSerializable(checked: true, disallowUnrecognizedKeys: true)
class GroupControlMessage {
  const GroupControlMessage({
    this.protocol = 'zd.group-call.control.v1',
    this.schemaVersion = 1,
    required this.kind,
    required this.callId,
    required this.commandId,
    required this.senderSessionId,
    required this.targetUserId,
    required this.targetSessionId,
    required this.version,
    required this.expiresAtMs,
    this.hostId = '',
    this.hostEpoch = 0,
    this.allowSelfUnmute = true,
    this.allowVideo = true,
    this.muteAll = false,
    this.cameraAllClosed = false,
    this.connectedAtMs,
    this.deadlineMs,
    this.sessions = const {},
    this.device,
    this.enabled,
    this.status,
    this.microphoneOn,
    this.cameraOn,
    this.error,
  });

  /// 固定协议命名空间，与普通聊天自定义消息隔离。
  final String protocol;

  /// 信封结构版本，未知版本不得降级执行。
  final int schemaVersion;

  /// 消息阶段，不从缺失字段猜测命令类型。
  final GroupControlMessageKind kind;

  /// 腾讯真实场次标识。
  final String callId;

  /// 同一逻辑命令及回执关联标识，重复接收不得重复执行设备。
  final String commandId;

  /// 实际发送者本次入会标识。
  final String senderSessionId;

  /// 唯一目标用户，群发由发送端逐人构造。
  final String targetUserId;

  /// 目标本次入会标识，仅 hello 允许空值请求当前策略。
  final String targetSessionId;

  /// 当前主持人代次中的递增操作版本。
  final int version;

  /// UTC 毫秒有效期，超时消息不能执行设备操作。
  final int expiresAtMs;

  /// 当前主持人或交接后的主持人，仅可信 IM 主持人消息可更新。
  final String hostId;

  /// 主持交接单调递增，旧主持人命令随交接失效。
  final int hostEpoch;

  /// 成员能否自行开启麦克风，与实际开关状态分离。
  final bool allowSelfUnmute;

  /// 成员能否自行开启摄像头，与实际开关状态分离。
  final bool allowVideo;

  /// 新入会是否应保持静音，不继承上次个人设备意图。
  final bool muteAll;

  /// 新入会是否应保持摄像头关闭，不继承上次个人设备意图。
  final bool cameraAllClosed;

  /// 初始主持首次真实 SDK 接通时固定的 UTC 毫秒起点，后续入会与交接不得改写。
  final int? connectedAtMs;

  /// 同场绝对截止点，必须等于 connectedAtMs 加一小时；不是后端强制结束承诺。
  final int? deadlineMs;

  /// 主持人确认的在场入会标识，交接时传递给新主持人。
  final Map<String, String> sessions;

  /// 设备命令目标，仅接受 microphone 或 camera。
  final String? device;

  /// 设备命令目标状态。
  final bool? enabled;

  /// 回执状态，必须使用真实执行结果或明确的未确认状态。
  final String? status;

  /// 回执中的 SDK 本端真实麦克风状态。
  final bool? microphoneOn;

  /// 回执中的 SDK 本端真实摄像头状态。
  final bool? cameraOn;

  /// 可展示失败原因，不携带凭证或原始敏感载荷。
  final String? error;

  factory GroupControlMessage.fromJson(Map<String, dynamic> json) =>
      _$GroupControlMessageFromJson(json);
  Map<String, dynamic> toJson() => _$GroupControlMessageToJson(this);

  /// 解码生成器支持的结构，限制载荷尺寸并拒绝缺失身份字段和未知协议。
  static GroupControlMessage? decode(String raw) {
    if (raw.length > 32768) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      // 生成器会将 num 转为 int；协议序号不得把小数截断成另一个有效版本。
      for (final key in [
        'version',
        'expiresAtMs',
        'schemaVersion',
        'hostEpoch'
      ]) {
        if (decoded.containsKey(key) && decoded[key] is! int) return null;
      }
      for (final key in ['connectedAtMs', 'deadlineMs']) {
        if (decoded[key] != null && decoded[key] is! int) return null;
      }
      final message = GroupControlMessage.fromJson(decoded);
      if (message.protocol != 'zd.group-call.control.v1' ||
          message.schemaVersion != 1 ||
          message.version < 0 ||
          message.hostEpoch < 0 ||
          message.expiresAtMs <= 0 ||
          [
            message.callId,
            message.commandId,
            message.senderSessionId,
            message.targetUserId
          ].any((id) => id.isEmpty || id != id.trim())) {
        return null;
      }
      // 只有 hello 能在尚未获知主持 session 时定向请求，其他消息必须命中具体入会。
      if (message.kind != GroupControlMessageKind.hello &&
          (message.targetSessionId.isEmpty ||
              message.targetSessionId != message.targetSessionId.trim())) {
        return null;
      }
      if ((message.connectedAtMs == null) != (message.deadlineMs == null) ||
          (message.connectedAtMs != null &&
              (message.connectedAtMs! <= 0 ||
                  message.deadlineMs! - message.connectedAtMs! != 3600000))) {
        return null;
      }
      return message;
    } catch (_) {
      return null;
    }
  }
}
