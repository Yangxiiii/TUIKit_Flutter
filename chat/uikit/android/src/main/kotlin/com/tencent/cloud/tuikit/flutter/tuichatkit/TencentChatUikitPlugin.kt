package com.tencent.cloud.tuikit.flutter.tuichatkit

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

  private var audioPlayerPlugin: AtomicAudioPlayerPlugin? = null
  private var audioRecorderPlugin: AtomicAudioRecorderPlugin? = null
  private var filePickerPlugin: AtomicFilePickerPlugin? = null
  private var videoPlayerPlugin: AtomicVideoPlayerPlugin? = null
  private var videoRecorderPlugin: AtomicVideoRecorderPlugin? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
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
