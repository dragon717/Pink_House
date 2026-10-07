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
    func publishSeries(cloud: OpsCloudSyncModel) async -> OpsSeriesPublishOutcome {
        // ── ① 整个系列一次落库（逐类型写进目录 + 落盘）──
        // 这是一次调用写完整个系列，不是让运营逐条点。
        let report = commitSeriesEntry()

        let items: [OpsSeriesPublishItem] = itemStates(from: report)
        let failed = items.filter { !$0.ok }

        // 草稿箱记录：**先建**（内容已经在目录里了），再决定发不发。
        let snapshot = try? ShopCatalogJSONCoding.encoder().encode(catalog)
        let job = upsertSeriesPublishJob(
            seriesID: report.seriesID ?? seriesEntry.seriesID,
            seriesName: seriesDisplayName,
            shopID: report.shopID ?? seriesEntry.shopID,
            items: items,
            catalogSnapshot: snapshot)

        // ── ② 条目有失败 → 不发起发布（发了就是「线上只有半个系列」）──
        if !failed.isEmpty || report.blocked {
            let status: OpsSeriesPublishStatus = report.blocked ? .failed : .partialFailed
            let reason = report.blocked
                ? (report.blockedByValidation
                    .map { ($0.entryName.isEmpty ? "" : $0.entryName + "：") + $0.message }
                    .joined(separator: "；"))
                : failed.map { ($0.name.isEmpty ? $0.id : $0.name) + "：" + ($0.message ?? "未说明原因") }
                    .joined(separator: "；")
            job.markFailed(status, error: reason, logPath: nil)
            job.items = items
            persistJob(job)
            return .failed(reason: reason, itemFailures: failed)
        }

        // ── ③ 内容已完整落库 → 标记「发布中」再发 ──
        job.markPublishing()
        job.items = items
        persistJob(job)

        // ── ④ 一次发布（内部自动取发布头 / 采用基线 / 真实发布）──
        switch await cloud.publishNow(workspace: self) {
        case .confirmed(let seq):
            // 只有**整个系列全部成功**才删草稿箱记录
            deleteJob(job)
            statusMessage = "系列「\(seriesDisplayName)」已发布（releaseSeq \(seq)）。"
            lastError = nil
            return .published(releaseSeq: seq)
        case .failed(let reason):
            job.markFailed(.failed, error: reason, logPath: cloud.lastRunLogURL?.path)
            persistJob(job)
            return .failed(reason: reason, itemFailures: [])
        }
    }

    /// 重试一次草稿箱里的失败任务：**复用同一条记录**，不新建（否则草稿箱会越堆越多）。
    @MainActor
    func retrySeriesPublish(job: OpsSeriesPublishJob, cloud: OpsCloudSyncModel) async
        -> OpsSeriesPublishOutcome {
        // ⚠️ 归属校验：重试的是**这条记录里的系列**，不是「向导当前打开的系列」。
        // 少了这道判断，运营在 A 系列的记录上点重试、而向导停在 B 系列时，
        // 会把 B 的内容当成 A 发出去 —— 这类错配改起来比失败贵得多。
        if !seriesEntry.seriesID.isEmpty && seriesEntry.seriesID != job.seriesID {
            let reason = "当前向导打开的是另一个系列（\(seriesDisplayName)），"
                + "不能替「\(job.seriesName)」重试：请先切到那个系列再点重试。"
            job.markFailed(.failed, error: reason, logPath: nil)
            persistJob(job)
            return .failed(reason: reason, itemFailures: job.failedItems)
        }

        // 「条目没落成」的重试要重新落一次（运营可能刚改完）；
        // 「发布本身失败」的重试不需要再写目录 —— 内容上次就落好了。
        let needsRecommit = !job.failedItems.isEmpty || job.status == .partialFailed
        var items = job.items
        if needsRecommit {
            let report = commitSeriesEntry()
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
        job.markPublishing()
        persistJob(job)
        switch await cloud.publishNow(workspace: self) {
        case .confirmed(let seq):
            deleteJob(job)
            return .published(releaseSeq: seq)
        case .failed(let reason):
            job.markFailed(.failed, error: reason, logPath: cloud.lastRunLogURL?.path)
            persistJob(job)
            return .failed(reason: reason, itemFailures: [])
        }
    }

    // MARK: 草稿箱读写

    /// 同一个系列只保留一条发布任务（重试沿用旧记录，不堆新的）。
    private func upsertSeriesPublishJob(
        seriesID: String,
        seriesName: String,
        shopID: String?,
        items: [OpsSeriesPublishItem],
        catalogSnapshot: Data?
    ) -> OpsSeriesPublishJob {
        let descriptor = FetchDescriptor<OpsSeriesPublishJob>(
            predicate: #Predicate { $0.seriesID == seriesID })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.items = items
            existing.catalogSnapshotJSON = catalogSnapshot
            existing.updatedAt = Date()
            try? context.save()
            return existing
        }
        let job = OpsSeriesPublishJob(
            seriesID: seriesID,
            seriesName: seriesName,
            shopID: shopID,
            shopName: catalog.shops.first(where: { $0.id == shopID })?.name,
            items: items,
            catalogSnapshotJSON: catalogSnapshot)
        context.insert(job)
        try? context.save()
        return job
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
