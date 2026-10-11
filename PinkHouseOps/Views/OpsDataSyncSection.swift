import AppKit
import SwiftUI

struct OpsDataSyncSection: View {
    @ObservedObject private var sync = OpsDataSyncModel.shared
    @ObservedObject private var holder = OpsWorkspaceHolder.shared

    var body: some View {
        Section("数据同步") {
            ForEach(OpsDataSyncModel.Operation.allCases) { operation in
                Button(operation == .migration ? sync.migrationTitle : operation.title) {
                    Task { await sync.run(operation, workspace: holder.workspace) }
                }
                .disabled(sync.isBusy || (operation != .migration && holder.workspace == nil))
            }
            Text("拉取自动下载图片、合并并保留本地独有数据；迁移增量更新线上，保留线上独有数据和下架记录。")
                .font(.caption).foregroundStyle(.secondary)
            OpsDataSyncResultView()
        }
    }
}

struct OpsDataSyncResultView: View {
    @ObservedObject private var sync = OpsDataSyncModel.shared
    @ObservedObject private var cloud = OpsCloudSyncModel.shared

    var body: some View {
        if sync.isRunning {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let progress = cloud.operationProgress, let fraction = progress.fraction {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(progress.title + " · " + (progress.countText ?? ""))
                            ProgressView(value: fraction)
                        }
                    } else {
                        ProgressView(cloud.operationProgress?.title ?? sync.currentTitle + "…")
                            .controlSize(.small)
                    }
                    Spacer(minLength: 8)
                    if let url = cloud.lastRunLogURL {
                        Button("打开日志") { NSWorkspace.shared.open(url) }
                    }
                }
                if let progress = cloud.operationProgress {
                    TimelineView(.periodic(from: progress.startedAt, by: 1)) { context in
                        Text(progress.timingText(at: context.date))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.font(.callout)
        } else if let result = sync.result {
            HStack(alignment: .top) {
                Label(result.message, systemImage: result.failed ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(result.failed ? Color.red : Color.secondary)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if let url = result.logURL {
                    Button("打开日志") { NSWorkspace.shared.open(url) }
                }
            }.font(.callout)
        }
    }
}
