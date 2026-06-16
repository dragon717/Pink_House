//
//  BookPageShareCardView.swift
//  ItemManager
//
//  书页分享卡片视图 - 只有正面，展示书页缩略图和书页名
//  使用莫妮卡色系配色方案
//

import SwiftUI
import SwiftData

// MARK: - 书页分享卡片视图（只有正面）
struct BookPageShareCardView: View {
    let pageName: String
    let thumbnailImage: UIImage?
    let bookName: String?
    let createDate: Date?
    let cardBackground: UIImage?
    @Environment(\.fontProvider) var fontProvider: FontProvider
    
    var body: some View {
        ZStack {
            // card_front 背景 - 不透明
            if let bg = cardBackground {
                Image(uiImage: bg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // 默认莫妮卡色系背景
                MonicaColors.cardGradient
            }
            
            // 内容卡片 - 透明背景
            VStack(spacing: 16) {
                // 书页缩略图
                if let img = thumbnailImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 220, height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: MonicaColors.primaryPink.opacity(0.2), radius: 8, x: 0, y: 4)
                } else {
                    // 占位图
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 220, height: 300)
                        .overlay(
                            VStack(spacing: 10) {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 48))
                                    .foregroundColor(MonicaColors.primaryPink.opacity(0.4))
                                Text("书页预览".appLocalized)
                                    .font(fontProvider.bodyFont())
                                    .foregroundColor(MonicaColors.mediumText)
                            }
                        )
                }
                
                // 书页名 - 粉边白边，与图片等宽
                Text(pageName)
                    .font(fontProvider.titleFont())
                    .pinkStrokeText(strokeWidth: 3, strokeColor: MonicaColors.primaryPink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 220)
                
                Spacer()
            }
            .padding(16)
            .frame(width: 260, height: 420)
            .background(Color.clear)
        }
        .frame(width: 280, height: 440)
        .cornerRadius(16)
    }
}

// MARK: - 平面书页分享卡片（Outfit）
struct OutfitShareCardView: View {
    let outfit: Outfit
    let cardBackground: UIImage?
    
    var thumbnailImage: UIImage? {
        guard outfit.shouldUseStoredSnapshot,
              let path = outfit.snapshotPath else { return nil }
        return ImageManager.shared.loadImage(fileName: path)
    }
    
    var body: some View {
        BookPageShareCardView(
            pageName: outfit.note.isEmpty ? "未命名书页" : outfit.note,
            thumbnailImage: thumbnailImage,
            bookName: outfit.book?.title,
            createDate: outfit.createdAt,
            cardBackground: cardBackground
        )
    }
}

// MARK: - 空间书页分享卡片（SpaceOutfit）
struct SpaceOutfitShareCardView: View {
    let outfit: SpaceOutfit
    let cardBackground: UIImage?
    
    var thumbnailImage: UIImage? {
        guard let path = outfit.snapshotPath else { return nil }
        return ImageManager.shared.loadImage(fileName: path)
    }
    
    var body: some View {
        BookPageShareCardView(
            pageName: outfit.note.isEmpty ? "未命名空间书页" : outfit.note,
            thumbnailImage: thumbnailImage,
            bookName: outfit.book?.title,
            createDate: outfit.createdAt,
            cardBackground: cardBackground
        )
    }
}

// MARK: - 预览
#Preview {
    BookPageShareCardView(
        pageName: "春日穿搭",
        thumbnailImage: nil,
        bookName: "日常OOTD",
        createDate: Date(),
        cardBackground: nil
    )
}
