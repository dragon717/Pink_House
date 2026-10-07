import AppKit
import SwiftUI
import PinkHouseOpsCore

/// 三步分别结算；部分完成时保留绿色成功步骤和橙色待修复步骤。
struct OpsSyncProgressView: View {
    let report: OpsSyncReport
    var detailed = false
    var onDismiss: (() -> Void)?
    @State private var showsIssues = false
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(report.title, systemImage: report.isComplete ? "checkmark.icloud" : "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                if let onDismiss, !report.isRunning {
                    Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
            }
            ForEach(report.steps) { step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(step.step.title).font(.callout.weight(.medium))
                        Spacer()
                        Text(step.state.title).font(.caption.weight(.semibold)).foregroundStyle(color(step.state))
                    }
                    if step.state == .running, step.progress == nil {
                        ProgressView().progressViewStyle(.linear)
                    } else {
                        ProgressView(value: step.progress ?? 0).tint(color(step.state))
                    }
                    Text(step.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            if !report.issues.isEmpty {
                HStack {
                    Label("\(report.issues.count) 项需要处理", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer()
                    if !detailed { Button("查看问题与日志…") { showsIssues = true }.controlSize(.small) }
                }
            } else if !detailed, !report.isRunning, !report.isComplete {
                Button("查看步骤与日志…") { showsIssues = true }.controlSize(.small)
            }
            if detailed { issueList }
        }
        .padding(14)
        .frame(maxWidth: detailed ? .infinity : 600, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)))
        .sheet(isPresented: $showsIssues) {
            VStack(alignment: .leading, spacing: 12) {
                OpsSyncProgressView(report: report, detailed: true)
                HStack {
                    Button("导出问题清单…") { exportIssues() }
                    SettingsLink { Label("打开设置处理合并冲突与数据", systemImage: "wrench.and.screwdriver") }
                    Spacer()
                    Button("关闭") { showsIssues = false }.keyboardShortcut(.cancelAction)
                }
                if let exportError {
                    Text(exportError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }.padding(20).frame(width: 760, height: 650)
        }
    }

    private var issueList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(report.issues) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(issue.step.title) · \(issue.owner)").font(.callout.weight(.medium))
                        Text(issue.message).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                }
                ForEach(report.steps) { step in
                    ForEach(step.logPaths, id: \.self) { path in
                        Button("\(step.step.title) · 打开日志") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }.font(.caption).help(path)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: .infinity)
    }

    private func color(_ state: OpsSyncState) -> Color {
        switch state {
        case .completed: return .green
        case .partial, .blocked: return .orange
        case .failed: return .red
        case .running: return .accentColor
        case .waiting, .skipped: return .secondary
        }
    }

    private func exportIssues() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "云端同步问题-\(report.issues.count).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let issues = report.issues.map { "\($0.step.title) | \($0.owner) | \($0.message)" }
        let logs = report.steps.flatMap { step in step.logPaths.map { "\(step.step.title) | 日志 | \($0)" } }
        let text = (["环境：\(report.environment)", "草稿：\(report.draftID)", report.summary, "", "问题清单："]
                    + issues + ["", "日志："] + logs).joined(separator: "\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8); exportError = nil }
        catch { exportError = "导出失败：\(error.localizedDescription)" }
    }
}
