//
//  CatalogChartRecognitionCard.swift
//  ItemManager
//
//  尺码表 / 预约价格表「识别结果」的**可视化板块**（2026-10-01 需求）。
//
//  ## 需求原文
//    「该识别功能最终需要在手机端以可视化的板块形式展示出来，请确保移动端的
//      显示效果完整、适配良好。」
//
//  ## 这个视图只做一件事：把 `CatalogChartRecognition` 画出来
//
//  成功/失败的**判定与文案**全部来自共享包（`CatalogChartRecognition`），
//  本文件里**没有任何 `if 识别成功` 式的业务判断**——只有「成功画绿的、失败画红的」
//  这类纯呈现分支。两张表的文案不在这里分叉，所以不可能各写各的。
//
//  ## 移动端适配的几条硬要求（改动前先读）
//
//  1. **不设固定宽度**：`frame(maxWidth: .infinity)`，iPad 分栏、iPhone 竖屏、
//     Dynamic Type 放大后都不许出现横向截断；
//  2. **长表靠横向滚动，不靠压缩**：价格表/尺码表的列名可能很长
//     （「后裙长（含肩带可调节）」），压着列宽会把表挤成乱码。所以预览区是
//     `ScrollView(.horizontal)`，行标签列固定宽度常驻在左侧；
//  3. **文字一律换行不截断**：结论与引导话术 `fixedSize(horizontal: false, vertical: true)`，
//     中文长句在窄屏上必须能折行显示完整；
//  4. **表面色不许写死**：底色用状态色 `opacity` 叠在容器原有背景上，
//     深色模式自动跟随（仓库红线：视图层不许拿 `Color.white` / 固定 hex 当表面色）；
//  5. **字体用语义字号**（`.subheadline` / `.footnote` / `.caption`），不用固定 pt，
//     否则「设置 → 显示与亮度 → 文字大小」调到最大就废了。
//
//  ## ⚠️ 为什么表格本体要单独拆成 `CatalogChartTablePreview`
//
//  `ImageRenderer`（离屏快照唯一手段）**不绘制 `ScrollView` 的内容** ——
//  画布只保留它占的高度，内容区一片空白。整卡快照里那看起来就是
//  「表格没画出来」，而真机上其实是好的。所以：
//    · 线上渲染路径**不变**，卡片仍然用 `ScrollView(.horizontal)` 兜住长表；
//    · 表格本体抽成**不含滚动容器**的独立 View，快照直接渲染它，
//      才能真正核对「列名 / 数值 / 对齐」画对了没有。
//  工程里 `MidsummerYearRail` / `MidsummerYearRailContent` 就是同一个拆法。
//  （回归锁：`ItemManagerTests/CatalogChartRecognitionCardSnapshotTests.swift`）
//

import Foundation
import SwiftUI

extension CatalogChartRecognition {

    /// 状态色：成功绿 / 失败红。
    ///
    /// **只此一处** —— 卡片、表格预览以及将来任何消费它的视图都读这个，
    /// 免得出现「这边绿那边红」。判定本身（`isSuccess`）来自共享包，这里只负责配色。
    var statusTint: Color { isSuccess ? .green : .red }
}

struct CatalogChartRecognitionCard: View {

    let recognition: CatalogChartRecognition

    /// 预览最多渲染多少行（超出只给「共 N 行」，避免一屏被一张长表吃光）
    var previewRowLimit: Int = 8

    /// 是否渲染识别到的表格预览（成功且确有内容时才可能显示）
    var showsTablePreview: Bool = true

    init(recognition: CatalogChartRecognition,
         previewRowLimit: Int = 8,
         showsTablePreview: Bool = true) {
        self.recognition = recognition
        self.previewRowLimit = previewRowLimit
        self.showsTablePreview = showsTablePreview
    }

    // MARK: 状态色

    /// 成功绿 / 失败红。口径见 `CatalogChartRecognition.statusTint`。
    private var accent: Color { recognition.statusTint }

    private var statusIcon: String {
        recognition.isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var statusBadgeText: String {
        recognition.isSuccess ? "识别成功" : "识别失败"
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if recognition.isSuccess {
                if showsTablePreview, recognition.hasRecognizedContent {
                    tablePreview
                }
            } else if let guidance = recognition.guidance {
                guidanceRow(guidance)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        }
        // 「移动端显示效果」的机器可验证锚点：交互验收据此断言板块真的画出来了，
        // 并读出它给的是「识别成功」还是「识别失败」。标识是**稳定契约**，别随手改。
        .accessibilityIdentifier(Self.rootIdentifier)
    }

    // MARK: 结论头

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.subheadline)
                    .foregroundStyle(accent)
                Self.emphasisText(recognition.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(statusBadgeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent, in: Capsule())
            }
            Self.emphasisText(recognition.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(recognition.summaryLine))
        // VoiceOver 只读 summaryLine（标题 + 徽标 + 依据一次读完，不重复）；
        // 标识给交互验收用，`label` 里就带着「识别成功 / 识别失败」，不需要另设状态字段。
        .accessibilityIdentifier(Self.headlineIdentifier)
    }

    // MARK: 失败引导

    private func guidanceRow(_ guidance: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.caption)
                .foregroundStyle(accent)
                .padding(.top, 1)
            Self.emphasisText(guidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 共享文案 → 富文本

    /// 共享包那几句话（`headline` / `detail` / `guidance`）可能带 `**强调**`，
    /// 而 **`Text(变量)` 不解析 Markdown** —— `Text("a"+"b")` 同样不解析。
    /// 不过这道转换，`**` 会在界面上逐字显示成星号。
    ///
    /// ⚠️ 两个参数都不能去：`.inlineOnlyPreservingWhitespace` 保证
    /// 「只认行内语法」+「原样保留空白」。与 Mac 端 `opsMarkdown`、
    /// 以及本仓库既有的 `ShopCatalogOpsUploadSection.emphasisText` 同一口径。
    ///
    /// 返回 `AttributedString`（而不是 `Text`）是为了能被单测断言：
    /// `String(CatalogChartRecognitionCard.emphasis("**行标签列**、不占名额").characters)`
    /// 必须是 `行标签列、不占名额`。
    nonisolated static func emphasis(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private static func emphasisText(_ text: String) -> Text {
        Text(emphasis(text))
    }

    // MARK: 识别到的表格预览

    private var tablePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 长表交给横向滚动；表本体见 `CatalogChartTablePreview`
            ScrollView(.horizontal, showsIndicators: false) {
                CatalogChartTablePreview(recognition: recognition,
                                         previewRowLimit: previewRowLimit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(rowCountNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var rowCountNote: String {
        let total = recognition.recognizedRows.count
        let shown = min(total, max(previewRowLimit, 1))
        return shown < total ? "仅预览前 \(shown) 行，共 \(total) 行" : "共 \(total) 行"
    }

    // MARK: 无障碍 / 交互验收标识（稳定契约）

    /// 板块根容器
    static let rootIdentifier = "shopCatalog.chartRecognition.card"
    /// 结论头：`label` == `recognition.summaryLine`（含「…识别成功 / …识别失败」与依据）
    static let headlineIdentifier = "shopCatalog.chartRecognition.headline"
}

// MARK: - 表格本体（**不含滚动容器**，因此可被快照渲染）

/// 识别到的表格：列名行 + 数据行。
///
/// 与 `CatalogChartRecognitionCard` 共用同一份状态色与同一份字号口径；
/// 拆出来的唯一目的是让 `ImageRenderer` 能画到它（原因见文件头）。
/// **不要**在这里加 `ScrollView` —— 加了就又拍不出来了。
struct CatalogChartTablePreview: View {

    let recognition: CatalogChartRecognition
    var previewRowLimit: Int = 8

    private var accent: Color { recognition.statusTint }

    /// 行标签列固定宽度。
    ///
    /// **必须固定**：各行标签宽度不同的话，后面的值列就跟着错位了。
    /// 取值覆盖常见款式名（「大蝴蝶结背心裙」7 字 ≈ 84pt）让它们单行显示；
    /// ⚠️ **再长的标签必须换行显示完整，绝不截断** —— 价格表的行标签就是**款式名**，
    /// 那是这一行最关键的信息（尺码表的 S/M/L 才短）。这是与商品详情页
    /// `ShopCatalogProductDetailView.structuredTable` 一致的口径（那边也是固定宽 + 换行）。
    /// 回归锁：`testLongRowLabelWrapsInsteadOfTruncating`。
    private static let labelColumnWidth: CGFloat = 88
    /// 值列固定宽度：保证上下行数字对齐（**值本身永远单行**，数字换行没有意义）
    private static let valueColumnWidth: CGFloat = 76

    private var columns: [String] { recognition.recognizedColumns }

    private var previewRows: [CatalogSizeRow] {
        Array(recognition.recognizedRows.prefix(max(previewRowLimit, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerCells
            ForEach(Array(previewRows.enumerated()), id: \.offset) { _, row in
                valueCells(row)
            }
        }
    }

    /// 表头行：左上角留空（行标签列），其余是列名
    private var headerCells: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("")
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                // 列名**换行不截断**：「后裙长（含肩带可调节）」这类长列名必须看全，
                // 否则用户根本认不出这一列是什么（截断成「后裙长（含肩…」等于没写）。
                Text(column)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Self.valueColumnWidth, alignment: .leading)
            }
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(0.25))
                .frame(height: 0.5)
        }
    }

    /// 数据行：行标签固定宽度常驻，值按列对齐
    private func valueCells(_ row: CatalogSizeRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // 行标签**换行不截断**（口径见 `labelColumnWidth`）
            Text(row.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.offset) { index, _ in
                Text(value(of: row, at: index))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(value(of: row, at: index) == "—" ? .tertiary : .secondary)
                    .lineLimit(1)
                    .frame(width: Self.valueColumnWidth, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private func value(of row: CatalogSizeRow, at index: Int) -> String {
        guard row.values.indices.contains(index), let value = row.values[index] else { return "—" }
        return value
    }
}

// MARK: - 便捷封装

extension CatalogChartRecognitionCard {

    /// 「提交后常驻显示」的包装：没识别过（`.idle`）或输入为空时不占位。
    ///
    /// - Parameters:
    ///   - recognition: 结论；nil = 还没识别过
    ///   - isInputEmpty: 两张输入框（列名 / 行）是否都为空 —— 空输入不显示失败卡片，
    ///     否则一进页面就红一条「识别失败」，看起来像出错了。
    struct Conditional: View {
        let recognition: CatalogChartRecognition?
        let isInputEmpty: Bool
        var previewRowLimit: Int = 8

        var body: some View {
            if let recognition, !isInputEmpty {
                CatalogChartRecognitionCard(recognition: recognition,
                                            previewRowLimit: previewRowLimit)
            }
        }
    }
}
