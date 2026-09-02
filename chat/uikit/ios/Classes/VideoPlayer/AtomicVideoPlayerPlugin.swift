import Flutter
import UIKit

public class AtomicVideoPlayerPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Register InlineVideoPlayer PlatformView (controls handled by Flutter)
        //
        // 注册 InlineVideoPlayer 平台视图（控件由 Flutter 处理）
        let inlineFactory = InlineVideoPlayerViewFactory(messenger: registrar.messenger())
        registrar.register(
            inlineFactory,
            withId: "tencent_chat_uikit/inline_video_player"
        )
    }
}
