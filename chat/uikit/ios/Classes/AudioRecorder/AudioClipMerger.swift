import Foundation
import AVFoundation

/// 按录制顺序合并音轨并输出独立文件，原音在导出失败时仍保持可用。
enum AudioClipMerger {
    /// 新文件验证通过后才回传路径与毫秒时长，由草稿决定何时替换和清理。
    static func merge(
        paths: [String],
        destination: String,
        completion: @escaping (Result<(path: String, durationMs: Int), Error>) -> Void
    ) {
        let output = URL(fileURLWithPath: destination)
        guard paths.count >= 2,
              !FileManager.default.fileExists(atPath: destination),
              !paths.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL == output.standardizedFileURL }) else {
            completion(.failure(NSError(domain: "ChatAudioMerge", code: 1)))
            return
        }
        do {
            let composition = AVMutableComposition()
            guard let track = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw NSError(domain: "ChatAudioMerge", code: 2) }
            let limit = CMTime(seconds: 60, preferredTimescale: 60000)
            var cursor = CMTime.zero

            // 用音轨时间范围拼接，预览停顿不进入结果。
            for path in paths {
                let asset = AVURLAsset(url: URL(fileURLWithPath: path))
                guard let source = asset.tracks(withMediaType: .audio).first else {
                    throw NSError(domain: "ChatAudioMerge", code: 3)
                }
                let duration = CMTimeMinimum(source.timeRange.duration, CMTimeSubtract(limit, cursor))
                guard duration.isNumeric && CMTimeCompare(duration, .zero) > 0 else {
                    throw NSError(domain: "ChatAudioMerge", code: 4)
                }
                try track.insertTimeRange(
                    CMTimeRange(start: source.timeRange.start, duration: duration),
                    of: source, at: cursor
                )
                cursor = CMTimeAdd(cursor, duration)
                if CMTimeCompare(cursor, limit) >= 0 { break }
            }
            // 使用系统M4A导出预设统一续录片段，避免容器直接追加导致无法解码。
            guard let exporter = AVAssetExportSession(
                asset: composition, presetName: AVAssetExportPresetAppleM4A
            ), exporter.supportedFileTypes.contains(.m4a) else {
                throw NSError(domain: "ChatAudioMerge", code: 5)
            }
            exporter.outputURL = output
            exporter.outputFileType = .m4a
            exporter.exportAsynchronously {
                guard exporter.status == .completed else {
                    try? FileManager.default.removeItem(at: output)
                    completion(.failure(exporter.error ?? NSError(domain: "ChatAudioMerge", code: 6)))
                    return
                }
                // 重新解析输出音轨，失败时仅移除新文件，不能破坏原草稿。
                let merged = AVURLAsset(url: output)
                let seconds = CMTimeGetSeconds(merged.duration)
                guard seconds.isFinite, seconds >= 1, seconds <= 60,
                      !merged.tracks(withMediaType: .audio).isEmpty else {
                    try? FileManager.default.removeItem(at: output)
                    completion(.failure(NSError(domain: "ChatAudioMerge", code: 7)))
                    return
                }
                completion(.success((destination, Int((seconds * 1000).rounded()))))
            }
        } catch {
            completion(.failure(error))
        }
    }
}
