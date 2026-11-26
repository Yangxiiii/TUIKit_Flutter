import 'dart:async';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/foundation.dart';

import '../tui_call_kit.dart' show GroupMemberSubtitleLoader;

/// 保存单聊对端的组织副标题，横幅与全屏共用一次资料查询。
final class CallPeerOrganization extends ValueNotifier<String> {
  CallPeerOrganization() : super('');

  /// 宿主更换资料来源后，旧查询不能再写回。
  GroupMemberSubtitleLoader? _loader;

  /// 同一账号、通话及对端只查询一次，包括没有组织资料的结果。
  ({String account, String callId, String userId})? _scope;

  /// 清理或换场后使仍在途的查询失效。
  int _generation = 0;

  /// 注册宿主资料来源并清除以前的展示结果。
  void setLoader(GroupMemberSubtitleLoader? loader) {
    if (identical(_loader, loader)) return;
    _loader = loader;
    clear();
  }

  /// 只向属于当前通话及对端的界面交付副标题。
  String forPeer(String callId, String userId) =>
      _scope?.callId == callId && _scope?.userId == userId ? value : '';

  /// 单聊主叫展示唯一受邀者，被叫展示发起人，两端按同一个人查询和绑定资料。
  static String peerId(CallInfo call, String selfId) => call.inviterId == selfId
      ? call.inviteeIds.firstOrNull ?? ''
      : call.inviterId;

  /// 对端身份明确后独立加载资料；主叫振铃期间 SDK 可能尚未分配通话 ID。
  void refresh(String account, String callId, String userId) {
    final loader = _loader;
    if (loader == null ||
        account.isEmpty ||
        userId.isEmpty ||
        userId == account) {
      clear();
      return;
    }
    final scope = (account: account, callId: callId, userId: userId);
    final previous = _scope;
    if (previous == scope) return;
    if (previous != null &&
        previous.account == account &&
        previous.userId == userId &&
        previous.callId.isEmpty) {
      // 同一次主叫等待分配 ID，沿用已开始的请求及当前资料。
      _scope = scope;
      return;
    }
    clear();
    _scope = scope;
    unawaited(_load(loader, scope, _generation));
  }

  /// 只接收本次查询的用户字段，失败时保持副标题为空。
  Future<void> _load(
    GroupMemberSubtitleLoader loader,
    ({String account, String callId, String userId}) scope,
    int generation,
  ) async {
    try {
      final result = await loader(scope.account, [scope.userId]);
      if (generation == _generation) {
        value = result[scope.userId]?.trim() ?? '';
      }
    } on Object {
      // 组织资料属于辅助展示，查询失败仍保留原通话界面。
    }
  }

  /// 清除当前对端并使在途资料失效，保留宿主的数据来源。
  void clear() {
    if (_scope == null) return;
    _generation++;
    _scope = null;
    value = '';
  }
}
