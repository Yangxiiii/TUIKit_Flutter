package io.trtc.tuikit.atomicx.albumpicker

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.io.File

/**
 * 处理 Flutter 相册选择和编辑调用，回传选中媒体或编辑副本。
 */
class AtomicAlbumPickerPlugin(
    private val pluginBinding: FlutterPlugin.FlutterPluginBinding
) : MethodCallHandler, EventChannel.StreamHandler, ActivityResultListener {

    companion object {
        private const val METHOD_CHANNEL_NAME = "atomic_x/album_picker"
        private const val EVENT_CHANNEL_NAME = "atomic_x/album_picker_events"

        // 在当前 Flutter Activity 上区分编辑和其他插件的返回事件。
        private val EDIT_REQUEST_CODE = AlbumImageEditActivity::class.java.name.hashCode() and 0xffff
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    // Activity 重建期间重新注册监听，保留正在等待的编辑结果。
    private var activityBinding: ActivityPluginBinding? = null
    // 同一时间只处理一个编辑请求，避免把结果交给错误的调用方。
    private var pendingEditResult: Result? = null
    private val albumPickerHandler = AlbumPickerHandler(pluginBinding.flutterAssets) { event ->
        eventSink?.success(event)
    }

    init {
        methodChannel = MethodChannel(pluginBinding.binaryMessenger, METHOD_CHANNEL_NAME)
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(pluginBinding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel?.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pickMedia" -> {
                albumPickerHandler.handlePickMedia(call, result)
            }

            "editImage" -> editImage(call, result)

            else -> {
                result.notImplemented()
            }
        }
    }

    /** 注册当前 Flutter Activity 的编辑结果监听。 */
    fun attachActivity(binding: ActivityPluginBinding) {
        detachActivity()
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    /** 解绑 Activity，永久退出时结束尚未完成的编辑请求。 */
    fun detachActivity(permanent: Boolean = false) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        if (permanent) {
            val result = pendingEditResult
            pendingEditResult = null
            result?.success(null)
        }
    }

    /** 校验本地原图路径，并通过独立 Activity 打开腾讯相册编辑器。 */
    private fun editImage(call: MethodCall, result: Result) {
        val path = call.argument<String>("imagePath")
        val activity = activityBinding?.activity
        if (path.isNullOrBlank() || !File(path).isAbsolute) {
            result.error("ALBUM_EDIT_SOURCE", "图片路径无效", null)
            return
        }
        if (activity == null || pendingEditResult != null) {
            result.error("ALBUM_EDIT_UNAVAILABLE", "当前无法打开相册编辑", null)
            return
        }
        pendingEditResult = result
        try {
            val intent = Intent(activity, AlbumImageEditActivity::class.java)
                .putExtra(AlbumImageEditActivity.EXTRA_SOURCE, path)
            activity.startActivityForResult(intent, EDIT_REQUEST_CODE)
        } catch (_: RuntimeException) {
            pendingEditResult = null
            result.error("ALBUM_EDIT_UNAVAILABLE", "无法打开相册编辑", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != EDIT_REQUEST_CODE) return false
        val result = pendingEditResult
        pendingEditResult = null
        val output = data?.getStringExtra(AlbumImageEditActivity.EXTRA_OUTPUT)
        if (result == null) {
            // Flutter 已退出时没有调用方保存并清理这次导出的副本。
            output?.let { File(it).delete() }
            return true
        }
        when {
            resultCode == Activity.RESULT_CANCELED -> result.success(null)
            resultCode == Activity.RESULT_OK && output != null -> result.success(output)
            else -> result.error(
                "ALBUM_EDIT_FAILED",
                data?.getStringExtra(AlbumImageEditActivity.EXTRA_ERROR) ?: "图片编辑失败",
                null
            )
        }
        return true
    }

    // EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        detachActivity(permanent = true)
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
    }
}
