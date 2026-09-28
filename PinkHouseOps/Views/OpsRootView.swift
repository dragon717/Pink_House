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

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
                workspace = OpsWorkspace(context: modelContext)
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
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seriesEntry: return "系列上新"
        case .catalog: return "店家与系列"
        case .products: return "商品管理"
        case .preview: return "本地预览"
        }
    }

    var symbolName: String {
        switch self {
        case .seriesEntry: return "sparkles.rectangle.stack"
        case .catalog: return "storefront"
        case .products: return "tshirt"
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

    init(workspace: OpsWorkspace, initialSection: OpsSection = .seriesEntry) {
        self.workspace = workspace
        _section = State(initialValue: initialSection)
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
        .toolbar {
            // 「云端同步」是**唯一**的上下云入口（读线上基线 / 拉回目录 / 发布），
            // 之所以放在工具栏而不是新增分区：发布中心区已在 09-27 按需求移除，
            // 但「Mac 既不下云也不上云」这个洞必须有人能走通。
            ToolbarItem(placement: .primaryAction) {
                Button {
                    cloudSync.showsSheet = true
                } label: {
                    Label("云端同步", systemImage: "cloud")
                }
                .help("读取线上基线 / 从线上拉回目录 / 构建待发布包并发布（经受控发布器）")
            }
        }
        .sheet(isPresented: $cloudSync.showsSheet) {
            OpsCloudSyncSheet(workspace: workspace)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .seriesEntry:
            OpsSeriesWizardView(workspace: workspace)
        case .catalog:
            OpsCatalogEditorView(workspace: workspace)
        case .products:
            OpsProductsView(workspace: workspace)
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
