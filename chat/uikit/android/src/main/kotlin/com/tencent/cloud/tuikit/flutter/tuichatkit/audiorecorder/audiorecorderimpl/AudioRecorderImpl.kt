package com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecorderimpl
import android.Manifest
import android.os.Looper
import android.util.Log
import com.tencent.qcloud.tuicore.permission.PermissionCallback
import com.tencent.qcloud.tuicore.permission.PermissionRequester
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.AudioRecorderListener
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.ResultCode
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecordercore.AudioRecorderInternalInterface
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecordercore.AudioRecorderSystem
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecordercore.AudioRecorderTXUGC
import io.trtc.tuikit.atomicx.basecomponent.utils.ContextProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// 原生录音器统一上报毫秒进度、dBFS音量和终态，由适配器转到主线程。
interface RecorderListener {
    fun onRecordTime(time: Int)
    fun onAmplitudeChanged(db: Int)
    fun onCompleted(resultCode: ResultCode, path: String?)
}

/// 协调权限、录音器选择与主线程回调；普通录音回传实时音量，AI降噪按需使用腾讯录音器。
class AudioRecorderImpl() {
    companion object {
        private var TAG: String? = "AudioRecorderImpl"
    }

    private var recorder: AudioRecorderInternalInterface? = null
    private val mainCoroutineScope = CoroutineScope(Dispatchers.Main)
    private var isRecording = false
    private var isCancelRecord = false
    private var audioFilePath: String? = null

    private var listener: AudioRecorderListener? = null

    var onRecordTime: ((timeMs: Int) -> Unit)? = null
    var onPowerLevel: ((powerLevel: Int) -> Unit)? = null

    fun startRecord(
        filepath: String?,
        enableAIDeNoise: Boolean,
        minRecordDurationMs: Int,
        maxRecordDurationMs: Int,
        listener: AudioRecorderListener
    ) {
        this.listener = listener
        Log.i(TAG, "start record filepath:$filepath")
        PermissionRequester.newInstance(Manifest.permission.RECORD_AUDIO).callback(object : PermissionCallback() {
            override fun onGranted() {
                runOnMainThread { startRecordInternal(filepath, enableAIDeNoise, minRecordDurationMs, maxRecordDurationMs) }
            }

            override fun onDenied() {
                Log.i(TAG, "request record audio permission refuse")
                onRecordingComplete(ResultCode.ERROR_RECORD_PERMISSION_DENIED, "", 0)
            }
        }).request()
    }

    /// 权限通过后启动单次录音，完成参数检查后才占用麦克风。
    private fun startRecordInternal(
        filepath: String?,
        enableAIDeNoise: Boolean,
        minRecordDurationMs: Int,
        maxRecordDurationMs: Int
    ) {
        if (isRecording) {
            onRecordingComplete(ResultCode.ERROR_RECORDING, "", 0)
            return
        }

        isRecording = true
        isCancelRecord = false

        audioFilePath = filepath
        if (audioFilePath.isNullOrEmpty()) {
            audioFilePath = getFilePath()
        }

        if (audioFilePath.isNullOrEmpty()) {
            onRecordingComplete(ResultCode.ERROR_STORAGE_UNAVAILABLE, audioFilePath, 0)
            return
        }

        // 腾讯UGC当前只有时长和完成回调；未开启AI降噪时用已有系统实现回传真实音量。
        val context = ContextProvider.appContext
        recorder = if (enableAIDeNoise) {
            // shortcut: 腾讯AI降噪模式没有音量回调，启用该模式的波形前需升级支持音量回调的SDK。
            try {
                AudioRecorderTXUGC(context).also { it.init() }
            } catch (e: Exception) {
                Log.i("AudioRecorderFactory", "can not create ugc audio recorder." + e.message)
                AudioRecorderSystem(context)
            }
        } else {
            AudioRecorderSystem(context)
        }
        recorder?.setListener(RecorderListenerImpl())
        recorder?.enableAIDeNoise(enableAIDeNoise)
        recorder?.startRecord(filePath = audioFilePath, minRecordDurationMs, maxRecordDurationMs)
    }

    fun stopRecord() {
        runOnMainThread {
            if (isRecording) {
                recorder?.stopRecord()
                isRecording = false
            }
        }
    }

    fun cancelRecord() {
        Log.i(TAG, "cancel record")
        runOnMainThread {
            if (isRecording) {
                isCancelRecord = true
                recorder?.stopRecord()
                onRecordingComplete(ResultCode.ERROR_CANCEL, audioFilePath, 0)
            }
        }
    }

    private fun getFilePath(): String? {
        val context = ContextProvider.appContext
        val audioDir = File(context?.filesDir, "audio")
        val dirExists = audioDir.exists()
        if (!dirExists) {
            val dirCreated = audioDir.mkdirs()
            if (!dirCreated) {
                return null
            }
        }

        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        val outputFile = File(audioDir, "audio_$timestamp.m4a")
        return outputFile.absolutePath
    }

    private fun onRecordingComplete(resultCode: ResultCode, recordFilePath: String?, recordDuration: Int) {
        runOnMainThread {
            this.listener?.onCompleted(resultCode, recordFilePath, recordDuration)
            this.listener = null
        }
    }

    private fun runOnMainThread(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainCoroutineScope.launch {
                action()
            }
        }
    }

    /// 只转发当前录音进度与终态，取消的原生完成事件不重复交付文件。
    inner class RecorderListenerImpl : RecorderListener {
        private var recordTimeMs: Int = 0

        override fun onRecordTime(time: Int) {
            Log.i(TAG, "onRecordProcess time:$time")
            this@AudioRecorderImpl.runOnMainThread {
                recordTimeMs = time
                this@AudioRecorderImpl.onRecordTime?.invoke(recordTimeMs)
            }
        }

        override fun onAmplitudeChanged(db: Int) {
            this@AudioRecorderImpl.runOnMainThread {
                this@AudioRecorderImpl.onPowerLevel?.invoke(db)
            }
        }

        override fun onCompleted(resultCode: ResultCode, path: String?) {
            if (resultCode != ResultCode.SUCCESS) {
                Log.e(TAG, "on record completed. resultCode:$resultCode")
            }
            Log.i(TAG, "on record completed. path:$path")
            this@AudioRecorderImpl.runOnMainThread {
                isRecording = false
                if (!isCancelRecord) {
                    this@AudioRecorderImpl.onRecordingComplete(resultCode, path, recordTimeMs)
                }
            }
        }
    }
}
