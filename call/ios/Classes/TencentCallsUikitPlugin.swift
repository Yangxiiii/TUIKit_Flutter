import Flutter
import UIKit
import RTCRoomEngine
import AVFoundation

/// 提供通话振动、系统来电同步及可翻转摄像头能力查询。
public class TencentCallsUikitPlugin: NSObject, FlutterPlugin, VoIPDataSyncHandlerDelegate {
    let voIPDataSyncHandler: VoIPDataSyncHandler
    let channel: FlutterMethodChannel
    
    init(channel: FlutterMethodChannel) {
        voIPDataSyncHandler = VoIPDataSyncHandler()
        self.channel = channel
        super.init()
        voIPDataSyncHandler.voipDataSyncHandlerDelegate = self
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "tencent_calls_uikit", binaryMessenger: registrar.messenger())
        let instance = TencentCallsUikitPlugin(channel: channel)
                
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCameraCount":
            // 按前后朝向去重，多枚后置镜头不能表示支持前后翻转。
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
            ).devices
            let positions = Set(devices.filter {
                $0.position == .front || $0.position == .back
            }.map { $0.position.rawValue })
            result(positions.count)
        case "startVibration":
            startVibration(call, result: result)
        case "stopVibration":
            stopVibration(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startVibration(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        CallingVibrator.startVibration()
        result(nil)
    }
    
    private func stopVibration(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        CallingVibrator.stopVibration()
        result(nil)
    }
}


// MARK: VoIPDataSyncHandlerDelegate
extension TencentCallsUikitPlugin {
    func callMethodVoipChangeMute(mute: Bool) {
        channel.invokeMethod("voipMute", arguments: ["mute": mute])
    }
    
    func callMethodVoipChangeAudioPlaybackDevice(audioPlaybackDevice: TUIAudioPlaybackDevice) {
        channel.invokeMethod("voipAudioPlaybackDevice", arguments: ["audioPlaybackDevice": audioPlaybackDevice.rawValue])
    }
    
    func callMethodVoipHangup() {
        channel.invokeMethod("voipHangup", arguments: [:])
    }
    
    func callMethodVoipAccept() {
        channel.invokeMethod("voipAccept", arguments: [:])
    }
}
