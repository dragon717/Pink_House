//
//  OpsWorkspace.swift
//  PinkHouseOps
//
//  Mac 运营工具的**编排层**：草稿装载、素材导入、发布前校验、导出待发布包。
//
//  ## 它在架构里的位置（计划 §3）
//
//      SharedCatalog（领域事实：模型 / 协议 / 图片规范化 / 发布门禁）
//            ↑                    ↑
//      ItemManager（iOS）    PinkHouseOps（Mac，本文件所在层）
//
//  本文件只做编排与落盘，**不重新定义任何口径**：
//    · 图片规范化与 mediaKey → `ShopCatalogMediaStaging`
//    · 发布前门禁       → `ShopCatalogPublicationGate`
//    · 任务状态机       → `MediaUploadJobMachine`
//    · JSON 编解码      → `ShopCatalogJSONCoding`
//    · 整包归档         → `ShopCatalogExportArchive`
//
//  ## 为什么素材必须立刻复制进 staging
//
//  `.fileImporter` 给的是 **security-scoped URL**：作用域只在当前会话内有效，
//  下次启动就取不到了；运营把图放在移动硬盘 / 另一台机器上再拔掉，文件也没了。
//  所以拿到 URL 的第一件事是把字节**复制进应用自己的目录**，
//  之后一切以 staging 副本为准（计划 §4.1 第 2 步）。
//  目录 JSON 同理 —— 导入之后草稿内容就是唯一事实来源，不再回读原路径。
//

import Combine
import Foundation
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class OpsWorkspace: ObservableObject {

    // MARK: 状态

    /// 当前草稿的元数据（nil = 还没建过草稿）
    @Published private(set) var draft: OpsCatalogDraftRecord?
    /// 内存里的工作副本。所有编辑改这一份，保存时整包编码落盘。
    @Published private(set) var catalog = ShopCatalog()
    /// 最近一次导入 / 导出 / 校验的可见反馈（界面上必须有地方显示，
    /// 否则「点了没反应」会被当成功能坏了 —— 计划 §7 的「失败必须可见」）
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?
    /// 导入的图片任务（按 mediaKey 唯一）
    @Published private(set) var mediaJobs: [MediaUploadJob] = []
    /// 最近一次发布前校验结果（nil = 还没校验过）
    @Published private(set) var review: ShopCatalogPublicationReview?

    private let context: ModelContext
    private let fileManager = FileManager.default

    init(context: ModelContext) {
        self.context = context
        loadOrCreateDraft()
    }

    // MARK: 目录位置

    /// 应用容器内的数据根目录。沙箱下就是
    /// `~/Library/Containers/bugod2.ItemManager.Ops/Data/Library/Application Support/PinkHouseOps/`
    var rootDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("PinkHouseOps", isDirectory: true)
    }

    /// 当前草稿的 staging 目录：图片副本与待发布包都放这里
    var stagingDirectory: URL {
        let name = draft?.stagingFolderName ?? "default"
        return rootDirectory
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// staging 里现有的文件名集合（门禁据此判断「引用到的图在不在本机」）
    var stagedFileNames: Set<String> {
        let names = (try? fileManager.contentsOfDirectory(atPath: stagingDirectory.path)) ?? []
        return Set(names)
    }

    // MARK: 草稿装载 / 保存

    private func loadOrCreateDraft() {
        let descriptor = FetchDescriptor<OpsCatalogDraftRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let existing = (try? context.fetch(descriptor)) ?? []
        if let first = existing.first {
            adopt(first)
            statusMessage = "已恢复上次草稿「\(first.title)」"
        } else {
            createDraft(title: defaultDraftTitle())
        }
        loadMediaJobs()
    }

    private func defaultDraftTitle() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: Date())) 上新"
    }

    private func adopt(_ record: OpsCatalogDraftRecord) {
        draft = record
        do {
            catalog = try ShopCatalogJSONCoding.decoder()
                .decode(ShopCatalog.self, from: record.catalogJSON)
            lastError = nil
        } catch {
            // 坏 JSON 不静默兜成空目录（会把能抢救的内容覆盖掉）
            catalog = ShopCatalog()
            lastError = "草稿内容无法解析，已按空目录打开且**不会自动覆盖**原文件："
                + error.localizedDescription
        }
        try? fileManager.createDirectory(
            at: stagingDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    func createDraft(title: String) -> OpsCatalogDraftRecord {
        let empty = ShopCatalog()
        let data = (try? ShopCatalogJSONCoding.encoder(prettyPrinted: true).encode(empty))
            ?? Data("{}".utf8)
        let record = OpsCatalogDraftRecord(title: title, catalogJSON: data)
        context.insert(record)
        try? context.save()
        adopt(record)
        statusMessage = "已新建草稿「\(title)」"
        lastError = nil
        return record
    }

    /// 落盘。**显式调用**，不在每次编辑时自动写盘 —— 自动写盘会让「误改了字段」
    /// 变得不可撤销，而且目录整包编码不便宜。
    func saveDraft() {
        guard let draft else { return }
        do {
            draft.catalogJSON = try ShopCatalogJSONCoding.encoder(prettyPrinted: true)
                .encode(catalog)
            draft.updatedAt = Date()
            try context.save()
            statusMessage = "已保存草稿（\(catalog.shops.count) 店家 / "
                + "\(catalog.series.count) 系列 / \(catalog.products.count) 商品）"
            lastError = nil
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: 编辑入口（全部只改内存副本，保存由运营显式触发）

    func addShop(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        catalog.shops.append(CatalogShop(id: "shop-\(shortID())", name: trimmed))
        markDirty()
    }

    func addSeries(shopID: String, name: String, year: Int?, month: Int?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let shop = catalog.shops.first(where: { $0.id == shopID }) else { return }
        var series = CatalogSeries(
            id: "series-\(shortID())", shopID: shop.id, name: trimmed)
        series.year = year
        series.month = month
        catalog.series.append(series)
        markDirty()
    }

    func addProduct(shopID: String, seriesID: String, name: String, category: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        catalog.products.append(CatalogProduct(
            id: "product-\(shortID())",
            shopID: shopID,
            seriesID: seriesID,
            name: trimmed,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines)))
        markDirty()
    }

    /// 商品图绑定：只接受已经在 staging 里的图片资源 id
    func bindImages(_ assetIDs: [String], toProduct productID: String) {
        guard let index = catalog.products.firstIndex(where: { $0.id == productID }) else { return }
        catalog.products[index].images = assetIDs
        markDirty()
    }

    func removeProduct(id: String) {
        catalog.products.removeAll { $0.id == id }
        catalog.variants.removeAll { $0.productID == id }
        catalog.sizeCharts.removeAll { $0.productID == id }
        catalog.saleEvents.removeAll { $0.productID == id }
        // 与 iOS 端口径一致：删除靠「墓碑」表达，发布端才知道这是「下架」而不是「漏传」
        if !catalog.removedProductIDs.contains(id) { catalog.removedProductIDs.append(id) }
        statusMessage = "已删除商品（已记入删除墓碑，发布端会把它当作下架）"
    }

    // MARK: 编辑（改名 / 改归属）

    func updateShop(id: String, name: String, aliases: [String]) {
        guard let index = catalog.shops.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "店家名不能为空。"
            return
        }
        catalog.shops[index].name = trimmed
        catalog.shops[index].aliases = aliases
        markDirty()
    }

    func updateSeries(
        id: String, shopID: String, name: String, year: Int?, month: Int?, season: String?
    ) {
        guard let index = catalog.series.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "系列名不能为空。"
            return
        }
        catalog.series[index].shopID = shopID
        catalog.series[index].name = trimmed
        catalog.series[index].year = year
        catalog.series[index].month = month
        catalog.series[index].season = season
        markDirty()
    }

    func updateProduct(
        id: String, shopID: String, seriesID: String, name: String, category: String
    ) {
        guard let index = catalog.products.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "商品名不能为空。"
            return
        }
        catalog.products[index].shopID = shopID
        catalog.products[index].seriesID = seriesID
        catalog.products[index].name = trimmed
        catalog.products[index].category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        markDirty()
    }

    // MARK: 删除店家 / 系列（有下级引用时**拒绝**，不做静默级联）

    /// 删除店家。有系列或商品还挂在它下面时**拒绝**并说明原因。
    ///
    /// 为什么不做级联删除：级联会一次改掉一大片实体，运营点一下「删店家」
    /// 却丢掉 20 个商品，是「部分成功/静默扩大影响」的典型。这里要求运营
    /// 自己先把下级挪走或删掉，每一步都看得见。
    @discardableResult
    func removeShop(id: String) -> Bool {
        let seriesCount = catalog.series.filter { $0.shopID == id }.count
        let productCount = catalog.products.filter { $0.shopID == id }.count
        guard seriesCount == 0, productCount == 0 else {
            lastError = "这个店家下面还有 \(seriesCount) 个系列、\(productCount) 个商品，"
                + "先挪走或删除它们再删店家（不做级联删除）。"
            return false
        }
        catalog.shops.removeAll { $0.id == id }
        if !catalog.removedShopIDs.contains(id) { catalog.removedShopIDs.append(id) }
        statusMessage = "已删除店家（已记入删除墓碑）"
        return true
    }

    @discardableResult
    func removeSeries(id: String) -> Bool {
        let productCount = catalog.products.filter { $0.seriesID == id }.count
        guard productCount == 0 else {
            lastError = "这个系列下面还有 \(productCount) 个商品，先挪走或删除它们再删系列。"
            return false
        }
        catalog.series.removeAll { $0.id == id }
        if !catalog.removedSeriesIDs.contains(id) { catalog.removedSeriesIDs.append(id) }
        statusMessage = "已删除系列（已记入删除墓碑）"
        return true
    }

    // MARK: 查询辅助（视图层不做口径判断）

    func shopName(for id: String) -> String {
        catalog.shops.first { $0.id == id }?.name ?? "（店家已删除）"
    }

    func seriesName(for id: String) -> String {
        catalog.series.first { $0.id == id }?.name ?? "（系列已删除）"
    }

    func asset(for id: String) -> CatalogAsset? {
        catalog.assets.first { $0.id == id }
    }

    /// 把 `local:<文件名>` 解析成 staging 目录里的真实文件 URL。
    ///
    /// 只认 `local:` 前缀：`thmedia:` / `http(s)://` / `bundle:` 都不是本机文件，
    /// 一律返回 nil（界面据此显示「非本机图」而不是空白）。
    func stagedFileURL(forReference reference: String?) -> URL? {
        guard let reference, reference.hasPrefix("local:") else { return nil }
        let name = String(reference.dropFirst("local:".count))
        guard !name.isEmpty else { return nil }
        let url = stagingDirectory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func markDirty() {
        statusMessage = "已修改（未保存）。记得点「保存草稿」。"
    }

    private func shortID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    // MARK: 导入目录 JSON

    /// 导入一份 `shop-catalog.json`（覆盖当前草稿内容）。
    /// 返回 false 表示失败，原因在 `lastError` 里。
    @discardableResult
    func importCatalog(from url: URL) -> Bool {
        // security-scoped：作用域用完必须还回去，否则系统会一直替我们持有权限
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: data)
            catalog = decoded
            saveDraft()
            statusMessage = "已导入 \(url.lastPathComponent)："
                + "\(decoded.shops.count) 店家 / \(decoded.series.count) 系列 / "
                + "\(decoded.products.count) 商品 / \(decoded.assets.count) 图片资源"
            lastError = nil
            return true
        } catch {
            lastError = "导入失败（目录 JSON 解不开，已保留当前草稿）：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 导入图片

    /// 导入图片：**规范化 → 内容寻址 → 立即复制进 staging**。
    ///
    /// 规范化在这里发生（而不是等发布端），因为：
    ///   · `mediaKey` 要进草稿 JSON，越早定下来越好；
    ///   · 长边 1600 的重编码很吃内存，一次导入一张比发布时批量处理更可控。
    ///
    /// 每张图同时创建一个 `CatalogAsset` 与一条上传任务；两者都用 `mediaKey` 做键，
    /// 重复导入同一张图（哪怕文件名不同）只会得到一条记录。
    func importImages(from urls: [URL]) {
        var imported = 0
        var skipped: [String] = []
        var failures: [String] = []

        try? fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let displayName = url.lastPathComponent
            do {
                let raw = try Data(contentsOf: url)
                // 规范化在这里做（不是发布时批量做）：mediaKey 要进草稿 JSON，
                // 越早定下来越好；长边 1600 的重编码很吃内存，逐张处理更可控。
                //
                // 「同一张图重复导入」不需要额外判重：规范化是确定性的
                // （同字节 → 同字节），因此 fileName 相同 → 下面 fileExists 直接复用。
                let staged = try ShopCatalogMediaStaging.stage(raw)

                let target = stagingDirectory.appendingPathComponent(staged.fileName)
                if fileManager.fileExists(atPath: target.path) {
                    skipped.append(displayName)
                } else {
                    try staged.data.write(to: target, options: .atomic)
                    imported += 1
                }

                upsertAssetAndJob(for: staged, sourceName: displayName)
            } catch let error as ShopCatalogMediaStagingError {
                failures.append("\(displayName)：\(error.errorDescription ?? "无法处理")")
            } catch {
                failures.append("\(displayName)：\(error.localizedDescription)")
            }
        }

        saveDraft()
        try? context.save()

        var parts = ["新增 \(imported) 张"]
        if !skipped.isEmpty { parts.append("\(skipped.count) 张内容重复已复用") }
        statusMessage = parts.joined(separator: "，")
        lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private func upsertAssetAndJob(
        for staged: ShopCatalogMediaStaging.StagedMedia, sourceName: String
    ) {
        // 1) 图片资源：mediaKey 存在 → 同一个媒体，只补 URL 字段
        let assetID = "asset-\(String(staged.mediaKey.prefix(12)))"
        if let index = catalog.assets.firstIndex(where: { $0.id == assetID }) {
            catalog.assets[index].thumbnailURL = "local:\(staged.fileName)"
            catalog.assets[index].previewURL = "local:\(staged.fileName)"
            catalog.assets[index].originalURL = "local:\(staged.fileName)"
            catalog.assets[index].width = staged.pixelWidth
            catalog.assets[index].height = staged.pixelHeight
        } else {
            catalog.assets.append(CatalogAsset(
                id: assetID,
                type: .productImage,
                thumbnailURL: "local:\(staged.fileName)",
                previewURL: "local:\(staged.fileName)",
                originalURL: "local:\(staged.fileName)",
                width: staged.pixelWidth,
                height: staged.pixelHeight))
        }

        // 2) 上传任务：同 mediaKey 只留一条
        var job = mediaJobs.first { $0.mediaKey == staged.mediaKey }
            ?? MediaUploadJob(
                mediaKey: staged.mediaKey,
                stagedFileName: staged.fileName,
                byteCount: staged.byteCount,
                mimeType: staged.mimeType)
        job.stagedFileName = staged.fileName
        job.byteCount = staged.byteCount
        job.mimeType = staged.mimeType
        persist(job)

        _ = sourceName    // 原始文件名只用于报错文案，不参与身份判定（身份 = 内容摘要）
    }

    // MARK: 上传任务落盘

    private func loadMediaJobs() {
        guard let draftID = draft?.id else { mediaJobs = []; return }
        let target = draftID
        let descriptor = FetchDescriptor<OpsMediaJobRecord>(
            predicate: #Predicate { $0.draftID == target },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        let records = (try? context.fetch(descriptor)) ?? []
        // 启动恢复：上次进程被杀留下的 `uploading` 一律回退成 `retryable`。
        // 保持 uploading 的话，新进程里它既不会前进也不会后退，界面永远卡在「上传中」。
        mediaJobs = records.map { record in
            let restored = MediaUploadJobMachine.recovered(record.job)
            if restored.state != record.job.state { record.apply(restored) }
            return restored
        }
        try? context.save()
    }

    /// 写回一条任务（存在则更新，不存在则插入）
    func persist(_ job: MediaUploadJob) {
        if let index = mediaJobs.firstIndex(where: { $0.mediaKey == job.mediaKey }) {
            mediaJobs[index] = job
        } else {
            mediaJobs.append(job)
        }
        guard let draftID = draft?.id else { return }
        let key = job.mediaKey
        let descriptor = FetchDescriptor<OpsMediaJobRecord>(
            predicate: #Predicate { $0.mediaKey == key && $0.draftID == draftID })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.apply(job)
        } else {
            context.insert(OpsMediaJobRecord(
                mediaKey: job.mediaKey,
                draftID: draftID,
                stagedFileName: job.stagedFileName,
                byteCount: job.byteCount,
                mimeType: job.mimeType,
                stateRawValue: job.state.rawValue,
                attemptCount: job.attemptCount,
                failureKindRawValue: job.failureKind?.rawValue,
                lastErrorMessage: job.lastErrorMessage,
                createdAt: job.createdAt,
                updatedAt: job.updatedAt,
                verifiedAt: job.verifiedAt))
        }
        try? context.save()
    }

    var mediaProgress: MediaUploadJobMachine.Progress {
        MediaUploadJobMachine.progress(of: mediaJobs)
    }

    /// 台账里记着、但 staging 目录里已经没有文件的图片。
    ///
    /// 这三者（目录文件 / 台账 / 目录 JSON 引用）是三个独立事实，**必须能分别看见**：
    ///   · 台账有、文件没有 → 别人手删过 staging，或者换过机器；
    ///   · 文件有、台账没有 → 直接往 staging 目录里丢了图（没走导入流程）；
    ///   · 目录 JSON 引用了不存在的文件 → 发布门禁会拦（`missingLocal`）。
    /// 本方法只负责第 1 种；第 2 种由 `rescanStagingDirectory()` 补台账；
    /// 第 3 种交给 `ShopCatalogPublicationGate`。
    var mediaKeysMissingStagedFile: [String] {
        let names = stagedFileNames
        return mediaJobs
            .filter { !names.contains($0.stagedFileName) }
            .map(\.mediaKey)
            .sorted()
    }

    /// 台账里没有、但 staging 目录里存在的文件名（孤儿素材）。
    var orphanStagedFileNames: [String] {
        let known = Set(mediaJobs.map(\.stagedFileName))
        return stagedFileNames.filter { !known.contains($0) }.sorted()
    }

    /// 重新扫 staging 目录，给「目录里有文件但台账没记」的图片补一条任务。
    ///
    /// 为什么要有：`.fileImporter` 不是唯一的素材来源 —— 运营会把图直接拷进
    /// staging 目录（尤其是「重新拿一份上次的素材」）。没有这一步，那些图
    /// 在界面上就是隐形的，而发布端**照样会上传它们**（它按文件名找文件，
    /// 不看台账）——「界面上没有、线上有图」是最难解释的一类不一致。
    ///
    /// 媒体键取自**文件名主干**：staging 的文件名由
    /// `ShopCatalogMediaStaging.StagedMedia.fileName` 固定生成为 `<mediaKey>.<ext>`，
    /// 所以主干就是媒体键。这里额外用 `isPayloadHash` 校验形态，
    /// 形态不对的（例如运营手放了一个 `备注.txt`）直接跳过，不伪造台账。
    @discardableResult
    func rescanStagingDirectory() -> Int {
        try? fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        var added: [String] = []
        for name in stagedFileNames.sorted() {
            let stem = (name as NSString).deletingPathExtension
            guard ShopCatalogSyncProtocol.isPayloadHash(stem) else { continue }
            if mediaJobs.contains(where: { $0.stagedFileName == name }) { continue }
            let url = stagingDirectory.appendingPathComponent(name)
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            persist(MediaUploadJob(
                mediaKey: stem,
                stagedFileName: name,
                byteCount: byteCount,
                mimeType: mimeType(forFileName: name)))
            added.append(name)
        }
        if added.isEmpty {
            statusMessage = "素材清单已是最新（台账 \(mediaJobs.count) 条）"
        } else {
            statusMessage = "已补记 \(added.count) 张原本只在目录里的图片"
        }
        return added.count
    }

    /// 删掉一条台账记录。**不动文件**，也不动目录 JSON 里的引用 ——
    /// 引用与文件该不该在，由发布门禁判定；删台账只是「不再跟踪这条」。
    func removeMediaJob(mediaKey: String) {
        mediaJobs.removeAll { $0.mediaKey == mediaKey }
        let key = mediaKey
        guard let draftID = draft?.id else { return }
        let descriptor = FetchDescriptor<OpsMediaJobRecord>(
            predicate: #Predicate { $0.mediaKey == key && $0.draftID == draftID })
        for record in (try? context.fetch(descriptor)) ?? [] {
            context.delete(record)
        }
        try? context.save()
        statusMessage = "已移除 1 条上传任务记录（文件与目录引用都没动）"
    }

    private func mimeType(forFileName name: String) -> String {
        let ext = (name as NSString).pathExtension
        if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime.lowercased()
        }
        return "application/octet-stream"
    }

    // MARK: 发布前校验（离线）

    /// 跑一遍发布门禁。这是 P1 的核心交付：**离线就能知道这份目录发出去会不会缺图**。
    @discardableResult
    func validate() -> ShopCatalogPublicationReview {
        let result = ShopCatalogPublicationGate.review(
            catalog,
            stagedFileNames: stagedFileNames,
            coverageStatus: draft?.coverageStatus ?? "complete")
        review = result
        if result.isBlocked {
            lastError = result.blockingIssues.joined(separator: "\n")
        } else {
            lastError = nil
        }
        statusMessage = result.summary
        return result
    }

    // MARK: 导出待发布包

    /// 生成待发布 tar：`shop-catalog.json` + `images/<文件名>`。
    ///
    /// 布局与 iOS 端「整包导出」完全一致，所以发布端**同一条命令**就能吃：
    ///     python3 tools/time_hall/publication/build_release.py \
    ///         --shop-catalog-archive <这个 tar> ...
    /// 不要自创第二种布局 —— 计划 §6 P4 明确警告不要出现第二套发布格式。
    func makePublicationArchive() throws -> Data {
        let references = Set(catalog.assets.flatMap { asset in
            [asset.originalURL, asset.thumbnailURL, asset.previewURL].compactMap { $0 }
        })
        let (imageEntries, missing) = ShopCatalogExportArchive.imageEntries(
            forLocalReferences: references,
            imageDirectory: stagingDirectory)

        // 缺图一律硬报错：静默跳过会让「图没传」以「用户看到空白」的形式暴露，
        // 比构建失败难查得多（与 build_release.py 同一口径）。
        guard missing.isEmpty else {
            throw OpsWorkspaceError.missingStagedFiles(missing)
        }

        var entries = [ShopCatalogExportArchive.Entry]()
        let json = try ShopCatalogJSONCoding.encoder(prettyPrinted: true).encode(catalog)
        entries.append(.init(name: "shop-catalog.json", data: json))
        entries.append(contentsOf: imageEntries)
        return ShopCatalogExportArchive.tarData(entries: entries)
    }

    func clearError() {
        lastError = nil
    }

    /// 成功类反馈入口（与 `reportFailure` 对称）。界面不许自己弹提示，
    /// 否则「有的成功看得见、有的看不见」。
    func reportSuccess(_ message: String) {
        lastError = nil
        statusMessage = message
    }

    /// 界面层的失败上报入口（唯一通道，见 `OpsRootView` 顶部说明）。
    /// 界面不许自己弹 alert 兜失败：文案一旦分散，就会出现「有的失败看得见、有的看不见」。
    func reportFailure(_ message: String) {
        lastError = message
    }

    var statusText: String? { statusMessage }
}

// MARK: - 错误

enum OpsWorkspaceError: LocalizedError {
    /// 目录引用的图片在 staging 里找不到
    case missingStagedFiles([String])
    /// 发布门禁未通过（结构问题或引用问题）
    case blockedByGate([String])

    var errorDescription: String? {
        switch self {
        case .missingStagedFiles(let names):
            return "有 \(names.count) 张被引用的图片在本机找不到，已中止生成待发布包："
                + names.prefix(5).joined(separator: "、")
                + (names.count > 5 ? " 等" : "")
        case .blockedByGate(let issues):
            return "发布前校验未通过（\(issues.count) 条）：" + issues.prefix(3).joined(separator: "；")
        }
    }
}
