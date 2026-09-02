import AVKit
import SwiftUI
import os.log

internal class AudioPlayerImpl: AudioPlayer, AVAudioPlayerDelegate {
    private let logger = Logger(subsystem: "AudioPlayer", category: "AudioPlayerControl")
    
    @Published public var isPlayingState: Bool = false
    @Published public var isPausedState: Bool = false
    @Published public var currentPlayingURL: URL? = nil
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

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

    override public func play(filePath: String) {
        logger.info("play: \(filePath)")

        let remote = isRemotePath(filePath)
        guard let url = remote
            ? URL(string: filePath)
            : (URL(string: filePath) ?? (URL(fileURLWithPath: filePath) as URL?)) else {
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
            playRemote(url)
        } else {
            playInternal(url)
        }
    }

    private func playRemote(_ url: URL) {
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
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

    private func playInternal(_ url: URL) {
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
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
