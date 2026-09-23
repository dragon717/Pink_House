//
//  ShopCatalogImagePickerButton.swift
//  ItemManager
//
//  运营端图片上传入口（V1.1 §4.2 配套，解决「尺码表 / 商品单图 / 预约价格表等
//  模块没有添加图片按钮」的问题）：
//    · PhotosPicker 选图（2026-09-24 起支持**一次多选**）→ ShopCatalogImageStore
//      落盘（长边 1600 / JPEG 0.85）
//    · 生成「local:<文件名>」引用回填绑定文本（随种子/覆盖层持久化，展示走
//      ShopCatalogImageResolver 的 local: 分支）
//    · .append = 商品图片多行文本追加一行（多选时按选择顺序逐张追加）；
//      .replace = 覆盖单值（原图/Logo/封面；多选时取第一张，单值字段语义不变）
//

import SwiftUI
import PhotosUI

struct ShopCatalogImagePickerButton: View {
    enum Mode { case append, replace }

    let mode: Mode
    @Binding var text: String
    var label: String = "添加图片"

    /// 单次最多可选张数：防止误触「全选相册」把覆盖层撑爆
    private static let maxSelectionCount = 10

    @State private var selections: [PhotosPickerItem] = []
    @State private var errorText: String?

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selections,
                         maxSelectionCount: Self.maxSelectionCount,
                         matching: .images) {
                Label(label.appLocalized, systemImage: "photo.badge.plus")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(.pink)
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: selections) { _, items in
            guard !items.isEmpty else { return }
            selections = []
            Task { await handle(items) }
        }
    }

    private func handle(_ items: [PhotosPickerItem]) async {
        // 逐张落盘；失败不静默——报告成功/失败张数，成功的照常写入
        var references: [String] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let reference = ShopCatalogImageStore.save(data) else { continue }
            references.append(reference)
        }
        await MainActor.run {
            if references.isEmpty {
                errorText = "图片保存失败，请重试"
                return
            }
            errorText = references.count < items.count
                ? "已保存 \(references.count)/\(items.count) 张，其余保存失败"
                : nil
            switch mode {
            case .append:
                let lines = text
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map(String.init) + references
                text = lines.joined(separator: "\n")
            case .replace:
                // 单值字段：多选只取第一张，语义与旧版一致
                text = references[0]
            }
        }
    }
}
