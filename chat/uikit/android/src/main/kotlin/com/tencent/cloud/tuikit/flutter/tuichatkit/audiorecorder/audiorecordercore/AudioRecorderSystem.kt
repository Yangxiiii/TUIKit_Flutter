package com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecordercore

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.os.SystemClock
import android.widget.Toast
import com.tencent.cloud.tuikit.flutter.tuichatkit.R
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.ResultCode
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecorderimpl.RecorderListener
import java.io.File
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/// 单路采集PCM，同时计算真实音量并编码为AAC；麦克风、编码器和文件均由采集任务释放。
class AudioRecorderSystem(private val context: Context) : AudioRecorderInternalInterface {
    private var listener: RecorderListener? = null
    /// 系统实现不支持AI降噪，只在腾讯录音器不可用且请求降噪时提示调试用户。
    private var isEnableAIDeNoise = false
    private val coroutineScope = CoroutineScope(Dispatchers.IO)
    private var job: Job? = null

    /// 主线程仅请求停止，采集线程写完编码尾帧后才发送完成回调，避免损坏M4A文件。
    @Volatile private var recording = false

    override fun setListener(listener: RecorderListener?) {
        this.listener = listener
    }

    override fun enableAIDeNoise(enable: Boolean) {
        isEnableAIDeNoise = enable
    }

    /// 校验输出位置并启动采集任务，文件封装和完成回调由采集线程按顺序处理。
    override fun startRecord(filePath: String?, minRecordDurationMs: Int, maxRecordDurationMs: Int) {
        if (job?.isActive == true) {
            listener?.onCompleted(ResultCode.ERROR_RECORDING, "")
            return
        }
        if (filePath.isNullOrEmpty()) {
            listener?.onCompleted(ResultCode.ERROR_STORAGE_UNAVAILABLE, "")
            return
        }
        if (isEnableAIDeNoise &&
            context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            Toast.makeText(context, R.string.audio_authorization_prompter, Toast.LENGTH_SHORT).show()
        }
        recording = true
        job = coroutineScope.launch { capture(filePath, minRecordDurationMs, maxRecordDurationMs) }
    }

    /// 请求采集线程结束输入并写完尾帧，不在主线程抢先释放编码资源。
    override fun stopRecord() {
        recording = false
    }

    /// 音量与编码读取同一份16位PCM，避免部分设备压缩采集时MediaRecorder峰值恒为零。
    private fun capture(path: String, minDurationMs: Int, maxDurationMs: Int) {
        var microphone: AudioRecord? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        var encoderStarted = false
        var durationMs = 0L
        var result = ResultCode.ERROR_RECORD_INNER_FAIL
        try {
            // 明确请求PCM输入，不能另开第二路麦克风只供动画使用。
            val minimum = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            check(minimum > 0) { "Unsupported PCM recording format" }
            val source = AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum, 8192))
            microphone = source
            check(source.state == AudioRecord.STATE_INITIALIZED) { "Microphone initialization failed" }
            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder = codec
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 128000)
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            encoderStarted = true
            val writer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = writer
            var track = -1
            val info = MediaCodec.BufferInfo()

            // 编码格式就绪后才能启动封装；停止时必须排空EOS，输出仍保持原有AAC/M4A契约。
            /// 普通采集排空已有输出；结束时等待EOS，最多两秒，避免停止后一直占用资源。
            fun drain(end: Boolean) {
                val deadline = SystemClock.elapsedRealtime() + 2000
                while (true) {
                    val index = codec.dequeueOutputBuffer(info, 10000)
                    if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        check(!muxerStarted) { "Encoder format changed twice" }
                        track = writer.addTrack(codec.outputFormat)
                        writer.start()
                        muxerStarted = true
                    } else if (index >= 0) {
                        try {
                            if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                                check(muxerStarted) { "Missing AAC output format" }
                                // AAC尾部会补齐1024采样帧，沿用拼接器的整帧边界，不能把编码填充写到时长上限之外。
                                if (info.presentationTimeUs + 1024_000_000L / SAMPLE_RATE <= maxDurationMs * 1000L) {
                                    writer.writeSampleData(track, codec.getOutputBuffer(index)!!, info)
                                }
                            }
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                        } finally {
                            codec.releaseOutputBuffer(index, false)
                        }
                    } else if (index == MediaCodec.INFO_TRY_AGAIN_LATER && !end) {
                        return
                    }
                    check(SystemClock.elapsedRealtime() < deadline) { "AAC encoder drain timed out" }
                }
            }

            source.startRecording()
            check(source.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Microphone start failed" }
            var lastPowerMs = 0L
            var peak = 0
            var samples = 0L
            // 按实际样本限制时长，不能用轮询耗时截断，否则续录会超过剩余额度。
            val maxSamples = maxDurationMs.toLong() * SAMPLE_RATE / 1000
            listener?.onRecordTime(0)
            while (recording && samples < maxSamples) {
                val index = codec.dequeueInputBuffer(10000)
                if (index >= 0) {
                    val input = codec.getInputBuffer(index)!!
                    input.clear()
                    val size = source.read(input, minOf(input.capacity(), 4096, ((maxSamples - samples) * 2).toInt()), AudioRecord.READ_BLOCKING)
                    check(size > 0 && size % 2 == 0) { "PCM read failed: $size" }
                    val pcm = input.duplicate().order(ByteOrder.LITTLE_ENDIAN)
                    for (offset in 0 until size step 2) peak = maxOf(peak, abs(pcm.getShort(offset).toInt()))
                    codec.queueInputBuffer(index, 0, size, samples * 1_000_000 / SAMPLE_RATE, 0)
                    samples += size / 2
                }
                drain(false)
                durationMs = samples * 1000 / SAMPLE_RATE
                if (durationMs - lastPowerMs >= POWER_INTERVAL_MS) {
                    val db = if (peak == 0) -90 else (20 * log10(peak / 32768.0)).toInt().coerceIn(-90, 0)
                    listener?.onAmplitudeChanged(db)
                    listener?.onRecordTime(durationMs.toInt())
                    peak = 0
                    lastPowerMs = durationMs
                }
            }
            source.stop()
            // 停止只结束输入，写出最后一帧后才能向Dart交还可识别、可拼接的文件。
            val deadline = SystemClock.elapsedRealtime() + 2000
            while (true) {
                val index = codec.dequeueInputBuffer(10000)
                if (index >= 0) {
                    codec.queueInputBuffer(index, 0, 0, samples * 1_000_000 / SAMPLE_RATE, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                drain(false)
                check(SystemClock.elapsedRealtime() < deadline) { "AAC encoder stop timed out" }
            }
            drain(true)
            check(muxerStarted) { "Empty AAC recording" }
            writer.stop()
            muxerStarted = false
            result = when {
                durationMs < minDurationMs -> ResultCode.ERROR_LESS_THAN_MIN_DURATION
                durationMs >= maxDurationMs -> ResultCode.SUCCESS_EXCEED_MAX_DURATION
                else -> ResultCode.SUCCESS
            }
        } catch (error: Exception) {
            android.util.Log.e("AudioRecorderSystem", "PCM recording failed", error)
            File(path).delete()
        } finally {
            // 失败、取消及正常停止共用释放路径，释放完才允许上层发起下一段录音。
            recording = false
            runCatching { microphone?.stop() }
            runCatching { microphone?.release() }
            if (encoderStarted) runCatching { encoder?.stop() }
            runCatching { encoder?.release() }
            if (muxerStarted) runCatching { muxer?.stop() }
            runCatching { muxer?.release() }
        }
        listener?.onRecordTime(durationMs.toInt())
        listener?.onCompleted(result, if (result == ResultCode.ERROR_RECORD_INNER_FAIL) "" else path)
    }

    companion object {
        /// 与原系统录音一致的44.1kHz单声道，续录片段保持相同编码配置。
        private const val SAMPLE_RATE = 44100
        /// 以100毫秒窗口聚合峰值，避免每个PCM帧都触发界面重建。
        private const val POWER_INTERVAL_MS = 100L
    }
}
