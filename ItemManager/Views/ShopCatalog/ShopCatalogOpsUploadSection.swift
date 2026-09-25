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
            Section("上传任务（\(uploadStore.jobs.count)）") {
                ForEach(uploadStore.jobs, id: \.jobID) { job in
                    jobRow(job)
                }
            }
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
