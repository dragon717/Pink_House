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
    @ObservedObject private var catalogStore = ShopCatalogStore.shared
    @State private var isRunning = false
    @State private var pendingConflicts: [String] = []
    @State private var conflictToken: String?

    var body: some View {
        let missingDrafts = ShopCatalogDraftStore.shared.recoverablePublishedDrafts(store: catalogStore)
        if !missingDrafts.isEmpty {
            Section("待恢复商品") {
                Text("\(missingDrafts.count) 件商品有入库回执，但当前目录缺少商品实体。")
                ForEach(missingDrafts) { draft in
                    Text("\(draft.newShopName) · \(draft.newSeriesName) · \(draft.name)")
                }
                Button("从保留的草稿恢复商品") {
                    do {
                        for draft in missingDrafts {
                            _ = try ShopCatalogDraftStore.shared.restoreMissingPublishedDraft(draft, store: catalogStore)
                        }
                        ToastManager.shared.showSuccess("商品已恢复到本机，请上传并发布")
                    } catch {
                        ToastManager.shared.showError(error.localizedDescription)
                    }
                }
                .disabled(isRunning)
            }
        }

        Section(content: {
            Button {
                Task { await runPublish() }
            } label: {
                Label(isRunning ? "\(publisher.phase.displayName)…" : "同步更新并上传",
                      systemImage: "icloud.and.arrow.up")
            }
            .disabled(isRunning || catalog == nil)

            if hasFailedJobs {
                Button {
                    Task { await runPublish() }
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

        conflictSection

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

    @ViewBuilder
    private var conflictSection: some View {
        if let token = conflictToken {
            Section("需要解决冲突") {
                Text("双方修改了以下字段。请选择这些冲突字段采用哪一方，其余新增和修改都会保留。")
                ForEach(pendingConflicts, id: \.self) { field in
                    Text(conflictDescription(field)).font(.caption).textSelection(.enabled)
                }
                Button("冲突字段保留本机修改并上传") {
                    Task { await runPublish(resolution: .init(token: token, preferLocal: true)) }
                }
                Button("冲突字段采用线上修改并上传") {
                    Task { await runPublish(resolution: .init(token: token, preferLocal: false)) }
                }
            }
            .disabled(isRunning)
        }
    }

    private func conflictDescription(_ path: String) -> String {
        let parts = path.split(separator: ".").map(String.init)
        guard parts.count >= 3 else { return path }
        let id = parts[1]
        let name: String
        switch parts[0] {
        case "shops": name = catalogStore.shop(id: id)?.name ?? id
        case "series": name = catalogStore.series(id: id)?.name ?? id
        case "products": name = catalogStore.product(id: id)?.name ?? id
        default: name = id
        }
        let labels = ["name": "名称", "category": "分类", "shopID": "关联店家",
                      "seriesID": "关联系列", "images": "图片", "designName": "款式名",
                      "price": "价格", "fabric": "面料", "logo": "店家图标",
                      "coverImage": "系列封面", "description": "描述"]
        return name + " · " + (labels[parts.last!] ?? parts.dropFirst(2).joined(separator: "."))
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
                    Text("还有 \(review.blockingIssues.count - 3) 条，同步失败时下方会列出完整原因。")
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
                    .lineLimit(3)
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

    private func runPublish(
        resolution: ShopCatalogOpsPublisher.ConflictResolution? = nil
    ) async {
        guard !isRunning, catalog != nil else { return }
        isRunning = true
        defer { isRunning = false }
        switch await publisher.synchronizeAndPublish(
            store: catalogStore, resolution: resolution) {
        case .conflicts(let fields, let token):
            pendingConflicts = fields
            conflictToken = token
        case .finished:
            pendingConflicts = []
            conflictToken = nil
        }
    }

    // MARK: 文案

    /// 把**变量**里的 `**强调**` 渲染成粗体。
    ///
    /// 根因（与 Mac 端 `opsMarkdown(_:)` 同一条）：`Text(字面量)` 会按 LocalizedStringKey
    /// 解析 Markdown，而 `Text(变量)` 与 `Text("a" + "b")` **不解析** ——
    /// 不转的话 `**不会被删**` 会逐字显示成星号，**不崩、不报错、编译与单测全绿**。
    /// 参数（`.inlineOnlyPreservingWhitespace`）两个都不能去，理由同 Mac 端那一份。
    private func emphasisText(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }

    private var hasFailedJobs: Bool {
        uploadStore.jobs.contains { $0.status.allowsManualRetry }
    }

    private var footerText: String {
        if let result = publisher.lastResult {
            return result.summary
        }
        return "自动拉取线上内容并合并，保留本机新增和修改；有冲突时先选择，再上传。回读验证成功后显示已发布。"
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
