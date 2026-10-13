import Foundation
import CryptoKit

nonisolated struct WardrobeStorageImageSource: Hashable, Sendable {
    let preferredCutout: String?
    let originals: [String]
    let revision: TimeInterval

    var key: String { ([preferredCutout ?? ""] + originals + [String(revision)]).joined(separator: "|") }
    var isEmpty: Bool { preferredCutout == nil && originals.isEmpty }
}

nonisolated struct WardrobeStorageResolvedImage: Sendable {
    let data: Data?
    let isCutout: Bool
    let canRetry: Bool
}

/// A single background worker bounds segmentation memory and coalesces identical source bytes.
/// Only successful, transparent derivatives survive relaunch; failures are retryable.
actor WardrobeStorageCutoutCache {
    static let shared = WardrobeStorageCutoutCache()
    private let directory: URL
    private let processor: @Sendable (Data) -> Data?
    private let memory = NSCache<NSString, NSData>()
    private var failures: [String: Date] = [:]
    private var writes = 0

    init(directory: URL? = nil, processor: @escaping @Sendable (Data) -> Data? = { WardrobeStorageCutoutProcessor.process($0) }) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WardrobeStorageCutouts/v1", isDirectory: true)
        self.processor = processor
        memory.countLimit = 80
        memory.totalCostLimit = 32 * 1024 * 1024
    }

    func resolve(_ source: WardrobeStorageImageSource, imagesDirectory: URL) -> WardrobeStorageResolvedImage {
        let paths = [source.preferredCutout].compactMap { $0 } + source.originals
        var seen = Set<String>()
        var fallback: Data?
        for path in paths {
            if Task.isCancelled { break }
            let file = (path as NSString).lastPathComponent
            guard !file.isEmpty, seen.insert(file).inserted,
                  let data = try? Data(contentsOf: imagesDirectory.appendingPathComponent(file)) else { continue }
            if fallback == nil || path == source.originals.first { fallback = data }
            if let cutout = cutout(for: data) {
                return WardrobeStorageResolvedImage(data: cutout, isCutout: true, canRetry: false)
            }
        }
        return WardrobeStorageResolvedImage(data: fallback, isCutout: false, canRetry: !paths.isEmpty)
    }

    func clearFailures() { failures.removeAll() }

    private func cutout(for data: Data) -> Data? {
        guard !Task.isCancelled else { return nil }
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let cached = memory.object(forKey: key as NSString) { return cached as Data }
        let file = directory.appendingPathComponent(key + ".png")
        if let cached = try? Data(contentsOf: file), let image = WardrobeStorageCutoutProcessor.decode(cached),
           WardrobeStorageCutoutProcessor.Pixels(image)?.isCutout == true {
            memory.setObject(cached as NSData, forKey: key as NSString, cost: cached.count)
            return cached
        }
        if let failedAt = failures[key], Date().timeIntervalSince(failedAt) < 120 { return nil }
        let processed = autoreleasepool { processor(data) }
        guard !Task.isCancelled else { return nil }
        guard let processed, let image = WardrobeStorageCutoutProcessor.decode(processed),
              WardrobeStorageCutoutProcessor.Pixels(image)?.isCutout == true else {
            failures[key] = Date()
            return nil
        }
        failures[key] = nil
        memory.setObject(processed as NSData, forKey: key as NSString, cost: processed.count)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? processed.write(to: file, options: .atomic)
        writes += 1
        if writes % 10 == 0 { trimDiskCache() }
        return processed
    }

    private func trimDiskCache() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.filter { $0.pathExtension == "png" }.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = entries.reduce(0) { $0 + $1.1 }
        while bytes > 128 * 1024 * 1024 || entries.count > 256 {
            let oldest = entries.removeFirst()
            try? FileManager.default.removeItem(at: oldest.0)
            bytes -= oldest.1
        }
    }
}
