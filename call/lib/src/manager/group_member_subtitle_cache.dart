import 'dart:async';

import 'package:flutter/foundation.dart';

import '../state/group_call_snapshot.dart';
import '../tui_call_kit.dart' show GroupMemberSubtitleLoader;

/// 按账号和展示场次加载宿主成员资料，只更新只读快照，不参与媒体或信令。
class GroupMemberSubtitleCache {
  GroupMemberSubtitleCache(
      {required GroupCallSession session, required String Function() accountId})
      : _session = session,
        _accountId = accountId {
    _session.addListener(refresh);
  }

  /// 只订阅本场展示事实，不读取或修改原生媒体状态。
  final GroupCallSession _session;

  /// 每次请求及返回时读取当前账号，避免捕获已经失效的登录值。
  final String Function() _accountId;

  /// 宿主可替换或注销查询器；旧查询器的迟到结果不能覆盖新资料来源。
  GroupMemberSubtitleLoader? _loader;

  /// 缓存只属于当前登录账号及展示代次，不跨新场次保留企业人员资料。
  String _scopeAccount = '';

  /// 对应 GroupCallSession 的生命周期，独立于尚未分配的 SDK callId。
  int _scopeGeneration = -1;

  /// 完整成员集合用于合并重复通知；失败后同一集合不随每秒通话刷新反复请求。
  Set<String>? _requestedMembers;

  /// 已成功查询过的成员包括无资料结果；同场追加邀请只请求尚未查询的 ID。
  final Set<String> _resolvedIds = {};

  /// 换账号、换场次、换成员集合及注销查询器都会使旧异步结果失效。
  int _requestGeneration = 0;

  /// 组件实例释放后不再接收快照通知或应用宿主返回值。
  bool _disposed = false;

  /// 更换宿主数据来源即清理旧副标题；新查询从当前有效场次重新开始。
  void setLoader(GroupMemberSubtitleLoader? loader) {
    if (identical(loader, _loader)) return;
    _loader = loader;
    clear();
    _session.updateMemberSubtitles(const {});
    refresh();
  }

  /// 场次和账号不匹配时丢弃缓存，同一集合只查询一次，避免 SDK 高频通知触发网络风暴。
  void refresh() {
    if (_disposed) return;
    final snapshot = _session.value;
    final account = _accountId();
    final generation = _session.generation;
    if (snapshot == null ||
        snapshot.ended ||
        account.isEmpty ||
        _loader == null) {
      clear();
      if (account.isEmpty) _session.updateMemberSubtitles(const {});
      return;
    }
    // 空 callId 到 SDK 正式标识属于同一展示代次，不能因此重查或误丢资料。
    if (_scopeAccount != account || _scopeGeneration != generation) {
      clear();
      _scopeAccount = account;
      _scopeGeneration = generation;
      if (snapshot.subtitleById.isNotEmpty) {
        // 即使宿主尚未清空旧场次，切号也先移除旧账号资料；通知会重新进入加载。
        _session.updateMemberSubtitles(const {});
        return;
      }
    }
    final members = snapshot.members.map((member) => member.id).toSet();
    if (setEquals(members, _requestedMembers)) return;
    _requestedMembers = members;
    final request = ++_requestGeneration;
    final missing = members.difference(_resolvedIds);
    if (missing.isEmpty) return;
    unawaited(_load(_loader!, account, generation, request, members,
        List.unmodifiable(missing)));
  }

  /// 资料返回后复核账号、场次和完整成员集；额外返回的用户不能写入展示缓存。
  Future<void> _load(
      GroupMemberSubtitleLoader loader,
      String account,
      int generation,
      int request,
      Set<String> members,
      List<String> ids) async {
    try {
      final result = await loader(account, ids);
      final current = _session.value;
      if (_disposed ||
          request != _requestGeneration ||
          account != _accountId() ||
          generation != _session.generation ||
          current == null ||
          current.ended ||
          !identical(loader, _loader) ||
          !setEquals(
              members, current.members.map((member) => member.id).toSet())) {
        return;
      }
      // 只接受本次请求中的真实资料，并保留同场此前成功加载的成员资料。
      _resolvedIds.addAll(ids);
      _session.updateMemberSubtitles({
        ...current.subtitleById,
        for (final id in ids)
          if (result[id]?.trim().isNotEmpty == true) id: result[id]!,
      });
    } catch (_) {
      // 资料失败不影响通话，也不编造机构；成员集合改变或重新注册后才重试。
    }
  }

  /// 清理仅限缓存及未完成查询，宿主查询器可在下一登录账号继续复用。
  void clear() {
    _requestGeneration++;
    _scopeAccount = '';
    _scopeGeneration = -1;
    _requestedMembers = null;
    _resolvedIds.clear();
  }

  /// 生命周期结束时取消监听并使仍在执行的宿主请求失效。
  void dispose() {
    _disposed = true;
    _session.removeListener(refresh);
    clear();
  }
}
