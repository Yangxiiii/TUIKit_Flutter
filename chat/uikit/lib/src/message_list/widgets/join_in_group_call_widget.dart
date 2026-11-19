import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/utils/tui_event_bus.dart';

/// 按群通话横幅展示真实参与者与加入状态，不发起新场次或修改群属性。
class JoinInGroupCallWidget extends StatefulWidget {
  const JoinInGroupCallWidget({
    required this.userIDs,
    required this.mediaType,
    required this.groupId,
    required this.callId,
    this.callStore,
    this.loginStore,
    this.memberNameLoader,
    super.key,
  });

  /// 群属性确认的去重参与者，顺序由腾讯数据决定。
  final List<String> userIDs;

  /// 当前通话的真实媒体类型，决定语音或视频文案。
  final CallMediaType mediaType;

  /// 用于查询参与者显示资料的群 ID。
  final String groupId;

  /// 传入既有加入事件链的真实场次 ID。
  final String callId;

  /// Flutter 通话默认使用共享 Store，宿主或测试可注入相同公开状态契约。
  final CallStore? callStore;

  /// 当前账号来源；与通话状态一起监听，退出或切换账号后立即收起旧横幅。
  final LoginStore? loginStore;

  /// 可复用宿主的成员资料缓存；未提供时查询腾讯群成员资料。
  final Future<String?> Function(String groupId, String userId)?
      memberNameLoader;

  @override
  State<JoinInGroupCallWidget> createState() => _JoinInGroupCallWidgetState();
}

/// 订阅本端场次与成员状态；异步姓名只应用于仍匹配的群、场次和成员。
class _JoinInGroupCallWidgetState extends State<JoinInGroupCallWidget> {
  /// 姓名加载失败时仍使用真实用户 ID，不编造发起人身份。
  String? _memberName;

  /// 区分快速切换群或场次后的迟到资料结果。
  int _nameGeneration = 0;

  /// 鸿蒙由原生通话引擎维护场次，横幅仅使用群属性确认加入资格。
  CallStore? get _store => widget.callStore ??
      (defaultTargetPlatform == TargetPlatform.ohos ? null : CallStore.shared);
  LoginStore get _loginStore => widget.loginStore ?? LoginStore.shared;

  /// 同场恢复只接受当前账号仍在等待或已接通，结束后残留的场次 ID 不授予资格。
  bool get _sameLiveCall {
    final store = _store;
    if (store == null) return false;
    final self = store.state.selfInfo.value;
    final account = _loginStore.loginState.loginUserInfo?.userID;
    return account?.isNotEmpty == true &&
        self.id == account &&
        store.state.activeCall.value.callId == widget.callId &&
        self.status != CallParticipantStatus.none;
  }

  /// 群属性只证明当前参与者；没有本端同场证据的其他群成员不开放加入入口。
  /// 拒绝或退出后的受邀历史没有可靠来源，本轮不根据群成员身份推断恢复资格。
  bool get _canDisplay {
    final login = _loginStore.loginState;
    final account = login.loginUserInfo?.userID;
    return login.loginStatus == LoginStatus.logined &&
        account?.isNotEmpty == true &&
        (widget.userIDs.contains(account) || _sameLiveCall);
  }

  @override
  void initState() {
    super.initState();
    _loadMemberName();
  }

  @override
  void didUpdateWidget(covariant JoinInGroupCallWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId ||
        oldWidget.callId != widget.callId ||
        oldWidget.userIDs.firstOrNull != widget.userIDs.firstOrNull ||
        oldWidget.memberNameLoader != widget.memberNameLoader) {
      _memberName = null;
      _loadMemberName();
    }
  }

  /// 仅查询首个真实参与者的名称；其他参与者由人数表达，不再加载头像列表。
  Future<void> _loadMemberName() async {
    final generation = ++_nameGeneration;
    final userId = widget.userIDs.firstOrNull;
    if (userId == null) return;
    try {
      // 查询只携带当前群及目标成员，返回后再核对本次请求代次。
      final name = await (widget.memberNameLoader ?? _queryMemberName)(
          widget.groupId, userId);
      if (!mounted || generation != _nameGeneration) return;
      setState(
          () => _memberName = name?.trim().isNotEmpty == true ? name : null);
    } on Object {
      // 资料失败只影响名称，不把仍有效的 callId 或当前加入状态抹掉。
      if (mounted && generation == _nameGeneration) {
        setState(() => _memberName = null);
      }
    }
  }

  /// 使用 SDK 的公开群成员查询，返回同一个目标用户的群名片、备注或昵称。
  Future<String?> _queryMemberName(String groupId, String userId) async {
    final result = await GroupMemberStore.create(groupID: groupId)
        .getMemberInfo(userIDList: [userId]);
    if (!result.isSuccess) return null;
    final member = result.memberInfoList
        .where((item) => item.userID == userId)
        .firstOrNull;
    return [member?.nameCard, member?.friendRemark, member?.nickname]
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return ListenableBuilder(
      listenable: Listenable.merge([
        if (store != null) ...[store.state.activeCall, store.state.selfInfo],
        _loginStore,
      ]),
      builder: (context, _) {
        if (widget.callId.isEmpty || widget.userIDs.length < 2 || !_canDisplay) {
          return const SizedBox.shrink();
        }
        // 只凭本端 SDK 已接通状态显示“已加入”，不能凭群属性里存在本人推断。
        final joined = _sameLiveCall &&
            store?.state.selfInfo.value.status == CallParticipantStatus.accept;
        return _banner(context, joined);
      },
    );
  }

  /// 固定单行横幅只展示通话摘要与加入动作，超长姓名不挤压操作按钮。
  Widget _banner(BuildContext context, bool joined) {
    final colors = context.appColors;
    final name = _memberName ?? widget.userIDs.first;
    final people =
        widget.userIDs.length > 1 ? '$name等${widget.userIDs.length}人' : name;
    final media = widget.mediaType == CallMediaType.audio ? '语音' : '视频';
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: colors.scrim.withValues(alpha: .2),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        // 固定通话图标与右侧按钮优先保留宽度，长名称只在正文区域省略。
        Icon(AppIcons.phone3, size: 24, color: colors.success),
        const SizedBox(width: 8),
        // 姓名与媒体独立绑定，人数来自已去重的腾讯群属性。
        Expanded(
            child: Text('$people正在$media通话',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14, height: 20 / 14, color: colors.textPrimary))),
        const SizedBox(width: 8),
        // 已加入仍可恢复通话，不作为禁用按钮处理。
        Semantics(
          identifier: 'tim.groupCallBanner.action',
          label: joined ? '已加入，返回通话' : '立即加入通话',
          child: joined
              ? TextButton(
                  onPressed: _join,
                  style: TextButton.styleFrom(
                      foregroundColor: colors.textSecondary),
                  child: const Text('已加入'))
              : FilledButton(
                  onPressed: _join,
                  style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      minimumSize: const Size(64, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                      textStyle: const TextStyle(fontSize: 12)),
                  child: const Text('立即加入')),
        ),
      ]),
    );
  }

  /// 沿用既有事件入口；生命周期层决定加入新场次或恢复同场的通话浮层。
  void _join() {
    // 账号或 SDK 状态可能先于重绘变化，点击时也不能使用上一帧的加入资格。
    if (!_canDisplay) return;
    final params = PublishParams()..isSticky = false;
    // 媒体沿用已验证的群属性枚举，原生入口据此申请麦克风或摄像头权限。
    params.data = {'callId': widget.callId, 'mediaType': widget.mediaType};
    TUIEventBus.shared.publish('call.startJoin', null, params);
  }
}
