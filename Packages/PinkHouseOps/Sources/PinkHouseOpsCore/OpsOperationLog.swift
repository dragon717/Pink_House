import Foundation

/// 一轮业务操作只生成一个文件，各桥接调用按执行顺序追加。
public final class OpsOperationLog {
    public let url: URL
    private let handle: FileHandle

    public init(directory: URL, title: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        url = directory.appendingPathComponent("\(formatter.string(from: Date()))-sync-\(UUID().uuidString.prefix(8)).log")
        let header = "# \(title)\n开始时间：\(ISO8601DateFormatter().string(from: Date()))\n"
        try Data(header.utf8).write(to: url, options: .atomic)
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    public func append(_ output: String) throws {
        try handle.write(contentsOf: Data(("\n" + output + "\n").utf8))
    }

    public func finish(_ result: String) throws {
        try append("最终结果：\(result)\n结束时间：\(ISO8601DateFormatter().string(from: Date()))")
    }

    deinit { try? handle.close() }
}
