//
//  OpsFormSupport.swift
//  PinkHouseOps
//
//  视图层共用的小组件：金额解析、可选日期、缩略图、表单外壳。
//
//  ## 为什么金额解析要单独抽出来，而不是各表单自己 `Decimal(string:)`
//
//  「留空」和「填错」是两个**方向相反**的语义，而它们在 `Decimal(string:) == nil`
//  这一点上长得完全一样：
//
//    · 留空  → 表示「清除这一项」（价格修正的完整快照语义）；
//    · 填错  → 必须**拒绝**，绝不能顺手当成「清除」——
//              运营打错一个字就把已确认的价格清掉了，而界面上什么都不会说。
//
//  所以解析结果是一个三态枚举，调用方必须显式处理 `invalid`。各表单各写一遍
//  `Decimal(string:) ?? nil`，就会把这个区别吃掉。
//

import AppKit
import SwiftUI

// MARK: - 文案渲染

/// 把「带轻量 Markdown 的普通 String」交给 SwiftUI 渲染。
///
/// ## 为什么必须有这一层（实测踩到）
///
/// `Text("**重点**")` —— **字面量**走的是 `LocalizedStringKey`，会解析 Markdown，加粗。
/// `Text(someString)` —— **变量**走的是 `String` 的逐字初始化器，不解析，
/// 于是同一对星号在界面上原样显示成 `**重点**`。
///
/// 本仓库（含 `SharedCatalog` 里那些 `guidance`）大量用 `**…**` 标重点，
/// 所以**凡是从变量来的文案都要过这一层**；写字面量时不用。
///
/// ## ⚠️ 但「过这一层」还不够 —— 这一层本身以前是坏的（2026-09-27 快照实测到）
///
/// 原来这里写的是 `Text(LocalizedStringKey(text))`，那是**错的**：
/// `LocalizedStringKey` 的 Markdown 解析发生在**字面量 / 字符串插值**那条路径上，
/// `LocalizedStringKey(_ value: String)` 这个「接一个运行时字符串」的初始化器
/// **不解析 Markdown**。后果是这一层等于没做，星号照样逐字显示。
///
/// 取证（`PinkHouseOps` 的应用内离屏快照，`publish.png`）：
/// `TargetEnvironment.localFixture.guidance` 里的 `**不代表已上线**`（该环境已于
/// 2026-09-29 移除，取证本身仍然成立）、
/// `ShopCatalogBaselineVerdict.unverified.guidance` 里的 `本页**不会**替你声称…`，
/// 在快照上都是**带星号**的原文。两处来自不同模块、走同一条渲染路径 —— 结论明确。
///
/// 修法：用 `AttributedString(markdown:)` **显式**解析，再交给 `Text`。
/// 关键参数是 `inlineOnlyPreservingWhitespace`，两个理由都要：
///   · `inlineOnly` —— 这些文案是**一句话/一段话**，不是文档。若允许块级语法，
///     行首的 `#` `-` `1.`（我们的路径、日志行里都有）会被吃成标题/列表；
///   · `PreservingWhitespace` —— 默认的 `.full` 会把**换行折成空格**，
///     而阻断项与结论是 `\n` 拼起来的多行，折了就读不成列表（这是静默的版式损坏）。
///
/// 解析失败（极少见的畸形 Markdown）就回落到逐字 `Text(text)` ——
/// **宁可显示星号，也不能把整句话吞掉**。
func opsMarkdown(_ text: String) -> Text {
    if let attributed = try? AttributedString(
        markdown: text,
        options: AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
        return Text(attributed)
    }
    return Text(text)
}

// MARK: - 金额三态

enum OpsDecimalField: Equatable {
    /// 没填 → 调用方按「清除这一项」处理
    case empty
    case value(Decimal)
    /// 填了但解析不出来 → 必须拒绝并提示原文
    case invalid
}

func opsParseDecimal(_ text: String) -> OpsDecimalField {
    let trimmed = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        // 全角字符与千分位是运营最容易打进来的东西，先在录入端归一
        .replacingOccurrences(of: "，", with: ",")
        .replacingOccurrences(of: "　", with: "")
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: "¥", with: "")
        .replacingOccurrences(of: "￥", with: "")
    guard !trimmed.isEmpty else { return .empty }
    guard let value = Decimal(string: trimmed) else { return .invalid }
    return .value(value)
}

/// 把三态解析结果变成「要么给值、要么给报错文案」。
/// `label` 用于报错里指明是哪一格（表单里通常有好几格金额）。
func opsResolveDecimal(
    _ text: String, label: String
) -> (value: Decimal?, isEmpty: Bool, error: String?) {
    switch opsParseDecimal(text) {
    case .empty:
        return (nil, true, nil)
    case .value(let value):
        return (value, false, nil)
    case .invalid:
        return (nil, false, "「\(label)」不是有效数字：\(text)。"
            + "（留空表示清除这一项；要清除请把这一格完全留空）")
    }
}

// MARK: - 可选日期

/// 「有 / 没有 + 一个日期」的三段式输入。
///
/// SwiftUI 的 `DatePicker` 只接受非可选 `Binding<Date>`，直接用会把
/// 「没填」静默变成「今天」—— 而「没填」在预约区间里是有含义的（选填的结束时间）。
struct OpsOptionalDateField: View {
    let label: String
    @Binding var isOn: Bool
    @Binding var date: Date
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isOn) {
                // ⚠️ `label` 是**变量**，必须过 `opsMarkdown` —— 调用方确实在 label 里
                // 用 `**…**` 标重点（如「预约结束时间（**驱动自动流转**）」）。
                // 用 `Text(label)` 会让星号逐字显示。
                // 这里**不接数据**（label 是界面文案，不是运营填的内容），
                // 所以 Markdown 解析不会改坏任何东西 —— 与 `OpsTag(text:)` 的取舍相反。
                opsMarkdown(label).font(.callout)
            }
            if isOn {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .padding(.leading, 18)
            } else if let help {
                // 同上：`help` 是变量。
                // 今天三个调用点都没有星号，所以这一处**目前没坏** ——
                // 但它是同一个陷阱，`tools/ops_ui/check_markdown_callsites.py` 会拦。
                opsMarkdown(help)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
    }
}

// MARK: - 缩略图

/// 素材缩略图。引用解不开时退化成占位图标 —— 留空白会被读成「图丢了」，
/// 占位图标读成「这里本来就没图」。
struct OpsThumbnail: View {
    let url: URL?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.secondary.opacity(0.10)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .font(.system(size: size * 0.32))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.14)
                .stroke(Color.secondary.opacity(0.20), lineWidth: 1))
    }
}

// MARK: - 表单外壳

/// 统一的表单外壳（标题 + 内容 + 取消/保存）。
///
/// ⚠️ 「保存」的语义是 **命令成功才关窗**（R05）。这条规则由外壳**自己**执行：
/// 调用方给的 `onConfirm` 返回 Bool，只有 true 才 `dismiss()`。
/// 让每个表单各自写 `if ok { dismiss() }` 就会有人漏写，而漏写的表现是
/// 「填完一整页、点了保存、窗口关了、内容没保存」——运营下次打开才发现。
struct OpsFormFrame<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var confirmTitle: String = "保存"
    var width: CGFloat = 460
    /// 内容区高度。给 ScrollView 一个有界高度，长表单（尺码表）不会被压扁。
    var contentHeight: CGFloat = 380
    @ViewBuilder var content: Content
    let onCancel: () -> Void
    /// 返回 true = 保存成功（外壳会关窗）；false = 留在表单里，错误已在全局 banner
    let onConfirm: () -> Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let subtitle {
                    // ⚠️ `subtitle` 是**变量**，必须过 `opsMarkdown` —— 而且各表单确实
                    // 在 subtitle 里用 `**…**` 标重点（如「⚠️ 这是**完整快照**：留空的那一项
                    // 会被**清除**」）。用 `Text(subtitle)` 会让星号逐字显示。
                    opsMarkdown(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: contentHeight)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button(confirmTitle) {
                    if onConfirm() { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: width)
    }
}

// MARK: - 内容卡

/// 统一的内容卡外壳（标题图标 + 内容）。
/// 从已删除的「工作台」页迁到这里：向导 / 商品管理 / 本地预览等页都在用它。
struct OpsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(OpsFlowPalette.textPrimary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OpsFlowPalette.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(OpsFlowPalette.cardBorder, lineWidth: 1))
        .shadow(color: OpsFlowPalette.cardShadow, radius: 10, x: 0, y: 4)
    }
}

// MARK: - 小标签

struct OpsTag: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// 一段「说明 + 依据」的灰字。视图层里凡是口径性的说明都用它，
/// 免得有的地方写了、有的地方漏了（漏掉的那处看起来像「这个规则不存在」）。
struct OpsFootnote: View {
    let text: String

    var body: some View {
        opsMarkdown(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
