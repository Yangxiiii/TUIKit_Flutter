import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart'
    show GroupCallControlMessage;

import '../state/group_control_state.dart';

part 'group_control_message.g.dart';

/// 设备指令与在席握手、策略同步、主持交接共用在线消息外层。
enum GroupControlMessageKind {
  hello,
  sync,
  command,
  ack,
  transfer,
  transferAck,
}

/// 恢复权限、关闭设备和请求本人开启是独立操作。
enum GroupControlAction { close, requestOpen, setAllowed }

/// 设备回执的实际状态，缺少 SDK 确认为 unknown。
enum GroupControlDeviceState { on, off, unavailable, unknown }

/// 会控线上回执状态，超时由等待方本地判定。
enum GroupControlAckStatus { applied, rejected, failed, expired }

/// v1 会控载荷，外层标记只用于路由，身份和入会权限由控制器验证。
@JsonSerializable(
  checked: true,
  disallowUnrecognizedKeys: true,
  includeIfNull: false,
)
class GroupControlMessage {
  const GroupControlMessage({
    required this.kind,
    required this.callId,
    required this.groupId,
    required this.commandId,
    required this.senderSessionId,
    required this.targetUserId,
    required this.targetSessionId,
    required this.version,
    required this.hostEpoch,
    this.expiresAtMs,
    this.device,
    this.action,
    this.allowed,
    this.status,
    this.deviceState,
    this.hostId,
    this.allowSelfUnmute,
    this.muteBlocksUnmute,
    this.allowVideo,
    this.muteAll,
    this.cameraAllClosed,
    this.connectedAtMs,
    this.deadlineMs,
    this.sessions,
  });

  /// 消息阶段，决定哪些附加字段可用。
  final GroupControlMessageKind kind;

  /// 腾讯 SDK 的真实通话场次 ID，同场重入沿用。
  final String callId;

  /// 该场通话所属的原始 IM 群 ID，临时多人通话为空。
  final String groupId;

  /// 单条逻辑指令的唯一标识，回执和重发沿用该值。
  final String commandId;

  /// IM 发送者本次入会的标识。
  final String senderSessionId;

  /// 目标 IM 用户 ID，与 C2C receiver 一致。
  final String targetUserId;

  /// 目标设备本次入会的标识，只有 hello 允许尚未获知目标入会标识。
  final String targetSessionId;

  /// 同一场次、同一主持权代次内递增的操作版本。
  @JsonKey(name: 'revision')
  final int version;

  /// 当前主持权代次，主持权交接后递增。
  final int hostEpoch;

  /// 指令或同步消息的有效期，使用 UTC Unix 毫秒时间戳。
  final int? expiresAtMs;

  /// 一个指令只控制一个设备类型，回执沿用原指令的设备。
  final GroupControlDevice? device;

  /// 目标设备的操作，开启必须由本人确认。
  final GroupControlAction? action;

  /// setAllowed 必填，true 只恢复权限，false 还会关闭正在采集的设备。
  final bool? allowed;

  /// 回执结果，发送成功不能作为 applied。
  final GroupControlAckStatus? status;

  /// 回执时 SDK 确认的设备状态。
  final GroupControlDeviceState? deviceState;

  /// 策略发布者或交接后的可信主持。
  final String? hostId;

  /// 同步的原始开麦权限，全员静音额外限制由 muteBlocksUnmute 表示。
  final bool? allowSelfUnmute, muteBlocksUnmute;

  /// 允许成员开启视频的策略，与实际采集无关。
  final bool? allowVideo;

  /// 新入会的默认关麦、关摄像头策略。
  final bool? muteAll, cameraAllClosed;

  /// 初始主持确认的同场接通时间及截止时间，单位为 UTC 毫秒。
  final int? connectedAtMs, deadlineMs;

  /// 交接时交给继任主持的已验证在席标识。
  final Map<String, String>? sessions;

  /// 生成 OA 自定义消息外层，发送给 IM 时序列化为字符串。
  Map<String, dynamic> toJson() => {
        'businessID': GroupCallControlMessage.businessID,
        'version': 1,
        'payload': _$GroupControlMessageToJson(this),
      };

  /// 校验外层、整数精度和每种消息的必填字段，失败后直接丢弃。
  static GroupControlMessage? decode(String raw) {
    if (raw.length > 32768) return null;
    try {
      // 聊天侧按业务标识拦截，执行侧只接受完整的当前版本外层。
      final envelope = jsonDecode(raw);
      if (envelope is! Map<String, dynamic> ||
          envelope.length != 3 ||
          envelope['businessID'] != GroupCallControlMessage.businessID ||
          envelope['version'] is! int ||
          envelope['version'] != 1 ||
          envelope['payload'] is! Map<String, dynamic>) {
        return null;
      }
      final payload = envelope['payload'] as Map<String, dynamic>;
      // 生成器会把 JSON 浮点数转成整数，先限制精度和取值。
      for (final key in [
        'revision',
        'hostEpoch',
        'expiresAtMs',
        'connectedAtMs',
        'deadlineMs',
      ]) {
        final number = payload[key];
        if (payload.containsKey(key) &&
            (number is! int || number < 0 || number > 9007199254740991)) {
          return null;
        }
      }
      final message = _$GroupControlMessageFromJson(payload);
      if ([
            message.callId,
            message.commandId,
            message.senderSessionId,
            message.targetUserId,
            if (message.kind != GroupControlMessageKind.hello)
              message.targetSessionId,
          ].any((id) => id.isEmpty || id != id.trim()) ||
          message.groupId != message.groupId.trim()) {
        return null;
      }
      // 同步元数据只在同步、交接中出现，设备指令仅使用对应设备的字段。
      final hasPolicy = const {
        'hostId',
        'allowSelfUnmute',
        'muteBlocksUnmute',
        'allowVideo',
        'muteAll',
        'cameraAllClosed',
        'connectedAtMs',
        'deadlineMs',
        'sessions',
      }.any(payload.containsKey);
      final hasAction = const {'action', 'allowed'}.any(payload.containsKey);
      final hasStatus = const {'status', 'deviceState'}.any(payload.containsKey);
      final hasExpiry = (message.expiresAtMs ?? 0) > 0;
      final valid = switch (message.kind) {
        GroupControlMessageKind.command => !hasPolicy &&
            !hasStatus &&
            hasExpiry &&
            message.device != null &&
            message.action != null &&
            (message.action == GroupControlAction.setAllowed
                ? message.allowed != null
                : !payload.containsKey('allowed')),
        GroupControlMessageKind.ack => !hasPolicy &&
            !hasAction &&
            message.expiresAtMs == null &&
            message.device != null &&
            message.status != null &&
            message.deviceState != null,
        GroupControlMessageKind.transferAck => !hasPolicy &&
            !hasAction &&
            message.expiresAtMs == null &&
            !payload.containsKey('device') &&
            message.status != null &&
            !payload.containsKey('deviceState'),
        GroupControlMessageKind.hello => !hasPolicy &&
            !hasAction &&
            !hasStatus &&
            hasExpiry &&
            message.targetSessionId.isEmpty &&
            !payload.containsKey('device'),
        GroupControlMessageKind.sync ||
        GroupControlMessageKind.transfer =>
          !hasAction &&
              !hasStatus &&
              hasExpiry &&
              !payload.containsKey('device') &&
              message.hostId?.isNotEmpty == true &&
              message.allowSelfUnmute != null &&
              message.muteBlocksUnmute != null &&
              message.allowVideo != null &&
              message.muteAll != null &&
              message.cameraAllClosed != null &&
              (message.connectedAtMs ?? 0) > 0 &&
              message.deadlineMs == message.connectedAtMs! + 3600000 &&
              (message.kind == GroupControlMessageKind.transfer
                  ? message.sessions != null
                  : !payload.containsKey('sessions')),
      };
      return valid ? message : null;
    } catch (_) {
      return null;
    }
  }
}
