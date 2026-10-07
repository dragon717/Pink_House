//
//  OpsRootView.swift
//  PinkHouseOps
//
//  运营工具主框架：侧栏分区 + 顶部状态条 + 分区内容。
//
//  ## 为什么要把「状态反馈」放在最外层而不是各页各写一份
//
//  计划 §7 要求「失败必须可见」。历史上这个仓库出过一次「错误文案还在赋值、
//  但渲染它的那段被重构删掉了」的静默失败（`TimeHallCatalogItemCard`），
//  使用者看到的就是「点了没反应」。所以反馈通道**只有一条**：
//  `OpsWorkspace.statusMessage` / `.lastError` → 这个 banner。
//  任何操作都不许自己再造一套提示；要报信息就写进这两个字段。
//
//  ## 只读隔离态为什么单独一条常驻横幅（方案 R03）
//
//  损坏草稿的提示不能只是「一条可以点『知道了』关掉的错误」——
//  关掉之后运营会以为没事了，然后在空目录上继续填、把它存回去。
//  所以隔离态由 `workspace.isCorrupted` 驱动一条**常驻**横幅，
//  并且**提供出口**（另存为新草稿 / 导出原始字节），而不是只告诉用户「出事了」。
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import PinkHouseOpsCore

struct OpsRootView: View {
    @Environment(\.modelContext) private var modelContext
    /// 工作区需要 modelContext 才能建，所以不能在属性初始化时构造
    @State private var workspace: OpsWorkspace?

    var body: some View {
        Group {
            if let workspace {
                OpsMainView(workspace: workspace)
            } else {
                // 只在一瞬间出现：建容器 + 读草稿都是同步的
                ProgressView("正在打开草稿库…")
                    .frame(minWidth: 720, minHeight: 480)
            }
        }
        .task {
            if workspace == nil {
                let created = OpsWorkspace(context: modelContext)
                workspace = created
                // 设置场景（Cmd+,）与主窗口共用这一份工作区 —— 另建一份就是两处真相。
                OpsWorkspaceHolder.shared.workspace = created
                OpsCloudSyncModel.shared.restoreSyncReport(workspace: created)
            }
        }
    }
}

// MARK: - 分区
//
// 分区顺序 = 一次新上的**实际行走顺序**：
//
//     系列上新（S1–S5 向导，需求 v1.2） → 店家与系列（结构）
//     → 商品管理（内容） → 本地预览（发之前自己看一眼）
//
//  2026-09-27 移除了「工作台 / 素材库 / 发布中心」三个分区及其页面、
//  路由与依赖代码；发布相关能力只保留服务层（校验 / 导出待发布包 / 基线）。

enum OpsSection: String, CaseIterable, Identifiable {
    case seriesEntry
    case catalog
    case products
    case publishQueue
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seriesEntry: return "系列上新"
        case .catalog: return "店家与系列"
        case .products: return "商品管理"
        case .publishQueue: return "发布草稿箱"
        case .preview: return "本地预览"
        }
    }

    var symbolName: String {
        switch self {
        case .seriesEntry: return "sparkles.rectangle.stack"
        case .catalog: return "storefront"
        case .products: return "tshirt"
        case .publishQueue: return "tray.2"
        case .preview: return "eye"
        }
    }
}

// MARK: - 主框架

struct OpsMainView: View {
    @ObservedObject var workspace: OpsWorkspace
    /// 云端同步面板是**单例**驱动：工具栏与向导 S5 打开的是同一份状态，
    /// 否则两处会各记一份「线上基线」，又变成两处真相。
    @StateObject private var cloudSync = OpsCloudSyncModel.shared

    /// 当前分区。默认「系列上新」；快照 harness 需要从别的分区起手
    /// （见 `OpsSnapshotHarness`），所以留了一个显式入口，
    /// 但它**只是初值**，之后完全由侧栏选择驱动。
    @State private var section: OpsSection
    /// 「系列上新」向导的起始步骤（同样只服务快照 harness：
    /// S2 的系列价格表卡片不在 S1 上，不给入口就拍不到）。
    private let initialWizardStep: OpsSeriesWizardStep

    init(workspace: OpsWorkspace,
         initialSection: OpsSection = .seriesEntry,
         initialWizardStep: OpsSeriesWizardStep = .selectShopSeries) {
        self.workspace = workspace
        _section = State(initialValue: initialSection)
        self.initialWizardStep = initialWizardStep
    }

    var body: some View {
        NavigationSplitView {
            List(OpsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbolName)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                DraftSummaryFooter(workspace: workspace)
            }
        } detail: {
            VStack(spacing: 0) {
                OpsStatusBanner(workspace: workspace)
                Divider()
                content
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .overlay(alignment: .top) {
            if let report = cloudSync.syncReport, showsSyncStatus,
               report.draftID == workspace.draft?.id,
               report.environment == cloudSync.targetEnvironment.rawValue {
                OpsSyncProgressView(report: report, onDismiss: { showsSyncStatus = false; updateToast = nil })
                    .padding(.top, 10).padding(.horizontal, 24)
            } else if let toast = updateToast {
                OpsUpdateToastView(toast: toast, onDismiss: { updateToast = nil },
                                   onExportMissing: exportMissingImages)
            }
        }
        .onChange(of: cloudSync.isSyncing) { _, running in
            if running { showsSyncStatus = true; updateToast = nil }
        }
        .toolbar {
            // 一键执行下载、上传、合并落盘，逐步展示结果与待修复数据。
            ToolbarItem(placement: .primaryAction) {
                Button {
                    updateCloudNow()
                } label: {
                    if cloudSync.isRunning || cloudSync.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("云端更新", systemImage: "arrow.triangle.2.circlepath.circle")
                    }
                }
                .disabled(cloudSync.isRunning || cloudSync.isSyncing || workspace.isCorrupted)
                .help("下载平台内容、上传本地变更、合并保存，逐步显示结果（环境与凭证在设置里配置）")
            }
        }
    }

    // MARK: 云端更新（一键）+ 悬浮框

    @State private var updateToast: OpsCloudUpdateToast?
    @State private var isUpdatingCloud = false
    @State private var showsSyncStatus = true

    private func updateCloudNow() {
        guard !isUpdatingCloud else { return }
        isUpdatingCloud = true
        updateToast = nil
        showsSyncStatus = true
        Task { @MainActor in
            let result = await cloudSync.publishNow(workspace: workspace)
            isUpdatingCloud = false
            if cloudSync.syncReport?.draftID == workspace.draft?.id,
               cloudSync.syncReport?.environment == cloudSync.targetEnvironment.rawValue {
                return
            }
            switch result {
            case .confirmed(let seq):
                updateToast = OpsCloudUpdateToast(
                    success: true,
                    title: "云端更新完成",
                    detail: "线上已是 releaseSeq \(seq)。",
                    logPath: cloudSync.lastRunLogURL?.path)
            case .failed(let reason):
                updateToast = OpsCloudUpdateToast(
                    success: false,
                    title: cloudSync.syncReport?.title ?? "同步未完成",
                    detail: reason,
                    logPath: cloudSync.lastRunLogURL?.path,
                    // 校验失败里若含悬空销售记录，直接给一键修复入口
                    canRepairDangling: workspace.danglingSaleEventCount > 0,
                    missingImageCount: workspace.missingStagedImages().count)
            }
            scheduleToastDismiss()
        }
    }

    /// 导出缺图清单（设置页用的是同一份 `OpsMissingImagesExport`）。
    /// 结果直接追加到当前这条失败悬浮框上 —— 反馈通道只有这一条，不另开弹窗。
    private func exportMissingImages() {
        if let message = OpsMissingImagesExport.save(from: workspace) {
            updateToast?.detail = (updateToast?.detail ?? "") + "  · " + message
        }
    }

    /// 悬浮框 15 秒后自己消失（失败的留着手动关，防止没人看到就没了）。
    private func scheduleToastDismiss() {
        guard updateToast?.success == true else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if updateToast?.success == true { updateToast = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .seriesEntry:
            OpsSeriesWizardView(workspace: workspace, initialStep: initialWizardStep)
        case .catalog:
            OpsCatalogEditorView(workspace: workspace)
        case .products:
            OpsProductsView(workspace: workspace)
        case .publishQueue:
            OpsSeriesPublishQueueView(workspace: workspace)
        case .preview:
            OpsPreviewView(workspace: workspace)
        }
    }
}

// MARK: - 侧栏底部：草稿概览 + 保存

struct DraftSummaryFooter: View {
    @ObservedObject var workspace: OpsWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Text(workspace.draft?.title ?? "（无草稿）")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                // 未保存 / 已保存必须是**两个不同的字面**：
                // 只显示「草稿」会让运营以为已经落盘了。
                if workspace.isCorrupted {
                    Text("只读").font(.caption2).foregroundStyle(.orange)
                } else if workspace.hasUnsavedChanges {
                    Text("● 未保存").font(.caption2).foregroundStyle(.orange)
                } else {
                    Text("已保存").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("第 \(workspace.currentRevision) 版 · 上次保存第 \(workspace.savedRevision) 版")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack(spacing: 10) {
                CountChip(label: "店家", value: workspace.catalog.shops.count)
                CountChip(label: "系列", value: workspace.catalog.series.count)
                CountChip(label: "商品", value: workspace.catalog.products.count)
                CountChip(label: "图片", value: workspace.catalog.assets.count)
            }
            Button {
                workspace.saveDraft()
            } label: {
                Label(workspace.hasUnsavedChanges ? "保存修改" : "保存草稿",
                      systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(workspace.draft == nil || workspace.isCorrupted)
            // 环境 / 凭证 / 从 iOS 恢复 / 数据修复都在设置里（Cmd+,）—— 侧栏常驻一个入口。
            // ⚠️ 必须用 `SettingsLink`：`NSApp.sendAction(showSettingsWindow:)` 在新版
            // SwiftUI 里不被响应（控制台刷 "Please use SettingsLink"，窗口打不开）。
            SettingsLink {
                Label("设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("打开设置（环境、凭证、日志、从 iOS 恢复、数据修复）")
        }
        .padding(12)
        .background(.bar)
    }
}

private struct CountChip: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)").font(.callout.weight(.semibold)).monospacedDigit()
            // `label` 是界面文案（店家 / 系列 / 商品 / 图片），过 opsMarkdown
            opsMarkdown(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 状态条（唯一的反馈通道）

struct OpsStatusBanner: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var showsBackupExporter = false
    @State private var backupDocument = RawDataDocument(data: Data())

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if workspace.isCorrupted {
                corruptedBanner
            }
            if workspace.isCorrupted == false, let error = workspace.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    opsMarkdown(error)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("知道了") { workspace.clearError() }
                        .buttonStyle(.link)
                }
            } else if let status = workspace.statusText {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    opsMarkdown(status).font(.callout).lineLimit(2)
                }
            } else if workspace.isCorrupted == false {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("就绪。所有编辑只在本机草稿里，直到导出待发布包。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if workspace.isCorrupted, let status = workspace.statusText, workspace.lastError == nil {
                opsMarkdown(status).font(.callout).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(backgroundStyle)
        .fileExporter(
            isPresented: $showsBackupExporter,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "损坏草稿原始字节.json"
        ) { result in
            switch result {
            case .success(let url):
                workspace.reportSuccess("已导出原始字节：\(url.lastPathComponent)")
            case .failure(let error):
                workspace.reportFailure("导出原始字节失败：\(error.localizedDescription)")
            }
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        if workspace.isCorrupted { return AnyShapeStyle(Color.red.opacity(0.10)) }
        if workspace.lastError != nil { return AnyShapeStyle(Color.orange.opacity(0.12)) }
        return AnyShapeStyle(.bar)
    }

    /// 常驻的只读隔离横幅（R03）：**不能关掉**，并且必须给出口
    private var corruptedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.doc.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                // 拼接结果 = String 变量 → 必须过 `opsMarkdown`（单字面量才自动解析 Markdown）
                opsMarkdown("草稿内容无法解析 —— 已进入**只读隔离**，保存 / 导入 / 导图 / 导出全部被拒绝，"
                     + "原始字节不会被覆盖。")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("当前展示的是空目录，**不要**在里面继续填内容：先另存为新草稿再干活。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("另存为新草稿并继续") {
                        workspace.recoverCorruptedDraftToNewDraft()
                    }
                    Button("导出原始字节…") {
                        if let draft = workspace.draft {
                            backupDocument = RawDataDocument(
                                data: draft.corruptedBackupJSON ?? draft.catalogJSON)
                            showsBackupExporter = true
                        }
                    }
                }
                .controlSize(.small)
            }
            Spacer(minLength: 4)
        }
    }
}

// MARK: - 原始字节导出用文档（损坏草稿留证）

struct RawDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 云端更新悬浮框（2026-10-07）

/// 一次「云端更新」的结果（工具栏一键按钮的反馈）。
struct OpsCloudUpdateToast: Equatable {
    var success: Bool
    var title: String
    var detail: String?
    /// 本次运行的日志文件路径（失败时这是排查入口，直接链过去）
    var logPath: String?
    /// 失败原因里有「悬空引用」可清时显示「数据修复」快捷入口
    /// （一键打开设置并自动弹清理确认框）。
    var canRepairDangling: Bool = false
    /// 失败原因里有「缺图」时显示「缺图清单」入口（缺图修不了，只能补 ——
    /// 至少给一份完整名单，别让人对着 284 这个数字干瞪眼）。
    var missingImageCount: Int = 0
}

/// 顶部悬浮的结果框：**一条**，新的更新会整体替换。
/// 成功自动消失；失败常驻直到手动关闭 —— 「失败了」不许没人看见。
struct OpsUpdateToastView: View {
    let toast: OpsCloudUpdateToast
    let onDismiss: () -> Void
    /// 导出缺图清单（失败原因里缺图条数 > 0 时才出现）
    let onExportMissing: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(toast.success ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title)
                    .font(.callout.weight(.semibold))
                if let detail = toast.detail {
                    // 变量文案过 opsMarkdown：`Text(变量)` 不解析 Markdown
                    opsMarkdown(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if let logPath = toast.logPath {
                        Button("打开日志") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: logPath)])
                        }
                        .controlSize(.small)
                    }
                    // 缺图**修不了**（图不在这台机器上），但完整名单能给 ——
                    // 门禁日志只显示前几条，运营得拿着名单去 iOS 端 / 图源核对。
                    if toast.missingImageCount > 0 {
                        Button("缺图清单（\(toast.missingImageCount)）") {
                            onExportMissing()
                        }
                        .controlSize(.small)
                    }
                    // 一键数据修复：`SettingsLink` 开设置窗口，同时置一次性指令，
                    // 设置场景收到后自动弹清理的二级确认框（两级都要用户亲手点）。
                    if toast.canRepairDangling {
                        SettingsLink {
                            Label("数据修复", systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .simultaneousGesture(TapGesture().onEnded {
                            OpsSettingsFocus.shared.repairPromptRequested = true
                        })
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(OpsFlowPalette.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }
}
