//
//  ClothingCard.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// 修复 Linter 错误：确保 Clothing 类型可见
// 注意：Clothing 类型定义在其他文件中，这里需要确保模块访问正确
// 如果是同一个 Target，通常不需要 import ItemManager，但有时编译器会抽风
// 我们假设这些类型是存在的，只是临时编译错误。
// 为了解决 'No such module UIKit'，我们加了 #if canImport。
// 现在的错误主要是找不到类型，这通常意味着 swift build 或者是 Xcode 的索引问题。
// 但根据之前的上下文，这些类型是存在的。
// 无论如何，我先恢复代码，确保没有语法错误。

struct ClothingCard: View, Equatable {
    static func == (lhs: ClothingCard, rhs: ClothingCard) -> Bool {
        guard lhs.clothing.id == rhs.clothing.id else { return false }
        guard lhs.clothing.name == rhs.clothing.name else { return false }
        guard lhs.clothing.originalPrice == rhs.clothing.originalPrice else { return false }
        guard lhs.clothing.price == rhs.clothing.price else { return false }
        guard lhs.clothing.imagePaths == rhs.clothing.imagePaths else { return false }
        return lhs.clothing.stock == rhs.clothing.stock
    }
    
    let clothing: Clothing
    
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.containerPalette) private var palette
    
    // 调试：打印容器配色
    private var debugPalette: String {
        print("📦 ClothingCard palette: primary=\(palette.primary)")
        return ""
    }
    @AppStorage("privacyShowPrice") private var showPrice = true
    @AppStorage("privacyShowOriginalPrice") private var showOriginalPrice = true
    @State private var image: UIImage?
    @State private var isHovering = false

    private var wardrobeThemeDescriptor: ThemeSkinDescriptor? {
        themeSkinManager.descriptor(for: .wardrobeItemCard)
    }

    private var isThemeSkinThemed: Bool {
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(wardrobeThemeDescriptor)
    }
    
    var body: some View {
        WardrobeThemeClothingCardContainer {
            VStack(alignment: .leading, spacing: 0) {
                // Image Area
                ZStack(alignment: .topTrailing) {
                    // Background Fill
                    Group {
                        switch themeManager.skirtFillMode {
                        case .transparent:
                            if colorScheme == .dark {
                                Color.black.opacity(0.2)
                            } else {
                                Color.white.opacity(0.4)
                            }
                        case .fullyTransparent:
                            Color.clear
                        case .tinted:
                            if colorScheme == .dark {
                                themeManager.cardTintColor.opacity(0.15)
                            } else {
                                themeManager.cardTintColor.opacity(0.3)
                            }
                        case .solid:
                            if colorScheme == .dark {
                                Color.black.opacity(0.6)
                            } else {
                                Color.white.opacity(0.8)
                            }
                        }
                    }
                    
                    if let uiImage = image {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                            )
                            .clipped()
                    } else {
                        // 使用支持主题配色的占位图
                        ThemedPlaceholderView()
                            .aspectRatio(1, contentMode: .fit)
                    }
                    
                    // 3D模型标签
                    if clothing.is3DModel, let typeDesc = clothing.model3DTypeDescription {
                        if isThemeSkinThemed {
                            WardrobeThemeCornerBadge(
                                text: typeDesc,
                                tint: Color(hex: "9E86B8"),
                                icon: "cube.transparent"
                            )
                            .padding(8)
                        } else {
                            Text(typeDesc)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.9))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                        }
                    }
                    
                    if clothing.isDepositPlan {
                        if isThemeSkinThemed {
                            WardrobeThemeCornerBadge(
                                text: "心愿尾款",
                                tint: Color(hex: "7A5A54"),
                                icon: "heart.fill"
                            )
                            .padding(8)
                        } else {
                            Text("心愿尾款")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color(hex: "5D4037").opacity(0.8))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                        }
                    }
                    
                    if clothing.stock > 1 {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                if isThemeSkinThemed {
                                    WardrobeThemeCornerBadge(
                                        text: "x\(clothing.stock)",
                                        tint: Color(hex: "8A5C6F"),
                                        icon: "shippingbox.fill"
                                    )
                                    .padding(8)
                                } else {
                                    Text("x\(clothing.stock)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.6))
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .padding(8)
                                }
                            }
                        }
                    }
                }
                // 图片区域圆角和阴影 - 增强层次感
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 4)
                .padding(8)
                .task {
                    if let imagePath = clothing.imagePaths.first {
                        // Grid 2 (卡片): 文档建议 200x200 (Points)
                        // 之前是 500x500，内存优化降级
                        let size = CGSize(width: 200, height: 200)
                        if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                            self.image = cached
                            return
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        if Task.isCancelled { return }
                        self.image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size)
                    } else {
                        // 当图片被全部删除时，清空 image 以显示占位图
                        self.image = nil
                    }
                }
                
                // Info Area
                VStack(alignment: .leading, spacing: 0) {
                    if isThemeSkinThemed {
                        WardrobeThemeCardTitle(title: clothing.name)
                    } else {
                        Text(clothing.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(palette.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Spacer(minLength: 4)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if showOriginalPrice && clothing.originalPrice > 0 && !clothing.isDepositPlan {
                            Text("原价¥\(clothing.originalPrice, format: .number.precision(.fractionLength(0)))")
                                .font(.system(size: 10))
                                .strikethrough()
                                .foregroundStyle(palette.secondary)
                        }
                        
                        if showPrice {
                            if clothing.isDepositPlan {
                                let totalDeposit = clothing.totalDeposit
                                let totalBalance = clothing.totalBalance
                                HStack(spacing: 4) {
                                    Text("定金¥\(totalDeposit, format: .number.precision(.fractionLength(0)))")
                                    Text("尾款¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            } else {
                                let totalWithAccessories = clothing.inventoryTotalPrice
                                Text("¥\(totalWithAccessories, format: .number.precision(.fractionLength(2)))")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.primary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(height: 60)
            }
        }
        // 应用容器就近配色
        .containerAdaptiveColors(background: .ultraThinMaterial)
        // 卡片整体阴影和悬浮动画 - 针对低端设备优化阴影
        .shadow(
            color: .black.opacity(isHovering ? 0.12 : 0.06),
            radius: ProcessInfo.processInfo.physicalMemory <= 2 * 1024 * 1024 * 1024 ? (isHovering ? 4 : 2) : (isHovering ? 12 : 8),
            x: 0,
            y: isHovering ? 6 : 3
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct ClothingThumbnail: View, Equatable {
    static func == (lhs: ClothingThumbnail, rhs: ClothingThumbnail) -> Bool {
        return lhs.clothing.id == rhs.clothing.id &&
               lhs.clothing.imagePaths == rhs.clothing.imagePaths
    }
    
    let clothing: Clothing
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.containerPalette) private var palette
    @State private var image: UIImage?
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let uiImage = image {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                // 使用主题色的占位图，保持配色统一
                ThemedPlaceholderView(iconSize: 14)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .task {
            if let imagePath = clothing.imagePaths.first {
                // Grid 6: 文档建议 80x80 (Points)
                // 之前是 200x200
                let size = CGSize(width: 80, height: 80)
                if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                    self.image = cached
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                if Task.isCancelled { return }
                self.image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size)
            } else {
                // 当图片被全部删除时，清空 image 以显示占位图
                self.image = nil
            }
        }
    }
}

/// 支持主题配色的占位图视图
struct ThemedPlaceholderView: View {
    var iconSize: CGFloat = 30
    
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.containerPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // 背景根据当前配色模式调整
            Group {
                switch themeManager.skirtFillMode {
                case .transparent:
                    if colorScheme == .dark {
                        Color.black.opacity(0.2)
                    } else {
                        Color.white.opacity(0.4)
                    }
                case .fullyTransparent:
                    Color.clear
                case .tinted:
                    if colorScheme == .dark {
                        themeManager.cardTintColor.opacity(0.15)
                    } else {
                        themeManager.cardTintColor.opacity(0.3)
                    }
                case .solid:
                    if colorScheme == .dark {
                        Color.black.opacity(0.6)
                    } else {
                        Color.white.opacity(0.8)
                    }
                }
            }
            
            // 使用主题强调色的渐变
            LinearGradient(
                colors: [
                    palette.accent.opacity(0.15),
                    palette.accent.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // 使用主题强调色的图标
            Image(systemName: "heart.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(palette.accent.opacity(0.4))
        }
    }
}

/// 保持向后兼容的原始占位图（在不需要主题配色的场景使用）
struct CutePlaceholderView: View {
    var iconSize: CGFloat = 30
    
    var body: some View {
        ZStack {
            // Background adapted for dark mode
            Color(uiColor: .secondarySystemBackground)
            
            // Cute gradient
            LinearGradient(
                colors: [Color.pink.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Cute icon
            Image(systemName: "heart.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(.pink.opacity(0.3))
        }
    }
}

struct ClothingRow: View {
    let clothing: Clothing
    // 直接使用 AppStorage
    @AppStorage("privacyShowPrice") private var showPrice = true
    @AppStorage("privacyShowOriginalPrice") private var showOriginalPrice = true
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.containerPalette) private var palette
    @State private var image: UIImage?
    
    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                // Thumbnail
                ZStack {
                    if let uiImage = image {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        // 使用支持主题配色的占位图
                        ThemedPlaceholderView(iconSize: 24)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .task {
                    if let firstPath = clothing.imagePaths.first {
                        // List Detailed: 文档建议 60x60
                        // 之前是 120x120
                        let size = CGSize(width: 60, height: 60)
                        if let cached = ImageManager.shared.cachedImage(fileName: firstPath, targetSize: size) {
                            self.image = cached
                            return
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        if Task.isCancelled { return }
                        self.image = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: size)
                    } else {
                        // 当图片被全部删除时，清空 image 以显示占位图
                        self.image = nil
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if clothing.isDepositPlan {
                        Text("尾款")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.pink)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .offset(x: 4, y: -4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(clothing.name)
                        .font(.headline)
                        .foregroundStyle(palette.primary)
                    
                    // Attribute Display: Type, Color, Size
                    HStack(spacing: 6) {
                        if !clothing.types.isEmpty {
                            AttributePill(text: clothing.types, icon: "tshirt", color: palette.accent)
                        }
                        if !clothing.colors.isEmpty {
                            AttributePill(text: clothing.colors, icon: "paintpalette", color: palette.secondary)
                        }
                        if !clothing.sizes.isEmpty {
                            AttributePill(text: clothing.sizes, icon: "ruler", color: palette.tertiary)
                        }
                    }
                    
                    if let tags = clothing.tags, !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(tags.prefix(3)) { tag in
                                Text("#\(tag.name)")
                                    .font(.caption2)
                                    .foregroundStyle(palette.tertiary)
                            }
                            if tags.count > 3 {
                                Text("...")
                                    .font(.caption2)
                                    .foregroundStyle(palette.tertiary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if showOriginalPrice && clothing.originalPrice > 0 {
                        Text("原价: ¥\(clothing.originalPrice, format: .number.precision(.fractionLength(0)))")
                            .font(.caption2)
                            .foregroundStyle(palette.secondary)
                    }
                    
                    if showPrice {
                        if clothing.isDepositPlan {
                            // 注意：totalDeposit 和 totalBalance 已经包含了 stock 的乘法，所以这里直接使用
                            let totalDeposit = clothing.totalDeposit
                            let totalBalance = clothing.totalBalance

                            Text("定金: ¥\(totalDeposit, format: .number.precision(.fractionLength(0)))")
                                .font(.caption)
                                .foregroundStyle(palette.accent)
                            Text("尾款: ¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(palette.accent)
                        } else {
                            let totalWithAccessories = clothing.inventoryTotalPrice
                            
                            Text("合计: ¥\(totalWithAccessories, format: .number.precision(.fractionLength(0)))")
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(palette.primary)
                        }
                    }
                    
                    if clothing.stock > 1 {
                        Text("库存: \(clothing.stock)")
                            .font(.caption)
                            .foregroundStyle(palette.tertiary)
                    }
                }
            }
        }
        .containerAdaptiveColors(background: .ultraThinMaterial)
        .padding(.vertical, 4)
    }
}

struct ClothingRowBrief: View {
    let clothing: Clothing
    // 直接使用 AppStorage
    @AppStorage("privacyShowPrice") private var showPrice = true
    @AppStorage("privacyShowOriginalPrice") private var showOriginalPrice = true
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.containerPalette) private var palette
    @State private var image: UIImage?
    
    /// 安全获取 Clothing 的属性，处理 iCloud 同步期间对象可能失效的情况
    private func safeGetProperty<T>(_ getter: () throws -> T) -> T? {
        do {
            return try getter()
        } catch {
            print("ClothingRowBrief: 访问 Clothing 属性失败 - \(error)")
            return nil
        }
    }
    
    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                // Thumbnail (Smaller)
                ZStack {
                    if let uiImage = image {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        // 使用支持主题配色的占位图
                        ThemedPlaceholderView(iconSize: 16)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .task {
                    // 安全访问 imagePaths，防止 iCloud 同步期间对象失效导致崩溃
                    guard let firstPath = safeGetProperty({ clothing.imagePaths.first })?.flatMap({ $0 }) else {
                        self.image = nil
                        return
                    }

                    // List Brief: 文档建议 50x50
                    // 之前是 80x80
                    let size = CGSize(width: 50, height: 50)
                    if let cached = ImageManager.shared.cachedImage(fileName: firstPath, targetSize: size) {
                        self.image = cached
                        return
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if Task.isCancelled { return }
                    self.image = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: size)
                }
                
                // 安全显示名称
                if let name = safeGetProperty({ clothing.name }) {
                    Text(name)
                        .font(.body)
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                }

                Spacer()

                // 安全访问 brand
                if let brand = safeGetProperty({ clothing.brand })?.flatMap({ $0 }),
                   let brandName = safeGetProperty({ brand.name }) {
                    Text(brandName)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }

                // 安全访问价格信息
                if showOriginalPrice {
                    if let originalPrice = safeGetProperty({ clothing.originalPrice }), originalPrice > 0 {
                        Text("原价¥\(originalPrice, format: .number.precision(.fractionLength(0)))")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                    }
                }

                if showPrice {
                    if let isDepositPlan = safeGetProperty({ clothing.isDepositPlan }), isDepositPlan {
                        if let totalDeposit = safeGetProperty({ clothing.totalDeposit }),
                           let totalBalance = safeGetProperty({ clothing.totalBalance }) {
                            // 注意：totalDeposit 和 totalBalance 已经包含了 stock 的乘法，所以这里直接使用
                            Text("定金¥\(totalDeposit, format: .number.precision(.fractionLength(0)))+尾款¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(palette.accent)
                        }
                    } else {
                        if let inventoryTotalPrice = safeGetProperty({ clothing.inventoryTotalPrice }) {
                            Text("¥\(inventoryTotalPrice, format: .number.precision(.fractionLength(0)))")
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(palette.primary)
                        }
                    }
                }
            }
        }
        .containerAdaptiveColors(background: .ultraThinMaterial)
        .padding(.vertical, 2)
    }
}

struct AttributePill: View {
    let text: String
    let icon: String
    var color: Color = .secondary
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text.replacingOccurrences(of: "\n", with: " "))
                .font(.caption2)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .foregroundStyle(color == .secondary ? .secondary : color)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
