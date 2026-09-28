//
//  ShopCatalogOpsUploadStore.swift
//  ItemManager
//
//  运营上传任务的本地存储（iOS 运营上传实施方案 §2.1 / §4）。
//
//  ## 为什么是**独立**容器
//
//  方案 §2.1 要求上传任务显式 `ModelConfiguration(cloudKitDatabase: .none)`。
//  主容器（`SharedPersistence.sharedModelContainer`）在运营账号开启 iCloud 时
//  是 `.private(iCloud.bugod2.ItemManager)` —— 任务一旦进去就会被自动同步到
//  运营的私有库，既违背「本地草稿」的定位，也会把未发布内容散出去。
//  所以这里单独建一个容器，**不**把 `ShopCatalogUploadJob` 加进主 Schema。
//
//  ## 测试隔离（红线）
//
//  单测宿主 = 主 App，`FileManager.default` 指向真实沙盒。
//  落盘测试必须用 `ShopCatalogOpsUploadStore(inMemory: true)`，
//  不走 `shared`（它写 Application Support/ShopCatalogOpsUpload.store）。
//

import Foundation
import Combine
import SwiftData

@MainActor
final class ShopCatalogOpsUploadStore: ObservableObject {

    static let shared = ShopCatalogOpsUploadStore()

    /// 任务列表（按更新时间倒序）。SwiftData 的 `@Query` 需要视图环境，
    /// 这一层是服务对象，自己在每次写入后重新拉取，UI 只消费这个数组。
    @Published private(set) var jobs: [ShopCatalogUploadJob] = []

    /// 容器创建失败的原因（磁盘满 / 迁移失败…）。**如实上报**，不静默空表。
    @Published private(set) var unavailableReason: String?

    private let container: ModelContainer?
    private let context: ModelContext?

    /// 独立容器：`cloudKitDatabase: .none`（方案 §2.1 硬要求）
    init(inMemory: Bool = false) {
        let schema = Schema([ShopCatalogUploadJob.self])
        let configuration = ModelConfiguration(
            "ShopCatalogOpsUpload",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.container = container
            self.context = container.mainContext
            self.unavailableReason = nil
        } catch {
            self.container = nil
            self.context = nil
            self.unavailableReason = "上传任务本地存储不可用：\(error.localizedDescription)"
            print("[ShopCatalogUpload] \(unavailableReason ?? "")")
        }
        reload()
        // 启动即修复：上一场会话留下的「上传中 / 发布头冲突」不属于任何进行中的运行
        repairStaleTasks()
    }

    // MARK: 读

    /// 重新拉取全部任务。任何写入之后都要调用，保证 `jobs` 与存储一致。
    func reload() {
        guard let context else {
            jobs = []
            return
        }
        let descriptor = FetchDescriptor<ShopCatalogUploadJob>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        jobs = (try? context.fetch(descriptor)) ?? []
    }

    func job(mediaKey: String) -> ShopCatalogUploadJob? {
        jobs.first { $0.mediaKey == mediaKey }
    }

    /// 按任务 ID 取（发布包 / 发布头这类非图片任务用 jobID 定位）
    func task(jobID: String) -> ShopCatalogUploadJob? {
        jobs.first { $0.jobID == jobID }
    }

    /// 需要自动重试、且退避时间已到的任务（供 UI 与上传入口使用）
    func dueRetryableJobs(now: Date = Date()) -> [ShopCatalogUploadJob] {
        jobs.filter { $0.status == .retryable && ($0.nextRetryAt ?? .distantPast) <= now }
    }

    // MARK: 分页（当前 / 失败 / 历史，2026-09-28）

    /// **失败**：需要人来处理的任务。**不分日期** —— 失败被时间藏进历史只会被遗忘。
    /// （终态失败 + 可重试；`conflict` 在启动时已被 `repairStaleTasks()` 复位，正常不会出现在这。）
    var failedJobs: [ShopCatalogUploadJob] {
        jobs.filter { $0.status.isTerminalFailure || $0.status == .retryable }
    }

    /// **当前**：今天的非失败任务 —— 正在跑的，以及今天刚跑完的。
    var currentJobs: [ShopCatalogUploadJob] {
        let failedIDs = Set(failedJobs.map(\.jobID))
        return jobs.filter {
            !failedIDs.contains($0.jobID) && Calendar.current.isDateInToday($0.updatedAt)
        }
    }

    /// **历史**：剩下的 —— 非今天的，以及更早的成功任务。只作留痕。
    var historyJobs: [ShopCatalogUploadJob] {
        let known = Set(failedJobs.map(\.jobID)).union(currentJobs.map(\.jobID))
        return jobs.filter { !known.contains($0.jobID) }
    }

    // MARK: 启动时脏数据修复

    /// 启动时把上一场会话留下的脏状态复位（2026-09-28）。
    ///
    /// 任务表是**本地**的（`cloudKitDatabase: .none`），App 被杀 / 崩溃 / 重启后，
    /// 会留下一批「只有一次运行进行中才有意义」的状态，不修就会一直挂在列表里：
    ///
    ///   · `.uploading` —— 上次会话中断，进度毫无意义。内容寻址 + 幂等，重跑即可；
    ///   · `.conflict` —— 发布头冲突（`changeTag`）只在一次运行里有意义：
    ///     启动时根本没有运行在跑，留着的 conflict 全是脏数据
    ///     （实测截图里连**媒体任务**都挂着「发布头冲突」，就是这个来源）。
    ///
    /// 统一复位成 `.staged`：下次发布重跑；**不清 `attemptCount`**（历史尝试次数是事实）。
    ///
    /// ⚠️ 只在启动路径调用（`init`）。发布运行中途调用会把正在跑的任务打回待办。
    func repairStaleTasks() {
        guard let context else { return }
        let stale = jobs.filter { $0.status == .uploading || $0.status == .conflict }
        guard !stale.isEmpty else { return }
        for job in stale {
            job.status = .staged
            job.lastError = nil
            job.nextRetryAt = nil
            job.updatedAt = Date()
        }
        save(context)
        reload()
    }

    // MARK: 写

    /// 登记一条任务。同 `mediaKey` 已存在时**只补空字段**，不覆盖已有状态 ——
    /// 否则「重新暂存」会把一条已经传完（`mediaVerified`）的任务打回 `staged`。
    @discardableResult
    func stage(
        mediaKey: String,
        productID: String,
        assetID: String,
        filePath: String,
        mimeType: String,
        byteCount: Int
    ) -> ShopCatalogUploadJob? {
        guard let context else { return nil }
        if let existing = job(mediaKey: mediaKey) {
            if existing.productID.isEmpty { existing.productID = productID }
            if existing.assetID.isEmpty { existing.assetID = assetID }
            existing.updatedAt = Date()
            save(context)
            reload()
            return existing
        }
        let created = ShopCatalogUploadJob(
            jobID: mediaKey,
            productID: productID,
            assetID: assetID,
            stage: .media,
            status: .staged,
            mediaKey: mediaKey,
            filePath: filePath,
            mimeType: mimeType,
            byteCount: byteCount
        )
        context.insert(created)
        save(context)
        reload()
        return created
    }

    /// 就地修改一条任务（状态机入口都经过这里，保证落盘与内存同步）
    func update(mediaKey: String, _ mutate: (ShopCatalogUploadJob) -> Void) {
        guard let context, let target = job(mediaKey: mediaKey) else { return }
        mutate(target)
        save(context)
        reload()
    }

    /// 按 `jobID` 就地修改（发布包 / 发布头任务）
    func updateTask(jobID: String, _ mutate: (ShopCatalogUploadJob) -> Void) {
        guard let context, let target = task(jobID: jobID) else { return }
        mutate(target)
        save(context)
        reload()
    }

    /// 登记 / 更新一条**非图片**任务（阶段 = 商品包 / 发布头）。
    /// 存在时只推进阶段与序号，不重置状态 —— 重跑发布不能把「已发布」打回待办。
    @discardableResult
    func upsertTask(
        jobID: String,
        mediaKey: String,
        stage: ShopCatalogUploadStage,
        mimeType: String = "",
        byteCount: Int = 0,
        releaseSeq: Int = 0
    ) -> ShopCatalogUploadJob? {
        guard let context else { return nil }
        if let existing = task(jobID: jobID) {
            existing.stage = stage
            if releaseSeq > 0 { existing.releaseSeq = releaseSeq }
            existing.updatedAt = Date()
            save(context)
            reload()
            return existing
        }
        let created = ShopCatalogUploadJob(
            jobID: jobID,
            stage: stage,
            status: .staged,
            mediaKey: mediaKey,
            filePath: "",
            mimeType: mimeType,
            byteCount: byteCount,
            releaseSeq: releaseSeq
        )
        context.insert(created)
        save(context)
        reload()
        return created
    }

    /// 删除全部任务（上传成功后的清理入口）
    func removeAll() {
        guard let context else { return }
        for job in jobs { context.delete(job) }
        save(context)
        reload()
    }

    /// 方案 §4 尾注：**图片暂存文件只有在公共库回读校验完成后才能删除**。
    /// 这里按状态收口：只有 `mediaVerified` / `published` 的任务允许清暂存文件。
    /// - Returns: 实际删除的字节数
    @discardableResult
    func pruneVerifiedStagedFiles() -> Int {
        var freed = 0
        for job in jobs where job.status == .mediaVerified || job.status == .published {
            let url = URL(fileURLWithPath: job.filePath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if (try? FileManager.default.removeItem(at: url)) != nil { freed += size }
        }
        return freed
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            // 落盘失败必须可见：静默失败会让「任务丢了」变成无从解释的现象
            unavailableReason = "上传任务写入失败：\(error.localizedDescription)"
            print("[ShopCatalogUpload] \(unavailableReason ?? "")")
        }
    }
}
