import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuikit_atomic_x/atomicx.dart';

/// 提供不可通过公开构造函数创建的 SDK 通话资料，仅用于边界测试。
class FakeCallInfo extends Fake implements CallInfo {
  FakeCallInfo(
      {this.callId = '',
      this.mediaType,
      this.inviterId = 'self',
      this.chatGroupId = '',
      this.inviteeIds = const [],
      this.startTime = 0});

  /// 本测试场次的 SDK 标识。
  @override
  final String callId;

  /// 空类型表示没有有效通话。
  @override
  final CallMediaType? mediaType;

  /// 测试主叫身份。
  @override
  final String inviterId;

  /// 测试群来源，空值表示临时多人。
  @override
  final String chatGroupId;

  /// 初始受邀人员。
  @override
  final List<String> inviteeIds;

  /// SDK 接通时间，零表示尚未接通。
  @override
  final int startTime;
}

/// 模拟成员真实状态，不构造任何原生媒体资源。
class FakeParticipant extends Fake implements CallParticipantInfo {
  FakeParticipant(this.id,
      {this.status = CallParticipantStatus.waiting,
      this.name = '',
      this.avatarURL = '',
      this.isMicrophoneOpened = false,
      this.isCameraOpened = false});

  /// 测试成员标识。
  @override
  final String id;

  /// SDK 等待或已接通状态。
  @override
  final CallParticipantStatus status;

  /// 用于验证移除成员后仍保留显示资料。
  @override
  final String name;

  /// 用于验证头像资料补齐。
  @override
  final String avatarURL;

  /// 模拟 SDK available 事件，仅测试主动更新该字段时才改变设备事实。
  @override
  final bool isMicrophoneOpened, isCameraOpened;
}

/// 可通知的 SDK 状态替身，用于权限等待期间改变场次。
class FakeCallState extends Fake implements CallState {
  /// 当前测试场次。
  @override
  final ValueNotifier<CallInfo> activeCall =
      ValueNotifier<CallInfo>(FakeCallInfo());

  /// 当前账号的入会状态。
  @override
  final ValueNotifier<CallParticipantInfo> selfInfo =
      ValueNotifier<CallParticipantInfo>(
          FakeParticipant('self', status: CallParticipantStatus.none));

  /// 实时成员列表，不含已经移出的拒绝和超时成员。
  @override
  final ValueNotifier<List<CallParticipantInfo>> allParticipants =
      ValueNotifier<List<CallParticipantInfo>>([]);
}

/// 仅记录经过校验的 SDK 请求，并允许延迟或抛错验证调用者恢复行为。
class FakeCallStore extends Fake implements CallStore {
  /// 由每个测试独立控制的 SDK 当前状态。
  @override
  final FakeCallState state = FakeCallState();

  /// 所有实际发出的发起请求。
  final List<List<String>> starts = [];

  /// 所有实际发出的追加邀请。
  final List<List<String>> invitations = [];

  /// 所有实际发出的加入请求。
  final List<String> joins = [];

  /// 记录真实发送到替身的结束动作，验证迟到交接不会误挂新通话。
  int hangups = 0;

  /// SDK 收到的最新参数，验证调用方参数未被改写。
  CallParams? lastParams;

  /// 测试选择延迟完成或抛出异常。
  Future<CompletionHandler> Function()? operation;

  @override
  Future<CompletionHandler> calls(
      List<String> ids, CallMediaType mediaType, CallParams? params) {
    starts.add(ids);
    lastParams = params;
    return operation?.call() ?? Future.value(CompletionHandler());
  }

  @override
  Future<CompletionHandler> invite(List<String> ids, CallParams? params) {
    invitations.add(ids);
    return operation?.call() ?? Future.value(CompletionHandler());
  }

  @override
  Future<CompletionHandler> join(String callId) {
    joins.add(callId);
    return operation?.call() ?? Future.value(CompletionHandler());
  }

  @override
  Future<CompletionHandler> hangup() {
    hangups++;
    return operation?.call() ?? Future.value(CompletionHandler());
  }
}
