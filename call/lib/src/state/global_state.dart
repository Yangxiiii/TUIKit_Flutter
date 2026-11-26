import 'package:flutter/foundation.dart';
import '../tui_call_kit.dart' show GroupMemberPicker;
import 'group_call_snapshot.dart';
import 'group_control_state.dart';
import '../manager/call_peer_organization.dart';
import '../manager/group_control_controller.dart';
import '../manager/group_call_recording.dart';

export 'group_call_snapshot.dart';

/// 保存通话组件配置及仅供展示的群通话结果，SDK 仍负责有效会话。
class GlobalState {
  static GlobalState instance = GlobalState._internal();
  GlobalState._internal();

  /// 来电铃声静音配置，不代表成员麦克风权限。
  bool _enableMuteMode = false;

  /// 是否提供应用内浮窗入口。
  bool _enableFloatWindow = false;

  /// 本地视频背景模糊偏好。
  bool _enableBlurBackground = false;

  /// 所有待接听来电是否优先使用顶部横幅，包含群及临时多人。
  bool _enableIncomingBanner = false;

  /// 本地转写开关，独立于群云端录制能力。
  bool _enableAITranscriber = false;

  /// 宿主指定的来电铃声音频资源。
  String? _callingBellAssetName;

  /// 宿主的组织/群成员选人入口；未配置时仅群来源使用 SDK 默认选人。
  GroupMemberPicker? groupMemberPicker;

  /// 当前宿主提供的群标题，随账号退出清理，不作为群权限依据。
  final Map<String, String> _groupTitles = {};

  /// 仅保留当前群场次的显示状态，由 CallKit 监听真实 SDK 事件更新。
  final GroupCallSession groupCallSession = GroupCallSession();

  /// 单聊来电横幅与全屏共享当前对端的机构岗位。
  final CallPeerOrganization callPeerOrganization = CallPeerOrganization();

  /// 云端录制片段随 SDK 通话生命周期收尾，浮窗和全屏共享。
  final groupCallRecording = GroupCallRecording();

  /// 本次真实入会的会控入口，SDK 生命周期层创建/清理，UI 不另存主持权限。
  GroupControlController? groupControlController;

  /// 通知设备初始化本端预览句柄已就绪，随视图销毁或退出账号清除。
  final groupLocalVideoView =
      ValueNotifier<({String callId, String userId, int viewId})?>(null);

  /// 全局只读会控展示出口，未知或退出状态为空。
  final ValueNotifier<GroupControlState?> _groupControl = ValueNotifier(null);

  /// 仅订阅控制器投影，页面不能通过此出口自行写入主持权或设备结果。
  ValueListenable<GroupControlState?> get groupControl => _groupControl;

  /// 生命周期层投影控制器状态，不允许外部改写设备或主持状态。
  void setGroupControlState(GroupControlState? state) =>
      _groupControl.value = state;

  /// UI 观察邀请结果及已结束的重呼提示，不用此值判断 SDK 忙线。
  ValueListenable<GroupCallSnapshot?> get groupCall => groupCallSession;

  /// 绑定宿主已读取的群标题，不在 SDK 包内查询企业业务接口。
  void setGroupCallTitle(String groupId, String title) {
    if (groupId.isEmpty) return;
    _groupTitles[groupId] = title;
    groupCallSession.updateGroupTitle(groupId, title);
  }

  /// 找不到群标题时返回空值，由界面使用通话类型文案。
  String groupCallTitle(String groupId) => _groupTitles[groupId] ?? '';

  /// 退出账号后清理群资料和展示结果，保留宿主提供的选人能力。
  void clearGroupCall() {
    groupLocalVideoView.value = null;
    _groupTitles.clear();
    groupCallSession.clear();
  }

  bool get enableMuteMode => _enableMuteMode;
  bool get enableFloatWindow => _enableFloatWindow;
  bool get enableBlurBackground => _enableBlurBackground;
  bool get enableIncomingBanner => _enableIncomingBanner;
  bool get enableAITranscriber => _enableAITranscriber;
  String? get callingBellAssetName => _callingBellAssetName;

  void setEnableMuteMode(bool enable) {
    _enableMuteMode = enable;
  }

  void setEnableFloatWindow(bool enable) {
    _enableFloatWindow = enable;
  }

  void setEnableBlurBackground(bool enable) {
    _enableBlurBackground = enable;
  }

  void setEnableIncomingBanner(bool enable) {
    _enableIncomingBanner = enable;
  }

  void setEnableAITranscriber(bool enable) {
    _enableAITranscriber = enable;
  }

  void setCallingBellAssetName(String assetName) {
    _callingBellAssetName = assetName;
  }
}
