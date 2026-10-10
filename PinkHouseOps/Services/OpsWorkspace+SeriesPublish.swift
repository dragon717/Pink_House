//
//  OpsWorkspace+SeriesPublish.swift
//  PinkHouseOps
//
//  「发布整个系列」的编排（需求 2026-10-07）。
//
//  ## 一句话
//
//  运营**点一次**「发布整个系列」→ 整个系列先**完整落库草稿箱**并标记「发布中」
//  → **一次**发布请求把整个系列写上公共库 → 只有全部成功才删草稿箱记录；
//  失败/部分成功**保留草稿**并给出条目级失败状态与重试入口。
//
//  ## 硬约束（逐条对应需求）
//
//  1. **以系列为单位一次提交**：一次点击、一个发布任务、一份整包。
//     绝不按条目各发一次 —— 那会出现「线上只有半个系列」这种更难的现场。
//  2. **不「读线上 → 拉回本地 → 再回写」**：不再把线上整份目录拉回来重建本地内容。
//     发布前只由受控发布器**内部**取一次线上发布头（元数据，几 KB），
//     用它算出发布号与 `previousReleaseSeq` —— 这两个值没有线上就拿不到，
//     发布器（`ops_publish_bridge.py:955/1052`）自己也要它。
//     ⚠️ 代价写在这里：不拉回就发布，等于本地整包**取代**线上那一版
//     （R4 警告过的「整块覆盖」）。这是运营选定的「无感」口径，
//     所以每次自动采用基线都会**写进日志留痕**，出事能回溯。
//  3. **先落库草稿箱再发布**：内容完整落盘后才把状态改成「发布中」；
//     即使发布接口返回成功，也**必须**走完落库流程（不允许只在内存里处理）。
//  4. **只有全部成功才删草稿**：失败 / 部分成功 → 记录保留 + 条目级状态 + 重试入口。
//

import Foundation
// MemberImportVisibility：本文件直接用了 `ModelContext` 的 `insert` / `delete` / `save`
// 与 `FetchDescriptor`，必须在使用它的文件里显式 import —— 少了会连带报
// 「cannot find 'FetchDescriptor' in scope」，那个报错看不出真正原因。
import SwiftData

// MARK: - 结果

/// 一次「发布整个系列」的结果。运营只看这两种。
enum OpsSeriesPublishOutcome: Equatable {
    /// 全部条目发布成功（受控发布器回读确认过），草稿箱记录已删除
    case published(releaseSeq: Int)
    /// 没发出去（或没确认）。`reason` 可定位；`itemFailures` 是条目级明细（可能为空）。
    case failed(reason: String, itemFailures: [OpsSeriesPublishItem])
}

// MARK: - 编排

extension OpsWorkspace {

    /// 发布整个系列（一键）。**唯一的入口**，界面只负责把结果说清楚。
    ///
    /// 顺序不能改：落库 → 标记发布中 → 一次发布 → 成功才删草稿。
    ///
    /// - Parameter cloud: 受控发布器的编排（单例，与云端同步面板同一份状态）
    @MainActor
    func publishSeries(cloud: OpsCloudSyncModel,
                       publishNow: ((OpsWorkspace) async -> OpsPublishInvocationResult)? = nil) async -> OpsSeriesPublishOutcome {
        // ── ① 整个系列一次落库（逐类型写进目录 + 落盘）──
        // 这是一次调用写完整个系列，不是让运营逐条点。
        let report = commitSeriesEntry()

        let items: [OpsSeriesPublishItem] = itemStates(from: report)
        let failed = items.filter { !$0.ok }

        // 完整落盘草稿箱后才能开始网络发布；保存失败保留输入。
        let job: OpsSeriesPublishJob
        do {
            let staged = try stageSeriesPublishJob(report: report)
            job = staged.job
            if !failed.isEmpty || report.blocked {
                let reason = report.blocked
                    ? report.blockedByValidation
                        .map { ($0.entryName.isEmpty ? "" : $0.entryName + "：") + $0.message }
                        .joined(separator: "；")
                    : failed.map { ($0.name.isEmpty ? $0.id : $0.name) + "：" + ($0.message ?? "未说明原因") }
                        .joined(separator: "；")
                job.markFailed(report.blocked ? .failed : .partialFailed, error: reason, logPath: nil)
                do { try saveCatalogContext(context) } catch { staged.undo(); throw error }
                return .failed(reason: reason, itemFailures: failed)
            }
            job.markPublishing()
            do { try saveCatalogContext(context) } catch { staged.undo(); throw error }
        } catch {
            let reason = "存入发布草稿箱失败（填写内容已保留）：\(error.localizedDescription)"
            lastError = reason
            return .failed(reason: reason, itemFailures: failed)
        }
        let submissionID = job.submissionID

        // 冻结完成操作对应的输入；网络等待期间允许继续编辑。
        let completedEntry = seriesEntry
        let completedDraftID = draft?.id
        let completedName = job.seriesName
        // 可替换的发布调用供离线回归；默认仍走同一受控发布器。
        let result: OpsPublishInvocationResult
        if let publishNow {
            result = await publishNow(self)
        } else {
            result = await cloud.publishNow(workspace: self)
        }
        // ── ④ 一次发布（内部自动取发布头 / 采用基线 / 真实发布）──
        switch result {
        case .confirmed(let seq):
            // 只有**整个系列全部成功**才删草稿箱记录
            if job.submissionID == submissionID { deleteJob(job) }
            statusMessage = "系列「\(completedName)」已发布（releaseSeq \(seq)）。"
            lastError = nil
            finishSeriesEntry(expected: completedEntry, draftID: completedDraftID)
            return .published(releaseSeq: seq)
        case .failed(let reason):
            if job.submissionID == submissionID {
                job.markFailed(.failed, error: reason, logPath: cloud.lastRunLogURL?.path)
                persistJob(job)
            }
            return .failed(reason: reason, itemFailures: [])
        }
    }

    /// 重试一次草稿箱里的失败任务：**复用同一条记录**，不新建（否则草稿箱会越堆越多）。
    @MainActor
    func retrySeriesPublish(job: OpsSeriesPublishJob, cloud: OpsCloudSyncModel,
                            publishNow: ((OpsWorkspace) async -> OpsPublishInvocationResult)? = nil) async
        -> OpsSeriesPublishOutcome {
        guard !cloud.isRunning, !cloud.isSyncing, job.status != .publishing,
              job.status != .published else {
            return .failed(reason: "已有发布进行中或此系列已经发布，请先查看结果。", itemFailures: [])
        }
        guard job.draftID == nil || job.draftID == draft?.id else {
            return .failed(reason: "此系列属于另一份本机草稿，请先打开所属草稿再发布。", itemFailures: [])
        }
        guard job.environment == nil || job.environment == cloud.targetEnvironment.rawValue else {
            return .failed(reason: "请先切换到此草稿记录的目标环境（\(job.environment ?? "")）再发布。", itemFailures: [])
        }
        let needsRecommit = !job.failedItems.isEmpty || job.status == .partialFailed
        guard (!job.seriesID.isEmpty && catalog.series.contains(where: { $0.id == job.seriesID }))
                || needsRecommit, !isCorrupted else {
            return .failed(reason: "当前草稿中找不到此系列或草稿不可编辑，不能发布此记录。", itemFailures: [])
        }
        // 「条目没落成」的重试要重新落一次（运营可能刚改完）；
        // 「发布本身失败」的重试不需要再写目录 —— 内容上次就落好了。
        var items = job.items
        if needsRecommit {
            guard seriesEntry.seriesID == job.seriesID else {
                return .failed(reason: "此系列还有条目需要修正，请在上新向导打开对应系列后重试。", itemFailures: job.failedItems)
            }
            let report = commitSeriesEntry()
            if report.allOK, let seriesID = report.seriesID { job.seriesID = seriesID }
            items = itemStates(from: report)
            job.items = items
            let failed = items.filter { !$0.ok }
            if !failed.isEmpty || report.blocked {
                let reason = report.blocked
                    ? report.blockedByValidation
                        .map { ($0.entryName.isEmpty ? "" : $0.entryName + "：") + $0.message }
                        .joined(separator: "；")
                    : failed.map { ($0.name.isEmpty ? $0.id : $0.name) + "：" + ($0.message ?? "未说明原因") }
                        .joined(separator: "；")
                job.markFailed(report.blocked ? .failed : .partialFailed, error: reason, logPath: nil)
                persistJob(job)
                return .failed(reason: reason, itemFailures: failed)
            }
        }
        let previousStatus = job.status
        let previousAttempts = job.attemptCount
        let previousUpdatedAt = job.updatedAt
        let previousSnapshot = job.catalogSnapshotJSON
        job.markPublishing()
        do {
            // 从所属目录的最新保存内容发布；不把旧快照覆盖到运营的新编辑上。
            job.catalogSnapshotJSON = try ShopCatalogJSONCoding.encoder().encode(catalog)
            try saveCatalogContext(context)
        } catch {
            job.status = previousStatus
            job.attemptCount = previousAttempts
            job.updatedAt = previousUpdatedAt
            job.catalogSnapshotJSON = previousSnapshot
            return .failed(reason: "发布状态保存失败，尚未上传：\(error.localizedDescription)", itemFailures: [])
        }
        let submissionID = job.submissionID
        let completedEntry = seriesEntry
        let completedDraftID = draft?.id
        let result: OpsPublishInvocationResult
        if let publishNow { result = await publishNow(self) }
        else { result = await cloud.publishNow(workspace: self) }
        switch result {
        case .confirmed(let seq):
            let completedSeriesID = job.seriesID
            let completedName = job.seriesName
            if job.submissionID == submissionID { deleteJob(job) }
            statusMessage = "系列「\(completedName)」已发布（releaseSeq \(seq)）。"
            lastError = nil
            if completedEntry.seriesID == completedSeriesID {
                finishSeriesEntry(expected: completedEntry, draftID: completedDraftID)
            }
            return .published(releaseSeq: seq)
        case .failed(let reason):
            if job.submissionID == submissionID {
                job.markFailed(.failed, error: reason, logPath: cloud.lastRunLogURL?.path)
                persistJob(job)
            }
            return .failed(reason: reason, itemFailures: [])
        }
    }

    // MARK: 草稿箱读写

    /// 从草稿箱显式切到记录所属的目录；先保存当前工作，避免覆盖正在填写的下一份系列。
    func openSeriesPublishDraft(job: OpsSeriesPublishJob) -> Bool {
        guard let ownerID = job.draftID else {
            lastError = "此旧记录没有所属草稿信息，请打开原草稿后发布。"
            return false
        }
        if ownerID == draft?.id { return true }
        guard !OpsCloudSyncModel.shared.isRunning, !OpsCloudSyncModel.shared.isSyncing,
              let current = draft, !current.isCorrupted else { return false }
        if hasUnsavedChanges, !saveDraft() { return false }
        let previousJSON = current.seriesEntryJSON
        do {
            current.seriesEntryJSON = try ShopCatalogJSONCoding.encoder().encode(seriesEntry)
            try saveCatalogContext(context)
        } catch {
            current.seriesEntryJSON = previousJSON
            lastError = "当前填写内容保存失败，未切换草稿：\(error.localizedDescription)"
            return false
        }
        return adoptDraft(id: ownerID)
    }

    /// 草稿箱记录与空白向导一起落盘：只有这一步成功才清空界面。
    func storeSubmittedSeriesDraft(report: OpsSeriesEntryCommitReport) -> Bool {
        guard report.allOK else { return false }
        do {
            let staged = try stageSeriesPublishJob(report: report)
            guard finishSeriesEntry(expected: seriesEntry, draftID: draft?.id) else {
                staged.undo()
                lastError = "存入发布草稿箱失败，已保留填写内容：" + (lastError ?? "未能保存空白表单")
                return false
            }
            return true
        } catch {
            lastError = "存入发布草稿箱失败，已保留填写内容：\(error.localizedDescription)"
            return false
        }
    }

    /// 同一目录草稿中的同一系列复用记录；修改暂存于当前 context，调用方负责
    /// 检查落盘结果，失败只回退这条记录，不能回滚运营的其它编辑。
    private func stageSeriesPublishJob(report: OpsSeriesEntryCommitReport) throws
        -> (job: OpsSeriesPublishJob, undo: () -> Void) {
        let seriesID = report.seriesID ?? seriesEntry.seriesID
        let snapshot = try ShopCatalogJSONCoding.encoder().encode(catalog)
        let matches = try context.fetch(FetchDescriptor<OpsSeriesPublishJob>(
            predicate: #Predicate { $0.seriesID == seriesID }))
        let ownerID = draft?.id
        let existing = matches.first { $0.draftID == ownerID }
        let shopID = report.shopID ?? seriesEntry.shopID
        let job = existing ?? OpsSeriesPublishJob(seriesID: seriesID, seriesName: seriesDisplayName)
        let old = (name: job.seriesName, shop: job.shopID, shopName: job.shopName,
                   draft: job.draftID, submission: job.submissionID, status: job.statusRaw,
                   items: job.itemsJSON, snapshot: job.catalogSnapshotJSON, environment: job.environment,
                   error: job.lastError, log: job.logPath, seq: job.releaseSeq, attempts: job.attemptCount, updated: job.updatedAt)
        if existing == nil { context.insert(job) }
        job.seriesName = seriesDisplayName
        job.shopID = shopID
        job.shopName = catalog.shops.first { $0.id == shopID }?.name
        job.draftID = ownerID
        job.submissionID = UUID().uuidString
        job.status = .pending
        job.items = itemStates(from: report)
        job.catalogSnapshotJSON = snapshot
        job.environment = OpsCloudSyncModel.shared.targetEnvironment.rawValue
        job.lastError = nil
        job.logPath = nil
        job.releaseSeq = nil
        job.updatedAt = Date()
        return (job, { [context] in
            if existing == nil {
                context.delete(job)
            } else {
                job.seriesName = old.name
                job.shopID = old.shop
                job.shopName = old.shopName
                job.draftID = old.draft
                job.submissionID = old.submission
                job.statusRaw = old.status
                job.itemsJSON = old.items
                job.catalogSnapshotJSON = old.snapshot
                job.environment = old.environment
                job.lastError = old.error
                job.logPath = old.log
                job.releaseSeq = old.seq
                job.attemptCount = old.attempts
                job.updatedAt = old.updated
            }
        })
    }

    private func persistJob(_ job: OpsSeriesPublishJob) {
        job.updatedAt = Date()
        try? context.save()
    }

    /// 只有整个系列全部发布成功才走这里。
    private func deleteJob(_ job: OpsSeriesPublishJob) {
        context.delete(job)
        try? context.save()
    }

    /// 草稿箱列表（前端「发布草稿箱」页面的数据源）。
    func seriesPublishJobs() -> [OpsSeriesPublishJob] {
        var descriptor = FetchDescriptor<OpsSeriesPublishJob>(
            sortBy: [SortDescriptor(\OpsSeriesPublishJob.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 50
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: 条目状态

    /// 这次发布的系列名（草稿箱记录上显示的那一个）。
    /// 已落库的系列取目录里的名字；还没建的新系列取向导里填的名字。
    private var seriesDisplayName: String {
        if !seriesEntry.seriesID.isEmpty {
            return catalog.series.first(where: { $0.id == seriesEntry.seriesID })?.name
                ?? seriesEntry.seriesID
        }
        let typed = seriesEntry.newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? "（未命名系列）" : typed
    }

    /// 把一次系列级提交的结果摊成条目级状态：运营要看到**是哪一条**没成。
    ///
    /// 系列级的东西（S2 价格表）也算一条 —— 漏了它就会出现
    /// 「条目全绿但价格表没发上去」，那正是本项目最忌讳的谎。
    private func itemStates(from report: OpsSeriesEntryCommitReport)
        -> [OpsSeriesPublishItem] {
        var items: [OpsSeriesPublishItem] = report.entryResults.map {
            OpsSeriesPublishItem(id: $0.id, name: $0.entryName, ok: $0.ok,
                                 message: $0.ok ? nil : $0.message)
        }
        if report.blocked {
            // 整次被拦：每一条校验问题都算一条失败条目（定位到类型与字段）
            return report.blockedByValidation.map {
                OpsSeriesPublishItem(id: $0.id, name: $0.entryName, ok: false, message: $0.message)
            }
        }
        if let priceChartError = report.priceChartError {
            items.append(OpsSeriesPublishItem(
                id: "series-price-chart", name: "系列价格表", ok: false, message: priceChartError))
        }
        if !report.draftSaved {
            items.append(OpsSeriesPublishItem(
                id: "draft-persist", name: "草稿落库", ok: false,
                message: lastError ?? "草稿落盘失败（内容仍在界面上）"))
        }
        return items
    }
}
