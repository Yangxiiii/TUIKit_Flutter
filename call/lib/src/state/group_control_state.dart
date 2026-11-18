import 'package:flutter/foundation.dart';

/// 会控设备，仅包括本次明确接入的麦克风和摄像头。
enum GroupControlDevice { microphone, camera }

/// 本机结果来自 SDK 操作或媒体事件，远端执行须核对目标回执和设备状态。
enum GroupControlStatus {
  success,
  failed,
  denied,
  expired,
  timeout,
  unconfirmed,
  unavailable
}

/// 单个目标的设备执行结果，可用于展示真实失败及未确认原因。
@immutable
class GroupControlOutcome {
  const GroupControlOutcome(this.status,
      {this.error, this.microphoneOn, this.cameraOn});

  /// 设备执行结果，IM 消息发送成功不能推导设备成功。
  final GroupControlStatus status;

  /// 面向用户的失败原因；不能包含 UserSig 等身份凭证。
  final String? error;

  /// 目标 SDK 报告的真实麦克风状态，未知时为空。
  final bool? microphoneOn;

  /// 目标 SDK 报告的真实摄像头状态，未知时为空。
  final bool? cameraOn;

  /// 供 UI 汇总，不能把部分成功或发送成功折算为真实执行成功。
  bool get success => status == GroupControlStatus.success;
}

/// 一次主持操作的逐人真实回执，部分失败不得折算成全员成功。
@immutable
class GroupControlResult {
  GroupControlResult(Map<String, GroupControlOutcome> outcomes)
      : outcomes = Map.unmodifiable(outcomes);

  /// 目标用户到实际执行结果，包含发送失败及等待超时。
  final Map<String, GroupControlOutcome> outcomes;

  /// 必须存在目标且所有目标均成功；空名单不会显示全员成功。
  bool get success =>
      outcomes.isNotEmpty && outcomes.values.every((v) => v.success);
}

/// 当前入会的只读主持权限、策略和执行进度，设备状态与授权分别表达。
@immutable
class GroupControlState {
  GroupControlState(
      {required this.callId,
      required this.sessionId,
      required this.selfId,
      required this.hostId,
      required this.policyKnown,
      required this.version,
      required this.allowSelfUnmute,
      required this.allowVideo,
      required this.muteAll,
      required this.cameraAllClosed,
      required this.microphoneOn,
      required this.cameraOn,
      this.connectedAtMs,
      this.deadlineMs,
      Map<String, Set<GroupControlDevice?>> pendingByUserId = const {},
      Map<String, GroupControlOutcome> resultsByUserId = const {},
      Map<(String, GroupControlDevice), GroupControlOutcome>
          resultsByDevice = const {}})
      : pendingByUserId = Map.unmodifiable({
          for (final entry in pendingByUserId.entries)
            entry.key: Set<GroupControlDevice?>.unmodifiable(entry.value),
        }),
        resultsByUserId = Map.unmodifiable(resultsByUserId),
        resultsByDevice = Map.unmodifiable(resultsByDevice);

  /// 腾讯真实场次。
  final String callId;

  /// 本次入会随机标识，每次重新入会重新生成。
  final String sessionId;

  /// 当前 SDK 登录账号。
  final String selfId;

  /// 经 SDK 初始邀请人或可信交接确认的主持人。
  final String hostId;

  /// 未同步策略时禁止自行打开设备，也不能执行主持操作。
  final bool policyKnown;

  /// 当前主持策略版本，确认弹窗返回后应复核此版本。
  final int version;

  /// 自行开启麦克风权限，不代表当前麦克风已开。
  final bool allowSelfUnmute;

  /// 自行开启摄像头权限，不代表当前摄像头已开。
  final bool allowVideo;

  /// 当前全员静音策略，决定新入会默认麦克风状态。
  final bool muteAll;

  /// 当前全员关闭摄像头策略，决定新入会默认摄像头状态。
  final bool cameraAllClosed;

  /// 本端麦克风与摄像头按钮各自使用的状态。
  final bool microphoneOn, cameraOn;

  /// 可信主持首次接通的统一 UTC 毫秒起点，未知策略时可以为空。
  final int? connectedAtMs;

  /// 所有同场成员继承的绝对截止点，迟到入会与主持交接不得延长。
  final int? deadlineMs;

  /// 用户各设备独立等待确认，集合内的 null 表示策略或主持交接。
  final Map<String, Set<GroupControlDevice?>> pendingByUserId;

  /// 最近操作的逐目标结果，发送成功不能提前写 success。
  final Map<String, GroupControlOutcome> resultsByUserId;

  /// 每个用户和设备各自的最近结果，用于对应设备的状态提示。
  final Map<(String, GroupControlDevice), GroupControlOutcome> resultsByDevice;

  /// 通用策略进度不会让无关的设备按钮一并转圈。
  bool isDevicePending(String userId, GroupControlDevice device) =>
      pendingByUserId[userId]?.contains(device) == true;

  /// 主持权必须已由可信消息确认，未知策略阶段没有管理权限。
  bool get canManage => policyKnown && hostId == selfId;

  /// 主持可自行开启；普通成员只能在已同步的允许策略下开启。
  bool get canOpenMicrophone => policyKnown && (canManage || allowSelfUnmute);

  /// 摄像头权限与设备实际状态分离，UI 应另读 cameraOn。
  bool get canOpenCamera => policyKnown && (canManage || allowVideo);
}
