package com.tencent.cloud.tuikit.flutter.tuichatkit.audioplayer
import com.tencent.cloud.tuikit.flutter.tuichatkit.audioplayer.impl.MediaAudioPlayer

/** 共享原生播放器契约，恢复位置以毫秒传入并在准备完成后应用。 */
abstract class AudioPlayer {
    companion object {
        val shared: AudioPlayer by lazy {
            MediaAudioPlayer()
        }
    }

    abstract fun play(filePath: String, startPositionMs: Int = 0)

    abstract fun pause()

    abstract fun resume()

    abstract fun stop()

    /** 切换扬声器或听筒，硬件不支持或切换失败时向调用方抛错。 */
    abstract fun setAudioOutputDevice(device: AudioOutputDevice): AudioPlayer

    abstract fun setListener(listener: AudioPlayerListener?): AudioPlayer

    abstract fun getCurrentPosition(): Int

    abstract fun getDuration(): Int

    abstract fun isPlaying(): Boolean

    abstract fun isPaused(): Boolean
}

enum class AudioOutputDevice {
    SPEAKER,
    EARPIECE
}

interface AudioPlayerListener {

    fun onPlay() {}

    fun onPause() {}

    fun onResume() {}

    fun onProgressUpdate(currentPosition: Int, duration: Int) {}

    fun onCompletion() {}

    fun onError(errorMessage: String) {}

    fun onAudioOutputChanged(device: AudioOutputDevice) {}
}
