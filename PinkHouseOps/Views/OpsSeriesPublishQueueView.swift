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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explainCard
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
    }

    private var explainCard: some View {
        OpsCard(title: "发布草稿箱", systemImage: "tray.2") {
            VStack(alignment: .leading, spacing: 4) {
                OpsFootnote(text: "点「发布整个系列」时，内容会**先完整落进这里**再发。"
                            + "发成功了记录就没了；失败或部分成功会一直留着，"
                            + "逐条标出是哪一条没发成，改完直接重试。")
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
                    statusBadge(job.status)
                    if let environment = job.environment {
                        Text(environment)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("第 \(job.attempts) 次尝试")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
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
                HStack(spacing: 8) {
                    Button("重试发布") { retry(job) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRetrying)
                    Button("打开日志文件") {
                        if let logPath = job.logPath {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: logPath)])
                        }
                    }
                    .disabled(job.logPath == nil)
                    if isRetrying {
                        ProgressView().controlSize(.small)
                    }
                    if let retryMessage {
                        opsMarkdown(retryMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        retryMessage = nil
        Task { @MainActor in
            let outcome = await workspace.retrySeriesPublish(job: job, cloud: cloud)
            switch outcome {
            case .published(let seq):
                retryMessage = "发布成功（releaseSeq \(seq)），草稿箱记录已删除。"
            case .failed(let reason, _):
                retryMessage = "发布失败：" + reason
            }
            isRetrying = false
        }
    }
}
