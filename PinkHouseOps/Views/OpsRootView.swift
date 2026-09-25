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

import SwiftData
import SwiftUI

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

enum OpsSection: String, CaseIterable, Identifiable {
    case overview
    case catalog
    case media
    case validation
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .catalog: return "目录编辑"
        case .media: return "图片与上传任务"
        case .validation: return "发布前校验"
        case .preview: return "本地预览"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .catalog: return "list.bullet.rectangle"
        case .media: return "photo.on.rectangle.angled"
        case .validation: return "checkmark.shield"
        case .preview: return "eye"
        }
    }
}

// MARK: - 主框架

struct OpsMainView: View {
    @ObservedObject var workspace: OpsWorkspace
    @State private var section: OpsSection = .overview

    var body: some View {
        NavigationSplitView {
            List(OpsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbolName).tag(item)
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
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview:
            OpsOverviewView(workspace: workspace)
        case .catalog:
            OpsCatalogEditorView(workspace: workspace)
        case .media:
            OpsMediaLibraryView(workspace: workspace)
        case .validation:
            OpsValidationView(workspace: workspace)
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
            Text(workspace.draft?.title ?? "（无草稿）")
                .font(.callout.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 10) {
                CountChip(label: "店家", value: workspace.catalog.shops.count)
                CountChip(label: "系列", value: workspace.catalog.series.count)
                CountChip(label: "商品", value: workspace.catalog.products.count)
                CountChip(label: "图片", value: workspace.catalog.assets.count)
            }
            Button {
                workspace.saveDraft()
            } label: {
                Label("保存草稿", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(workspace.draft == nil)
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
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 状态条（唯一的反馈通道）

struct OpsStatusBanner: View {
    @ObservedObject var workspace: OpsWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = workspace.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("知道了") { workspace.clearError() }
                        .buttonStyle(.link)
                }
            } else if let status = workspace.statusText {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(status).font(.callout).lineLimit(2)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("就绪。所有编辑只在本机草稿里，直到导出待发布包。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(workspace.lastError == nil ? AnyShapeStyle(.bar) : AnyShapeStyle(Color.orange.opacity(0.12)))
    }
}
