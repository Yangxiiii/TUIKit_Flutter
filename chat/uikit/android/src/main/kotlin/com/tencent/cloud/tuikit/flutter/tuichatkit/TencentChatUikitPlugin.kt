package com.tencent.cloud.tuikit.flutter.tuichatkit

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import com.tencent.cloud.tuikit.flutter.tuichatkit.audioplayer.AtomicAudioPlayerPlugin
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.AtomicAudioRecorderPlugin
import com.tencent.cloud.tuikit.flutter.tuichatkit.filepicker.AtomicFilePickerPlugin
import com.tencent.cloud.tuikit.flutter.tuichatkit.videoplayer.AtomicVideoPlayerPlugin
import com.tencent.cloud.tuikit.flutter.tuichatkit.videorecorder.AtomicVideoRecorderPlugin

/** TencentChatUikitPlugin
 *
 * Hosts the chat-business native handlers that were previously bundled inside
 * AtomicXPlugin. Module/handler ownership matches the Dart-side migration:
 *   audio_player, audio_recoder, file_picker, video_player, video_recorder.
 *
 * 托管之前包含在 AtomicXPlugin 里的聊天业务原生处理器。模块/处理器的归属对应 Dart
 * 端的迁移：audio_player、audio_recorder、file_picker、video_player、video_recorder。
 */
class TencentChatUikitPlugin : FlutterPlugin, ActivityAware {
  companion object {
    private const val TAG = "TencentChatUikitPlugin"
  }

  /** 剪贴板通道随引擎注册与解除，避免分离后保留旧的回调。 */
  private var clipboardChannel: MethodChannel? = null

  private var audioPlayerPlugin: AtomicAudioPlayerPlugin? = null
  private var audioRecorderPlugin: AtomicAudioRecorderPlugin? = null
  private var filePickerPlugin: AtomicFilePickerPlugin? = null
  private var videoPlayerPlugin: AtomicVideoPlayerPlugin? = null
  private var videoRecorderPlugin: AtomicVideoRecorderPlugin? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    val clipboard = flutterPluginBinding.applicationContext
      .getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboardChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "tencent_chat_uikit")
      .also { channel ->
        channel.setMethodCallHandler { call, result ->
          try {
            when (call.method) {
              "writeMessageClipboard" -> {
                val text = call.argument<String>("text")
                val token = call.argument<String>("token")
                if (text == null || token == null) {
                  result.error("INVALID_ARGUMENT", null, null)
                } else {
                  // 纯文本作为唯一内容；Android 24 起可在描述里附带条目身份。
                  val clip = ClipData.newPlainText("", text)
                  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    clip.description.extras = PersistableBundle().apply {
                      putString("com.tencent.cloud.tuichatkit.clip-token", token)
                    }
                  }
                  clipboard.setPrimaryClip(clip)
                  result.success(null)
                }
              }
              "readMessageClipboardToken" -> result.success(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                  clipboard.primaryClipDescription?.extras
                    ?.getString("com.tencent.cloud.tuichatkit.clip-token")
                } else null
              )
              else -> result.notImplemented()
            }
          } catch (error: RuntimeException) {
            result.error("CLIPBOARD_UNAVAILABLE", null, null)
          }
        }
      }
    videoRecorderPlugin = AtomicVideoRecorderPlugin(flutterPluginBinding)
    audioRecorderPlugin = AtomicAudioRecorderPlugin(flutterPluginBinding)
    audioPlayerPlugin = AtomicAudioPlayerPlugin().also {
      it.onAttachedToEngine(flutterPluginBinding)
    }
    filePickerPlugin = AtomicFilePickerPlugin().also {
      it.onAttachedToEngine(flutterPluginBinding)
    }
    videoPlayerPlugin = AtomicVideoPlayerPlugin().also {
      it.onAttachedToEngine(flutterPluginBinding)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    clipboardChannel?.setMethodCallHandler(null)
    clipboardChannel = null
    videoRecorderPlugin?.dispose()
    videoRecorderPlugin = null
    audioRecorderPlugin?.dispose()
    audioRecorderPlugin = null
    audioPlayerPlugin?.onDetachedFromEngine(binding)
    audioPlayerPlugin = null
    filePickerPlugin?.onDetachedFromEngine(binding)
    filePickerPlugin = null
    videoPlayerPlugin?.onDetachedFromEngine(binding)
    videoPlayerPlugin = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    audioRecorderPlugin?.attachToActivity(binding.activity)
  }

  override fun onDetachedFromActivityForConfigChanges() {}

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

  override fun onDetachedFromActivity() {
    audioRecorderPlugin?.detachFromActivity()
  }
}
