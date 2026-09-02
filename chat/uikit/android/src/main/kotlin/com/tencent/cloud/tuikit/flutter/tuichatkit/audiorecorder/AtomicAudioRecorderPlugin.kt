package com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder
import android.app.Activity
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class AtomicAudioRecorderPlugin(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    
    companion object {
        private const val TAG = "AtomicAudioRecorderPlugin"
        private const val METHOD_CHANNEL_NAME = "tencent_chat_uikit/audio_recorder"
        private const val EVENT_CHANNEL_NAME = "tencent_chat_uikit/audio_recorder_events"
    }

    private val methodChannel: MethodChannel = MethodChannel(
        flutterPluginBinding.binaryMessenger,
        METHOD_CHANNEL_NAME
    )
    
    private val eventChannel: EventChannel = EventChannel(
        flutterPluginBinding.binaryMessenger,
        EVENT_CHANNEL_NAME
    )
    
    private var handler: AudioRecorderHandler? = null

    init {
        // Note: Activity will be set when available through ActivityAware
        //
        // 注意：Activity 会在通过 ActivityAware 可用时设置。
        Log.d(TAG, "AtomicAudioRecorderPlugin initialized")
    }

    fun attachToActivity(activity: Activity) {
        handler = AudioRecorderHandler(activity, methodChannel, eventChannel)
        methodChannel.setMethodCallHandler(handler)
        eventChannel.setStreamHandler(handler)
        Log.d(TAG, "AtomicAudioRecorderPlugin attached to activity")
    }

    fun detachFromActivity() {
        handler?.dispose()
        handler = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        Log.d(TAG, "AtomicAudioRecorderPlugin detached from activity")
    }

    fun dispose() {
        detachFromActivity()
    }
}
