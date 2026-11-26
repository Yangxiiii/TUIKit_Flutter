//  Created by lzmlsfe on 2025/7/4.

import os.log
import AVFoundation
import Foundation

/// 使用系统录音器限制采音时长，定时交付波形音量，并统一停止结果。
internal class AudioRecorderSystem: NSObject, AudioRecorderInternalProtocol, AVAudioRecorderDelegate {
    let logger = Logger(subsystem: "AudioRecoder", category: "AudioRecorderSystem")
    
    private var listener: AudioRecorderListener?
    private var recorder: AVAudioRecorder?
    /// 短于此时长的片段不能发送，单位为毫秒。
    private var minDurationMs: Int = 1000
    /// 当前片段的采音上限，续录时等于整条语音的剩余额度。
    private var maxDurationMs: Int = 60000

    /// 仅用于刷新波形和进度，在任一录音终态释放。
    private var recordTimer: Timer?
    
    private let recordSetting: [String: Any] = [
        AVSampleRateKey: 16000.0,
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVLinearPCMBitDepthKey: 16,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
    
    /// 会话准备完成后启动系统限时采音，上限由录音器执行。
    func startRecord(_ path : String, _ minDuration: Int, _ maxDuration: Int) {
        self.minDurationMs = minDuration
        self.maxDurationMs = maxDuration
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord)
            try session.setActive(true)
        } catch {
            logger.error("Failed to set audio session category or activate session: \(error)")
            listener?.onComplete(.errorRecordInnerFail);
            return
        }
        
        let url = URL(fileURLWithPath: path)
        do {
            let recorder = try AVAudioRecorder(url: url, settings: recordSetting)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            // 系统按录音时间截断，界面的进度采样间隔不会推迟停止。
            guard recorder.record(forDuration: Double(maxDurationMs) / 1000) else {
                listener?.onComplete(.errorRecordInnerFail)
                return
            }
            self.recorder = recorder
        } catch {
            logger.error("Failed to initialize AVAudioRecorder: \(error)")
            listener?.onComplete(.errorRecordInnerFail);
            return
        }
        
        // 每 100 毫秒采样一次，与 Android 保持一致；长按跟踪期间也要刷新波形。
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(onRecordTimer), userInfo: nil, repeats: true)
        recordTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        logger.info("start system recording")
    }
    
    /// 松手时读取尚未归零的录音时间，等文件关闭后再交付结果。
    func stopRecord() {
        // 已达到系统上限时由委托回调交付，避免松手抢先读到归零的时长。
        guard let recorder = recorder, recorder.isRecording else { return }
        let durationMs = min(Int(recorder.currentTime * 1000), maxDurationMs)
        recorder.delegate = nil
        recorder.stop()
        let result: AudioRecordResultCode = durationMs < minDurationMs
            ? .errorLessThanMinDuration : .success
        finishRecord(durationMs, result)
    }

    /// 手动停止已解除委托，仍由当前录音器交付的成功回调表示达到限时。
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recorder === self.recorder else { return }
        guard flag else {
            finishRecord(0, .errorRecordInnerFail)
            return
        }
        finishRecord(maxDurationMs, maxDurationMs < minDurationMs ? .errorLessThanMinDuration : .exceedMaxDuration)
    }

    /// 清理本次采音和计时后再发布终态，允许下一段重新启动。
    private func finishRecord(_ durationMs: Int, _ result: AudioRecordResultCode) {
        recorder = nil
        recordTimer?.invalidate()
        recordTimer = nil
        listener?.onProgress(durationMs)
        listener?.onComplete(result)
    }
    
    func setListener(_ listener: AudioRecorderListener) {
        self.listener = listener
    }
    
    func enableAIDeNoise(_ enable : Bool) {
        if (!enable) {
            return;
        }
        
        // Note: WindowToastManager is not available in Flutter plugin
        // System audio recorder does not support AI denoising
        //
        // 注意：Flutter 插件中不可用 WindowToastManager 系统音频录音器不支持 AI 降噪
        logger.error("system audio record do not support ai de noise");
        #if DEBUG
          logger.warning("AI DeNoise is not supported by system audio recorder.")
        #endif
    }
    
    /// 正在采音时才更新波形和进度，系统结束到委托交付之间忽略归零读数。
    @objc private func onRecordTimer() {
        guard let recorder = recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        listener?.onProgress(Int(recorder.currentTime * 1000))
        listener?.onPower(Int(recorder.averagePower(forChannel: 0)))
    }
}
