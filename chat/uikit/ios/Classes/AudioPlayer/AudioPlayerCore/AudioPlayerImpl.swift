import AVKit
import SwiftUI
import os.log

/// 复用原生本地及流媒体播放器，在开始播放前恢复本消息暂停位置。
internal class AudioPlayerImpl: AudioPlayer, AVAudioPlayerDelegate {
    private let logger = Logger(subsystem: "AudioPlayer", category: "AudioPlayerControl")
    
    @Published public var isPlayingState: Bool = false
    @Published public var isPausedState: Bool = false
    @Published public var currentPlayingURL: URL? = nil
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    /// 播放方式是共享偏好，原生会话在停止时恢复，下一条音源仍沿用该偏好。
    private var earpieceMode = false
    private var routeConfigured = false
    #if os(iOS)
    private var previousSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    #endif

    override public func setEarpiece(_ enabled: Bool) throws {
        let previous = earpieceMode
        let configured = routeConfigured
        earpieceMode = enabled
        routeConfigured = true
        // 未开始播放时只核实能力并保存偏好，立即归还系统音频会话。
        defer { if !isPlayingState { restoreAudioSession() } }
        do { try configureAudioSession() } catch {
            earpieceMode = previous
            routeConfigured = configured
            restoreAudioSession()
            if isPlayingState || isPausedState { try? configureAudioSession() }
            throw error
        }
    }

    /// 只在用户选择通信播放路由后采用双向会话，普通播放继续使用原有播放类别。
    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if routeConfigured {
            if previousSession == nil { previousSession = (session.category, session.mode, session.categoryOptions) }
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            try session.overrideOutputAudioPort(earpieceMode ? .none : .speaker)
            let expected: AVAudioSession.Port = earpieceMode ? .builtInReceiver : .builtInSpeaker
            guard session.currentRoute.outputs.contains(where: { $0.portType == expected }) else {
                throw NSError(domain: "ChatAudioRoute", code: 1)
            }
        } else {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        }
        #endif
    }

    /// 外部通话已改成其他会话模式时不回写旧配置，避免停止语音覆盖通话资源。
    private func restoreAudioSession() {
        #if os(iOS)
        guard let previous = previousSession else { return }
        previousSession = nil
        let session = AVAudioSession.sharedInstance()
        if session.category == .playAndRecord && session.mode == .default {
            try? session.overrideOutputAudioPort(.none)
            try? session.setCategory(previous.0, mode: previous.1, options: previous.2)
        }
        #endif
    }

    // Remote (http/https) playback uses AVPlayer because AVAudioPlayer cannot
    // stream remote URLs. Local files keep using AVAudioPlayer.
    //
    // 远程（http/https）播放使用AVPlayer，因为AVAudioPlayer不能播放远程URL。本地文件仍然使用AVAudioPlayer。
    private var remotePlayer: AVPlayer?
    private var remoteTimeObserver: Any?
    private var isRemote: Bool = false

    /// Whether the given path should be played as a streamed remote resource.
    ///
    /// 是否应将给定路径作为流媒体远程资源播放。
    private func isRemotePath(_ filePath: String) -> Bool {
        let lower = filePath.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    override public func play(filePath: String, startPositionMs: Int = 0) {
        logger.info("play: \(filePath)")

        let remote = isRemotePath(filePath)
        guard let url = remote
            ? URL(string: filePath)
            : URL(fileURLWithPath: filePath) else {
            logger.error("Invalid file path: \(filePath)")
            onError?("Invalid file path")
            return
        }

        if isPlayingState && currentPlayingURL == url {
            logger.info("Already playing same file, stopping")
            stop()
            return
        }

        if isPlayingState || isPausedState {
            logger.info("Stopping current playback")
            stop()
        }

        if remote {
            playRemote(url, startPositionMs: startPositionMs)
        } else {
            playInternal(url, startPositionMs: startPositionMs)
        }
    }

    private func playRemote(_ url: URL, startPositionMs: Int) {
        do {
            try configureAudioSession()
        } catch {
            logger.error("AudioSession error: \(error.localizedDescription)")
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        remotePlayer = player
        isRemote = true
        currentPlayingURL = url

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remoteDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remoteDidFail),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item)

        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        remoteTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self, self.isRemote else { return }
            self.onProgressUpdate?(self.getCurrentPosition(), self.getDuration())
        }

        if startPositionMs > 0 {
            player.seek(to: CMTime(seconds: Double(startPositionMs) / 1000, preferredTimescale: 1000))
        }
        player.play()
        isPlayingState = true
        isPausedState = false
        onPlay?()
        logger.info("Remote playback started")
    }

    @objc private func remoteDidFinish() {
        logger.info("Remote playback finished")
        let completion = onComplete
        teardownRemote()
        completion?()
    }

    @objc private func remoteDidFail() {
        logger.error("Remote playback failed")
        let errorCallback = onError
        teardownRemote()
        errorCallback?("Remote playback failed")
    }

    private func teardownRemote() {
        restoreAudioSession()
        if let observer = remoteTimeObserver {
            remotePlayer?.removeTimeObserver(observer)
            remoteTimeObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        remotePlayer?.pause()
        remotePlayer = nil
        isRemote = false
        isPlayingState = false
        isPausedState = false
        currentPlayingURL = nil
    }

    override public func pause() {
        // 暂停保留文件位置，但立即归还本播放器接管的系统路由。
        defer { if isPausedState { restoreAudioSession() } }
        logger.info("pause")
        if isRemote {
            guard let player = remotePlayer, isPlayingState else { return }
            player.pause()
            isPlayingState = false
            isPausedState = true
            onPause?()
            return
        }
        guard let player = audioPlayer, isPlayingState else { return }
        player.pause()
        isPlayingState = false
        isPausedState = true
        stopProgressUpdates()
        onPause?()
    }

    override public func resume() {
        logger.info("resume")
        guard isPausedState else { return }
        do { try configureAudioSession() } catch {
            onError?("Audio route restore failed")
            return
        }
        if isRemote {
            guard let player = remotePlayer, isPausedState else { return }
            player.play()
            isPlayingState = true
            isPausedState = false
            onResume?()
            return
        }
        guard let player = audioPlayer, isPausedState else { return }
        if player.play() {
            isPlayingState = true
            isPausedState = false
            startProgressUpdates()
            onResume?()
        }
    }

    override public func stop() {
        defer { restoreAudioSession() }
        logger.info("stop")
        if isRemote {
            teardownRemote()
            return
        }
        guard let player = audioPlayer else { return }
        player.stop()
        audioPlayer = nil
        isPlayingState = false
        isPausedState = false
        currentPlayingURL = nil
        stopProgressUpdates()
    }

    override public func getCurrentPosition() -> Int {
        if isRemote {
            guard let player = remotePlayer else { return 0 }
            let seconds = CMTimeGetSeconds(player.currentTime())
            return seconds.isFinite ? Int(seconds * 1000) : 0
        }
        guard let player = audioPlayer else { return 0 }
        return Int(player.currentTime * 1000) // Return milliseconds
    }

    override public func getDuration() -> Int {
        if isRemote {
            guard let item = remotePlayer?.currentItem else { return 0 }
            let seconds = CMTimeGetSeconds(item.duration)
            return seconds.isFinite ? Int(seconds * 1000) : 0
        }
        guard let player = audioPlayer else { return 0 }
        return Int(player.duration * 1000) // Return milliseconds
    }
    
    override public func isPlaying() -> Bool {
        return isPlayingState
    }
    
    override public func isPaused() -> Bool {
        return isPausedState
    }

    private func playInternal(_ url: URL, startPositionMs: Int) {
        do {
            try configureAudioSession()

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            // 新文件已经准备完成，先恢复毫秒起点，再通知界面开始播放。
            if let player = audioPlayer {
                player.currentTime = min(Double(startPositionMs) / 1000, player.duration)
            }
            if audioPlayer?.play() == true {
                isPlayingState = true
                isPausedState = false
                currentPlayingURL = url
                startProgressUpdates()
                onPlay?()
                logger.info("Playback started successfully")
            } else {
                logger.error("Audio playback failed")
                audioPlayer = nil
                isPlayingState = false
                isPausedState = false
                currentPlayingURL = nil
                onError?("Audio playback failed")
            }
        } catch {
            logger.error("Audio playback error: \(error.localizedDescription)")
            audioPlayer = nil
            isPlayingState = false
            isPausedState = false
            currentPlayingURL = nil
            onError?("Audio playback error: \(error.localizedDescription)")
        }
    }
    
    private func startProgressUpdates() {
        stopProgressUpdates()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlayingState else { return }
            let currentPosition = self.getCurrentPosition()
            let duration = self.getDuration()
            self.onProgressUpdate?(currentPosition, duration)
        }
    }
    
    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audioPlayer else { return }
        restoreAudioSession()
        logger.info("Playback finished successfully: \(flag)")
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingState = false
        isPausedState = false
        currentPlayingURL = nil
        stopProgressUpdates()
        onComplete?()
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === audioPlayer else { return }
        restoreAudioSession()
        let errorMessage = error?.localizedDescription ?? "Unknown error"
        logger.error("Audio player decoding error: \(errorMessage)")
        audioPlayer = nil
        isPlayingState = false
        isPausedState = false
        currentPlayingURL = nil
        stopProgressUpdates()
        onError?("Decode error: \(errorMessage)")
    }
}
