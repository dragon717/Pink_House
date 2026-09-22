//
//  AZIndexedList.swift
//  ItemManager
//
//  iOS 26/27 设计规范索引列表组件（供实体管理等长列表复用）：
//    · AZPinnedSearchBar —— 常驻固定搜索栏：放在 List 之外（VStack 上层），
//      无论内容滚动到哪都保持固定，符合 HIG「搜索控件位置恒定」要求
//    · AZIndexRail —— 右侧 A-Z 索引滑块：支持点按与上下滑动快速跳转分组，
//      iOS 26+ 使用 Liquid Glass（glassEffect），低版本回退超薄材质
//    · AZIndexGrouping —— 分组纯逻辑（nonisolated）：A-Z + 中文转拼音首字母 + 其它归 #
//

import SwiftUI
import UIKit

// 分组 / 字典序 / 搜索匹配的唯一实现在 Service 层：
// ItemManager/Services/ShopCatalog/AZIndexGrouping.swift
// （根因：Catalog 数组是录入顺序，任何直接遍历的列表都没有字典序保证）

// MARK: - Liquid Glass 兼容修饰符

extension View {
    /// iOS 26+ 使用 Liquid Glass；低版本回退超薄材质（保持视觉层级一致）
    @ViewBuilder
    func azLiquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }
}

// MARK: - 常驻固定搜索栏

/// 置于列表容器之外（VStack 上层）的搜索栏：不随内容滚动。
/// 视觉对齐系统搜索框：胶囊形、tertiarySystemFill、放大镜图标、聚焦时出现「取消」。
struct AZPinnedSearchBar: View {
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var placeholder: String = "搜索"

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .font(.body)
                    .focused($focused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("az-search-field")
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
            .contentShape(Capsule())
            .onTapGesture { focused = true }

            if focused {
                Button("取消") {
                    text = ""
                    focused = false
                }
                .font(.body)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: focused)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

// MARK: - 右侧 A-Z 索引滑块

/// 右侧索引滑块：点按或上下拖动跳转到对应分组（DragGesture minimumDistance 0 同时覆盖两种手势）。
/// 高度自适应可用空间（GeometryReader 等分槽位），各类屏幕尺寸下均正确分布。
struct AZIndexRail: View {
    let letters: [String]
    @Binding var hudLetter: String?
    let onJump: (String) -> Void

    @State private var currentIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let slotHeight = geo.size.height / CGFloat(max(letters.count, 1))
            VStack(spacing: 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { idx, letter in
                    Text(letter)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(currentIndex == idx ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: slotHeight)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 4)
            .frame(width: 28)
            .azLiquidGlass(in: Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !letters.isEmpty else { return }
                        let idx = min(max(Int(value.location.y / max(slotHeight, 1)), 0), letters.count - 1)
                        if currentIndex != idx {
                            currentIndex = idx
                            hudLetter = letters[idx]
                            onJump(letters[idx])
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { _ in
                        currentIndex = nil
                        hudLetter = nil
                    }
            )
        }
        .frame(width: 30)
        .padding(.trailing, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("字母索引")
        .accessibilityValue(currentIndex.map { letters[$0] } ?? "")
        .accessibilityHint("点按或上下滑动，快速跳转到对应字母分组")
        .accessibilityAdjustableAction { direction in
            guard !letters.isEmpty else { return }
            let next = (currentIndex ?? 0) + (direction == .increment ? 1 : -1)
            guard letters.indices.contains(next) else { return }
            currentIndex = next
            hudLetter = letters[next]
            onJump(letters[next])
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - 跳转 HUD（拖动时屏幕中央的大字母提示）

struct AZIndexHUD: View {
    let letter: String?

    var body: some View {
        Group {
            if let letter {
                Text(letter)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 84, height: 84)
                    .azLiquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: letter)
    }
}
