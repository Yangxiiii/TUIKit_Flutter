package com.tencent.cloud.tuikit.flutter.tuichatkit.videoplayer
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class AtomicVideoPlayerPlugin : FlutterPlugin {
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        
        // Register PlatformView for inline playback (Flutter controls)
        //
        // 注册 PlatformView 以实现内联播放（Flutter 控件）
        binding.platformViewRegistry.registerViewFactory(
            "tencent_chat_uikit/inline_video_player",
            InlineVideoPlayerViewFactoryWithChannel(binding)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = null
    }
}

/**
 * Factory that creates InlineVideoPlayerPlatformView with MethodChannel support
 *
 * 创建支持 MethodChannel 的 InlineVideoPlayerPlatformView 的工厂
 */
class InlineVideoPlayerViewFactoryWithChannel(
    private val binding: FlutterPlugin.FlutterPluginBinding
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<*, *>
        val platformView = InlineVideoPlayerPlatformView(context, viewId, creationParams)
        
        // Create and set MethodChannel for this view
        //
        // 为此视图创建并设置 MethodChannel
        val channel = MethodChannel(
            binding.binaryMessenger,
            "tencent_chat_uikit/inline_video_player_$viewId"
        )
        platformView.setMethodChannel(channel)
        
        return platformView
    }
}
