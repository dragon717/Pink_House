//
//  ClothingCard.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI

struct ClothingCard: View {
    let clothing: Clothing
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image Area
            ZStack(alignment: .topTrailing) {
                if let imagePath = clothing.imagePaths.first,
                   let uiImage = ImageManager.shared.loadImage(fileName: imagePath) {
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
                    Text("定尾计划")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(hex: "5D4037").opacity(0.8)) // Dark brown
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
            }
            
            // Info Area
            VStack(alignment: .leading, spacing: 4) {
                Text(clothing.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                if clothing.isDepositPlan {
                    Text("尾款: ¥\(clothing.balance, format: .number.precision(.fractionLength(2)))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.pink)
                } else {
                    Text("¥\(clothing.price, format: .number.precision(.fractionLength(2)))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "8D6E63")) // Brownish
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ClothingThumbnail: View {
    let clothing: Clothing
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let imagePath = clothing.imagePaths.first,
               let uiImage = ImageManager.shared.loadImage(fileName: imagePath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                CutePlaceholderView(iconSize: 14)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
