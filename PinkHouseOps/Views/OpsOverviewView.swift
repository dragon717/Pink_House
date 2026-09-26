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
                pendingCard
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

    // MARK: 待处理事项

    /// 工作台的第一张卡必须是「现在有什么没处理完」。
    ///
    /// 顺序不是按模块排的，是按**后果的严重程度**排的：
    ///   1. 结果待确认的发布 —— 不处理就可能重复发布（最贵）；
    ///   2. 只读隔离的草稿 —— 继续在里面填内容会白填；
    ///   3. 桥接器不可用 —— 发布这一整段根本走不通；
    ///   4. 校验阻断 / 过期；
    ///   5. 图片任务失败；
    ///   6. 未保存的修改。
    private var pendingCard: some View {
        let center = workspace.publishCenter
        let blockers = center.submissionBlockers
        let awaiting = center.jobsNeedingAttention
        let failedMedia = workspace.mediaProgress.failed

        var items: [(String, String, Bool)] = []
        if let awaitingQuery = center.jobs.first(where: { $0.state.requiresResultQuery }) {
            items.append(("结果待确认的发布（releaseSeq \(awaitingQuery.releaseSeq)）",
                          "**先去发布中心点「查询结果」**：切发布头之后结果不明时，"
                          + "重发会造成重复发布，甚至用旧内容回写已经前进的线上版本。",
                          true))
        }
        if workspace.isCorrupted {
            items.append(("草稿处于只读隔离",
                          "当前展示的是空目录，别在里面继续填：先「另存为新草稿并继续」。",
                          true))
        }
        if !center.bridgeProblems.isEmpty {
            items.append(("发布桥接不可用（\(center.bridgeProblems.count) 条）",
                          center.bridgeProblems.first ?? "", true))
        }
        if workspace.isReviewStale {
            items.append(("校验结果已过期",
                          "这份结果是第 \(workspace.reviewedRevision ?? 0) 版做的，"
                          + "当前是第 \(workspace.currentRevision) 版。导出/发布前要重新校验。",
                          false))
        } else if workspace.review?.isBlocked == true {
            items.append(("校验未通过（\(workspace.review?.blockingIssues.count ?? 0) 条阻断）",
                          "缺图的引用会被发布门禁拦下：到「发布中心」看逐条明细。", false))
        }
        if failedMedia > 0 {
            items.append(("有 \(failedMedia) 个图片任务处于「失败」",
                          "要么人工处理，要么它根本不该进这次发布。见「素材库」。", false))
        }
        if workspace.hasUnsavedChanges {
            items.append(("草稿有未保存的修改",
                          "发布的是**已保存**的内容：发布中心会因此拦住提交。", false))
        }
        if items.isEmpty, !blockers.isEmpty {
            items.append(("发布前置条件还差 \(blockers.count) 项",
                          blockers.first ?? "", false))
        }

        return OpsCard(title: items.isEmpty ? "现在没有待处理事项" : "待处理事项（\(items.count)）",
                       systemImage: items.isEmpty ? "checkmark.circle" : "bell.badge") {
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    Text("草稿、素材、校验与发布都没有卡住的事情。可以走「导出待发布包」或直接去发布中心。")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.2
                                  ? "exclamationmark.triangle.fill" : "circle.fill")
                                .font(.system(size: item.2 ? 13 : 6))
                                .foregroundStyle(item.2 ? Color.red : Color.orange)
                                .padding(.top, item.2 ? 2 : 6)
                            VStack(alignment: .leading, spacing: 2) {
                                opsMarkdown(item.0).font(.callout.weight(.medium))
                                if !item.1.isEmpty {
                                    opsMarkdown(item.1)
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if awaiting.isEmpty == false {
                    OpsFootnote(text: "发布台账里有 \(awaiting.count) 条待处理的任务 —— "
                                + "侧栏「发布中心」上有角标。")
                }
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
                    LabeledContent("编辑版本", value: "第 \(draft.currentRevision) 版"
                                   + (workspace.hasUnsavedChanges ? "（有未保存修改）" : "（已保存）"))
                    LabeledContent("最近保存",
                                   value: draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                // ⚠️ 这里**必须**用 `opsMarkdown`：`Text("a" + "b")` 的拼接结果是一个
                // **String 变量**，走的是逐字初始化器 → 不解析 Markdown → `**本机草稿**`
                // 会带着星号显示。只有**单个**字面量才自动走 LocalizedStringKey。
                opsMarkdown("所有编辑都只在**本机草稿**里，不会上传任何云端；"
                     + "要发布必须显式导出「待发布包」并交给受控发布流水线。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { draftTitle = workspace.draft?.title ?? "" }
    }

    private func applyTitle() {
        // 走统一入口：改名也是内容变更，要带版本与失败反馈（R05）。
        // 调用方不需要结果 —— 失败时错误已经进了全局 banner 的唯一反馈通道。
        workspace.renameDraft(title: draftTitle)
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
                // 同上：拼接 = String 变量，`\n` 拼起来的多行尤其要过 `opsMarkdown`
                // （它带了 `inlineOnlyPreservingWhitespace`，换行才不会被折成空格）。
                opsMarkdown("· 导入目录 JSON 会**整体替换**当前草稿内容（先保存再导入）。\n"
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
                StepRow(index: 1, text: "「店家与系列」：建店家 → 建系列（档期、发售阶段、系列价格表都在这一处配）。")
                StepRow(index: 2, text: "「商品管理」：逐商品补规格、尺码表、销售记录与价格修正，并把商品图绑上。")
                StepRow(index: 3, text: "「素材库」：确认每张图都进了暂存目录，且没有被误删的引用。")
                StepRow(index: 4, text: "「发布中心」：读取线上基线 → 确认发布号 → 冻结 → 提交 → **看回执**。")
                StepRow(index: 5, text: "「本地预览」：发布前自己按 店家 › 系列 › 商品 看一遍结构与价格。")
                OpsFootnote(text: "本工具不直接写公共库：发布由 tools/time_hall/publication 的受控发布器完成，"
                            + "签名私钥只在 Keychain，不进 App、不进日志。"
                            + "发布中心也是调它 —— 不是自己再实现一遍。")
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
            // `text` 是传进来的**变量**（导览文案里就有 `**看回执**`）→ 必须过 opsMarkdown
            opsMarkdown(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
