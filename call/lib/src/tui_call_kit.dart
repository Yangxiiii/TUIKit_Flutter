import 'package:flutter/cupertino.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:tencent_calls_uikit/src/tui_call_kit_impl.dart';
import 'bridge/bootloader/bootloader.dart';

abstract class TUICallKit {
  static final TUICallKit _instance = TUICallKitImpl.instance;
  static TUICallKit get instance => _instance;
  static NavigatorObserver navigatorObserver = Bootloader.instance;

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

  /// Join a current call
  ///
  /// @param callId        Unique ID for this call
  ///
  /// 加入当前通话
  ///
  /// @param callId 本次通话的唯一ID
  Future<void> join(String callId) async {
    // TODO: implement join
    //
    // TODO: 实现 join
    throw UnimplementedError();
  }

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
