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
//  2026-09-29 补两条（修「点了没反应」）：
//    · **上传前检查**：常态跑共享门禁 `ShopCatalogPublicationGate`（与 Mac 端同一份判定），
//      不点按钮就能看到「有多少处图片引用解不出图」—— 缺图是常态，不该等点了才知道；
//    · **一次列全**：`publisher.lastStagingIssues` 列出**所有**解不出图的文件。
//      原先 `plan` 抛第一条就停、返回值又被按钮丢弃 ⇒ 缺图时界面一个字都不显示。
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
                    // 结果由 `publisher` 自己发布（`lastResult` / `lastStagingIssues`）——
                    // 2026-09-29 之前这里是 `_ = …` 且 publisher 不写状态，缺图时**零反馈**，
                    // 运营看到的就是「点了没反应」。
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

        // 上传前检查：**不点也能看到**能不能发。缺图是常态（换设备 / 清沙盒都会造成），
        // 而「点下去才报错」会让运营以为是 App 卡了。
        if let review = preflightReview {
            preflightSection(review)
        }

        // 上次暂存 / 发布发现的问题：一次列全（不再只说第一条）
        if !publisher.lastStagingIssues.isEmpty {
            stagingIssueSection
        }

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

    // MARK: 上传前检查（共享门禁）

    /// 发布前图片门禁，判定**与 Mac 端同一份**（共享包 `ShopCatalogPublicationGate`，
    /// 🚫 不要在这里另写一套「文件在不在」的判断）。
    ///
    /// 用 `stagedFileNames` 只比文件名、不读字节，所以每次渲染都算得起。
    private var preflightReview: ShopCatalogPublicationReview? {
        guard let catalog else { return nil }
        return ShopCatalogPublicationGate.review(
            catalog,
            stagedFileNames: ShopCatalogImageStore.existingFileNames())
    }

    @ViewBuilder
    private func preflightSection(_ review: ShopCatalogPublicationReview) -> some View {
        Section {
            if review.isBlocked {
                Label("\(review.blockingIssues.count) 处图片引用解不出图，上传会被拦下",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
                ForEach(Array(review.blockingIssues.prefix(3).enumerated()), id: \.offset) { pair in
                    Text(pair.element)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if review.blockingIssues.count > 3 {
                    Text("还有 \(review.blockingIssues.count - 3) 条，按「仅暂存图片」可看全。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("图片齐了，可以上传", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
                Text("本机图片目录：\(ShopCatalogImageStore.existingFileNames().count) 个文件")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("上传前检查")
        } footer: {
            Text("与 Mac 端发布门禁共用同一份判定：local: 图片必须能在本机图片目录里找到，"
                 + "缺一张就整包不发（否则其它设备看到的是空白图）。")
        }
    }

    // MARK: 暂存问题清单

    /// 一次列全的问题清单。文案直接来自 `ShopCatalogOpsMediaIssue.displayText`
    /// （含「是哪个商品 / 哪个字段」），并允许长按复制 —— 现场取字比截图强。
    private var stagingIssueSection: some View {
        Section {
            ForEach(Array(publisher.lastStagingIssues.prefix(8).enumerated()), id: \.offset) { pair in
                Text(pair.element.displayText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if publisher.lastStagingIssues.count > 8 {
                Text("还有 \(publisher.lastStagingIssues.count - 8) 条未显示（同一次上传会一并处理）。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("上传失败原因（\(publisher.lastStagingIssues.count) 个文件）")
        } footer: {
            Text("这里列的是全部解不出图的文件，不是只报第一条。补上图之后重新上传即可。")
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
