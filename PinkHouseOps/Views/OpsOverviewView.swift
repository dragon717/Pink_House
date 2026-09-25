//
//  OpsOverviewView.swift
//  PinkHouseOps
//
//  概览页：导入入口 + 当前草稿统计 + 「接下来做什么」。
//
//  导入走系统 `.fileImporter`（Apple 原生支持多选：
//  `fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)`），
//  拿到的 URL 在 `OpsWorkspace` 里立刻 startAccessingSecurityScopedResource 并复制进
//  staging —— 只保存外部路径的话，运营换了机器/拔了硬盘就再也读不到那些图。
//

import SwiftUI
import UniformTypeIdentifiers

struct OpsOverviewView: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var showsCatalogImporter = false
    @State private var showsImageImporter = false
    @State private var draftTitle: String = ""

    /// 允许导入的图片类型，与协议白名单同源（`ShopCatalogSyncProtocol.mediaMimeAllowlist`）。
    /// 不放宽到 `.image`：客户端解不出来的类型不该走到发布这一步。
    private var importableImageTypes: [UTType] {
        var types: [UTType] = [.jpeg, .png, .gif]
        if let webp = UTType("org.webmproject.webp") { types.append(webp) }
        if let heic = UTType("public.heic") { types.append(heic) }
        return types
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                draftCard
                importCard
                statisticsCard
                nextStepsCard
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(
            isPresented: $showsCatalogImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleCatalogImport(result)
        }
        .fileImporter(
            isPresented: $showsImageImporter,
            allowedContentTypes: importableImageTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                workspace.importImages(from: urls)
            case .failure(let error):
                workspace.reportFailure("选择图片失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: 草稿

    private var draftCard: some View {
        OpsCard(title: "当前草稿", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("标题")
                        .frame(width: 44, alignment: .leading)
                        .foregroundStyle(.secondary)
                    TextField("例如：2026-10 上新", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { applyTitle() }
                    Button("改名") { applyTitle() }
                        .disabled(draftTitle == workspace.draft?.title)
                }
                if let draft = workspace.draft {
                    LabeledContent("草稿 ID", value: draft.id)
                    LabeledContent("最近保存", value: draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Text("所有编辑都只在**本机草稿**里，不会上传任何云端；"
                     + "要发布必须显式导出「待发布包」并交给受控发布流水线。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { draftTitle = workspace.draft?.title ?? "" }
    }

    private func applyTitle() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let draft = workspace.draft else { return }
        draft.title = trimmed
        workspace.saveDraft()
    }

    // MARK: 导入

    private var importCard: some View {
        OpsCard(title: "导入", systemImage: "square.and.arrow.down.on.square") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        showsCatalogImporter = true
                    } label: {
                        Label("导入目录 JSON", systemImage: "doc.badge.plus")
                    }
                    Button {
                        showsImageImporter = true
                    } label: {
                        Label("导入商品图", systemImage: "photo.badge.plus")
                    }
                }
                Text("· 导入目录 JSON 会**整体替换**当前草稿内容（先保存再导入）。\n"
                     + "· 图片会立刻按「长边 1600」重新编码、算出内容摘要（mediaKey）"
                     + "并复制进本机暂存目录；文件一旦导入就与原始位置无关。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func handleCatalogImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            workspace.importCatalog(from: url)
        case .failure(let error):
            workspace.reportFailure("选择文件失败：\(error.localizedDescription)")
        }
    }

    // MARK: 统计

    private var statisticsCard: some View {
        OpsCard(title: "内容统计", systemImage: "chart.bar") {
            let progress = workspace.mediaProgress
            VStack(alignment: .leading, spacing: 10) {
                let rows: [(String, Int)] = [
                    ("店家", workspace.catalog.shops.count),
                    ("系列", workspace.catalog.series.count),
                    ("商品", workspace.catalog.products.count),
                    ("规格", workspace.catalog.variants.count),
                    ("尺码表", workspace.catalog.sizeCharts.count),
                    ("销售记录", workspace.catalog.saleEvents.count),
                    ("图片资源", workspace.catalog.assets.count),
                    ("已删除墓碑", workspace.catalog.removedProductIDs.count),
                ]
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                    ForEach(rows, id: \.0) { row in
                        VStack(spacing: 2) {
                            Text("\(row.1)").font(.title3.weight(.semibold)).monospacedDigit()
                            Text(row.0).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Divider()
                LabeledContent("图片任务", value: mediaSummary(progress))
                if progress.hasFailures {
                    Text("有任务处于「失败」：要么人工处理，要么它根本不该进这次发布。")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func mediaSummary(_ progress: MediaUploadJobMachine.Progress) -> String {
        "共 \(progress.total)　已上传 \(progress.verified)　待处理 \(progress.pending)　失败 \(progress.failed)"
    }

    // MARK: 下一步

    private var nextStepsCard: some View {
        OpsCard(title: "接下来做什么", systemImage: "arrow.turn.down.right") {
            VStack(alignment: .leading, spacing: 8) {
                StepRow(index: 1, text: "在「目录编辑」里补齐店家 / 系列 / 商品，并把商品图绑到商品上。")
                StepRow(index: 2, text: "在「图片与上传任务」里确认图片都进了暂存目录（状态为「待上传」）。")
                StepRow(index: 3, text: "在「发布前校验」里跑一次门禁：**缺图 / 结构问题必须清零**。")
                StepRow(index: 4, text: "回到「发布前校验」导出「待发布包」（tar），交给受控发布流水线上传。")
                Text("本工具不直接写公共库：发布由 tools/time_hall/publication 的发布器完成，"
                     + "私钥只存在于 Keychain，不进 App、不进日志。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 通用小组件

struct OpsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }
}

private struct StepRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.16), in: Circle())
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
