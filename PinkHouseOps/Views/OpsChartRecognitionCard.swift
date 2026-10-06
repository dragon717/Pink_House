//
//  OpsChartRecognitionCard.swift
//  PinkHouseOps
//
//  尺码表 / 预约价格表「识别结果」的**可视化板块**（Mac 侧，2026-10-01 需求）。
//
//  ## 需求原文
//    「用户提交数据后，系统需根据识别结果给出明确提示，区分『识别成功』与
//      『识别失败』两种状态，尺码表和价格表的识别都要分别提供对应的结果提示。」
//
//  ## 这个视图只做一件事：把 `CatalogChartRecognition` 画出来
//
//  成功/失败的**判定与文案**全部来自共享包（`CatalogChartRecognition`），
//  本文件里**没有任何 `if 识别成功` 式的业务判断**——只有「成功画绿的、
//  失败画橙的」这类纯呈现分支。两张表的文案不在这里分叉，所以不可能各写各的。
//
//  ## 主题跟随（仓库铁律）
//
//  表面色只许用 `OpsFlowPalette` 的 token（全是动态 NSColor，浅色/深色各一份）：
//  成功用 `tileMint` + `okGreen`，失败用 `tileRed` + `warnOrange`。
//  **不许拿 `Color.white` / 固定 hex 当表面色** —— 深色模式会直接白板。
//
//  ## 变量文案一律过 `opsMarkdown`
//
//  `detail` / `guidance` 都是**变量**，SwiftUI 的 `Text(变量)` 不解析 Markdown；
//  共享文案哪天带了 `**强调**`，不过 `opsMarkdown` 就会把星号逐字显示出来。
//

import SwiftUI

struct OpsChartRecognitionCard: View {

    let recognition: CatalogChartRecognition

    /// 预览最多渲染多少行（超出只给「共 N 行」）
    var previewRowLimit: Int = 8

    init(recognition: CatalogChartRecognition, previewRowLimit: Int = 8) {
        self.recognition = recognition
        self.previewRowLimit = previewRowLimit
    }

    // MARK: 状态色（只此一处决定颜色）

    private var accent: Color {
        recognition.isSuccess ? OpsFlowPalette.okGreen : OpsFlowPalette.warnOrange
    }

    private var surface: Color {
        recognition.isSuccess ? OpsFlowPalette.tileMint : OpsFlowPalette.tileRed
    }

    private var statusIcon: String {
        recognition.isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var statusBadgeText: String {
        recognition.isSuccess ? "识别成功" : "识别失败"
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if recognition.isSuccess {
                if recognition.hasRecognizedContent { preview }
            } else if let guidance = recognition.guidance {
                guidanceRow(guidance)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(accent)
                opsMarkdown(recognition.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OpsFlowPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(statusBadgeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(accent, in: Capsule())
            }
            opsMarkdown(recognition.detail)
                .font(.caption)
                .foregroundStyle(OpsFlowPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(recognition.summaryLine))
    }

    private func guidanceRow(_ guidance: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lightbulb")
                .font(.caption2)
                .foregroundStyle(accent)
                .padding(.top, 1)
            opsMarkdown(guidance)
                .font(.caption)
                .foregroundStyle(OpsFlowPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 识别到的表格预览

    private var columns: [String] { recognition.recognizedColumns }

    private var previewRows: [CatalogSizeRow] {
        Array(recognition.recognizedRows.prefix(max(previewRowLimit, 1)))
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerCells
                    ForEach(Array(previewRows.enumerated()), id: \.offset) { _, row in
                        valueCells(row)
                    }
                }
            }
            // 横向滚动：列名可能很长（「后裙长（含肩带可调节）」），
            // 压着列宽会把整张表挤到读不出来。
            Text(previewRows.count < recognition.recognizedRows.count
                 ? "仅预览前 \(previewRows.count) 行，共 \(recognition.recognizedRows.count) 行"
                 : "共 \(recognition.recognizedRows.count) 行")
                .font(.caption2)
                .foregroundStyle(OpsFlowPalette.textSecondary)
        }
    }

    private var headerCells: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("")
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                // 列名是**数据**：显式 verbatim，绝不解析 Markdown
                //（`A_B` 会被吃成斜体、`*` 会变粗体 —— 那是改坏数据）
                // 列名**换行不截断**（口径见 `labelColumnWidth`）；`.help` 保留，
                // 列名极长折到 3 行以上时悬停仍能一行看全。
                Text(verbatim: column)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(OpsFlowPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Self.valueColumnWidth, alignment: .leading)
                    .help(column)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(0.25))
                .frame(height: 0.5)
        }
    }

    private func valueCells(_ row: CatalogSizeRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // 行标签同样按数据逐字渲染（「A_B」这类尺码标签不许被 Markdown 改形），
            // 且**换行不截断** —— 价格表的行标签就是**款式名**，截成「大蝴蝶结…」
            // 等于把这一行最关键的信息吃了（这里原先 `lineLimit(1)` 还没有 `.help` 兜底）。
            Text(verbatim: row.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(OpsFlowPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.offset) { index, _ in
                Text(verbatim: value(of: row, at: index))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(OpsFlowPalette.textSecondary)
                    .lineLimit(1)
                    .frame(width: Self.valueColumnWidth, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
    }

    private func value(of row: CatalogSizeRow, at index: Int) -> String {
        guard row.values.indices.contains(index), let value = row.values[index] else { return "—" }
        return value
    }

    // MARK: 布局常量

    /// 行标签列固定宽度（**必须固定**：各行宽度不同会让后面的值列错位）。
    /// 取值覆盖常见款式名（「大蝴蝶结背心裙」7 字 ≈ 84pt）使其单行显示；
    /// **再长的标签换行显示完整，绝不截断**（口径与 iOS 侧 `CatalogChartTablePreview` 一致）。
    private static let labelColumnWidth: CGFloat = 88
    /// 值列固定宽度（**值本身永远单行**，数字换行没有意义）
    private static let valueColumnWidth: CGFloat = 108
}

// MARK: - 便捷封装

/// 「提交后常驻显示」的包装：没内容时不占位。
///
/// 两个输入框都空 → 不显示。否则一进页面就红一条「识别失败」，
/// 用户会以为出错了（其实只是还没填）。
struct OpsChartRecognitionBlock: View {
    let recognition: CatalogChartRecognition?
    /// 两个输入框（列名 / 行）是否都为空
    let isInputEmpty: Bool
    var previewRowLimit: Int = 8

    var body: some View {
        if let recognition, !isInputEmpty {
            OpsChartRecognitionCard(recognition: recognition,
                                    previewRowLimit: previewRowLimit)
        }
    }
}
