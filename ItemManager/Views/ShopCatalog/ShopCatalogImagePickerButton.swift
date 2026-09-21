//
//  ShopCatalogImagePickerButton.swift
//  ItemManager
//
//  运营端图片上传入口（V1.1 §4.2 配套，解决「尺码表 / 商品单图 / 预约价格表等
//  模块没有添加图片按钮」的问题）：
//    · PhotosPicker 选图 → ShopCatalogImageStore 落盘（长边 1600 / JPEG 0.85）
//    · 生成「local:<文件名>」引用回填绑定文本（随种子/覆盖层持久化，展示走
//      ShopCatalogImageResolver 的 local: 分支）
//    · .append = 商品图片多行文本追加一行；.replace = 覆盖单值（原图/Logo/封面）
//

import SwiftUI
import PhotosUI

struct ShopCatalogImagePickerButton: View {
    enum Mode { case append, replace }

    let mode: Mode
    @Binding var text: String
    var label: String = "添加图片"

    @State private var selection: PhotosPickerItem?
    @State private var errorText: String?

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selection, matching: .images) {
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
        .onChange(of: selection) { _, item in
            guard let item else { return }
            selection = nil
            Task { await handle(item) }
        }
    }

    private func handle(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let reference = ShopCatalogImageStore.save(data) else {
            await MainActor.run { errorText = "图片保存失败，请重试" }
            return
        }
        await MainActor.run {
            errorText = nil
            switch mode {
            case .append:
                let lines = text
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map(String.init) + [reference]
                text = lines.joined(separator: "\n")
            case .replace:
                text = reference
            }
        }
    }
}
