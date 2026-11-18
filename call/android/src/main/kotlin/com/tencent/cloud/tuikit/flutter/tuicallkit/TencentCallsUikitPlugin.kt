package com.tencent.cloud.tuikit.flutter.tuicallkit
import android.app.KeyguardManager
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import com.tencent.cloud.tuikit.flutter.tuicallkit.view.NotificationView
import com.tencent.cloud.tuikit.flutter.tuicallkit.utils.CallingVibrator
import com.tencent.qcloud.tuicore.TUIConstants
import com.tencent.qcloud.tuicore.TUICore
import com.trtc.tuikit.common.foregroundservice.AudioForegroundService
import com.trtc.tuikit.common.foregroundservice.VideoForegroundService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/** 提供通话原生窗口、前台服务和设备能力查询。 */
class TencentCallsUikitPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var appContext: Context
  private lateinit var callingVibrator: CallingVibrator

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tencent_calls_uikit")
    channel.setMethodCallHandler(this)
    appContext = flutterPluginBinding.applicationContext
    callingVibrator = CallingVibrator(appContext)
    Companion.channel = channel
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getCameraCount" -> getCameraCount(result)
      "openNotificationView" -> openNotificationView(call, result)
      "closeNotificationView" -> closeNotificationView(call, result)
      "startVibration" -> startVibration(call, result)
      "stopVibration" -> stopVibration(call, result)
      "startForegroundService" -> startForegroundService(call, result)
      "stopForegroundService" -> stopForegroundService(call, result)
      "isScreenLocked" -> isScreenLocked(result)
      "imSDKInitSuccess" -> imSDKInitSuccess()
      else -> result.notImplemented()
    }
  }

  /** 只统计前后朝向，避免多枚后置镜头被误判为可翻转到前置。 */
  private fun getCameraCount(result: MethodChannel.Result) {
    try {
      val manager = appContext.getSystemService(Context.CAMERA_SERVICE) as CameraManager
      val facing = manager.cameraIdList.mapNotNull {
        manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING)
      }.filter {
        it == CameraCharacteristics.LENS_FACING_FRONT || it == CameraCharacteristics.LENS_FACING_BACK
      }.toSet()
      result.success(facing.size)
    } catch (error: Exception) {
      result.error("CAMERA_QUERY_FAILED", "无法读取摄像头能力", null)
    }
  }

  private fun openNotificationView(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val name = args?.get("name") as? String ?: ""
    val avatar = args?.get("avatar") as? String ?: ""
    val mediaTypeRaw = args?.get("mediaType")
    val mediaType = NotificationView.Companion.MediaType.entries.getOrNull(mediaTypeRaw as Int) ?: NotificationView.Companion.MediaType.Audio
    NotificationView.getInstance(appContext).showNotification(name, avatar, mediaType)
    result.success(null)
  }

  private fun closeNotificationView(call: MethodCall, result: MethodChannel.Result) {
    NotificationView.getInstance(appContext).cancelNotification()
    result.success(null)
  }

  private fun startVibration(call: MethodCall, result: MethodChannel.Result) {
    callingVibrator.startVibration()
    result.success(null)
  }

  private fun stopVibration(call: MethodCall, result: MethodChannel.Result) {
    callingVibrator.stopVibration()
    result.success(null)
  }

  private fun startForegroundService(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val isVideo = args?.get("isVideo") as? Boolean ?: false
    if (isVideo) {
      VideoForegroundService.start(appContext, "", "", 0)
    } else {
      AudioForegroundService.start(appContext, "", "", 0)
    }
    result.success(null)
  }

  private fun stopForegroundService(call: MethodCall, result: MethodChannel.Result) {
    VideoForegroundService.stop(appContext)
    AudioForegroundService.stop(appContext)
    result.success(null)
  }

  private fun isScreenLocked(result: MethodChannel.Result) {
    val keyguardManager = appContext.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
    result.success(keyguardManager?.isKeyguardLocked ?: false)
  }

  private fun imSDKInitSuccess() {
    TUICore.notifyEvent(TUIConstants.TUILogin.EVENT_IMSDK_INIT_STATE_CHANGED, TUIConstants.TUILogin.EVENT_SUB_KEY_INIT_SUCCESS, null)
  }

  companion object {
    @Volatile internal var channel: MethodChannel? = null

    fun emit(event: String, args: Map<String, Any?>? = null) {
      try {
        channel?.invokeMethod(event, args)
      } catch (_: Throwable) {
        // swallow if channel not ready
        //
        // 如果通道未就绪则吞掉
      }
    }
  }
}
