import AVFoundation
import AVKit
import SwiftUI

/// 共享原生播放器契约，播放起点统一使用毫秒。
public class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayerImpl()
    
    public var onComplete: (() -> Void)?
    public var onProgressUpdate: ((_ currentPosition: Int, _ duration: Int) -> Void)?
    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onResume: (() -> Void)?
    public var onError: ((_ errorMessage: String) -> Void)?
    
    public func play(filePath: String, startPositionMs: Int = 0) {}
    
    public func pause() {}
    
    public func resume() {}
    
    public func stop() {}

    /// 设置下一次及当前语音的播放模式，失败由Flutter保留原菜单状态。
    public func setEarpiece(_ enabled: Bool) throws {}
    
    public func getCurrentPosition() -> Int { return 0 }
    
    public func getDuration() -> Int { return 0 }
    
    public func isPlaying() -> Bool { return false }
    
    public func isPaused() -> Bool { return false }
    
    override internal init() {
        super.init()
    }
}
