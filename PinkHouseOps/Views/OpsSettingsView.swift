import AppKit
import UniformTypeIdentifiers
import SwiftUI
import SharedCatalog

struct OpsSettingsView: View {
    @ObservedObject private var model = OpsCloudSyncModel.shared
    @ObservedObject private var holder = OpsWorkspaceHolder.shared
    @State private var importMessage: String?
    @State private var importFailed = false
    @State private var repairMessage: String?
    @State private var repairFailed = false
    @State private var missingCount = 0
    @State private var showsRepairConfirm = false

    var body: some View {
        Form {
            OpsDataSyncSection()
            Section("发布环境") {
                Picker("编辑内容发布到", selection: $model.targetEnvironment) {
                    ForEach(ShopCatalogPublishTargetEnvironment.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }.pickerStyle(.radioGroup).disabled(model.isRunning || model.isSyncing)
                ForEach(model.credentialStates) { state in
                    Label(state.environment.displayName + (state.isConfigured ? "：已配置" : "：未配置"),
                          systemImage: state.isConfigured ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(state.isConfigured ? Color.secondary : Color.orange)
                }
                Button("导入当前环境凭证…") { model.importCredentialFile() }
                    .disabled(model.isRunning || model.isSyncing)
                DisclosureGroup("连接配置") {
                    ForEach(model.diagnosis, id: \.self) {
                        Text($0).font(.caption).foregroundStyle(.orange)
                    }
                    LabeledContent("仓库", value: model.settings.repoRootPath ?? "未授权")
                    Button("选择仓库目录…") { model.chooseRepoRoot() }
                    Text(model.interpreterText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                DisclosureGroup("导入与数据修复") {
                    HStack {
                        Button("导入整包…") { chooseAndImport(kind: .bundle) }
                        Button("导入 JSON…") { chooseAndImport(kind: .jsonOnly) }
                    }
                    Text("导入会替换当前草稿。整包需先解压，再选择包含 shop-catalog.json 与 images 的目录。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let importMessage {
                        Text(importMessage).foregroundStyle(importFailed ? Color.red : Color.secondary)
                    }
                    Divider()
                    Button("补齐本机缺失图片…") { chooseAndRepairImages() }
                        .disabled(missingCount == 0 || holder.workspace == nil)
                    Button("导出缺图清单…") { exportMissingImages() }
                        .disabled(missingCount == 0 || holder.workspace == nil)
                    Button("清理悬空销售记录…") { showsRepairConfirm = true }
                        .disabled((holder.workspace?.danglingSaleEventCount ?? 0) == 0)
                    if let repairMessage {
                        Text(repairMessage).foregroundStyle(repairFailed ? Color.red : Color.secondary)
                    }
                }.disabled(model.isRunning || model.isSyncing)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 580)
        .task { refreshCounters() }
        .onChange(of: holder.workspace?.currentRevision) { _, _ in refreshCounters() }
        .confirmationDialog("清理悬空销售记录", isPresented: $showsRepairConfirm, titleVisibility: .visible) {
            Button("删除 \(holder.workspace?.danglingSaleEventCount ?? 0) 条记录", role: .destructive) {
                repairDangling()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这些记录引用的商品已不存在。删除后无法撤销。")
        }
    }

    private func refreshCounters() {
        missingCount = holder.workspace?.missingStagedImages().count ?? 0
    }

    private func repairDangling() {
        guard let workspace = holder.workspace else {
            repairFailed = true
            repairMessage = "还没有可修复的工作区：请先打开主窗口（草稿库在主窗口里建）。"
            return
        }
        let removed = workspace.removeDanglingSaleEvents()
        if removed > 0 {
            repairFailed = false
            repairMessage = workspace.statusText ?? "已清理 \(removed) 条。"
        } else if let error = workspace.lastError {
            repairFailed = true
            repairMessage = error
        } else {
            // 0 条且无错误 = 确认期间数量变了，不算失败
            repairFailed = false
            repairMessage = workspace.statusText ?? "没有可清理的悬空销售记录。"
        }
    }

    /// 导出缺图清单：拿到完整名单才能去 iOS 端 / 图源逐张核对。
    /// 门禁日志只显示前几条阻断项，光看那个数字无从下手。
    private func exportMissingImages() {
        guard let workspace = holder.workspace else {
            repairFailed = true
            repairMessage = "还没有可用的工作区：请先打开主窗口（草稿库在主窗口里建）。"
            return
        }
        // 与主窗口失败悬浮框共用 `OpsMissingImagesExport`（保存面板 + 文案只写一处）
        if let message = OpsMissingImagesExport.save(from: workspace) {
            repairFailed = message.hasPrefix("导出缺图清单失败")
            repairMessage = message
        }
    }

    private func chooseAndRepairImages() {
        guard let workspace = holder.workspace else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择完整图片包的解压目录或 images 文件夹，只补当前缺失的图片"
        panel.prompt = "补齐图片"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let report = workspace.repairMissingImages(from: url) {
            refreshCounters()
            repairFailed = missingCount > 0 || !report.failures.isEmpty
            repairMessage = (workspace.statusText ?? report.summary)
                + (workspace.lastError.map { "\n" + $0 } ?? "")
        } else {
            repairFailed = true
            repairMessage = workspace.lastError ?? "补图失败"
        }
    }

    // 从 iOS 恢复

    /// 两种形状：解开后的整包目录（带 images/）与单独的 JSON。
    /// 服务层 `OpsWorkspace.importHandoffPackage(from:)` 两种都认
    /// （`OpsHandoffLayout.resolve`），所以这里只负责把选择形状说清楚。
    private enum ImportKind {
        case bundle
        case jsonOnly
    }

    private func chooseAndImport(kind: ImportKind) {
        guard let workspace = holder.workspace else {
            importFailed = true
            importMessage = "还没有可导入的工作区：请先打开主窗口（草稿库在主窗口里建）。"
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = (kind == .jsonOnly)
        panel.canChooseDirectories = (kind == .bundle)
        panel.allowsMultipleSelection = false
        switch kind {
        case .bundle:
            panel.message = "选择 iOS 整包解开后的目录（含 shop-catalog.json 与 images/）"
            panel.prompt = "导入整包"
        case .jsonOnly:
            panel.allowedContentTypes = [.json]
            panel.message = "选择那份 shop-catalog.json（同目录有图会一起拷）"
            panel.prompt = "导入 JSON"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // ⚠️ 结果**必须**出声：只写 lastError 不动界面 = 运营点完像没反应。
        if let report = workspace.importHandoffPackage(from: url) {
            importFailed = false
            importMessage = report.summary
                + (report.missingText.map { " ⚠️ " + $0 } ?? "")
        } else {
            importFailed = true
            importMessage = workspace.lastError ?? "导入失败（未说明原因）"
        }
    }
}
