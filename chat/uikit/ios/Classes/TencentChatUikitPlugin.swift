import Flutter
import UIKit

/// TencentChatUikitPlugin
///
/// Hosts the chat-business native handlers that previously lived in
/// AtomicXPlugin. Module/handler ownership matches the Dart-side migration:
///   audio_player, audio_recoder, file_picker, video_player, video_recorder.
///
/// 托管之前在 AtomicXPlugin 中的聊天业务原生处理程序。模块/处理程序的归属与 Dart
/// 端迁移一致：audio_player、audio_recoder、file_picker、video_player、video_recorder。
public class TencentChatUikitPlugin: NSObject, FlutterPlugin {
  private var videoRecorder: AtomicVideoRecorderPlugin?
  private var audioRecorder: AtomicAudioRecorderPlugin?
  private var audioPlayer: AtomicAudioPlayerPlugin?
  private var filePicker: AtomicFilePickerPlugin?
  private var videoPlayer: AtomicVideoPlayerPlugin?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "tencent_chat_uikit",
      binaryMessenger: registrar.messenger()
    )
    let instance = TencentChatUikitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    instance.videoRecorder = AtomicVideoRecorderPlugin(registrar: registrar)
    instance.audioRecorder = AtomicAudioRecorderPlugin(registrar: registrar)
    instance.audioPlayer = AtomicAudioPlayerPlugin(registrar: registrar)
    instance.filePicker = AtomicFilePickerPlugin(registrar: registrar)
    instance.videoPlayer = AtomicVideoPlayerPlugin.register(with: registrar) as? AtomicVideoPlayerPlugin
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "writeMessageClipboard":
      guard let args = call.arguments as? [String: String],
            let text = args["text"], let token = args["token"] else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: nil, details: nil))
        return
      }
      // 同一个条目提供公开文字和随机身份，其他应用读取到的文字不会包含格式。
      UIPasteboard.general.items = [[
        "public.utf8-plain-text": text,
        "com.tencent.cloud.tuichatkit.clip-token": Data(token.utf8),
      ]]
      result(nil)
    case "readMessageClipboardToken":
      let data = UIPasteboard.general.data(forPasteboardType: "com.tencent.cloud.tuichatkit.clip-token")
      result(data.flatMap { String(data: $0, encoding: .utf8) })
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  deinit {
    videoRecorder?.dispose()
    audioRecorder?.dispose()
    audioPlayer?.dispose()
    filePicker?.dispose()
  }
}
