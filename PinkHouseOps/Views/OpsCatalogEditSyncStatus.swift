import SwiftUI
import PinkHouseOpsCore

/// 保存同步的持续反馈；始终标出两个环境，不把图片上传完误报为整个保存完成。
struct OpsCatalogEditSyncStatus: View {
    @ObservedObject var workspace: OpsWorkspace
    var body: some View {
        if let progress = workspace.catalogEditSyncProgress {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title(progress)).font(.callout.weight(.medium))
                    Spacer()
                    Text("第 \(progress.revision) 版 · \(Int(progress.fraction * 100))%")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fraction)
                    .tint(progress.state == .failed ? .orange : .accentColor)
                ForEach(["development", "production"], id: \.self) { environment in
                    HStack(alignment: .top) {
                        Image(systemName: progress.environments[environment]?.releaseSeq == nil
                              ? "circle" : "checkmark.circle.fill")
                        Text(environment == "development" ? "开发环境" : "线上环境")
                        Text(progress.environments[environment]?.detail ?? "等待同步")
                            .foregroundStyle(.secondary)
                    }.font(.caption)
                }
                if let error = progress.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if workspace.canRetrySavedSeriesSync {
                    Button("继续同步并核对结果") { workspace.retrySavedSeriesSync() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
        }
    }
    private func title(_ progress: OpsCatalogEditProgress) -> String {
        switch progress.state {
        case .queued: "修改已保存，等待同步"
        case .running: "正在同步已保存修改"
        case .failed: "本机已保存，同步尚未完成"
        case .complete: "两个环境的修改均已核验完成"
        }
    }
}
