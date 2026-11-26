//  Created by lzmlsfe on 2025/7/10.
//

import AVFoundation
import Foundation
import tuikit_atomic_x
import os.log

/// 协调系统与腾讯录音器，并向平台桥接交付音量、进度和录音结果。
internal class AudioRecorderImpl: AudioRecorder {
    private let logger = Logger(subsystem: "AudioRecoder", category: "AudioRecorderControl")
    /// 默认最短可发送时长，单位为毫秒。
    private static let kMinDuration: Int = 1000
    /// 单条语音默认采音上限，单位为毫秒。
    private static let kMaxDuration: Int = 60000
    
    private var recordedFilePath: String?
    /// 当前片段使用的录音器，停止与取消必须交给同一实例。
    private var recorder: AudioRecorderInternalProtocol?
    /// 普通语音从系统录音器读取实时音量。
    private let systemRecorder = AudioRecorderSystem()
    /// 仅在请求 AI 降噪时初始化腾讯录音器。
    private lazy var denoisingRecorder = AudioRecorderTXUGC()
    private var isCancelRecord:Bool = false
    /// 录音开始后置位；手动停止或录音器主动结束后允许下一次录音。
    private var isRecording: Bool = false
    /// 当前原生片段的毫秒上限，续录时取整条语音的剩余额度。
    private var maxDurationMs: Int = AudioRecorderImpl.kMaxDuration
    /// 最近一次原生录音进度，作为正常结束时回传的毫秒时长。
    private var currentTime: Int = 0
    
    /// 请求麦克风权限，通过后在主线程启动当前毫秒额度内的录音。
    override public func startRecord(filepath: String? = nil, enableAIDeNoise: Bool = false,
                                     minDurationMs: Int = AudioRecorderImpl.kMinDuration, maxDurationMs: Int = AudioRecorderImpl.kMaxDuration) {
        logger.info("start record file path is \( filepath ?? "") enableAIDeNoise : \(enableAIDeNoise) minDuration: \(minDurationMs) maxDuration : \(maxDurationMs)")
        
        checkMicPermission { [weak self] isGranted, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if isGranted {
                    self.executeOnMainThread {
                        self.startRecordInternal(
                            filepath,
                            enableAIDeNoise: enableAIDeNoise,
                            minDurationMs: minDurationMs,
                            maxDurationMs: maxDurationMs
                        )
                    }
                } else {
                    self.logger.error("request record audio permission refuse")
                    self.notifyCompleteOnMainThread(.errorRecordPermissionDenied)
                }
            }
        }
    }
    
    override public func stopRecord() {
        logger.info("stop record")
        executeOnMainThread {
            if (!self.isRecording) {
                return
            }
            self.isRecording = false
            if let recorder = self.recorder  {
                recorder.stopRecord()
            }
        }
    }
    
    override public func cancelRecord() {
        logger.info("cancel record")
        executeOnMainThread {
            if (!self.isRecording) {
                return
            }
            self.isCancelRecord = true
            self.notifyCompleteOnMainThread(.errorCancel)
            self.stopRecord()
        }
    }
    
    /// 两种录音器共用回调，平台桥接沿用同一事件格式。
    private lazy var recorderListener: AudioRecorderListener = {
        var listener = AudioRecorderListener()
        listener.onProgress = { [weak self] duration in
            self?.currentTime = duration
            self?.onRecordTime?(duration)
        }
        listener.onPower = { [weak self] power in
            self?.onPowerLevel?(power)
        }
        listener.onComplete = { [weak self] result in
            self?.onComplete(result)
        }
        return listener
    }()
    
    /// 权限通过后为当前片段选择录音器，重复启动不能改写正在采音的配置。
    private func startRecordInternal(
        _ filepath: String?,
        enableAIDeNoise: Bool,
        minDurationMs: Int,
        maxDurationMs: Int
    ) {
        logger.info("start record internal")
        if isRecording {
            logger.error("recording failed because it is currently being recorded")
            notifyCompleteOnMainThread(.errorRecording)
            return
        }
        
        recordedFilePath = filepath
        if recordedFilePath == nil {
            recordedFilePath = createRecordedFilePath()
        }
        
        guard let recordedFilePath = recordedFilePath, !recordedFilePath.isEmpty else {
            logger.error("start record fail. because recorder init fail or recorded file path is empty")
            notifyCompleteOnMainThread(.errorStorageUnavailable)
            return
        }
        
        // 腾讯录音器仅回传时长和完成事件，普通录音选择系统录音器提供波形音量。
        let recorder: AudioRecorderInternalProtocol
        if enableAIDeNoise, let denoisingRecorder = denoisingRecorder {
            denoisingRecorder.enableAIDeNoise(true)
            recorder = denoisingRecorder
        } else {
            recorder = systemRecorder
        }
        recorder.setListener(recorderListener)
        self.recorder = recorder
        self.maxDurationMs = maxDurationMs
        
        // 原生启动失败可能在 startRecord 内同步回调，先置位才能在终态正确复位。
        isRecording = true
        isCancelRecord = false
        recorder.startRecord(recordedFilePath, minDurationMs, maxDurationMs)
    }
    
    private func createRecordedFilePath()->String {
        let path = ChatUtils.generateMediaPath(messageType: .sound, withExtension: "m4a")
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        return path
    }
    
    private func checkMicPermission(completion: @escaping (Bool, Bool) -> Void) {
        let permission = AVAudioSession.sharedInstance().recordPermission
        
        if permission == .denied || permission == .undetermined {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted, true)
                }
            }
            return
        }
        
        let isGranted = permission == .granted
        completion(isGranted, false)
    }
    
    /// 统一把终态和毫秒时长交给平台桥接；超时以原生上限为准，不依赖最后一次进度采样。
    private func notifyCompleteOnMainThread(_ retCode: AudioRecordResultCode) {
        executeOnMainThread {
            if !self.isCancelRecord {
                let durationMs = retCode == .exceedMaxDuration ? self.maxDurationMs : self.currentTime
                self.onRecordingComplete?(retCode, self.recordedFilePath ?? "", durationMs)
            } else {
                DispatchQueue.global().async {
                    self.removeRecordFile(self.recordedFilePath)
                }
            }
            self.currentTime = 0;
        }
    }
    
    /// 原生自动停止与手动停止经过同一终态，避免录满一条后阻止后续录音。
    private func onComplete(_ retCode:AudioRecordResultCode) {
        executeOnMainThread {
            self.isRecording = false
            self.notifyCompleteOnMainThread(retCode)
        }
    }
    
    private func removeRecordFile(_ path : String?) {
        logger.info("remove record file")
        if let path = path, FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
    
    func executeOnMainThread(_ closure: @escaping () -> Void) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.async {
                closure()
            }
        }
    }
}
