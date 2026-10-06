//
//  ShopCatalogChartPasteSheet.swift
//  ItemManager
//
//  「识别录入」面板（2026-09-23 需求 M 的「直接粘贴」入口 + 2026-10-01 识别结果板块）。
//
//  用户诉求原文：
//    「增加『直接粘贴』入口：请允许我直接从外部复制整段 标签:值 文本粘贴进来，
//      系统直接识别并按行拆分保存。不要让我在你们这个残缺的输入框里一点点手敲。」
//    「用户提交数据后，系统需根据识别结果给出明确提示，区分『识别成功』与
//      『识别失败』两种状态，尺码表和价格表的识别都要分别提供对应的结果提示。」
//
//  唯一通道 = **粘贴文本识别**（走 `CatalogManualChartText` 整段实时解析）。
//  结论一律由共享包的 `CatalogChartRecognition` 判定并出文案，
//  本文件**不自己拼「识别成功 / 识别失败」**。
//
//  ⚠️ **不要再加「上传图片识别」入口**（2026-09-23 需求一：用户反馈图片识别
//     「频繁报错 + 常驻霸屏」，要求整条移除）。`CatalogChartExtraction` 与它的
//     门禁口径保留在 App 内但**没有界面入口，这是有意为之**，别借它加回来。
//
//  三条硬口径（改动前先读）：
//    1. **预览即落库结果**：预览区消费的就是保存链路那套解析，不是另一份近似实现；
//    2. **失败不写库**：文本通道解析失败时允许用户「仍要填入」，但**只在解析出内容时
//       才覆盖对应输入框**，绝不清空用户手填的内容；
//    3. **两种表各自出提示**：标题、结论文案、引导话术都由 `kind` 派生，不共用一句话。
//

import SwiftUI
import UIKit

/// 粘贴录入的用途（决定标题与示例文案）
enum ShopCatalogChartPasteKind {
    /// 预约价格表（系列编辑页）
    case priceChart
    /// 尺码表（商品深度编辑 / 补录草稿 / 款式录入）
    case sizeChart

    var title: String {
        switch self {
        case .priceChart: return "识别价格表文本"
        case .sizeChart: return "识别尺码表文本"
        }
    }

    /// 与共享包的图表类型一一对应（判定与文案的唯一口径按它分叉）
    var chartKind: CatalogChartKind {
        switch self {
        case .priceChart: return .price
        case .sizeChart: return .size
        }
    }

    var example: String {
        switch self {
        case .priceChart:
            return CatalogChartTemplate.PriceChart.columnsText + "\n"
                + Self.iosRows(CatalogChartTemplate.PriceChart.rowsText)
        case .sizeChart:
            return CatalogChartTemplate.SizeChart.columnsText + "\n"
                + Self.iosRows(CatalogChartTemplate.SizeChart.rowsText)
        }
    }

    /// 共享模板（Mac 语法：`款式 = 值1, 值2`）→ iOS 粘贴示例（`款式:值1,值2`）。
    ///
    /// ⚠️ **两端行语法不同**：iOS 的 `CatalogManualChartText.parseRows` 按**冒号**切，
    /// Mac 的 `OpsChartTextParsing` 按**等号**切。所以示例必须各按各的语法出，
    /// 不能直接把模板贴过来。
    ///
    /// 但**列名与值个数必须同源** —— 否则就会出现
    /// 「iOS 示例显示 4 列、第 2 行只给 3 个值」这种自相矛盾的示范，
    /// 用户把这段贴进 Mac 立刻失败（正是 2026-10-01 报障的形态）。
    /// 所以这里只做「等号→冒号」的等价替换，其余照抄模板。
    private static func iosRows(_ rowsText: String, limit: Int = 3) -> String {
        rowsText
            .split(separator: "\n")
            .prefix(limit)
            .map { $0.replacingOccurrences(of: " = ", with: ":") }
            .joined(separator: "\n")
    }

    /// ⚠️ 示例里**不写「款式 / 尺码」**：它们是行标签列（渲染时占最左边那一列），
    /// 写进列名会被剔除，用户却会照着为它留一个空位 → 列数与值个数对不上。
    /// 口径与 Mac 侧、与 `CatalogChartTextSyntax.labelColumnNames` 一致。
    var columnHint: String {
        switch self {
        case .priceChart:
            return "列名（只写数据列，逗号分隔，如：\(CatalogChartTemplate.PriceChart.columnsText)）"
        case .sizeChart: return "尺码表列名（只写数据列，逗号分隔，如：胸围,衣长,肩宽）"
        }
    }
}

/// 识别录入入口按钮：自带弹窗与状态，放进 Form 行即可。
///
/// 除了按钮本身，它还会在**下方常驻显示识别结论板块**（成功/失败）——
/// 因为这个组件被尺码表与价格表的全部录入入口共用（5 处），
/// 结论挂在组件内部就等于两种表、所有入口都拿到了对应提示，不必逐个改调用点。
///
/// `externalTrigger` 供「解析失败」弹窗里的按钮复用同一个入口
/// （置 true 即打开，组件内部消费后置回 false）。
struct ShopCatalogChartPasteButton: View {
    let kind: ShopCatalogChartPasteKind
    @Binding var columnsText: String
    @Binding var rowsText: String
    @Binding var externalTrigger: Bool

    @State private var showing = false

    init(kind: ShopCatalogChartPasteKind,
         columnsText: Binding<String>,
         rowsText: Binding<String>,
         externalTrigger: Binding<Bool> = .constant(false)) {
        self.kind = kind
        self._columnsText = columnsText
        self._rowsText = rowsText
        self._externalTrigger = externalTrigger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showing = true
            } label: {
                Label("粘贴文本录入（推荐，最准）", systemImage: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .medium))
            }
            .sheet(isPresented: $showing) {
                ShopCatalogChartPasteSheet(kind: kind,
                                           columnsText: $columnsText,
                                           rowsText: $rowsText)
            }
            .onChange(of: externalTrigger) { _, requested in
                guard requested else { return }
                externalTrigger = false
                // 等「解析失败」弹窗收完再拉起 sheet，避免两个 presentation 打架
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    showing = true
                }
            }

            if let recognition {
                CatalogChartRecognitionCard(recognition: recognition)
            }
        }
    }

    /// 当前两个输入框的识别结论。
    ///
    /// 与保存链路**同一套解析**（`parseColumns` / `parseRows` → `normalized`），
    /// 所以卡片上说成功就是真的能存、说失败就是真的存不成形状。
    /// 两个框都空时返回 nil（不显示卡片）——否则一进页面就红一条「识别失败」，
    /// 看起来像出错了。
    private var recognition: CatalogChartRecognition? {
        let hasColumns = !columnsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRows = !rowsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasColumns || hasRows else { return nil }
        let parsed = CatalogManualChartText.normalized(
            columns: CatalogManualChartText.parseColumns(columnsText),
            rows: CatalogManualChartText.parseRows(rowsText))
        return .verdict(kind: kind.chartKind,
                        source: .pastedText,
                        columns: parsed.columns,
                        rows: parsed.rows)
    }
}

struct ShopCatalogChartPasteSheet: View {
    let kind: ShopCatalogChartPasteKind
    @Binding var columnsText: String
    @Binding var rowsText: String
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText = ""
    @State private var pasteboardNote: String?
    @FocusState private var editorFocused: Bool

    /// 实时解析结果：与保存链路同一套口径，预览即落库结果
    private var parsed: CatalogManualChartText.PastedChart {
        CatalogManualChartText.parsePastedText(pastedText)
    }

    /// 当前该展示的结论。空输入 → nil（不显示卡片）。
    private var recognition: CatalogChartRecognition? {
        guard !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .verdict(kind: kind.chartKind,
                        source: .pastedText,
                        columns: parsed.columns,
                        rows: parsed.rows)
    }

    /// 有内容可填才允许确认（与旧版一致：空解析不给填）
    private var canApply: Bool {
        !parsed.columnsText.isEmpty || !parsed.rowsText.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                pasteSection
                outcomeSection
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(canApply && recognition?.isSuccess == false ? "仍要填入" : "识别并填入") {
                        apply()
                    }
                    .disabled(!canApply)
                }
            }
            .onAppear {
                editorFocused = true
                if pastedText.isEmpty, let clipboard = UIPasteboard.general.string,
                   !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pasteboardNote = "剪贴板里已有内容，点上方「从剪贴板填入」即可贴入"
                }
            }
        }
    }

    // MARK: ① 粘贴区域

    private var pasteSection: some View {
        Section {
            Button {
                fillFromPasteboard()
            } label: {
                Label("从剪贴板填入", systemImage: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedText)
                    .frame(minHeight: 150)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($editorFocused)
                if pastedText.isEmpty {
                    Text("把整段表格文本粘到这里…\n\n\(kind.example)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            if let pasteboardNote {
                Text(pasteboardNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if !pastedText.isEmpty {
                Button("清空", role: .destructive) {
                    pastedText = ""
                    pasteboardNote = nil
                }
                .font(.system(size: 13))
            }
        } header: {
            Text("粘贴区域")
        } footer: {
            Text("支持三种来源：①「列名行 + 每行 标签:值,值」纯文本；② Markdown 表格；③ 从 Excel / Numbers 直接复制（制表符分隔）。中文逗号、全角冒号、行首编号符号都会自动处理；表标题、店铺名等非表格文字会被忽略。")
                .font(.system(size: 11))
        }
    }

    // MARK: ② 识别结果（唯一出结论的地方）

    private var outcomeSection: some View {
        Section {
            if let recognition {
                CatalogChartRecognitionCard(recognition: recognition)
            } else {
                Text("还没有可识别的表格内容")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("识别结果（" + kind.chartKind.displayName + "）")
        } footer: {
            Text("结论与保存用的是同一套判定：预览即落库结果。识别失败时下方输入框仍可继续手工修正。")
                .font(.system(size: 11))
        }
    }

    // MARK: 动作

    private func fillFromPasteboard() {
        guard let clipboard = UIPasteboard.general.string,
              !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pasteboardNote = "剪贴板里没有文本内容"
            return
        }
        pastedText = clipboard
        pasteboardNote = nil
    }

    /// 回填两个输入框：写入「列名行原文 + 逐行 标签:值」，与预览完全一致。
    ///
    /// ⚠️ **只在解析出内容时才覆盖对应输入框**。原实现是无条件赋值，
    /// 于是「未识别到列名行」这条路径会把用户已经手填好的列名**静默清空** ——
    /// 界面上一句提示都没有，用户只会觉得「点了识别，列名没了」。
    private func apply() {
        let chart = parsed
        if !chart.columnsText.isEmpty { columnsText = chart.columnsText }
        if !chart.rowsText.isEmpty { rowsText = chart.rowsText }
        dismiss()
    }
}
