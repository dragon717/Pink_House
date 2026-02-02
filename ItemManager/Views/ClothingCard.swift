//
//  ClothingCard.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Foundation

struct ClothingCard: View, Equatable {
    static func == (lhs: ClothingCard, rhs: ClothingCard) -> Bool {
        return lhs.clothing.id == rhs.clothing.id &&
               lhs.clothing.name == rhs.clothing.name &&
               lhs.clothing.originalPrice == rhs.clothing.originalPrice &&
               lhs.clothing.price == rhs.clothing.price &&
               lhs.clothing.imagePaths == rhs.clothing.imagePaths &&
               lhs.clothing.stock == rhs.clothing.stock
    }
    
    let clothing: Clothing
    @AppStorage("privacyShowPrice") private var showPrice = true
    @AppStorage("privacyShowOriginalPrice") private var showOriginalPrice = true
    @State private var image: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image Area
            ZStack(alignment: .topTrailing) {
                if let uiImage = image {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    CutePlaceholderView()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .task {
                if let imagePath = clothing.imagePaths.first {
                    // 预估卡片宽度: 屏幕宽度/2 (Grid2) approx 180-200pt -> @2x 400px, @3x 600px
                    // Grid3 approx 120pt -> 360px
                    // Safe bet: 500x500
                    self.image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: CGSize(width: 500, height: 500))
                }
            }
            
            // Info Area
            VStack(alignment: .leading, spacing: 4) {
                Text(clothing.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                if showOriginalPrice && clothing.originalPrice > 0 {
                    Text("原价: ¥\(clothing.originalPrice, format: .number.precision(.fractionLength(0)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if showPrice {
                    if clothing.isDepositPlan {
                        let totalDeposit = clothing.deposit * Decimal(clothing.stock)
                        let totalBalance = clothing.balance * Decimal(clothing.stock)
                        Text("定金: ¥\(totalDeposit, format: .number.precision(.fractionLength(0))) + 尾款: ¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.pink)
                    } else {
                        let totalWithAccessories = (clothing.price + clothing.accessoriesPrice) * Decimal(clothing.stock)
                        Text("¥\(totalWithAccessories, format: .number.precision(.fractionLength(2)))")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: "8D6E63")) // Brownish
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
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
                            .scaledToFill()
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
                self.image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: CGSize(width: 200, height: 200))
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
                            .scaledToFill()
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
                        self.image = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: CGSize(width: 120, height: 120))
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
                            let totalDeposit = clothing.deposit * Decimal(clothing.stock)
                            let totalBalance = clothing.balance * Decimal(clothing.stock)
                            
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
                            .scaledToFill()
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
                        self.image = await ImageManager.shared.loadImageAsync(fileName: firstPath, targetSize: CGSize(width: 80, height: 80))
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
                    Text("原¥\(clothing.originalPrice, format: .number.precision(.fractionLength(0)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if showPrice {
                    if clothing.isDepositPlan {
                        let totalDeposit = clothing.deposit * Decimal(clothing.stock)
                        let totalBalance = clothing.balance * Decimal(clothing.stock)
                        Text("定¥\(totalDeposit, format: .number.precision(.fractionLength(0)))+尾¥\(totalBalance, format: .number.precision(.fractionLength(0)))")
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
