import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_calls_uikit/src/control/group_control_media.dart';
import 'package:tencent_calls_uikit/src/control/group_control_transport.dart';
import 'package:tencent_calls_uikit/src/manager/group_control_controller.dart';
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_member.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_presentation.dart';

/// 离线管理预览运行正式会控控制器，只有传输和设备是内存替身，不登录腾讯。
class GroupControlPreviewSession extends ChangeNotifier {
  GroupControlPreviewSession(List<GroupCallMember> members) {
    _members = members;
    final joined = members
        .where((member) => member.joined)
        .map((member) => member.id)
        .toList();
    for (final id in joined) {
      final device = _PreviewMedia();
      _media[id] = device;
      final control = GroupControlController(
          callId: 'offline-call',
          selfId: id,
          inviterId: 'self',
          groupId: 'offline-group',
          video: true,
          transport: _PreviewTransport(id, _streams),
          media: device,
          guard: ActionGuard(),
          newId: () => '$id-${++_serial}');
      _controls[id] = control;
      control.updateMembers(joined);
      control.addListener(_changed);
    }
  }

  /// 主持人的当前真实控制器状态；仅用于离线样例，不写入 GlobalState。
  GroupControlController get host => _controls['self']!;

  /// 本预览交互按入会和动作合并，不与生产导航守卫混用。
  final ActionGuard guard = ActionGuard();

  /// 已销毁预览不得再修改草稿或响应迟到回执。
  bool _disposed = false;

  /// 离线入会及命令仍使用唯一标识，禁止不同替身复用同一session或命令。
  int _serial = 0;
  /// 保留固定邀请资料；设备值在读取时由各参与者执行结果补充。
  late final List<GroupCallMember> _members;
  /// 正式控制器和替身媒体按参与者对应，销毁时一并清理。
  final Map<String, GroupControlController> _controls = {};
  final Map<String, _PreviewMedia> _media = {};
  /// 端点流只属于本次离线预览，不接入真实账号或聊天消息监听。
  final Map<String, StreamController<GroupControlInbound>> _streams = {};

  /// 三端先完成同场入会同步，后续操作增加延迟供检查等待状态。
  Future<void> start() async {
    for (final control in _controls.values) {
      if (_disposed) return;
      await control.start();
    }
    await Future<void>.delayed(Duration.zero);
    if (_disposed) return;
    for (final media in _media.values) {
      media.delay = const Duration(milliseconds: 350);
    }
    notifyListeners();
  }

  /// 头像资料沿用夹具，已加入成员的开关只读取各自替身设备经过控制器后的结果。
  List<GroupCallMember> get members => _members.map((member) {
        final media = _media[member.id];
        return GroupCallMember(
            id: member.id,
            name: member.name,
            avatarUrl: member.avatarUrl,
            subtitle: member.subtitle,
            status: member.status,
            joinedOrder: member.joinedOrder,
            microphoneOn: media?.microphoneOn ?? member.microphoneOn,
            cameraOn: media?.cameraOn ?? member.cameraOn,
            volume: member.volume);
      }).toList();

  /// 使用与生产相同的确认边界，返回控制器逐成员结果而不是发送结果。
  Future<bool> execute(String key, GroupControlState expected,
          Future<GroupControlResult> Function() operation) =>
      guard.singleFlight<bool>(('offline.control', key, expected.sessionId),
          () async {
        if (!isCurrentGroupControlOperation(
            expected: expected,
            current: host.value,
            presentationIsCurrent: !_disposed)) {
          return false;
        }
        final result = await operation();
        return !_disposed && result.success;
      });

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final control in _controls.values) {
      control.removeListener(_changed);
      control.dispose();
    }
    for (final stream in _streams.values) {
      unawaited(stream.close());
    }
    for (final media in _media.values) {
      media.dispose();
    }
    super.dispose();
  }
}

/// 定向传输只连接当前预览中的控制器，发送者来自本地端点而非消息正文。
class _PreviewTransport implements GroupControlTransport {
  _PreviewTransport(this._selfId, this._streams) {
    _streams.putIfAbsent(_selfId, () => StreamController.broadcast(sync: true));
  }
  /// 发送者绑定于端点，不能被消息正文里的身份字段替换。
  final String _selfId;
  final Map<String, StreamController<GroupControlInbound>> _streams;
  @override
  Stream<GroupControlInbound> get messages => _streams[_selfId]!.stream;
  @override
  Future<void> send(String targetUserId, String payload) async {
    final stream = _streams[targetUserId];
    if (stream == null || stream.isClosed) return;
    stream.add(GroupControlInbound(senderId: _selfId, payload: payload));
  }

  @override
  Future<Set<String>> loadAdministrators(
          String groupId, List<String> memberIds) async =>
      {};
}

/// 不访问原生摄像头或麦克风；延迟结束后才发布替身设备状态并供正式控制器生成 ACK。
class _PreviewMedia extends ChangeNotifier implements GroupControlMedia {
  /// 初始同步不延迟，完成后使用350毫秒显示真实控制器的在途状态。
  Duration delay = Duration.zero;

  /// 替身设备只有执行结束才更新状态，不以控制消息送达提前翻转。
  bool _microphone = false, _camera = false;
  @override
  Listenable get changes => this;
  @override
  bool get microphoneOn => _microphone;
  @override
  bool get cameraOn => _camera;
  @override
  Future<GroupControlOutcome> setDevice(GroupControlDevice device, bool enabled,
      {required bool Function() isCurrent}) async {
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    if (!isCurrent()) {
      return const GroupControlOutcome(GroupControlStatus.expired);
    }
    if (device == GroupControlDevice.microphone) {
      _microphone = enabled;
    } else {
      _camera = enabled;
    }
    notifyListeners();
    return GroupControlOutcome(GroupControlStatus.success,
        microphoneOn: _microphone, cameraOn: _camera);
  }
}
