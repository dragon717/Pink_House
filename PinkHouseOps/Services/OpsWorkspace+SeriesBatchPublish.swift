import Foundation
import SwiftData
import SharedCatalog

extension OpsWorkspace {
    /// 批量发布只接收已完整提交的系列，同一目录和环境共用一次受控发布。
    /// 有待修正条目的记录仍由单系列重试入口重新提交，避免批量操作改写向导。
    func seriesBatchPublishBlockReason(job: OpsSeriesPublishJob, cloud: OpsCloudSyncModel) -> String? {
        guard draft != nil, !isCorrupted else { return "当前草稿不可发布。" }
        guard job.status == .pending || job.status == .failed else {
            return job.status == .partialFailed ? "请先修正失败条目，再提交此系列。" : "此系列正在发布或已经发布。"
        }
        guard job.draftID == nil || job.draftID == draft?.id else { return "请先打开此系列所属草稿。" }
        guard job.environment == nil || job.environment == cloud.targetEnvironment.rawValue else {
            return "请先切换到 \(job.environment ?? "") 环境。"
        }
        guard !job.items.isEmpty, job.failedItems.isEmpty else { return "请先修正并完整提交此系列。" }
        guard catalog.series.contains(where: { $0.id == job.seriesID }) else { return "当前草稿中找不到此系列。" }
        return nil
    }

    @MainActor
    func publishSelectedSeries(jobs selected: [OpsSeriesPublishJob], cloud: OpsCloudSyncModel,
                               publishNow: ((OpsWorkspace) async -> OpsPublishInvocationResult)? = nil) async
        -> OpsSeriesPublishOutcome {
        guard !cloud.isRunning, !cloud.isSyncing else {
            return .failed(reason: "已有同步或发布进行中，请等待完成后发布所选系列。", itemFailures: [])
        }
        // 同一记录不能重复计数、重复增加尝试次数。
        var seen = Set<String>()
        let jobs = selected.filter { seen.insert($0.id).inserted }
        guard !jobs.isEmpty else { return .failed(reason: "请先勾选要发布的系列。", itemFailures: []) }
        for job in jobs {
            if let reason = seriesBatchPublishBlockReason(job: job, cloud: cloud) {
                return .failed(reason: "系列「\(job.seriesName)」：\(reason)", itemFailures: job.failedItems)
            }
        }

        let previous = jobs.map { ($0.statusRaw, $0.attemptCount, $0.updatedAt, $0.catalogSnapshotJSON) }
        do {
            let snapshot = try ShopCatalogJSONCoding.encoder().encode(catalog)
            for job in jobs {
                job.markPublishing()
                job.catalogSnapshotJSON = snapshot
            }
            // 全组状态一起落盘后才允许上传，任何保存失败都不发网络请求。
            try saveCatalogContext(context)
        } catch {
            for (job, old) in zip(jobs, previous) {
                job.statusRaw = old.0
                job.attemptCount = old.1
                job.updatedAt = old.2
                job.catalogSnapshotJSON = old.3
            }
            let reason = "批量发布状态保存失败，尚未上传：\(error.localizedDescription)"
            lastError = reason
            return .failed(reason: reason, itemFailures: [])
        }

        // 后台等待期间可再次提交同一系列；旧回执只确认开始时的那一版。
        let submissions = jobs.map { $0.submissionID }
        let result: OpsPublishInvocationResult
        if let publishNow { result = await publishNow(self) }
        else { result = await cloud.publishNow(workspace: self) }
        let unchanged = zip(jobs, submissions).compactMap { job, submission in
            job.submissionID == submission ? job : nil
        }
        switch result {
        case .confirmed(let seq):
            // 先存云端已确认的事实，再清理记录；清理失败也不能把它当成待发布重传。
            for job in unchanged {
                job.status = .published
                job.releaseSeq = seq
                job.lastError = nil
                job.logPath = cloud.lastRunLogURL?.path
                job.updatedAt = Date()
            }
            do {
                try saveCatalogContext(context)
            } catch {
                lastError = "所选 \(jobs.count) 个系列已发布（releaseSeq \(seq)），本机确认状态保存失败，请核对发布结果：\(error.localizedDescription)"
                statusMessage = "批量发布已获云端确认。"
                return .published(releaseSeq: seq)
            }
            for job in unchanged { context.delete(job) }
            do {
                try saveCatalogContext(context)
                lastError = nil
                statusMessage = "所选 \(jobs.count) 个系列已发布（releaseSeq \(seq)）。"
            } catch {
                // 上一步已成功保存整个 context，之后没有 await 或其它编辑。
                // 此处唯一的未保存变更是删除记录，rollback 只撤回本轮清理。
                // SwiftData 对已删除对象再次 insert 并不能取消删除标记。
                context.rollback()
                lastError = "所选系列已发布，本机草稿箱记录清理失败：\(error.localizedDescription)"
                statusMessage = "批量发布成功（releaseSeq \(seq)），保留已发布记录供核对。"
            }
            // 草稿箱发布不清空当前正在填写的下一份系列。
            return .published(releaseSeq: seq)
        case .failed(let reason):
            for job in unchanged { job.markFailed(.failed, error: reason, logPath: cloud.lastRunLogURL?.path) }
            do {
                try saveCatalogContext(context)
                lastError = reason
            } catch {
                lastError = reason + "；本机失败状态保存失败：\(error.localizedDescription)"
            }
            return .failed(reason: lastError ?? reason, itemFailures: [])
        }
    }
}
