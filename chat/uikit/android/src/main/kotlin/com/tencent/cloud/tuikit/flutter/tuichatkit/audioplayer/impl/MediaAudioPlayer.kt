package com.tencent.cloud.tuikit.flutter.tuichatkit.audioplayer.impl
import android.content.Context
import android.media.AudioDeviceInfo
import android.os.Build
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.tencent.cloud.tuikit.flutter.tuichatkit.audioplayer.AudioOutputDevice
import com.tencent.cloud.tuikit.flutter.tuichatkit.audioplayer.AudioPlayer
import com.tencent.cloud.tuikit.flutter.tuichatkit.audioplayer.AudioPlayerListener
import io.trtc.tuikit.atomicx.basecomponent.utils.ContextProvider
import java.io.File


/** 装载当前音源，忽略已释放播放器的迟到事件，文件切换后可恢复暂停位置。 */
class MediaAudioPlayer : AudioPlayer() {
    private var mediaPlayer: MediaPlayer? = null
    private var currentFilePath: String? = null
    private var listener: AudioPlayerListener? = null
    private var isPaused = false
    /** 播放路由偏好跨文件保留，停止时恢复本应用接管前的音频模式。 */
    private var currentOutputDevice = AudioOutputDevice.SPEAKER
    private var routeConfigured = false
    /** 接管前的模式和扬声器状态只在本播放器释放资源时恢复。 */
    private var previousAudioMode: Int? = null
    private var previousSpeaker: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var audioManager: AudioManager

    init {
        val context = ContextProvider.appContext
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    private val progressUpdater = object : Runnable {
        override fun run() {
            if (isPlaying()) {
                try {
                    val currentPosition = getCurrentPosition()
                    val duration = getDuration()
                    listener?.onProgressUpdate(currentPosition, duration)
                } catch (e: Exception) {
                    Log.e(TAG, "Progress update error", e)
                }

                mainHandler.postDelayed(this, PROGRESS_UPDATE_INTERVAL)
            }
        }
    }

    override fun play(filePath: String, startPositionMs: Int) {
        Log.d(TAG, "play: $filePath")

        if (mediaPlayer != null) {
            stop()
        }

        try {
            val isRemote = filePath.startsWith("http://", true) ||
                filePath.startsWith("https://", true)

            if (!isRemote) {
                val file = File(filePath)
                if (!file.exists() || !file.canRead()) {
                    val errorMsg = "File not found: $filePath"
                    Log.e(TAG, errorMsg)
                    listener?.onError(errorMsg)
                    return
                }
            }

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .build()
                )

                setDataSource(filePath)
                setOnCompletionListener { completed ->
                    if (mediaPlayer !== completed) return@setOnCompletionListener
                    stopProgressUpdates()
                    restoreAudioMode()
                    listener?.onCompletion()

                    release()
                    mediaPlayer = null
                    isPaused = false
                }

                setOnErrorListener { failed, what, extra ->
                    if (mediaPlayer !== failed) return@setOnErrorListener true
                    stopProgressUpdates()
                    val errorMessage = "Play error, code: $what, extra: $extra"
                    Log.e(TAG, errorMessage)
                    restoreAudioMode()
                    listener?.onError(errorMessage)

                    release()
                    mediaPlayer = null
                    isPaused = false
                    true
                }

                setOnPreparedListener { prepared ->
                    if (mediaPlayer !== prepared) return@setOnPreparedListener
                    try {
                        applyAudioOutputDevice()
                    } catch (error: Exception) {
                        listener?.onError("Audio route error: ${error.message}")
                        stop()
                        return@setOnPreparedListener
                    }

                    // 先定位后发声，不能先播出其他消息的开头再跳回暂停点。
                    if (startPositionMs > 0) seekTo(startPositionMs.coerceAtMost(duration))
                    start()
                    isPaused = false

                    listener?.onPlay()

                    startProgressUpdates()
                }
                // 回调先注册，随后才准备音源，本地同步准备也不会漏掉开始事件。
                if (isRemote) prepareAsync() else prepare()
            }

            currentFilePath = filePath

        } catch (e: Exception) {
            Log.e(TAG, "Play error", e)
            listener?.onError("Play error: ${e.message}")
            mediaPlayer?.release()
            mediaPlayer = null
        }
    }

    override fun pause() {
        Log.d(TAG, "pause")
        if (isPlaying()) {
            mediaPlayer?.pause()
            isPaused = true
            stopProgressUpdates()
            // 暂停和后台中断先归还路由，不能继续占用通话模式。
            restoreAudioMode()
            listener?.onPause()
        }
    }

    override fun resume() {
        Log.d(TAG, "resume")
        if (isPaused && mediaPlayer != null) {
            applyAudioOutputDevice()
            mediaPlayer?.start()
            isPaused = false
            startProgressUpdates()
            listener?.onResume()
        }
    }

    /** 先解除当前源所有权，再释放资源，准备过程中的旧回调也会被忽略。 */
    override fun stop() {
        val previous = mediaPlayer
        mediaPlayer = null
        try {
            previous?.reset()
        } catch (error: Exception) {
            Log.e(TAG, "Stop error", error)
        } finally {
            previous?.release()
            isPaused = false
            stopProgressUpdates()
            restoreAudioMode()
        }
    }

    /** 无听筒设备明确失败，活动播放切换失败时保留原偏好。 */
    override fun setAudioOutputDevice(device: AudioOutputDevice): AudioPlayer {
        if (device == AudioOutputDevice.EARPIECE) {
            require(audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .any { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }) { "Earpiece is unavailable" }
        }
        val configured = routeConfigured
        routeConfigured = true
        try {
            if (isPlaying()) applyAudioOutputDevice(device)
        } catch (error: Exception) {
            routeConfigured = configured
            try { applyAudioOutputDevice(currentOutputDevice) } catch (_: Exception) { }
            throw error
        }
        currentOutputDevice = device
        routeConfigured = true
        listener?.onAudioOutputChanged(device)
        return this
    }

    /** 语音使用通信音轨，Android12及以上通过明确设备选择确认原生结果。 */
    private fun applyAudioOutputDevice(device: AudioOutputDevice = currentOutputDevice) {
        // 用户未主动选择时尊重耳机，不能因默认扬声器偏好把私密音频强制外放。
        val external = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            it.type != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER && it.type != AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
        }
        if (!routeConfigured && external) return
        if (previousAudioMode == null) {
            previousAudioMode = audioManager.mode
            previousSpeaker = audioManager.isSpeakerphoneOn
        }
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val targetType = if (device == AudioOutputDevice.SPEAKER)
                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER else AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                val target = audioManager.availableCommunicationDevices.firstOrNull { it.type == targetType }
                    ?: error("Audio output unavailable")
                check(audioManager.setCommunicationDevice(target)) { "Audio route rejected" }
            } else {
                audioManager.isSpeakerphoneOn = device == AudioOutputDevice.SPEAKER
            }
        } catch (error: Exception) {
            restoreAudioMode()
            throw error
        }
    }

    /** 只有接管过模式才恢复，避免每个气泡销毁时改动共享通话资源。 */
    private fun restoreAudioMode() {
        val mode = previousAudioMode ?: return
        previousAudioMode = null
        if (audioManager.mode != AudioManager.MODE_IN_COMMUNICATION) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) audioManager.clearCommunicationDevice()
        audioManager.mode = mode
        audioManager.isSpeakerphoneOn = previousSpeaker
    }

    override fun setListener(listener: AudioPlayerListener?): AudioPlayer {
        this.listener = listener
        return this
    }

    override fun getCurrentPosition(): Int {
        return try {
            mediaPlayer?.currentPosition ?: 0
        } catch (e: Exception) {
            Log.e(TAG, "Get current position failed", e)
            0
        }
    }

    override fun getDuration(): Int {
        return try {
            mediaPlayer?.duration ?: 0
        } catch (e: Exception) {
            Log.e(TAG, "Get duration failed", e)
            0
        }
    }

    override fun isPlaying(): Boolean {
        return try {
            mediaPlayer?.isPlaying ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Check play state failed", e)
            false
        }
    }

    override fun isPaused(): Boolean {
        return isPaused && mediaPlayer != null
    }

    private fun startProgressUpdates() {
        stopProgressUpdates()
        mainHandler.post(progressUpdater)
    }

    private fun stopProgressUpdates() {
        mainHandler.removeCallbacks(progressUpdater)
    }

    companion object {
        private const val TAG = "MediaAudioPlayer"
        private const val PROGRESS_UPDATE_INTERVAL = 100L
    }
}
