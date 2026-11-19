import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:tencent_calls_uikit/src/tui_call_kit_impl.dart';
import 'bridge/bootloader/bootloader.dart';
import 'control/group_control_transport.dart';
import 'manager/group_call_result_tracker.dart' show GroupCallResultHandler;
import 'manager/group_call_recording.dart' show GroupCallRecordingHandler;
import 'state/group_call_metadata.dart' show GroupCallStartedHandler;

export 'manager/group_call_recording.dart' show GroupCallRecordingHandler;

/// 宿主选人入口；groupId 为空表示独立多人，excludedUserIds 含已占名额成员和本人。
typedef GroupMemberPicker = Future<List<String>?> Function(BuildContext context,
    String? groupId, Set<String> excludedUserIds, int maxInvitees);

/// 宿主按当前登录账号查询真实机构岗位副标题；返回键必须是请求中的腾讯用户 ID。
typedef GroupMemberSubtitleLoader = Future<Map<String, String>> Function(
    String accountId, List<String> userIds);

/// 向宿主提供通话及外观接入点，媒体和信令由腾讯 SDK 管理。
abstract class TUICallKit {
  static final TUICallKit _instance = TUICallKitImpl.instance;
  static TUICallKit get instance => _instance;

  /// 鸿蒙由原生 CallKit 持有通话状态，通话页面使用原生窗口或鸿蒙展示层。
  static bool get usesNativeHarmonyCallKit =>
      Platform.operatingSystem == 'ohos';

  /// 鸿蒙无需启动 Android 和 iOS 使用的 Flutter 通话路由监听。
  static NavigatorObserver navigatorObserver = usesNativeHarmonyCallKit
      ? NavigatorObserver()
      : Bootloader.instance;

  /// login TUICallKit
  ///
  /// @param sdkAppId      sdkAppId
  /// @param userId        userId
  /// @param userSig       userSig
  ///
  /// 登录 TUICallKit
  ///
  /// @param sdkAppId sdkAppId @param userId 用户ID @param userSig 用户签名
  Future<CompletionHandler> login(
    int sdkAppId,
    String userId,
    String userSig,
  ) async {
    // TODO: implement login
    //
    // TODO：实现登录
    throw UnimplementedError();
  }

  /// logout TUICallKit
  ///
  ///
  /// 登出 TUICallKit
  Future<void> logout() async {
    // TODO: implement logout
    //
    // TODO：实现登出
    throw UnimplementedError();
  }

  /// Set user profile
  ///
  /// @param nickname User name, which can contain up to 500 bytes
  /// @param avatar   User profile photo URL, which can contain up to 500 bytes
  ///                 For example: https://liteav.sdk.qcloud.com/app/res/picture/voiceroom/avatar/user_avatar1.png
  /// @param callback Set the result callback
  ///
  /// 设置用户资料
  ///
  /// @param nickname 用户名，最多可包含500字节 @param avatar 用户头像URL，最多可包含500字节
  ///
  /// @param callback 设置结果回调
  Future<CompletionHandler> setSelfInfo(String nickname, String avatar) async {
    // TODO: implement setSelfInfo
    //
    // TODO: 实现 setSelfInfo
    throw UnimplementedError();
  }

  /// Make a call
  ///
  /// @param userIdList    List of userId
  /// @param callMediaType Call type
  /// @param params        Call extension parameters
  ///
  /// 发起通话
  ///
  /// @param userIdList 用户ID列表 @param callMediaType 通话类型 @param params 通话扩展参数
  Future<CompletionHandler> calls(
    List<String> userIdList,
    CallMediaType callMediaType, [
    CallParams? params,
  ]) async {
    // TODO: implement calls
    //
    // TODO: 实现 calls
    throw UnimplementedError();
  }

  /// 使用服务端分配的 [callId] 加入当前通话。
  /// 鸿蒙群入口可传 [mediaType]，以便在加入前申请对应设备权限。
  Future<void> join(String callId, {CallMediaType? mediaType});

  /// Set the ringtone (preferably shorter than 30s)
  ///
  /// First introduce the ringtone resource into the project
  /// Then set the resource as a ringtone
  ///
  /// @param filePath Callee ringtone path
  ///
  /// 设置铃声（最好不超过30秒）
  ///
  /// 先将铃声资源导入项目，然后将该资源设置为铃声
  ///
  /// @param filePath 被叫铃声路径
  Future<void> setCallingBell(String assetName) async {
    // TODO: implement setCallingBell
    //
    // TODO: 实现 setCallingBell
    throw UnimplementedError();
  }

  ///Enable the mute mode (the callee doesn't ring)
  ///
  /// 启用静音模式（被叫不响铃）
  Future<void> enableMuteMode(bool enable) async {
    // TODO: implement enableMuteMode
    //
    // TODO: 实现 enableMuteMode
    throw UnimplementedError();
  }

  ///Enable the floating window
  ///
  /// 启用悬浮窗口
  Future<void> enableFloatWindow(bool enable) async {
    // TODO: implement enableFloatWindow
    //
    // 待办：实现 enableFloatWindow
    throw UnimplementedError();
  }

  Future<void> enableVirtualBackground(bool enable) async {
    // TODO: implement enableVirtualBackground
    //
    // 待办：实现 enableVirtualBackground
    throw UnimplementedError();
  }

  /// Enable AI Transcriber
  ///
  /// 启用 AI 转录功能
  Future<void> enableAITranscriber(bool enable) async {
    // TODO: implement enableAITranscriber
    //
    // 待办：实现 enableAITranscriber
    throw UnimplementedError();
  }

  void enableIncomingBanner(bool enable);

  /// 注册群与独立多人通话的追加选人入口；返回 null 表示取消。
  void setGroupMemberPicker(GroupMemberPicker? picker);

  /// 注册只读成员资料来源；传 null 清除已缓存的机构岗位，不影响邀请或会控权限。
  void setGroupMemberSubtitleLoader(GroupMemberSubtitleLoader? loader);

  /// 注册已登录 IM 的在线会控通道；null 立即撤销旧 session 并清理待执行命令。
  void setGroupControlTransport(GroupControlTransport? transport);

  /// IM 重连成功后请求当前策略，不从聊天历史重放旧设备命令。
  void syncGroupControlPolicy();

  /// 注册本人通话结果发布器，发送失败传播为记录失败，不影响 SDK 媒体清理。
  void setGroupCallResultHandler(GroupCallResultHandler? handler);

  /// 注册群通话和临时多人发起通知发布器，随宿主登录装配和清除。
  void setGroupCallStartedHandler(GroupCallStartedHandler? handler);

  /// 绑定已登录宿主的云端录制时间接口，传 null 禁用入口并清理本端片段状态。
  void setGroupCallRecordingHandler(GroupCallRecordingHandler? handler);

  /// 当前已由 SDK 确认接通的 OA 群或多人呼叫，用于更新原发起气泡。
  ValueListenable<String?> get acceptedCallAttempt;

  /// 设置已由宿主读取的群名称，供群通话标题展示。
  void setGroupCallTitle(String groupId, String title);

  /// Call experimental interface
  ///
  /// @param jsonObject
  ///
  /// 调用实验接口
  Future<void> callExperimentalAPI(String json) async {
    // TODO: implement callExperimentalAPI
    //
    // 待办：实现 callExperimentalAPI
    throw UnimplementedError();
  }
}
