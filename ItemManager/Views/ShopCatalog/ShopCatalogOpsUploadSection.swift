//
//  ShopCatalogOpsUploadSection.swift
//  ItemManager
//
//  运营中心 · 「上传发布」区（iOS 运营上传实施方案 §6 验收口径的可视化）。
//
//  展示口径（方案 §4 的本地任务表 + §6 的可见状态）：
//    · 每张图一条任务，状态 `staged → uploading → mediaVerified`；
//    · 发布包 / 发布头各占一条任务（阶段 = 商品包 / 发布头）；
//    · **只有第 6 步（只读端回读）成功**才显示「已发布」—— 方案 §3.4 第 7 步；
//    · 失败一定带原因和重试入口，绝不静默（项目既有「失败必须可见」口径）。
//

import SwiftUI

struct ShopCatalogOpsUploadSection: View {

    /// 待发布的完整目录（种子 + 覆盖层）
    let catalog: ShopCatalog?

    @ObservedObject private var publisher = ShopCatalogOpsPublisher.shared
    @ObservedObject private var uploadStore = ShopCatalogOpsUploadStore.shared

    @State private var isRunning = false

    var body: some View {
        Section(content: {
            Button {
                Task { await runPublish() }
            } label: {
                Label(isRunning ? "\(publisher.phase.displayName)…" : "上传并发布到公共库",
                      systemImage: "icloud.and.arrow.up")
            }
            .disabled(isRunning || catalog == nil)

            if let catalog {
                Button {
                    _ = publisher.stageOnly(catalog: catalog)
                } label: {
                    Label("仅暂存图片（不上传）", systemImage: "photo.stack")
                }
                .disabled(isRunning)
            }

            if hasFailedJobs {
                Button {
                    Task { await runRetry() }
                } label: {
                    Label("重试失败项", systemImage: "arrow.clockwise")
                }
                .disabled(isRunning)
            }
            // 去重拦截必须可见：只说「图片 N 张」看不出是不是又全传了一遍
            if let stats = publisher.lastMediaStats {
                Text(stats.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }, header: {
            Text("上传发布")
        }, footer: {
            Text(footerText)
        })

        if let reason = uploadStore.unavailableReason {
            Section {
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }

        if !uploadStore.jobs.isEmpty {
            uploadTaskSection
        }
    }

    // MARK: 任务分页（当前 / 失败 / 历史）

    private enum UploadTaskTab: String, CaseIterable {
        case current = "当前"
        case failed = "失败"
        case history = "历史"
    }

    /// 页签状态挂在这个 Section 级视图上（不是挂在 List 行视图上，
    /// 行重建会把 `@State` 归零 —— 项目反模式清单第 4 条）
    @State private var taskTab: UploadTaskTab = .current

    private func jobs(for tab: UploadTaskTab) -> [ShopCatalogUploadJob] {
        switch tab {
        case .current: return uploadStore.currentJobs
        case .failed: return uploadStore.failedJobs
        case .history: return uploadStore.historyJobs
        }
    }

    @ViewBuilder
    private var uploadTaskSection: some View {
        Section {
            Picker("任务分页", selection: $taskTab) {
                ForEach(UploadTaskTab.allCases, id: \.self) { tab in
                    Text("\(tab.rawValue) \(jobs(for: tab).count)").tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let visible = jobs(for: taskTab)
            if visible.isEmpty {
                Text("这个页签暂时没有任务")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(visible, id: \.jobID) { job in
                jobRow(job)
            }
        } header: {
            Text("上传任务（共 \(uploadStore.jobs.count) 条）")
        } footer: {
            Text(taskTabFootnote)
        }
    }

    private var taskTabFootnote: String {
        switch taskTab {
        case .current:
            return "今天的任务。上次会话中断留下的「上传中」会在启动时自动复位成「待上传」。"
        case .failed:
            return "需要处理的失败任务（不分日期，避免被时间藏起来）。"
        case .history:
            return "非今天的任务，只作留痕。"
        }
    }

    // MARK: 行

    @ViewBuilder
    private func jobRow(_ job: ShopCatalogUploadJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(job.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(job.status.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color(for: job.status))
            }
            HStack(spacing: 8) {
                Text(job.stage.displayName)
                Text("\(job.byteCount) 字节")
                if job.attemptCount > 0 { Text("第 \(job.attemptCount) 次尝试") }
                if job.releaseSeq > 0 { Text("序号 \(job.releaseSeq)") }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            if let error = job.lastError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            if let next = job.nextRetryAt, job.status == .retryable {
                Text("计划于 \(next.formatted(.dateTime.hour().minute().second())) 重试")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: 动作

    private func runPublish() async {
        guard let catalog else { return }
        isRunning = true
        defer { isRunning = false }
        _ = await publisher.publish(catalog: catalog)
    }

    private func runRetry() async {
        guard let catalog else { return }
        isRunning = true
        defer { isRunning = false }
        _ = await publisher.retryFailed(catalog: catalog)
    }

    // MARK: 文案

    private var hasFailedJobs: Bool {
        uploadStore.jobs.contains { $0.status.allowsManualRetry }
    }

    private var footerText: String {
        if let result = publisher.lastResult {
            return result.summary
        }
        return "上传会把「local: 图片」→ THMedia、「商品 JSON」→ THDataPack、"
            + "最后条件切换 THRelease；只有只读端回读成功才会显示「已发布」。"
    }

    private func color(for status: ShopCatalogUploadStatus) -> Color {
        switch status {
        case .published: return .green
        case .mediaVerified, .staged: return .secondary
        case .uploading: return .blue
        case .blocked, .conflict, .publishedButUnverified, .failed, .stagedFailed: return .red
        case .retryable: return .orange
        }
    }
}
