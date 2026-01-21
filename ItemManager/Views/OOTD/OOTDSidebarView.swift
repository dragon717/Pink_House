
import SwiftUI
import SwiftData

struct OOTDSidebarView: View {
    @Binding var isVisible: Bool
    @Binding var currentOutfit: Outfit?
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @Environment(\.modelContext) private var modelContext
    
    var onAdd: () -> Void
    var onDelete: (Outfit) -> Void
    
    // Namespace for matched geometry effect (optional, but nice for animations)
    @Namespace private var animation
    
    @State private var outfitToDelete: Outfit?
    @State private var showingDeleteAlert = false
    
    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                // Header Area
                HStack {
                    Text("我的搭配")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                // .background(.ultraThinMaterial) // iOS 18 style glass header
                
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // New Outfit Button - Modern Card Style
                        Button(action: onAdd) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.1))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                
                                Text("新建搭配")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        // Outfit List
                        ForEach(outfits) { outfit in
                            OutfitCard(
                                outfit: outfit,
                                isSelected: currentOutfit?.id == outfit.id,
                                onDelete: {
                                    outfitToDelete = outfit
                                    showingDeleteAlert = true
                                }
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    currentOutfit = outfit
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: 280)
            .background(Color(uiColor: .systemBackground))
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1),
                    alignment: .trailing
            )
            .transition(.move(edge: .leading).combined(with: .opacity))
            .alert("删除搭配", isPresented: $showingDeleteAlert, presenting: outfitToDelete) { outfit in
                Button("删除", role: .destructive) {
                    onDelete(outfit)
                    outfitToDelete = nil
                }
                Button("取消", role: .cancel) {
                    outfitToDelete = nil
                }
            } message: { outfit in
                Text("确定要删除搭配“\(outfit.note.isEmpty ? "未命名" : outfit.note)”吗？此操作无法撤销。")
            }
        }
    }
}

struct OutfitCard: View {
    let outfit: Outfit
    let isSelected: Bool
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let snapshotPath = outfit.snapshotPath,
                       let uiImage = ImageManager.shared.loadImage(fileName: snapshotPath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color(uiColor: .tertiarySystemFill)
                            Image(systemName: "tshirt")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(outfit.note.isEmpty ? "未命名搭配" : outfit.note)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(outfit.createdAt.formatted(date: .numeric, time: .shortened))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                        .padding(.trailing, 8)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            
            // Delete Button (Top Right corner)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.red.gradient)
                    .clipShape(Circle())
                    .shadow(color: .red.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .offset(x: 6, y: -6)
            .opacity(isSelected || isHovering ? 1 : 0) // Show when selected or potentially hovered (though hover is macos mostly)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .contentShape(Rectangle()) // Better hit testing
    }
}
