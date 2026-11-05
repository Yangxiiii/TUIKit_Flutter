import Foundation
import AVFoundation

/// 在具备AVFoundation的主机上验证顺序拼接、输入保护及失败清理。
@main
enum AudioClipMergerCheck {
    static func main() throws {
        let arguments = CommandLine.arguments
        precondition(arguments.count == 4)
        let paths = [arguments[1], arguments[2]]
        let output = arguments[3]
        let originals = try paths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        let merged = try run(paths, output).get()
        precondition(merged.path == output && merged.durationMs > 2000)
        let decoded = try AVAudioFile(forReading: URL(fileURLWithPath: output))
        precondition(decoded.length > 0)

        // 对已合并音频再次续录，验证结果仍是完整的A+B+A且累计时长增长。
        let continued = try run([output, paths[0]], output + ".continued.m4a").get()
        let continuedAudio = try AVAudioFile(forReading: URL(fileURLWithPath: continued.path))
        precondition(continued.durationMs > merged.durationMs + 1000 && continuedAudio.length > decoded.length)

        // 已有目标必须保持原样，损坏输入也不能留下半成品或影响原音。
        if case .success = run(paths, paths[0]) { preconditionFailure("Existing output replaced") }
        let failedOutput = output + ".failed.m4a"
        if case .success = run([paths[0], output + ".missing"], failedOutput) {
            preconditionFailure("Missing input accepted")
        }
        precondition(!FileManager.default.fileExists(atPath: failedOutput))
        for (index, path) in paths.enumerated() {
            let unchanged = try Data(contentsOf: URL(fileURLWithPath: path))
            precondition(unchanged == originals[index])
        }
        print("Audio merge verified: \(merged.durationMs) ms; continued: \(continued.durationMs) ms")
    }

    /// 仅用于命令行自检，等待原生异步导出并保留原始错误。
    private static func run(
        _ paths: [String], _ destination: String
    ) -> Result<(path: String, durationMs: Int), Error> {
        let ready = DispatchSemaphore(value: 0)
        var result: Result<(path: String, durationMs: Int), Error>?
        AudioClipMerger.merge(paths: paths, destination: destination) {
            result = $0
            ready.signal()
        }
        precondition(ready.wait(timeout: .now() + 30) == .success)
        return result!
    }
}
