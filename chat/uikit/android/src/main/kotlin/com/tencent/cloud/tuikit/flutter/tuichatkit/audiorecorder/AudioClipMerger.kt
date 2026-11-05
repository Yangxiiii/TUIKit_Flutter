package com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/** 将同一录音草稿的 AAC 音轨顺序封装为一个新文件，失败时不修改任何源文件。 */
internal object AudioClipMerger {
    /** 所有时间戳均为微秒，整条语音的上限不因续录而重置。 */
    private const val MAX_DURATION_US = 60_000_000L

    /** 只接受新输出路径；调用方成功取得结果后才可替换原草稿。 */
    fun merge(paths: List<String>, destination: String): Map<String, Any> {
        require(paths.size >= 2) { "At least two audio clips are required" }
        val output = File(destination)
        require(!output.exists()) { "Output already exists" }
        require(paths.none { File(it).canonicalPath == output.canonicalPath }) { "Output overlaps input" }
        require(paths.all { File(it).isFile && File(it).length() > 0 }) { "Missing audio clip" }
        output.parentFile?.mkdirs()
        var muxer: MediaMuxer? = null
        try {
            val writer = MediaMuxer(destination, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = writer
            var track = -1
            var sampleRate = 0
            var channels = 0
            var offsetUs = 0L
            val buffer = ByteBuffer.allocateDirect(1024 * 1024)
            val info = MediaCodec.BufferInfo()

            // 复制压缩音频帧并平移时间戳，排除用户停留在预览页的等待时间。
            for (path in paths) {
                val extractor = MediaExtractor()
                try {
                    extractor.setDataSource(path)
                    val sourceTrack = (0 until extractor.trackCount).firstOrNull {
                        extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME) == "audio/mp4a-latm"
                    } ?: error("AAC audio track not found")
                    val format = extractor.getTrackFormat(sourceTrack)
                    val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    val count = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (track < 0) {
                        sampleRate = rate
                        channels = count
                        track = writer.addTrack(format)
                        writer.start()
                    } else {
                        require(rate == sampleRate && count == channels) { "Incompatible audio clips" }
                    }
                    extractor.selectTrack(sourceTrack)
                    val firstUs = extractor.sampleTime
                    require(firstUs >= 0) { "Empty audio track" }
                    val frameUs = 1024_000_000L / sampleRate
                    var endUs = offsetUs
                    while (true) {
                        buffer.clear()
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) break
                        val timestamp = offsetUs + extractor.sampleTime - firstUs
                        if (timestamp + frameUs > MAX_DURATION_US) break
                        info.set(0, size, timestamp, extractor.sampleFlags)
                        writer.writeSampleData(track, buffer, info)
                        endUs = timestamp + frameUs
                        if (!extractor.advance()) break
                    }
                    require(endUs > offsetUs) { "No audio samples appended" }
                    offsetUs = endUs
                } finally {
                    extractor.release()
                }
                if (offsetUs >= MAX_DURATION_US) break
            }
            writer.stop()
            writer.release()
            muxer = null

            // 重新打开封装结果确认可解析，不能把写入成功等同于有效音频。
            val metadata = MediaMetadataRetriever()
            val durationMs = try {
                metadata.setDataSource(destination)
                metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toIntOrNull()
                    ?: error("Missing audio duration")
            } finally {
                metadata.release()
            }
            require(durationMs in 1000..60000 && output.length() > 0) { "Invalid merged audio" }
            return mapOf("filePath" to destination, "durationMs" to durationMs)
        } catch (error: Exception) {
            output.delete()
            throw error
        } finally {
            muxer?.release()
        }
    }
}
