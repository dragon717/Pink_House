//
//  OpsFetchedMedia.swift
//  PinkHouseOps
//
//  「从远端下载图片字节」的产物模型（双向同步里「下载」那一档）。
//
//  ## 为什么要在包里单独建一个模型，而不是让界面去读目录
//
//  桥接器把结果写成两份东西：`<hash>.<ext>` 一堆文件 + 一份 `fetch-manifest.json`。
//  如果让界面自己列目录，就会出现「数出来 8 个文件」这种结论 —— 而它**分不清**：
//    · 远端根本没有这条 THMedia（`missing`）；
//    · 摘要不符被丢弃（`corrupt`）；
//    · 认不出图片格式被跳过（`unrecognizedFormat`）。
//  这三种「没拿到」的处置完全不同：第一种是正常的（远端本来就可能没有），
//  后两种是**要看一眼的问题**。合成一句「下载了 8 张」就把它们全吞了。
//
//  所以明细从 manifest 读，**它是桥接器唯一的下结论处**。
//
//  ## 文件名即内容摘要（这是能用起来的前提）
//
//  桥接器落盘的文件名是 `<内容摘要>.<后缀>`，而 staging 的命名口径
//  （`ShopCatalogMediaStaging.StagedMedia.fileName`）**逐字相同**。
//  所以下载下来的文件可以**直接进 staging**，不需要改名、不需要对照表 ——
//  顺带保证「下次再跑不会重复下载」（内容寻址天然幂等）。
//

import Foundation
import SharedCatalog

// MARK: - 一张图

/// 一张下载成功的图。
public nonisolated struct OpsFetchedMediaFile: Identifiable, Equatable, Sendable {
    /// 内容摘要（64 位 hex），同时充当 `id`
    public let contentHash: String
    /// 落盘文件名（`<contentHash>.<ext>`）
    public let fileName: String
    public let byteCount: Int

    public var id: String { contentHash }

    public init(contentHash: String, fileName: String, byteCount: Int = 0) {
        self.contentHash = contentHash
        self.fileName = fileName
        self.byteCount = byteCount
    }

    /// 短摘要（界面上放不下 64 位）
    public var shortHash: String { String(contentHash.prefix(12)) + "…" }
}

// MARK: - 一次下载的全部结果

public nonisolated struct OpsFetchedMedia: Equatable, Sendable {

    /// 落盘目录（`<hash>.<ext>` 与 `fetch-manifest.json` 都在这里）
    public var directory: String
    /// 从哪个环境下载的
    public var environment: String
    /// 请求了几张（去重后）
    public var requested: Int
    /// 下载成功并自证摘要的
    public var files: [OpsFetchedMediaFile]
    /// 远端**确实没有**这几条 THMedia（正常情况，不是失败）
    public var missing: [String]
    /// 摘要不符 / 落盘失败，已丢弃（**要看一眼**）
    public var corrupt: [String]
    /// 认不出图片格式，已跳过（**要看一眼**：不猜后缀，见桥接器的说明）
    public var unrecognizedFormat: [String]
    public var pending: [String]
    public var fetchedAt: Date

    public init(
        directory: String,
        environment: String,
        requested: Int = 0,
        files: [OpsFetchedMediaFile] = [],
        missing: [String] = [],
        corrupt: [String] = [],
        unrecognizedFormat: [String] = [],
        fetchedAt: Date = Date(),
        pending: [String] = []
    ) {
        self.directory = directory
        self.environment = environment
        self.requested = requested
        self.files = files
        self.missing = missing
        self.corrupt = corrupt
        self.unrecognizedFormat = unrecognizedFormat
        self.fetchedAt = fetchedAt
        self.pending = pending
    }

    public var directoryURL: URL { URL(fileURLWithPath: directory, isDirectory: true) }

    /// 一句话结论。**只报事实**，不写「同步完成」这类越界的措辞 ——
    /// 下载只是双向同步的一半，另一半（上传）由发布完成。
    public var summaryText: String {
        var parts = ["下载 \(files.count)/\(requested) 张"]
        if !missing.isEmpty { parts.append("远端没有 \(missing.count) 张") }
        if !corrupt.isEmpty { parts.append("摘要不符 \(corrupt.count) 张") }
        if !unrecognizedFormat.isEmpty { parts.append("认不出格式 \(unrecognizedFormat.count) 张") }
        if !pending.isEmpty { parts.append("未完成 \(pending.count) 张") }
        return "\(environment) · " + parts.joined(separator: " · ")
    }

    /// 有没有**需要人看一眼**的问题（远端没有不算问题）。
    public var hasAnomalies: Bool { !corrupt.isEmpty || !unrecognizedFormat.isEmpty || !pending.isEmpty }

    // MARK: 读 manifest

    /// 桥接器写的 `fetch-manifest.json`（只取本模型需要的字段，其余一概忽略 ——
    /// 桥接器加字段时不该让 App 解不开）。
    private struct Manifest: Decodable {
        struct Item: Decodable {
            let contentHash: String
            let fileName: String
            let byteCount: Int?
        }
        let requested: Int?
        let downloaded: [Item]?
        let missing: [String]?
        let corrupt: [String]?
        let unrecognizedFormat: [String]?
        let pending: [String]?
    }

    /// 从落盘目录读明细。**读不出来返回 nil** —— 调用方必须把它当成
    /// 「这次没有可用结果」，而不是「下载了 0 张」（后者会让人以为远端没有图）。
    public static func load(directory: String, environment: String) -> OpsFetchedMedia? {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("fetch-manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else { return nil }
        let files = (manifest.downloaded ?? []).map {
            OpsFetchedMediaFile(contentHash: $0.contentHash,
                                fileName: $0.fileName,
                                byteCount: $0.byteCount ?? 0)
        }
        return OpsFetchedMedia(
            directory: directory,
            environment: environment,
            requested: manifest.requested ?? files.count,
            files: files,
            missing: manifest.missing ?? [],
            corrupt: manifest.corrupt ?? [],
            unrecognizedFormat: manifest.unrecognizedFormat ?? [],
            pending: manifest.pending ?? [])
    }

    /// 从一次桥接调用的结果里取出下载结果。
    /// nil = 这次跑的不是 `fetchMedia`，或桥接器没给出目录（**不是**「下载了 0 张」）。
    public static func from(
        result: OpsBridgeRunResult,
        environment: String,
        at date: Date = Date()
    ) -> OpsFetchedMedia? {
        guard let path = result.fetchedMediaPath, !path.isEmpty else { return nil }
        return load(directory: path, environment: environment)
    }
}
