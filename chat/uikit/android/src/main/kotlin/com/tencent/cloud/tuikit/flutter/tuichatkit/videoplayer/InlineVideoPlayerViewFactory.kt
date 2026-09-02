package com.tencent.cloud.tuikit.flutter.tuichatkit.videoplayer
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory for creating inline video player views
 * This player only renders video - controls are handled by Flutter
 *
 * 用于创建内联视频播放器视图的工厂，该播放器仅渲染视频 - 控件由 Flutter 处理
 */
class InlineVideoPlayerViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<*, *>
        return InlineVideoPlayerPlatformView(context, viewId, creationParams)
    }
}

/**
 * Inline video player that only renders video without any controls
 * All playback control is done via MethodChannel from Flutter
 *
 * 仅渲染视频而无任何控件的内联视频播放器，所有播放控制通过 Flutter 的 MethodChannel 完成
 */
class InlineVideoPlayerPlatformView(
    private val context: Context,
    private val viewId: Int,
    creationParams: Map<*, *>?
) : PlatformView, MethodChannel.MethodCallHandler {

    private val containerView: FrameLayout
    private val textureView: TextureView
    private val player: ExoPlayer
    private var methodChannel: MethodChannel? = null
    
    private val handler = Handler(Looper.getMainLooper())
    private var positionUpdateRunnable: Runnable? = null
    private var isDisposed = false
    
    // Video dimensions for aspect ratio calculation
    //
    // 视频尺寸用于计算宽高比
    private var videoWidth = 0
    private var videoHeight = 0

    init {
        val videoPath = creationParams?.get("videoPath") as? String ?: ""
        val videoUri = Uri.parse("file://$videoPath")

        // Create container with black background
        //
        // 创建黑色背景的容器
        containerView = FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
        }
        
        // Create TextureView for video rendering (avoids SurfaceView buffer conflicts)
        //
        // 创建用于视频渲染的 TextureView（避免 SurfaceView 缓冲冲突）
        textureView = TextureView(context)
        containerView.addView(textureView)

        // Create ExoPlayer
        //
        // 创建 ExoPlayer
        player = ExoPlayer.Builder(context).build().apply {
            setVideoTextureView(textureView)
            setMediaItem(MediaItem.fromUri(videoUri))
            
            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    when (playbackState) {
                        Player.STATE_READY -> {
                            sendToFlutter("onReady", mapOf(
                                "duration" to duration,
                                "videoWidth" to videoWidth,
                                "videoHeight" to videoHeight
                            ))
                            sendToFlutter("onDurationChanged", duration)
                        }
                        Player.STATE_ENDED -> {
                            sendToFlutter("onCompleted", null)
                            stopPositionUpdates()
                        }
                    }
                }
                
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    sendToFlutter("onPlayingChanged", isPlaying)
                    if (isPlaying) {
                        startPositionUpdates()
                    } else {
                        stopPositionUpdates()
                    }
                }
                
                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    if (videoSize.width > 0 && videoSize.height > 0) {
                        videoWidth = videoSize.width
                        videoHeight = videoSize.height
                        updateTextureViewSize()
                        sendToFlutter("onVideoSizeChanged", mapOf(
                            "width" to videoWidth,
                            "height" to videoHeight
                        ))
                    }
                }
            })
            
            prepare()
        }
    }
    
    /**
     * Update TextureView size to maintain aspect ratio
     *
     * 更新 TextureView 尺寸以保持宽高比
     */
    private fun updateTextureViewSize() {
        if (videoWidth <= 0 || videoHeight <= 0) return
        
        containerView.post {
            val containerWidth = containerView.width
            val containerHeight = containerView.height
            
            if (containerWidth <= 0 || containerHeight <= 0) return@post
            
            val videoAspect = videoWidth.toFloat() / videoHeight.toFloat()
            val containerAspect = containerWidth.toFloat() / containerHeight.toFloat()
            
            val (targetWidth, targetHeight) = if (videoAspect > containerAspect) {
                // Video is wider - fit to width
                //
                // 视频较宽 - 适应宽度
                containerWidth to (containerWidth / videoAspect).toInt()
            } else {
                // Video is taller - fit to height
                //
                // 视频较高 - 适应高度
                (containerHeight * videoAspect).toInt() to containerHeight
            }
            
            textureView.layoutParams = FrameLayout.LayoutParams(targetWidth, targetHeight).apply {
                gravity = Gravity.CENTER
            }
        }
    }
    
    fun setMethodChannel(channel: MethodChannel) {
        methodChannel = channel
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> {
                // If playback ended, seek to start before playing
                if (player.playbackState == Player.STATE_ENDED) {
                    player.seekTo(0)
                }
                player.play()
                result.success(null)
            }
            "pause" -> {
                player.pause()
                result.success(null)
            }
            "seekTo" -> {
                val positionMs = (call.arguments as? Number)?.toLong() ?: 0L
                player.seekTo(positionMs)
                result.success(null)
            }
            "getPosition" -> {
                result.success(player.currentPosition)
            }
            "getDuration" -> {
                result.success(player.duration)
            }
            "isPlaying" -> {
                result.success(player.isPlaying)
            }
            else -> result.notImplemented()
        }
    }
    
    private fun sendToFlutter(method: String, arguments: Any?) {
        if (!isDisposed) {
            handler.post {
                methodChannel?.invokeMethod(method, arguments)
            }
        }
    }
    
    private fun startPositionUpdates() {
        stopPositionUpdates()
        positionUpdateRunnable = object : Runnable {
            override fun run() {
                if (!isDisposed && player.isPlaying) {
                    sendToFlutter("onPositionChanged", player.currentPosition)
                    handler.postDelayed(this, 100) // Update every 100ms
                }
            }
        }
        handler.post(positionUpdateRunnable!!)
    }
    
    private fun stopPositionUpdates() {
        positionUpdateRunnable?.let {
            handler.removeCallbacks(it)
        }
        positionUpdateRunnable = null
    }

    override fun getView(): View = containerView

    override fun dispose() {
        isDisposed = true
        stopPositionUpdates()
        methodChannel?.setMethodCallHandler(null)
        player.stop()
        player.release()
    }
}
