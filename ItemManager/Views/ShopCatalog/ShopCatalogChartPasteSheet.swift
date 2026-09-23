//
//  ShopCatalogChartPasteSheet.swift
//  ItemManager
//
//  「粘贴文本录入」入口（2026-09-23 需求 M）。
//
//  用户诉求原文：
//    「增加『直接粘贴』入口：请允许我直接从外部复制整段 标签:值 文本粘贴进来，
//      系统直接识别并按行拆分保存。不要让我在你们这个残缺的输入框里一点点手敲。」
//
//  交互口径：
//    · 整段丢进来（含列名行 / Markdown 表格 / Excel 制表符都行），实时解析；
//    · 预览区展示**落库后**的列与行（与保存链路同一套解析，预览即结果）；
//    · 确认后回填「列名」「行」两个输入框，用户仍可在原页面继续微调。
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
        case .priceChart: return "粘贴价格表文本"
        case .sizeChart: return "粘贴尺码表文本"
        }
    }

    var example: String {
        switch self {
        case .priceChart:
            return """
            款式,预约价,定金,尾款,现货价
            大蝴蝶结背心裙:318,91,227,368
            蝴蝶结半裙:268,80,188
            """
        case .sizeChart:
            return """
            尺码,前裙长,胸围,推荐胸围
            S:110,96,86-92
            M:114,102,92-98
            """
        }
    }

    var columnHint: String {
        switch self {
        case .priceChart: return "列名（逗号分隔，如：款式,预约价,定金,尾款）"
        case .sizeChart: return "尺码表列名（逗号分隔，如：尺码,胸围,衣长）"
        }
    }
}

/// 「粘贴文本录入」入口按钮：自带弹窗与状态，放进 Form 行即可。
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
        Button {
            showing = true
        } label: {
            Label("粘贴文本录入（推荐，最准）", systemImage: "doc.on.clipboard")
                .font(.system(size: 13, weight: .medium))
        }
        .sheet(isPresented: $showing) {
            ShopCatalogChartPasteSheet(kind: kind, columnsText: $columnsText, rowsText: $rowsText)
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        fillFromPasteboard()
                    } label: {
                        Label("从剪贴板填入", systemImage: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .medium))
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $pastedText)
                            .frame(minHeight: 170)
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

                Section {
                    if parsed.isEmpty {
                        Text("还没有可识别的表格内容")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        if parsed.columns.isEmpty {
                            Text("未识别到列名行，将按你填写的列名对照保存")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        } else {
                            Text("列名：\(parsed.columns.joined(separator: " / "))")
                                .font(.system(size: 12, weight: .medium))
                        }
                        ForEach(Array(parsed.rows.prefix(30).enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 8) {
                                Text(row.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 118, alignment: .leading)
                                Text(row.values.map { $0 ?? "—" }.joined(separator: "  ·  "))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if parsed.rows.count > 30 {
                            Text("…共 \(parsed.rows.count) 行")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("识别预览（确认后即为保存内容）")
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("识别并填入") { apply() }
                        .disabled(parsed.isEmpty)
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

    private func fillFromPasteboard() {
        guard let clipboard = UIPasteboard.general.string,
              !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pasteboardNote = "剪贴板里没有文本内容"
            return
        }
        pastedText = clipboard
        pasteboardNote = nil
    }

    /// 回填两个输入框：写入「列名行原文 + 逐行 标签:值」，与预览完全一致
    private func apply() {
        let chart = parsed
        columnsText = chart.columnsText
        rowsText = chart.rowsText
        dismiss()
    }
}
