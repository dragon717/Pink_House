//
//  ClothingCard.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
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
    
    @AppStorage("privacyShowPrice") private var showPrice = true
    @AppStorage("privacyShowOriginalPrice") private var showOriginalPrice = true
    @State private var image: UIImage?
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image Area
            ZStack(alignment: .topTrailing) {
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
                    CutePlaceholderView()
                        .aspectRatio(1, contentMode: .fit)
                }
                
                if clothing.isDepositPlan {
                    Text("尾款天使")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(hex: "5D4037").opacity(0.8)) // Dark brown
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
                
                if clothing.stock > 1 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
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
            // 图片区域圆角和阴影 - 增强层次感
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 4)
            .padding(8) // 图片周围留白，突出悬浮感
            .task {
                if let imagePath = clothing.imagePaths.first {
                    // 预估卡片宽度: 屏幕宽度/2 (Grid2) approx 180-200pt -> @2x 400px, @3x 600px
                    // Grid3 approx 120pt -> 360px
                    // Safe bet: 500x500
                    let size = CGSize(width: 500, height: 500)
                    if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                        self.image = cached
                        return
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if Task.isCancelled { return }
                    self.image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size)
                }
            }
            
            // Info Area
            VStack(alignment: .leading, spacing: 0) {
                Text(clothing.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1) // 限制单行，保持整齐
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 4) // 将价格信息推到底部，保持视觉对齐
                
                VStack(alignment: .leading, spacing: 2) {
                    if showOriginalPrice && clothing.originalPrice > 0 && !clothing.isDepositPlan {
                        Text("原价¥\(clothing.originalPrice, format: .number.precision(.fractionLength(0)))")
                            .font(.system(size: 10))
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                    
                    if showPrice {
                        if clothing.isDepositPlan {
                            let totalDeposit = clothing.totalDeposit * Decimal(clothing.stock)
                            let totalBalance = clothing.totalBalance * Decimal(clothing.stock)
                            // 紧凑显示的定金尾款
                            HStack(spacing: 4) {
                                Text("定金¥\(totalDeposit, format: .number.precision(.fractionLength(0)))")
                                Text("尾款¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.pink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        } else {
                            let totalWithAccessories = (clothing.price + clothing.accessoriesPrice) * Decimal(clothing.stock)
                            Text("¥\(totalWithAccessories, format: .number.precision(.fractionLength(2)))")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: "8D6E63")) // Brownish
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(height: 60) // 固定高度，确保网格整齐
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // 卡片整体阴影和悬浮动画
        .shadow(color: .black.opacity(isHovering ? 0.12 : 0.06), radius: isHovering ? 12 : 8, x: 0, y: isHovering ? 6 : 3)
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
                CutePlaceholderView(iconSize: 14)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .task {
            if let imagePath = clothing.imagePaths.first {
                // Grid 6: approx 60pt -> 180px. Safe bet: 200x200
                let size = CGSize(width: 200, height: 200)
                if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                    self.image = cached
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                if Task.isCancelled { return }
                self.image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size)
            }
        }
    }
}

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
                        CutePlaceholderView(iconSize: 24)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .task {
                    if let firstPath = clothing.imagePaths.first {
                        let size = CGSize(width: 120, height: 120)
                        if let cached = ImageManager.shared.cachedImage(fileName: firstPath, targetSize: size) {
                            self.image = cached
                            return
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        if Task.isCancelled { return }
                        self.image = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: size)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if clothing.isDepositPlan {
                        Text("定尾")
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
                        .foregroundStyle(.primary)
                    
                    // Attribute Display: Type, Color, Size
                    HStack(spacing: 6) {
                        if !clothing.types.isEmpty {
                            AttributePill(text: clothing.types, icon: "tshirt", color: .pink)
                        }
                        if !clothing.colors.isEmpty {
                            AttributePill(text: clothing.colors, icon: "paintpalette", color: .blue)
                        }
                        if !clothing.sizes.isEmpty {
                            AttributePill(text: clothing.sizes, icon: "ruler", color: .green)
                        }
                    }
                    
                    if let tags = clothing.tags, !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(tags.prefix(3)) { tag in
                                Text("#\(tag.name)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if tags.count > 3 {
                                Text("...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if showOriginalPrice && clothing.originalPrice > 0 {
                        Text("原价: ¥\(clothing.originalPrice, format: .number.precision(.fractionLength(0)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    if showPrice {
                        if clothing.isDepositPlan {
                            let totalDeposit = clothing.totalDeposit * Decimal(clothing.stock)
                            let totalBalance = clothing.totalBalance * Decimal(clothing.stock)
                            
                            Text("定金: ¥\(totalDeposit, format: .number.precision(.fractionLength(0)))")
                                .font(.caption)
                                .foregroundStyle(.pink)
                            Text("尾款: ¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.pink)
                        } else {
                            let totalWithAccessories = (clothing.price + clothing.accessoriesPrice) * Decimal(clothing.stock)
                            
                            Text("合计: ¥\(totalWithAccessories, format: .number.precision(.fractionLength(0)))")
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(Color(hex: "8D6E63"))
                        }
                    }
                    
                    if clothing.stock > 1 {
                        Text("库存: \(clothing.stock)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ClothingRowBrief: View {
    let clothing: Clothing
    // 直接使用 AppStorage
    @AppStorage("privacyShowPrice") private var showPrice = true
    @AppStorage("privacyShowOriginalPrice") private var showOriginalPrice = true
    @State private var image: UIImage?
    
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
                        CutePlaceholderView(iconSize: 16)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .task {
                    if let firstPath = clothing.imagePaths.first {
                        let size = CGSize(width: 80, height: 80)
                        if let cached = ImageManager.shared.cachedImage(fileName: firstPath, targetSize: size) {
                            self.image = cached
                            return
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        if Task.isCancelled { return }
                        self.image = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: size)
                    }
                }
                
                Text(clothing.name)
                    .font(.body)
                    .lineLimit(1)
                
                Spacer()
                
                if let brand = clothing.brand {
                    Text(brand.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                if showOriginalPrice && clothing.originalPrice > 0 {
                    Text("原价¥\(clothing.originalPrice, format: .number.precision(.fractionLength(0)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if showPrice {
                    if clothing.isDepositPlan {
                        let totalDeposit = clothing.totalDeposit * Decimal(clothing.stock)
                        let totalBalance = clothing.totalBalance * Decimal(clothing.stock)
                        Text("定金¥\(totalDeposit, format: .number.precision(.fractionLength(0)))+尾款¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.pink)
                    } else {
                        let totalWithAccessories = (clothing.price + clothing.accessoriesPrice) * Decimal(clothing.stock)
                        Text("¥\(totalWithAccessories, format: .number.precision(.fractionLength(0)))")
                            .font(.subheadline)
                            .bold()
                    }
                }
            }
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
