//
//  OpsSeriesPublishQueueView.swift
//  PinkHouseOps
//
//  「发布草稿箱」页面：**系列发布**留下未发出去的记录都在这里。
//
//  ## 它回答的三个问题
//
//  1. **哪些系列还没发上去**（运营看：列表 + 状态徽章）；
//  2. **是哪一条没成**（运营看：条目级 ✓ / ✗ + 原因）—— 只写「发布失败」等于没说；
//  3. **现在该怎么办**（运营做：重试 / 放弃删除）。
//
//  ## 为什么记录「只有全部成功才删」
//
//  草稿箱的存在意义就是「内容不丢」。发布**部分**成功时如果删了记录，
//  剩下的失败条目就没有任何入口再被看到 —— 那才是真的丢了。
//  所以删除只在 `OpsWorkspace.publishSeries` 确认**整个系列**都发出去之后发生。
//

import SwiftUI
import SwiftData

struct OpsSeriesPublishQueueView: View {
    @ObservedObject var workspace: OpsWorkspace

    /// 数据源直接查 SwiftData：发布过程中状态一变，列表就跟着变。
    /// 不用 `@State` 缓存一份 —— 缓存就是「两处真相」。
    @Query(sort: \OpsSeriesPublishJob.updatedAt, order: .reverse)
    private var jobs: [OpsSeriesPublishJob]

    @ObservedObject private var cloud = OpsCloudSyncModel.shared
    @State private var isRetrying = false
    @State private var retryMessage: String?
    @State private var selectedJobIDs: Set<String>
    @State private var activeJobIDs: Set<String> = []

    init(workspace: OpsWorkspace, selectedJobIDs: Set<String> = []) {
        self.workspace = workspace
        _selectedJobIDs = State(initialValue: selectedJobIDs)
    }

    private var isBusy: Bool { isRetrying || cloud.isRunning || cloud.isSyncing }
    private var eligibleJobs: [OpsSeriesPublishJob] {
        jobs.filter { workspace.seriesBatchPublishBlockReason(job: $0, cloud: cloud) == nil }
    }
    private var selectedJobs: [OpsSeriesPublishJob] {
        eligibleJobs.filter { selectedJobIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explainCard
                if !jobs.isEmpty { selectionControls }
                if let retryMessage {
                    opsMarkdown(retryMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if jobs.isEmpty {
                    emptyCard
                } else {
                    ForEach(jobs) { job in
                        jobCard(job)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .onChange(of: workspace.draft?.id) { _, _ in selectedJobIDs.removeAll() }
        .onChange(of: cloud.targetEnvironment.rawValue) { _, _ in selectedJobIDs.removeAll() }
        .onChange(of: jobs.map(\.id)) { _, ids in selectedJobIDs.formIntersection(ids) }
    }

    private var selectionControls: some View {
        HStack(spacing: 12) {
            Button("全选可发布系列") { selectedJobIDs = Set(eligibleJobs.map(\.id)) }
                .disabled(isBusy || eligibleJobs.isEmpty)
            Button("清除选择") { selectedJobIDs.removeAll() }
                .disabled(isBusy || selectedJobIDs.isEmpty)
            Text(isRetrying ? "正在发布 \(activeJobIDs.count) 个系列" : "已选 \(selectedJobs.count) 个系列")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("发布所选系列（\(isRetrying ? activeJobIDs.count : selectedJobs.count)）", systemImage: "paperplane") { publishSelected() }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || selectedJobs.isEmpty)
        }
    }

    private var explainCard: some View {
        OpsCard(title: "发布草稿箱", systemImage: "tray.2") {
            VStack(alignment: .leading, spacing: 4) {
                OpsFootnote(text: "在系列上新点「提交整个系列（写入草稿）」后，系列会出现在这里，状态为「待发布」。"
                            + "可勾选多个系列，点「发布所选系列」一起上传；成功后移除记录，失败时保留内容和原因供重试。")
                OpsFootnote(text: "可一起发布当前草稿、当前环境中已完整提交的系列。同步可在后台运行，期间仍可继续编辑。")
            }
        }
    }

    private var emptyCard: some View {
        OpsCard(title: "现在是空的", systemImage: "checkmark.tray") {
            Text("没有待发布 / 发布失败的系列。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func jobCard(_ job: OpsSeriesPublishJob) -> some View {
        OpsCard(title: job.seriesName, systemImage: statusSymbol(job.status)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Toggle("选择此系列", isOn: Binding(
                        get: { selectedJobIDs.contains(job.id) },
                        set: { if $0 { selectedJobIDs.insert(job.id) } else { selectedJobIDs.remove(job.id) } }))
                        .toggleStyle(.checkbox)
                        .disabled(isBusy || workspace.seriesBatchPublishBlockReason(job: job, cloud: cloud) != nil)
                    statusBadge(job.status)
                    if let environment = job.environment {
                        Text(environment)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if job.attempts > 0 {
                        Text("第 \(job.attempts) 次尝试")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let reason = workspace.seriesBatchPublishBlockReason(job: job, cloud: cloud),
                   job.status != .publishing, job.status != .published {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                if let shopName = job.shopName { LabeledContent("店家", value: shopName) }
                LabeledContent("线上发布号",
                               value: job.releaseSeq.map { "releaseSeq \($0)" } ?? "—")

                // 条目级状态：**失败条目必须逐条可见**
                if !job.items.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(job.items) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(item.ok ? Color.green : Color.red)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name.isEmpty ? item.id : item.name)
                                        .font(.callout)
                                    if let message = item.message {
                                        opsMarkdown(message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }

                if let error = job.lastError {
                    opsMarkdown("失败原因：" + error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let logPath = job.logPath {
                    Text("日志：\(logPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let ownerID = job.draftID, ownerID != workspace.draft?.id {
                    Text("此系列属于另一份草稿，打开所属草稿后可发布。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("打开所属草稿") {
                        if workspace.openSeriesPublishDraft(job: job) { retryMessage = nil }
                        else { retryMessage = workspace.lastError }
                    }
                    .disabled(isBusy)
                }
                HStack(spacing: 8) {
                    Button(job.status == .pending ? "发布整个系列" : "重试发布") { retry(job) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy || job.status == .publishing || job.status == .published
                                  || (job.draftID != nil && job.draftID != workspace.draft?.id))
                    Button("打开日志文件") {
                        if let logPath = job.logPath {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: logPath)])
                        }
                    }
                    .disabled(job.logPath == nil)
                    if isRetrying && activeJobIDs.contains(job.id) {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: OpsSeriesPublishStatus) -> some View {
        Text(status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor(status))
    }

    private func badgeColor(_ status: OpsSeriesPublishStatus) -> Color {
        switch status {
        case .published: return .green
        case .publishing, .pending: return .orange
        case .partialFailed, .failed: return .red
        }
    }

    private func statusSymbol(_ status: OpsSeriesPublishStatus) -> String {
        switch status {
        case .published: return "checkmark.seal"
        case .publishing: return "arrow.triangle.2.circlepath"
        case .pending: return "clock"
        case .partialFailed: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        }
    }

    private func retry(_ job: OpsSeriesPublishJob) {
        guard !isRetrying else { return }
        isRetrying = true
        activeJobIDs = [job.id]
        retryMessage = nil
        Task { @MainActor in
            let outcome = await workspace.retrySeriesPublish(job: job, cloud: cloud)
            switch outcome {
            case .published(let seq):
                selectedJobIDs.remove(job.id)
                retryMessage = workspace.lastError ?? "发布成功（releaseSeq \(seq)），草稿箱记录已删除。"
            case .failed(let reason, _):
                retryMessage = "发布失败：" + reason
            }
            isRetrying = false
            activeJobIDs.removeAll()
        }
    }

    private func publishSelected() {
        guard !isBusy, !selectedJobs.isEmpty else { return }
        let batch = selectedJobs
        let ids = Set(batch.map(\.id))
        isRetrying = true
        activeJobIDs = ids
        retryMessage = nil
        Task { @MainActor in
            let outcome = await workspace.publishSelectedSeries(jobs: batch, cloud: cloud)
            switch outcome {
            case .published(let seq):
                selectedJobIDs.subtract(ids)
                retryMessage = workspace.lastError ?? "所选 \(batch.count) 个系列发布成功（releaseSeq \(seq)）。"
            case .failed(let reason, _):
                retryMessage = "批量发布未完成：" + reason
            }
            isRetrying = false
            activeJobIDs.removeAll()
        }
    }
}
