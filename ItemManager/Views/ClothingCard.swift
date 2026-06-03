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

private func wardrobeVisibleImageLoadPriority() -> TaskPriority {
    ProcessInfo.processInfo.physicalMemory <= 3_500_000_000 ? .utility : .userInitiated
}

private func deferVisibleWardrobeImageDecodeForFirstFrame() async {
    let delay: UInt64 = ProcessInfo.processInfo.physicalMemory <= 3_500_000_000
        ? 60_000_000
        : 30_000_000
    try? await Task.sleep(nanoseconds: delay)
}

private func wardrobeLocalizedNumber(_ value: Decimal, fractionLength: Int = 0) -> String {
    value.formatted(
        .number
            .precision(.fractionLength(fractionLength))
            .locale(LanguageManager.shared.locale)
    )
}

private func wardrobeCurrencyText(label: String, amount: Decimal, fractionLength: Int = 0) -> String {
    "%@¥%@".appLocalized(label, wardrobeLocalizedNumber(amount, fractionLength: fractionLength))
}

private func wardrobeCurrencyLineText(label: String, amount: Decimal, fractionLength: Int = 0) -> String {
    "%@: ¥%@".appLocalized(label, wardrobeLocalizedNumber(amount, fractionLength: fractionLength))
}

private func wardrobeLabelValueText(label: String, value: String) -> String {
    "%@: %@".appLocalized(label, value)
}

private func wardrobeDepositPlanSummary(deposit: Decimal, balance: Decimal) -> String {
    "\(wardrobeCurrencyText(label: "定金".appLocalized, amount: deposit))+\(wardrobeCurrencyText(label: "尾款".appLocalized, amount: balance))"
}

struct WardrobeCellSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let brandName: String?
    let originalPrice: Decimal
    let price: Decimal
    let imagePaths: [String]
    let stock: Int
    let isDepositPlan: Bool
    let isFullPaymentReservation: Bool
    let totalDeposit: Decimal
    let totalBalance: Decimal
    let fullPaymentReservationTotalAmount: Decimal
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
        self.isFullPaymentReservation = clothing.isFullPaymentReservation
        self.totalDeposit = clothing.wardrobeListTotalDeposit
        self.totalBalance = clothing.wardrobeListTotalBalance
        self.fullPaymentReservationTotalAmount = clothing.wardrobeListFullPaymentReservationTotalAmount
        self.inventoryTotalPrice = clothing.wardrobeListInventoryTotalPrice
        self.is3DModel = clothing.is3DModel
        self.model3DTypeDescription = clothing.model3DTypeDescription
        self.types = clothing.types
        self.colors = clothing.colors
        self.sizes = clothing.sizes
        self.tagNames = clothing.tags?.map(\.name) ?? []
    }
}

struct WardrobeCellThemeInputs: Hashable, Sendable {
    let cardStyleRawValue: String
    let skirtFillModeRawValue: String
    let isDarkMode: Bool
    let cardBackgroundHex: String
    let cardTintHex: String
    let transparentOpacity: Double
    let tintOpacity: Double

    nonisolated static let fallback = WardrobeCellThemeInputs(
        cardStyleRawValue: "solid",
        skirtFillModeRawValue: "transparent",
        isDarkMode: false,
        cardBackgroundHex: "#FFFFFF",
        cardTintHex: "#FFB6C1",
        transparentOpacity: 1.0,
        tintOpacity: 0.2
    )

    @MainActor
    static func current(themeManager: ThemeManager, colorScheme: ColorScheme) -> WardrobeCellThemeInputs {
        WardrobeCellThemeInputs(
            cardStyleRawValue: themeManager.cardStyle.rawValue,
            skirtFillModeRawValue: themeManager.skirtFillMode.rawValue,
            isDarkMode: colorScheme == .dark,
            cardBackgroundHex: themeManager.cardBackgroundColor.toHex(),
            cardTintHex: themeManager.cardTintColor.toHex(),
            transparentOpacity: themeManager.transparentOpacity,
            tintOpacity: themeManager.tintOpacity
        )
    }

    private var cardStyle: CardStyle {
        CardStyle(rawValue: cardStyleRawValue) ?? .solid
    }

    private var skirtFillMode: SkirtFillMode {
        SkirtFillMode(rawValue: skirtFillModeRawValue) ?? .transparent
    }

    private var cardBackgroundColor: Color {
        Color(hex: cardBackgroundHex)
    }

    private var cardTintColor: Color {
        Color(hex: cardTintHex)
    }

    var listCardFillColor: Color {
        switch cardStyle {
        case .fullyTransparent:
            return Color.clear
        case .transparent:
            return cardBackgroundColor.opacity(max(transparentOpacity, 0.18))
        case .tinted:
            return cardBackgroundColor.opacity(max(tintOpacity, 0.18))
        case .solid:
            return cardBackgroundColor
        }
    }

    var listCardStrokeColor: Color {
        cardTintColor.opacity(listCardStrokeOpacity)
    }

    private var listCardStrokeOpacity: Double {
        switch cardStyle {
        case .fullyTransparent:
            return 0.18
        case .transparent, .tinted:
            return 0.24
        case .solid:
            return 0.12
        }
    }

    var imageBackgroundColor: Color {
        switch skirtFillMode {
        case .transparent:
            return isDarkMode ? Color.black.opacity(0.2) : Color.white.opacity(0.4)
        case .fullyTransparent:
            return Color.clear
        case .tinted:
            return cardTintColor.opacity(isDarkMode ? 0.15 : 0.3)
        case .solid:
            return isDarkMode ? Color.black.opacity(0.6) : Color.white.opacity(0.8)
        }
    }
}

private struct WardrobeListCellContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let themeInputs: WardrobeCellThemeInputs
    let content: Content

    init(
        cornerRadius: CGFloat,
        padding: CGFloat,
        themeInputs: WardrobeCellThemeInputs = .fallback,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.themeInputs = themeInputs
        self.content = content()
    }

    var body: some View {
        ZStack {
            WardrobeListCellBackground(cornerRadius: cornerRadius, themeInputs: themeInputs)

            content
                .padding(padding)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
    }
}

struct WardrobeListCellBackground: View {
    let cornerRadius: CGFloat
    let themeInputs: WardrobeCellThemeInputs

    init(cornerRadius: CGFloat, themeInputs: WardrobeCellThemeInputs = .fallback) {
        self.cornerRadius = cornerRadius
        self.themeInputs = themeInputs
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(themeInputs.listCardFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(themeInputs.listCardStrokeColor, lineWidth: 1)
            )
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
        lhs.wardrobeThemeDescriptor == rhs.wardrobeThemeDescriptor &&
        lhs.imageTargetSize == rhs.imageTargetSize &&
        lhs.themeInputs == rhs.themeInputs
    }
    
    let snapshot: WardrobeCellSnapshot
    let showPrice: Bool
    let showOriginalPrice: Bool
    let wardrobeThemeDescriptor: ThemeSkinDescriptor?
    let imageTargetSize: CGSize
    let themeInputs: WardrobeCellThemeInputs
    
    @Environment(\.containerPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?

    @MainActor
    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true,
        imageTargetSize: CGSize = CGSize(width: 160, height: 160),
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: snapshot,
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: ThemeSkinManager.shared.descriptor(for: .wardrobeItemCard),
            imageTargetSize: imageTargetSize,
            themeInputs: themeInputs
        )
    }

    @MainActor
    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?,
        imageTargetSize: CGSize = CGSize(width: 160, height: 160),
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.snapshot = snapshot
        self.showPrice = showPrice
        self.showOriginalPrice = showOriginalPrice
        self.wardrobeThemeDescriptor = wardrobeThemeDescriptor
        self.imageTargetSize = imageTargetSize
        self.themeInputs = themeInputs
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true,
        imageTargetSize: CGSize = CGSize(width: 160, height: 160),
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            imageTargetSize: imageTargetSize,
            themeInputs: themeInputs
        )
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?,
        imageTargetSize: CGSize = CGSize(width: 160, height: 160),
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: wardrobeThemeDescriptor,
            imageTargetSize: imageTargetSize,
            themeInputs: themeInputs
        )
    }

    private var isThemeSkinThemed: Bool {
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(wardrobeThemeDescriptor)
    }

    private var imageTaskKey: String {
        "\(snapshot.firstImagePath ?? "nil")_\(Int(imageTargetSize.width))x\(Int(imageTargetSize.height))"
    }

    private var titleColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor, colorScheme: colorScheme) : palette.primary
    }

    private var themedSecondaryColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor, colorScheme: colorScheme).opacity(0.78) : palette.secondary
    }

    private var themedAccentColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.accent(for: wardrobeThemeDescriptor, colorScheme: colorScheme) : palette.accent
    }

    private var showsCompactPriceInfo: Bool {
        (showOriginalPrice && snapshot.originalPrice > 0 && !snapshot.isDepositPlan) || showPrice
    }

    private var compactPriceSurfaceFill: Color {
        isThemeSkinThemed ? themedAccentColor.opacity(0.14) : themedAccentColor.opacity(0.08)
    }

    private var compactPriceSurfaceStroke: Color {
        isThemeSkinThemed ? themedAccentColor.opacity(0.28) : themedAccentColor.opacity(0.16)
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
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(badgeForegroundColor(for: tint))
        .themeSkinLegibleText(level: .chip, slot: .discountBadge, descriptor: wardrobeThemeDescriptor)
        .background(badgeFillColor(for: tint))
        .clipShape(Capsule())
    }
    
    var body: some View {
        WardrobeThemeClothingCardContainer(
            descriptor: wardrobeThemeDescriptor,
            scrollOptimized: true,
            themeInputs: themeInputs
        ) {
            VStack(alignment: .leading, spacing: 0) {
                // Image Area
                ZStack(alignment: .topTrailing) {
                    // Background Fill
                    themeInputs.imageBackgroundColor
                    
                    if let uiImage = image {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .interpolation(.medium)
                                    .scaledToFit()
                            )
                            .clipped()
                    } else {
                        // 使用支持主题配色的占位图
                        ThemedPlaceholderView(themeInputs: themeInputs)
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
                            text: snapshot.isFullPaymentReservation ? "全款预约".appLocalized : "心愿尾款".appLocalized,
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
                .task(id: imageTaskKey) {
                    if let imagePath = snapshot.firstImagePath {
                        let size = imageTargetSize
                        if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                            self.image = cached
                            return
                        }
                        if Task.isCancelled { return }
                        await deferVisibleWardrobeImageDecodeForFirstFrame()
                        if Task.isCancelled { return }
                        let loadedImage = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size, priority: wardrobeVisibleImageLoadPriority())
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
                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 4)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if showOriginalPrice && snapshot.originalPrice > 0 && !snapshot.isDepositPlan {
                            Text(wardrobeCurrencyText(label: "原价".appLocalized, amount: snapshot.originalPrice))
                                .font(.system(size: 10))
                                .strikethrough()
                                .foregroundStyle(themedSecondaryColor)
                                .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                        }
                        
                        if showPrice {
                            if snapshot.isDepositPlan {
                                if snapshot.isFullPaymentReservation {
                                    Text(wardrobeCurrencyText(label: "全款".appLocalized, amount: snapshot.fullPaymentReservationTotalAmount))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(themedAccentColor)
                                        .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                } else {
                                    let totalDeposit = snapshot.totalDeposit
                                    let totalBalance = snapshot.totalBalance
                                    HStack(spacing: 4) {
                                        Text(wardrobeCurrencyText(label: "定金".appLocalized, amount: totalDeposit))
                                        Text(wardrobeCurrencyText(label: "尾款".appLocalized, amount: totalBalance))
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(themedAccentColor)
                                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                }
                            } else {
                                let totalWithAccessories = snapshot.inventoryTotalPrice
                                Text("¥\(totalWithAccessories, format: .number.precision(.fractionLength(2)))")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(titleColor)
                                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                            }
                        }
                    }
                    .padding(.horizontal, showsCompactPriceInfo ? 6 : 0)
                    .padding(.vertical, showsCompactPriceInfo ? 5 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if showsCompactPriceInfo {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(compactPriceSurfaceFill)
                        }
                    }
                    .overlay {
                        if showsCompactPriceInfo {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(compactPriceSurfaceStroke, lineWidth: 0.7)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(height: 60)
            }
        }
    }
}

struct ClothingThumbnail: View, Equatable {
    static func == (lhs: ClothingThumbnail, rhs: ClothingThumbnail) -> Bool {
        lhs.snapshot == rhs.snapshot &&
        lhs.imageTargetSize == rhs.imageTargetSize &&
        lhs.themeInputs == rhs.themeInputs
    }
    
    let snapshot: WardrobeCellSnapshot
    let imageTargetSize: CGSize
    let themeInputs: WardrobeCellThemeInputs
    @State private var image: UIImage?

    init(
        snapshot: WardrobeCellSnapshot,
        imageTargetSize: CGSize = CGSize(width: 64, height: 64),
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.snapshot = snapshot
        self.imageTargetSize = imageTargetSize
        self.themeInputs = themeInputs
    }

    @MainActor
    init(
        clothing: Clothing,
        imageTargetSize: CGSize = CGSize(width: 64, height: 64),
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            imageTargetSize: imageTargetSize,
            themeInputs: themeInputs
        )
    }

    private var imageTaskKey: String {
        "\(snapshot.firstImagePath ?? "nil")_\(Int(imageTargetSize.width))x\(Int(imageTargetSize.height))"
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let uiImage = image {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(uiImage: uiImage)
                            .resizable()
                            .interpolation(.low)
                            .scaledToFit()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                // 使用主题色的占位图，保持配色统一
                ThemedPlaceholderView(iconSize: 14, themeInputs: themeInputs)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .task(id: imageTaskKey) {
            if let imagePath = snapshot.firstImagePath {
                let size = imageTargetSize
                if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                    self.image = cached
                    return
                }
                if Task.isCancelled { return }
                await deferVisibleWardrobeImageDecodeForFirstFrame()
                if Task.isCancelled { return }
                let loadedImage = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size, priority: wardrobeVisibleImageLoadPriority())
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
    let themeInputs: WardrobeCellThemeInputs
    
    @Environment(\.containerPalette) private var palette

    init(iconSize: CGFloat = 30, themeInputs: WardrobeCellThemeInputs = .fallback) {
        self.iconSize = iconSize
        self.themeInputs = themeInputs
    }
    
    var body: some View {
        ZStack {
            // 背景根据当前配色模式调整
            themeInputs.imageBackgroundColor
            
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
        lhs.wardrobeThemeDescriptor == rhs.wardrobeThemeDescriptor &&
        lhs.themeInputs == rhs.themeInputs
    }

    let snapshot: WardrobeCellSnapshot
    let showPrice: Bool
    let showOriginalPrice: Bool
    let wardrobeThemeDescriptor: ThemeSkinDescriptor?
    let themeInputs: WardrobeCellThemeInputs

    @Environment(\.containerPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?

    @MainActor
    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true,
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: snapshot,
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: ThemeSkinManager.shared.descriptor(for: .wardrobeItemCard),
            themeInputs: themeInputs
        )
    }

    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?,
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.snapshot = snapshot
        self.showPrice = showPrice
        self.showOriginalPrice = showOriginalPrice
        self.wardrobeThemeDescriptor = wardrobeThemeDescriptor
        self.themeInputs = themeInputs
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true,
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            themeInputs: themeInputs
        )
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?,
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: wardrobeThemeDescriptor,
            themeInputs: themeInputs
        )
    }

    private var isThemeSkinThemed: Bool {
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(wardrobeThemeDescriptor)
    }

    private var rowPrimaryColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor, colorScheme: colorScheme) : palette.primary
    }

    private var rowSecondaryColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor, colorScheme: colorScheme).opacity(0.76) : palette.secondary
    }

    private var rowAccentColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.accent(for: wardrobeThemeDescriptor, colorScheme: colorScheme) : palette.accent
    }

    private var showsRowPriceInfo: Bool {
        (showOriginalPrice && snapshot.originalPrice > 0) || showPrice || snapshot.stock > 1
    }

    private var rowPriceSurfaceFill: Color {
        isThemeSkinThemed ? rowAccentColor.opacity(0.12) : rowAccentColor.opacity(0.07)
    }

    private var rowPriceSurfaceStroke: Color {
        isThemeSkinThemed ? rowAccentColor.opacity(0.24) : rowAccentColor.opacity(0.14)
    }
    
    var body: some View {
        WardrobeThemeClothingCardContainer(
            cornerRadius: 24,
            descriptor: wardrobeThemeDescriptor,
            scrollOptimized: true,
            themeInputs: themeInputs
        ) {
            HStack(spacing: 16) {
                // Thumbnail
                ZStack {
                    if let uiImage = image {
                        Image(uiImage: uiImage)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        // 使用支持主题配色的占位图
                        ThemedPlaceholderView(iconSize: 24, themeInputs: themeInputs)
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
                        await deferVisibleWardrobeImageDecodeForFirstFrame()
                        if Task.isCancelled { return }
                        let loadedImage = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: size, priority: wardrobeVisibleImageLoadPriority())
                        if Task.isCancelled { return }
                        self.image = loadedImage
                    } else {
                        // 当图片被全部删除时，清空 image 以显示占位图
                        self.image = nil
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if snapshot.isDepositPlan {
                        Text(snapshot.isFullPaymentReservation ? "全款".appLocalized : "尾款".appLocalized)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .themeSkinLegibleText(level: .chip, slot: .discountBadge, descriptor: wardrobeThemeDescriptor)
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
                        .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                    
                    // Attribute Display: Type, Color, Size
                    HStack(spacing: 6) {
                        if !snapshot.types.isEmpty {
                            AttributePill(text: snapshot.types, icon: "tshirt", color: rowAccentColor, themeSkinDescriptor: wardrobeThemeDescriptor)
                        }
                        if !snapshot.colors.isEmpty {
                            AttributePill(text: snapshot.colors, icon: "paintpalette", color: rowSecondaryColor, themeSkinDescriptor: wardrobeThemeDescriptor)
                        }
                        if !snapshot.sizes.isEmpty {
                            AttributePill(text: snapshot.sizes, icon: "ruler", color: isThemeSkinThemed ? rowAccentColor.opacity(0.82) : palette.tertiary, themeSkinDescriptor: wardrobeThemeDescriptor)
                        }
                    }
                    
                    if !snapshot.tagNames.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(snapshot.tagNames.prefix(3).enumerated()), id: \.offset) { _, tagName in
                                Text("#\(tagName)")
                                    .font(.caption2)
                                    .foregroundStyle(isThemeSkinThemed ? rowSecondaryColor : palette.tertiary)
                                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                            }
                            if snapshot.tagNames.count > 3 {
                                Text("...")
                                    .font(.caption2)
                                    .foregroundStyle(isThemeSkinThemed ? rowSecondaryColor : palette.tertiary)
                                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if showOriginalPrice && snapshot.originalPrice > 0 {
                        Text(wardrobeCurrencyLineText(label: "原价".appLocalized, amount: snapshot.originalPrice))
                            .font(.caption2)
                            .foregroundStyle(rowSecondaryColor)
                            .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                    }
                    
                    if showPrice {
                        if snapshot.isDepositPlan {
                            if snapshot.isFullPaymentReservation {
                                Text("全款预约".appLocalized)
                                    .font(.caption2)
                                    .foregroundStyle(rowAccentColor)
                                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Text("¥\(snapshot.fullPaymentReservationTotalAmount, format: .number.precision(.fractionLength(0)))")
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(rowAccentColor)
                                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                            } else {
                                // 注意：totalDeposit 和 totalBalance 已经包含了 stock 的乘法，所以这里直接使用
                                let totalDeposit = snapshot.totalDeposit
                                let totalBalance = snapshot.totalBalance

                                Text(wardrobeCurrencyLineText(label: "定金".appLocalized, amount: totalDeposit))
                                    .font(.caption)
                                    .foregroundStyle(rowAccentColor)
                                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                                Text(wardrobeCurrencyLineText(label: "尾款".appLocalized, amount: totalBalance))
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(rowAccentColor)
                                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                            }
                        } else {
                            let totalWithAccessories = snapshot.inventoryTotalPrice
                            
                            Text(wardrobeCurrencyLineText(label: "合计".appLocalized, amount: totalWithAccessories))
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(rowPrimaryColor)
                                .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                        }
                    }
                    
                    if snapshot.stock > 1 {
                        Text(wardrobeLabelValueText(label: "库存".appLocalized, value: "\(snapshot.stock)"))
                            .font(.caption)
                            .foregroundStyle(isThemeSkinThemed ? rowSecondaryColor : palette.tertiary)
                            .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                    }
                }
                .padding(.horizontal, showsRowPriceInfo ? 8 : 0)
                .padding(.vertical, showsRowPriceInfo ? 6 : 0)
                .background(alignment: .trailing) {
                    if showsRowPriceInfo {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(rowPriceSurfaceFill)
                    }
                }
                .overlay {
                    if showsRowPriceInfo {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(rowPriceSurfaceStroke, lineWidth: 0.7)
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
        lhs.wardrobeThemeDescriptor == rhs.wardrobeThemeDescriptor &&
        lhs.themeInputs == rhs.themeInputs
    }

    let snapshot: WardrobeCellSnapshot
    let showPrice: Bool
    let showOriginalPrice: Bool
    let wardrobeThemeDescriptor: ThemeSkinDescriptor?
    let themeInputs: WardrobeCellThemeInputs

    @Environment(\.containerPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?

    @MainActor
    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true,
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: snapshot,
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: ThemeSkinManager.shared.descriptor(for: .wardrobeItemCard),
            themeInputs: themeInputs
        )
    }

    init(
        snapshot: WardrobeCellSnapshot,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?,
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.snapshot = snapshot
        self.showPrice = showPrice
        self.showOriginalPrice = showOriginalPrice
        self.wardrobeThemeDescriptor = wardrobeThemeDescriptor
        self.themeInputs = themeInputs
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowPrice") as? Bool ?? true,
        showOriginalPrice: Bool = UserDefaults.standard.object(forKey: "privacyShowOriginalPrice") as? Bool ?? true,
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            themeInputs: themeInputs
        )
    }

    @MainActor
    init(
        clothing: Clothing,
        showPrice: Bool,
        showOriginalPrice: Bool,
        wardrobeThemeDescriptor: ThemeSkinDescriptor?,
        themeInputs: WardrobeCellThemeInputs = .fallback
    ) {
        self.init(
            snapshot: WardrobeCellSnapshot(clothing: clothing),
            showPrice: showPrice,
            showOriginalPrice: showOriginalPrice,
            wardrobeThemeDescriptor: wardrobeThemeDescriptor,
            themeInputs: themeInputs
        )
    }

    private var isThemeSkinThemed: Bool {
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(wardrobeThemeDescriptor)
    }

    private var rowPrimaryColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor, colorScheme: colorScheme) : palette.primary
    }

    private var rowSecondaryColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.labelColor(for: wardrobeThemeDescriptor, colorScheme: colorScheme).opacity(0.76) : palette.secondary
    }

    private var rowAccentColor: Color {
        isThemeSkinThemed ? SkyConcertThemeSkin.accent(for: wardrobeThemeDescriptor, colorScheme: colorScheme) : palette.accent
    }
    
    var body: some View {
        WardrobeThemeClothingCardContainer(
            cornerRadius: 24,
            descriptor: wardrobeThemeDescriptor,
            scrollOptimized: true,
            themeInputs: themeInputs
        ) {
            HStack(spacing: 12) {
                // Thumbnail (Smaller)
                ZStack {
                    if let uiImage = image {
                        Image(uiImage: uiImage)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        // 使用支持主题配色的占位图
                        ThemedPlaceholderView(iconSize: 16, themeInputs: themeInputs)
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
                    await deferVisibleWardrobeImageDecodeForFirstFrame()
                    if Task.isCancelled { return }
                    let loadedImage = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: size, priority: wardrobeVisibleImageLoadPriority())
                    if Task.isCancelled { return }
                    self.image = loadedImage
                }
                
                Text(snapshot.name)
                    .font(.body)
                    .foregroundStyle(rowPrimaryColor)
                    .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                    .lineLimit(1)

                Spacer()

                if let brandName = snapshot.brandName {
                    Text(brandName)
                        .font(.caption)
                        .foregroundStyle(rowSecondaryColor)
                        .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                        .lineLimit(1)
                }

                if showOriginalPrice {
                    if snapshot.originalPrice > 0 {
                        Text(wardrobeCurrencyText(label: "原价".appLocalized, amount: snapshot.originalPrice))
                            .font(.caption)
                            .foregroundStyle(rowSecondaryColor)
                            .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                    }
                }

                if showPrice {
                    if snapshot.isDepositPlan {
                        Text(snapshot.isFullPaymentReservation
                             ? wardrobeCurrencyText(label: "全款".appLocalized, amount: snapshot.fullPaymentReservationTotalAmount)
                             : wardrobeDepositPlanSummary(deposit: snapshot.totalDeposit, balance: snapshot.totalBalance))
                            .font(.caption)
                            .bold()
                            .foregroundStyle(rowAccentColor)
                            .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
                    } else {
                        Text("¥\(snapshot.inventoryTotalPrice, format: .number.precision(.fractionLength(0)))")
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(rowPrimaryColor)
                            .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: wardrobeThemeDescriptor)
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
    var themeSkinDescriptor: ThemeSkinDescriptor? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text.replacingOccurrences(of: "\n", with: " "))
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .truncationMode(.tail)
                .allowsTightening(true)
        }
        .themeSkinLegibleText(level: .inline, slot: .wardrobeItemCard, descriptor: themeSkinDescriptor)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .foregroundStyle(color == .secondary ? .secondary : color)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
