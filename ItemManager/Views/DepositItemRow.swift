//
//  DepositItemRow.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI

struct DepositItemRow: View {
    let clothing: Clothing
    @State private var isExpanded: Bool = false
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                // Top Section: Image + Basic Info
                HStack(alignment: .top, spacing: 12) {
                    // Image
                    if let imagePath = clothing.imagePaths.first,
                       let uiImage = ImageManager.shared.loadImage(fileName: imagePath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    }
                    
                    // Basic Info
                    VStack(alignment: .leading, spacing: 6) {
                        Text(clothing.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        if let brand = clothing.brand {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill") // Placeholder icon
                                    .font(.caption2)
                                Text(brand.name)
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        // Tags
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(clothing.types.split(separator: ","), id: \.self) { type in
                                    TagView(text: String(type))
                                }
                                ForEach(clothing.sizes.split(separator: ","), id: \.self) { size in
                                    TagView(text: String(size))
                                }
                                ForEach(clothing.colors.split(separator: ","), id: \.self) { color in
                                    TagView(text: String(color))
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                // Timeline Section
                VStack(spacing: 12) {
                    // Purchase/Deposit Info
                    TimelineRow(title: "定金", date: clothing.depositDate, trailing: "距离开始: 2天") // "2 days left" is hardcoded as logic is complex
                    
                    if isExpanded {
                        TimelineRow(title: "尾款", date: clothing.finalPaymentDate)
                    }
                    
                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text(isExpanded ? "收起" : "展开全部 (3个阶段)")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                // Note Section
                if !clothing.note.isEmpty {
                    Text("备注: \(clothing.note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Footer
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.orange)
                    Text("预估尾款时间: \(formatDate(clothing.finalPaymentDate))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    
                    Spacer()
                    
                    Button {
                        // Action
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.badge")
                            Text("备忘")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "5D4037"))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "待定" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }
}

struct TagView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct TimelineRow: View {
    let title: String
    let date: Date?
    var trailing: String? = nil
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 40, alignment: .leading)
            
            if let date = date {
                Text(formatDate(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("待定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let trailing = trailing {
                Text(trailing)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
