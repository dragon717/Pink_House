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

struct WardrobeCellSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let brandName: String?
    let originalPrice: Decimal
    let price: Decimal
    let imagePaths: [String]
    let stock: Int
    let isDepositPlan: Bool
    let totalDeposit: Decimal
    let totalBalance: Decimal
    let inventoryTotalPrice: Decimal
    let is3DModel: Bool
    let model3DTypeDescription: String?
    let types: String
    let colors: String
    let sizes: String
    let tagNames: [String]

    var firstImagePath: String? {
        imagePaths.first
    }

    @MainActor
    init(clothing: Clothing) {
        self.id = clothing.id
        self.name = clothing.name
        self.brandName = clothing.brand?.name
        self.originalPrice = clothing.originalPrice
        self.price = clothing.price
        self.imagePaths = clothing.imagePaths
        self.stock = clothing.stock
        self.isDepositPlan = clothing.isDepositPlan
        self.totalDeposit = clothing.totalDeposit
        self.totalBalance = clothing.totalBalance
        self.inventoryTotalPrice = clothing.inventoryTotalPrice
        self.is3DModel = clothing.is3DModel
        self.model3DTypeDescription = clothing.model3DTypeDescription
        self.types = clothing.types
        self.colors = clothing.colors
        self.sizes = clothing.sizes
        self.tagNames = clothing.tags?.map(\.name) ?? []
    }
}

private struct WardrobeListCellContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: Content

    init(cornerRadius: CGFloat, padding: CGFloat, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        ZStack {
            WardrobeListCellBackground(cornerRadius: cornerRadius)

            content
                .padding(padding)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
    }
}

struct WardrobeListCellBackground: View {
    @Environment(ThemeManager.self) private var themeManager

    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(themeManager.cardTintColor.opacity(strokeOpacity), lineWidth: 1)
            )
    }

    private var fillColor: Color {
        switch themeManager.cardStyle {
        case .fullyTransparent:
            return Color.clear
        case .transparent:
            return themeManager.cardBackgroundColor.opacity(max(themeManager.transparentOpacity, 0.18))
        case .tinted:
            return themeManager.cardBackgroundColor.opacity(max(themeManager.tintOpacity, 0.18))
        case .solid:
            return themeManager.cardBackgroundColor
        }
    }

    private var strokeOpacity: Double {
        switch themeManager.cardStyle {
        case .fullyTransparent:
            return 0.18
        case .transparent, .tinted:
            return 0.24
        case .solid:
            return 0.12
        }
    }
}

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
        lhs.snapshot == rhs.snapshot &&
        lhs.showPrice == rhs.showPrice &&
        lhs.showOriginalPrice == rhs.showOriginalPrice &&
        lhs.wardrobeThemeDescriptor == rhs.wardrobeThemeDescriptor
    }
    
    let snapshot: WardrobeCellSnapshot
    let showPrice: Bool
    let showOriginalPrice: Bool
    let wardrobeThemeDescriptor: ThemeSkinDescriptor?
    
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.containerPalette) private var palette
    @State private var image: UIImage?

    @MainActor
    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true
    ) {
        self.init(
            snapshot: snapshot,
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: ThemeSkinManager.shared.descriptor(for: .wardrobeItemCard)
        )
    }

    @MainActor
    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?
    ) {
        self.snapshot = snapshot
        self.showPrice = showPrice
        self.showOriginalPrice = showOriginalPrice
        self.wardrobeThemeDescriptor = wardrobeThemeDescriptor
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice
        )
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: wardrobeThemeDescriptor
        )
    }

    private var isThemeSkinThemed: Bool {
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(wardrobeThemeDescriptor)
    }

    private var titleColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor) : palette.primary
    }

    private func badgeFillColor(for tint: Color) -> Color {
        isThemeSkinThemed ? tint.opacity(0.18) : tint.opacity(0.88)
    }

    private func badgeForegroundColor(for tint: Color) -> Color {
        isThemeSkinThemed ? tint : .white
    }

    @ViewBuilder
    private func wardrobeCellBadge(text: String, tint: Color, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(badgeForegroundColor(for: tint))
        .background(badgeFillColor(for: tint))
        .clipShape(Capsule())
    }
    
    var body: some View {
        WardrobeThemeClothingCardContainer(descriptor: wardrobeThemeDescriptor, scrollOptimized: true) {
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
                    if snapshot.is3DModel, let typeDesc = snapshot.model3DTypeDescription {
                        wardrobeCellBadge(
                            text: typeDesc,
                            tint: Color(hex: "9E86B8"),
                            icon: "cube.transparent"
                        )
                        .padding(8)
                    }
                    
                    if snapshot.isDepositPlan {
                        wardrobeCellBadge(
                            text: "心愿尾款",
                            tint: Color(hex: "7A5A54"),
                            icon: "heart.fill"
                        )
                        .padding(8)
                    }
                    
                    if snapshot.stock > 1 {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                wardrobeCellBadge(
                                    text: "x\(snapshot.stock)",
                                    tint: Color(hex: "8A5C6F"),
                                    icon: "shippingbox.fill"
                                )
                                .padding(8)
                            }
                        }
                    }
                }
                // 图片区域圆角和阴影 - 增强层次感
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(8)
                .task(id: snapshot.firstImagePath) {
                    if let imagePath = snapshot.firstImagePath {
                        // Grid 2 (卡片): 文档建议 200x200 (Points)
                        // 之前是 500x500，内存优化降级
                        let size = CGSize(width: 200, height: 200)
                        if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                            self.image = cached
                            return
                        }
                        if Task.isCancelled { return }
                        let loadedImage = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size, priority: .userInitiated)
                        if Task.isCancelled { return }
                        self.image = loadedImage
                    } else {
                        // 当图片被全部删除时，清空 image 以显示占位图
                        self.image = nil
                    }
                }
                
                // Info Area
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        if isThemeSkinThemed {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text(snapshot.name)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(titleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 4)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if showOriginalPrice && snapshot.originalPrice > 0 && !snapshot.isDepositPlan {
                            Text("原价¥\(snapshot.originalPrice, format: .number.precision(.fractionLength(0)))")
                                .font(.system(size: 10))
                                .strikethrough()
                                .foregroundStyle(palette.secondary)
                        }
                        
                        if showPrice {
                            if snapshot.isDepositPlan {
                                let totalDeposit = snapshot.totalDeposit
                                let totalBalance = snapshot.totalBalance
                                HStack(spacing: 4) {
                                    Text("定金¥\(totalDeposit, format: .number.precision(.fractionLength(0)))")
                                    Text("尾款¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            } else {
                                let totalWithAccessories = snapshot.inventoryTotalPrice
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
        // 卡片整体静态阴影 - 避免 iPhone 列表滚动中无效 hover/spring diff
        .shadow(
            color: .black.opacity(0.025),
            radius: 1,
            x: 0,
            y: 1
        )
    }
}

struct ClothingThumbnail: View, Equatable {
    static func == (lhs: ClothingThumbnail, rhs: ClothingThumbnail) -> Bool {
        lhs.snapshot == rhs.snapshot
    }
    
    let snapshot: WardrobeCellSnapshot
    @State private var image: UIImage?

    init(snapshot: WardrobeCellSnapshot) {
        self.snapshot = snapshot
    }

    @MainActor
    init(clothing: Clothing) {
        self.init(snapshot: WardrobeCellSnapshot(clothing: clothing))
    }
    
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
        .task(id: snapshot.firstImagePath) {
            if let imagePath = snapshot.firstImagePath {
                // Grid 6: 文档建议 80x80 (Points)
                // 之前是 200x200
                let size = CGSize(width: 80, height: 80)
                if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                    self.image = cached
                    return
                }
                if Task.isCancelled { return }
                let loadedImage = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size, priority: .userInitiated)
                if Task.isCancelled { return }
                self.image = loadedImage
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

struct ClothingRow: View, Equatable {
    static func == (lhs: ClothingRow, rhs: ClothingRow) -> Bool {
        lhs.snapshot == rhs.snapshot &&
        lhs.showPrice == rhs.showPrice &&
        lhs.showOriginalPrice == rhs.showOriginalPrice &&
        lhs.wardrobeThemeDescriptor == rhs.wardrobeThemeDescriptor
    }

    let snapshot: WardrobeCellSnapshot
    let showPrice: Bool
    let showOriginalPrice: Bool
    let wardrobeThemeDescriptor: ThemeSkinDescriptor?

    @Environment(\.containerPalette) private var palette
    @State private var image: UIImage?

    @MainActor
    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true
    ) {
        self.init(
            snapshot: snapshot,
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: ThemeSkinManager.shared.descriptor(for: .wardrobeItemCard)
        )
    }

    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?
    ) {
        self.snapshot = snapshot
        self.showPrice = showPrice
        self.showOriginalPrice = showOriginalPrice
        self.wardrobeThemeDescriptor = wardrobeThemeDescriptor
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice
        )
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: wardrobeThemeDescriptor
        )
    }

    private var isThemeSkinThemed: Bool {
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(wardrobeThemeDescriptor)
    }

    private var rowPrimaryColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor) : palette.primary
    }

    private var rowSecondaryColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor).opacity(0.72) : palette.secondary
    }

    private var rowAccentColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.accent(for: wardrobeThemeDescriptor) : palette.accent
    }
    
    var body: some View {
        WardrobeThemeClothingCardContainer(
            cornerRadius: 24,
            descriptor: wardrobeThemeDescriptor,
            scrollOptimized: true
        ) {
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
                .task(id: snapshot.firstImagePath) {
                    if let firstPath = snapshot.firstImagePath {
                        // List Detailed: 文档建议 60x60
                        // 之前是 120x120
                        let size = CGSize(width: 60, height: 60)
                        if let cached = ImageManager.shared.cachedImage(fileName: firstPath, targetSize: size) {
                            self.image = cached
                            return
                        }
                        if Task.isCancelled { return }
                        let loadedImage = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: size, priority: .userInitiated)
                        if Task.isCancelled { return }
                        self.image = loadedImage
                    } else {
                        // 当图片被全部删除时，清空 image 以显示占位图
                        self.image = nil
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if snapshot.isDepositPlan {
                        Text("尾款")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(isThemeSkinThemed ? rowAccentColor : Color.pink)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .offset(x: 4, y: -4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.name)
                        .font(.headline)
                        .foregroundStyle(rowPrimaryColor)
                    
                    // Attribute Display: Type, Color, Size
                    HStack(spacing: 6) {
                        if !snapshot.types.isEmpty {
                            AttributePill(text: snapshot.types, icon: "tshirt", color: rowAccentColor)
                        }
                        if !snapshot.colors.isEmpty {
                            AttributePill(text: snapshot.colors, icon: "paintpalette", color: rowSecondaryColor)
                        }
                        if !snapshot.sizes.isEmpty {
                            AttributePill(text: snapshot.sizes, icon: "ruler", color: isThemeSkinThemed ? rowAccentColor.opacity(0.82) : palette.tertiary)
                        }
                    }
                    
                    if !snapshot.tagNames.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(snapshot.tagNames.prefix(3).enumerated()), id: \.offset) { _, tagName in
                                Text("#\(tagName)")
                                    .font(.caption2)
                                    .foregroundStyle(isThemeSkinThemed ? rowSecondaryColor : palette.tertiary)
                            }
                            if snapshot.tagNames.count > 3 {
                                Text("...")
                                    .font(.caption2)
                                    .foregroundStyle(isThemeSkinThemed ? rowSecondaryColor : palette.tertiary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if showOriginalPrice && snapshot.originalPrice > 0 {
                        Text("原价: ¥\(snapshot.originalPrice, format: .number.precision(.fractionLength(0)))")
                            .font(.caption2)
                            .foregroundStyle(rowSecondaryColor)
                    }
                    
                    if showPrice {
                        if snapshot.isDepositPlan {
                            // 注意：totalDeposit 和 totalBalance 已经包含了 stock 的乘法，所以这里直接使用
                            let totalDeposit = snapshot.totalDeposit
                            let totalBalance = snapshot.totalBalance

                            Text("定金: ¥\(totalDeposit, format: .number.precision(.fractionLength(0)))")
                                .font(.caption)
                                .foregroundStyle(rowAccentColor)
                            Text("尾款: ¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(rowAccentColor)
                        } else {
                            let totalWithAccessories = snapshot.inventoryTotalPrice
                            
                            Text("合计: ¥\(totalWithAccessories, format: .number.precision(.fractionLength(0)))")
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(rowPrimaryColor)
                        }
                    }
                    
                    if snapshot.stock > 1 {
                        Text("库存: \(snapshot.stock)")
                            .font(.caption)
                            .foregroundStyle(isThemeSkinThemed ? rowSecondaryColor : palette.tertiary)
                    }
                }
            }
            .padding(16)
        }
        .padding(.vertical, 4)
    }
}

struct ClothingRowBrief: View, Equatable {
    static func == (lhs: ClothingRowBrief, rhs: ClothingRowBrief) -> Bool {
        lhs.snapshot == rhs.snapshot &&
        lhs.showPrice == rhs.showPrice &&
        lhs.showOriginalPrice == rhs.showOriginalPrice &&
        lhs.wardrobeThemeDescriptor == rhs.wardrobeThemeDescriptor
    }

    let snapshot: WardrobeCellSnapshot
    let showPrice: Bool
    let showOriginalPrice: Bool
    let wardrobeThemeDescriptor: ThemeSkinDescriptor?

    @Environment(\.containerPalette) private var palette
    @State private var image: UIImage?

    @MainActor
    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true
    ) {
        self.init(
            snapshot: snapshot,
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: ThemeSkinManager.shared.descriptor(for: .wardrobeItemCard)
        )
    }

    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?
    ) {
        self.snapshot = snapshot
        self.showPrice = showPrice
        self.showOriginalPrice = showOriginalPrice
        self.wardrobeThemeDescriptor = wardrobeThemeDescriptor
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice
        )
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: wardrobeThemeDescriptor
        )
    }

    private var isThemeSkinThemed: Bool {
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(wardrobeThemeDescriptor)
    }

    private var rowPrimaryColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor) : palette.primary
    }

    private var rowSecondaryColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor).opacity(0.72) : palette.secondary
    }

    private var rowAccentColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.accent(for: wardrobeThemeDescriptor) : palette.accent
    }
    
    var body: some View {
        WardrobeThemeClothingCardContainer(
            cornerRadius: 24,
            descriptor: wardrobeThemeDescriptor,
            scrollOptimized: true
        ) {
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
                .task(id: snapshot.firstImagePath) {
                    guard let firstPath = snapshot.firstImagePath else {
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
                    if Task.isCancelled { return }
                    let loadedImage = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: size, priority: .userInitiated)
                    if Task.isCancelled { return }
                    self.image = loadedImage
                }
                
                Text(snapshot.name)
                    .font(.body)
                    .foregroundStyle(rowPrimaryColor)
                    .lineLimit(1)

                Spacer()

                if let brandName = snapshot.brandName {
                    Text(brandName)
                        .font(.caption)
                        .foregroundStyle(rowSecondaryColor)
                        .lineLimit(1)
                }

                if showOriginalPrice {
                    if snapshot.originalPrice > 0 {
                        Text("原价¥\(snapshot.originalPrice, format: .number.precision(.fractionLength(0)))")
                            .font(.caption)
                            .foregroundStyle(rowSecondaryColor)
                    }
                }

                if showPrice {
                    if snapshot.isDepositPlan {
                        // 注意：totalDeposit 和 totalBalance 已经包含了 stock 的乘法，所以这里直接使用
                        Text("定金¥\(snapshot.totalDeposit, format: .number.precision(.fractionLength(0)))+尾款¥\(snapshot.totalBalance, format: .number.precision(.fractionLength(0)))")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(rowAccentColor)
                    } else {
                        Text("¥\(snapshot.inventoryTotalPrice, format: .number.precision(.fractionLength(0)))")
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(rowPrimaryColor)
                    }
                }
            }
            .padding(16)
        }
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
