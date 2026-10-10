import Foundation
import SharedCatalog

/// 补交接包遗漏的本地图片。仅接受原引用文件名，保留原字节和已有 staging 文件。
public nonisolated enum OpsLocalImageRepair {
    public struct Report: Equatable, Sendable {
        public var restored: [String] = []
        public var alreadyPresent: [String] = []
        public var missing: [String] = []
        public var failures: [String: String] = [:]

        public var summary: String {
            "已补入 \(restored.count) 张图片；\(missing.count) 张在所选目录中找不到，\(failures.count) 张未能补入。"
        }
    }

    /// 来源可以是 images/、整包根目录或只套一层的解压目录；不需要导入目录 JSON。
    public static func restore(
        fileNames: Set<String>, from directory: URL, to staging: URL
    ) throws -> Report {
        let manager = FileManager.default
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        var directories = [root.appendingPathComponent("images", isDirectory: true), root]
        let children = try manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let packages = children.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                && manager.fileExists(atPath: $0.appendingPathComponent("shop-catalog.json").path)
        }
        if packages.count == 1, let package = packages.first {
            directories += [package.appendingPathComponent("images", isDirectory: true), package]
        }
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        var report = Report()
        for name in fileNames.sorted() {
            guard ShopCatalogMediaReferences.localFileName(in: "local:" + name) == name else {
                report.failures[name] = "图片文件名不合法"
                continue
            }
            let target = staging.appendingPathComponent(name)
            guard !manager.fileExists(atPath: target.path) else {
                report.alreadyPresent.append(name)
                continue
            }
            let candidates = directories.map { $0.appendingPathComponent(name) }
            var found = false
            for candidate in candidates {
                let source = candidate.resolvingSymlinksInPath().standardizedFileURL
                guard source.path.hasPrefix(root.path + "/"),
                      manager.fileExists(atPath: source.path) else { continue }
                found = true
                do {
                    let data = try Data(contentsOf: source, options: .mappedIfSafe)
                    if let reason = ShopCatalogMediaStaging.rejectionReason(forStoredBytes: data) {
                        report.failures[name] = reason
                        continue
                    }
                    // 先完整写临时文件再移动；写盘失败不能留下被门禁误认作已补齐的残片。
                    let temporary = staging.appendingPathComponent(".image-repair-\(UUID().uuidString)")
                    defer { try? manager.removeItem(at: temporary) }
                    try data.write(to: temporary, options: .atomic)
                    // moveItem 遇到已有目标会失败，保留并发期间刚补入的原文件。
                    try manager.moveItem(at: temporary, to: target)
                    report.restored.append(name)
                    report.failures.removeValue(forKey: name)
                    break
                } catch {
                    report.failures[name] = error.localizedDescription
                }
            }
            if !found { report.missing.append(name) }
        }
        return report
    }
}
