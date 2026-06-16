//
//  CanvasStickerBarView.swift
//  ItemManager
//
//  画布顶部贴纸管理栏 - 显示已添加的抠图贴纸列表
//  支持点击列表项选中画布上对应的贴纸
//

import SwiftUI
import SwiftData

/// 画布顶部贴纸管理栏
struct CanvasStickerBarView: View {
    @Bindable var outfit: Outfit
    @Binding var selectedItemId: UUID?
    
    // 回调
    var onDeleteItem: (OutfitItem) -> Void
    var onBringToFront: (OutfitItem) -> Void
    
    // 显示状态
    @State private var isVisible = true
    
    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                VStack(spacing: 0) {
                    // 标题栏
                    HStack {
                        Image(systemName: "photo.fill.on.rectangle.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                        
                        Text("已添加贴纸".appLocalized)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(outfit.items?.count ?? 0)/20")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.pink.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    Divider()
                    
                    // 贴纸列表
                    if outfit.items?.isEmpty ?? true {
                        emptyView
                    } else {
                        stickerList
                    }
                }
                .background(.ultraThinMaterial)
                .background(Color(UIColor.systemBackground).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 显示/隐藏按钮
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isVisible.toggle()
                }
            } label: {
                Image(systemName: isVisible ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
            }
            .padding(.top, isVisible ? 8 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // 下滑手势隐藏
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height > 50 && isVisible {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isVisible = false
                        }
                    } else if value.translation.height < -50 && !isVisible {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isVisible = true
                        }
                    }
                }
        )
    }
    
    // MARK: - 空状态
    private var emptyView: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("还没有贴纸".appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.vertical, 20)
            Spacer()
        }
    }
    
    // MARK: - 贴纸列表
    private var stickerList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach((outfit.items ?? []).sorted(by: { $0.zIndex < $1.zIndex })) { item in
                    StickerThumbnailCell(
                        item: item,
                        isSelected: selectedItemId == item.id,
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedItemId = item.id
                            }
                        },
                        onDelete: {
                            onDeleteItem(item)
                        },
                        onBringToFront: {
                            onBringToFront(item)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(height: 90)
    }
}

// MARK: - 贴纸缩略图单元格
struct StickerThumbnailCell: View {
    @Bindable var item: OutfitItem
    let isSelected: Bool
    
    let onTap: () -> Void
    let onDelete: () -> Void
    let onBringToFront: () -> Void
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // 背景
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.pink.opacity(0.15) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 2)
                    )
                
                // 图片内容
                Group {
                    if let uiImage = loadedImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    } else if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                
                // 选中指示器
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.pink)
                                .background(Circle().fill(Color(UIColor.systemBackground)))
                        }
                        Spacer()
                    }
                    .padding(4)
                }
                
                // 序号标签
                VStack {
                    HStack {
                        Text("\(item.zIndex + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(4)
            }
            .frame(width: 70, height: 70)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onBringToFront()
            } label: {
                Label("置于顶层".appLocalized, systemImage: "arrow.up.to.line")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除".appLocalized, systemImage: "trash")
            }
        }
        .task(id: item.cutout?.imagePath) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let cutout = item.cutout, !cutout.imagePath.isEmpty else {
            isLoading = false
            loadedImage = nil
            return
        }
        
        isLoading = true
        if let image = await ImageManager.shared.loadImageAsync(fileName: cutout.imagePath) {
            loadedImage = image
        } else {
            loadedImage = nil
        }
        isLoading = false
    }
}

// MARK: - 预览
#Preview {
    CanvasStickerBarView(
        outfit: Outfit(note: "测试"),
        selectedItemId: .constant(nil),
        onDeleteItem: { _ in },
        onBringToFront: { _ in }
    )
    .frame(height: 120)
    .background(Color.gray.opacity(0.1))
}
