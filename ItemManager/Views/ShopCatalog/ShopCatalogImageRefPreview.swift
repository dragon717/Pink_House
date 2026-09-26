//
//  ShopCatalogImageRefPreview.swift
//  ItemManager
//
//  上传图片引用的**缩略图预览**（2026-09-26 需求：上传的图片直接渲染出来，
//  不再以「local:xxx.jpg」这类文件名文本展示）。
//
//  ── 口径 ──
//
//  引用的**载体不变**：仍是换行分隔的文本绑定（表单 / 编辑中快照 / 保存口径
//  全都不动）——本组件只负责「展示 + 移除」，把文件名文本从界面上拿掉，
//  图片本身顶上来。加载统一走 `ShopCatalogAssetImage`
//  （local: / Bundle / http(s) / thmedia: 四类引用同一套口径，含失败重试）。
//
//  两个变体：
//    · Single —— 单值字段（封面 / Logo / 尺码表原图）：一张大图 + 「移除图片」；
//    · Multi  —— 多值字段（商品图片 / 预约价格表多图）：自适应网格 + 每格 × 移除。
//                 `showsReferenceCaption` 给「配色尺码按引用绑定」的场景用：
//                 格子下方标注引用原文（点按复制），否则用户没法在配色尺码行
//                 填第三段完成图文绑定。
//

import SwiftUI

// MARK: - 单值字段

struct ShopCatalogSingleImagePreview: View {
    let reference: String
    var height: CGFloat = 150
    var onRemove: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ShopCatalogAssetImage(reference: reference)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("移除图片", systemImage: "trash")
                        .font(.system(size: 12))
                }
            }
        }
    }
}

// MARK: - 多值字段（绑定文本 = 每行一个引用）

struct ShopCatalogMultiImagePreview: View {
    @Binding var referencesText: String
    /// 配色尺码等按引用串绑定的场景：格子下方标注引用原文（点按复制）
    var showsReferenceCaption = false
    var height: CGFloat = 110

    var body: some View {
        let refs = Self.references(in: referencesText)
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(Array(refs.enumerated()), id: \.offset) { index, reference in
                    cell(reference: reference, index: index)
                }
            }
            Text(footerText(count: refs.count))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func cell(reference: String, index: Int) -> some View {
        VStack(spacing: 4) {
            ShopCatalogAssetImage(reference: reference)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(4)
                    .accessibilityLabel("移除第 \(index + 1) 张图片")
                }
            if showsReferenceCaption {
                // 配色尺码行第三段要填的正是这串引用；点一下复制，免得手抄
                Text(reference)
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { UIPasteboard.general.string = reference }
                    .accessibilityLabel("图片引用 \(reference)，点按复制")
            }
        }
    }

    private func footerText(count: Int) -> String {
        var text = "已上传 \(count) 张，点图右上角 × 移除"
        if showsReferenceCaption {
            text += "；配色尺码行第三段填图下标注的引用完成图文绑定（点引用可复制）"
        }
        return text
    }

    // MARK: 引用文本 ↔ 列表（载体不变：每行一个引用）

    private static func references(in text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func remove(at index: Int) {
        var refs = Self.references(in: referencesText)
        guard refs.indices.contains(index) else { return }
        refs.remove(at: index)
        referencesText = refs.joined(separator: "\n")
    }
}
