import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tencent_calls_uikit/src/tui_call_kit_impl.dart';
import 'package:tencent_calls_uikit/tencent_calls_uikit.dart';
import 'call_kit_platform_interface.dart';

/// 在 Flutter 和原生插件之间转发通话平台事件。
class MethodChannelTUICallKit extends TUICallKitPlatform {
  /// 通话插件使用的通道，负责转发 Android 初始化和平台通话事件。
  final methodChannel = const MethodChannel('tencent_calls_uikit');
  MethodChannelTUICallKit() {
    methodChannel.setMethodCallHandler((call) async {
      _handleNativeCall(call);
    });
  }

  @override
  void startVibration() {
    if (kIsWeb) return;
    methodChannel.invokeMethod('startVibration', {});
  }

  @override
  void stopVibration() {
    if (kIsWeb) return;
    methodChannel.invokeMethod('stopVibration', {});
  }

  @override
  void openAndroidNotificationView(
    String name,
    String avatar,
    CallMediaType mediaType,
  ) {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      methodChannel.invokeMethod('openNotificationView', {
        "name": name,
        "avatar": avatar,
        "mediaType": mediaType.index,
      });
    }
  }

  @override
  void closeAndroidNotificationView() {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      methodChannel.invokeMethod('closeNotificationView', {});
    }
  }

  @override
  void startForegroundService(bool isVideo) {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      methodChannel.invokeMethod('startForegroundService', {
        "isVideo": isVideo,
      });
    }
  }

  @override
  void stopForegroundService() {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      methodChannel.invokeMethod('stopForegroundService', {});
    }
  }

  @override
  Future<bool> isScreenLocked() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      final result = await methodChannel.invokeMethod<bool>('isScreenLocked');
      return result ?? false;
    }
    return false;
  }

  @override
  void imSDKInitSuccess() {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      // 原生端只转发初始化事件，通道异常也不应逸出到应用会话。
      methodChannel.invokeMethod<void>('imSDKInitSuccess').ignore();
    }
  }

  void _handleNativeCall(MethodCall call) {
    switch (call.method) {
      case "voipMute":
        _handleVoipChangeMute(call);
        break;
      case "voipAudioPlaybackDevice":
        _handleVoipChangeAudioPlaybackDevice(call);
        break;
      case "voipHangup":
        _handleVoipHangup();
        break;
      case "voipAccept":
        _handleVoipAccept();
        break;
      case "fcmReject":
        _handleFcmReject();
        break;
      case "fcmAccept":
        _handleFcmAccept();
        break;
      default:
        break;
    }
  }

  void _handleFcmReject() {
    TUICallKitImpl.instance.fcmDataSyncHandler.handleFcmReject();
  }

  void _handleFcmAccept() {
    TUICallKitImpl.instance.fcmDataSyncHandler.handleFcmAccept();
  }

  void _handleVoipChangeMute(MethodCall call) {
    bool mute = call.arguments['mute'];
    TUICallKitImpl.instance.voIPDataSyncHandler.handleVoipChangeMute(mute);
  }

  void _handleVoipChangeAudioPlaybackDevice(MethodCall call) {
    AudioRoute audioDevice = call.arguments['audioPlaybackDevice'] == 0
        ? AudioRoute.speakerphone
        : AudioRoute.earpiece;
    TUICallKitImpl.instance.voIPDataSyncHandler
        .handleVoipChangeAudioPlaybackDevice(audioDevice);
  }

  void _handleVoipHangup() {
    TUICallKitImpl.instance.voIPDataSyncHandler.handleVoipHangup();
  }

  void _handleVoipAccept() {
    TUICallKitImpl.instance.voIPDataSyncHandler.handleVoipAccept();
  }
}
