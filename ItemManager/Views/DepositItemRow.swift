//
//  DepositItemRow.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData

struct DepositItemRow: View {
    @Environment(\.modelContext) private var modelContext
    let clothing: Clothing
    @State private var isExpanded: Bool = false
    @State private var showEditNoteAlert: Bool = false
    @State private var editingNote: String = ""
    
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
                        CutePlaceholderView(iconSize: 24)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        
                        Text("定¥\(clothing.deposit.formatted(.number.precision(.fractionLength(0)))) + 尾¥\(clothing.balance.formatted(.number.precision(.fractionLength(0))))")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.pink)
                        
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
                    if isExpanded {
                        // Phase 1: Purchase
                        TimelineRow(title: "下单", date: clothing.purchaseDate)
                    }
                    
                    // Phase 2: Deposit (Always shown or shown as part of list)
                    // If collapsed, we only show Deposit. If expanded, we show it in order.
                    // Actually, the screenshot shows "Deposit" at the top even when collapsed.
                    // So we keep "Deposit" always visible, but maybe its position implies order?
                    // Let's stick to the screenshot: "Deposit" is the main row.
                    
                    TimelineRow(title: "定金", date: clothing.depositDate, trailing: getDepositTimeStatus())
                    
                    if isExpanded {
                        // Phase 3: Final Payment
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
                        editingNote = clothing.note
                        showEditNoteAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                            Text("修改备注")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "5D4037"))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .alert("修改备注", isPresented: $showEditNoteAlert) {
                        TextField("请输入备注", text: $editingNote)
                        Button("取消", role: .cancel) { }
                        Button("保存") {
                            clothing.note = editingNote
                            try? modelContext.save()
                        }
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
    
    private func getDepositTimeStatus() -> String? {
        guard let date = clothing.depositDate else { return nil }
        let now = Date()
        let calendar = Calendar.current
        
        // Calculate days between now and target date
        let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date))
        
        if let days = components.day {
            if days > 0 {
                return "距离开始: \(days)天"
            } else if days == 0 {
                // Check if it's future time today or past time today
                if date > now {
                    return "即将开始"
                } else {
                    return "已开始: 今天"
                }
            } else {
                return "已开始: \(abs(days))天"
            }
        }
        return nil
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
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
