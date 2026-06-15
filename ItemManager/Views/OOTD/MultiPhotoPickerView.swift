//
//  MultiPhotoPickerView.swift
//  ItemManager
//
//  多选照片选择器 - 遵循苹果官方规范
//  支持从图库多选照片，确认后才进行抠图
//

import SwiftUI
import PhotosUI
import SwiftData

/// 多选照片选择器视图
/// 遵循苹果 Human Interface Guidelines 的设计原则
struct MultiPhotoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - 回调
    var onComplete: ([CutoutItem]) -> Void
    
    // MARK: - 状态
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isProcessing = false
    @State private var processingProgress = 0
    @State private var processingMessage = ""
    @State private var showConfirmation = false
    @State private var showMaxSelectionAlert = false
    @State private var cutoutResults: [CutoutItem] = []
    @State private var previewLoadTask: Task<Void, Never>?
    
    // MARK: - 常量
    private let maxSelectionCount = 20
    private let minRecommendedCount = 1
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isProcessing {
                    processingView
                } else if showConfirmation {
                    confirmationView
                } else {
                    selectionView
                }
            }
            .navigationTitle("选择照片".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isProcessing {
                        Button("取消".appLocalized) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 选择视图
    private var selectionView: some View {
        VStack(spacing: 0) {
            // 顶部提示区域
            headerView
            
            Divider()
            
            // 已选照片预览区域
            if !selectedItems.isEmpty {
                selectedPhotosPreview
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 系统 PhotosPicker
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: maxSelectionCount,
                selectionBehavior: .ordered,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                VStack(spacing: 16) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.pink)
                    
                    Text(selectedItems.isEmpty ? "从图库选择".appLocalized : "已选择 %d 张照片".appLocalized(selectedItems.count))
                        .font(.headline)
                    
                    if selectedItems.isEmpty {
                        Text("最多可选择 %d 张".appLocalized(maxSelectionCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("点击继续添加更多照片".appLocalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(16)
                .padding()
            }
            .onChange(of: selectedItems) { _, newItems in
                let itemsForPreview: [PhotosPickerItem]
                if newItems.count > maxSelectionCount {
                    showMaxSelectionAlert = true
                    itemsForPreview = Array(newItems.prefix(maxSelectionCount))
                    selectedItems = itemsForPreview
                } else {
                    itemsForPreview = newItems
                }
                // 加载选中图片的预览
                loadSelectedImages(from: itemsForPreview)
            }
            
            // 底部操作栏
            bottomActionBar
        }
        .alert("选择数量限制".appLocalized, isPresented: $showMaxSelectionAlert) {
            Button("确定".appLocalized, role: .cancel) {}
        } message: {
            Text("一次最多只能选择 %d 张照片".appLocalized(maxSelectionCount))
        }
        .onDisappear {
            previewLoadTask?.cancel()
        }
    }
    
    // MARK: - 已选照片预览
    private var selectedPhotosPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已选照片预览".appLocalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(selectedItems.count)/\(maxSelectionCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                        selectedPhotoCell(image: image, index: index)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .frame(height: 120)
        }
        .background(Color.gray.opacity(0.03))
    }
    
    // MARK: - 单个已选照片单元格
    private func selectedPhotoCell(image: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.pink.opacity(0.3), lineWidth: 2)
                )
            
            // 序号标签
            Text("\(index + 1)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.pink)
                .clipShape(Capsule())
                .padding(4)
            
            // 删除按钮
            Button {
                removeItem(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.red.opacity(0.8))
                    .shadow(radius: 2)
            }
            .padding(4)
            .offset(x: 8, y: -8)
        }
    }
    
    // MARK: - 加载已选图片
    private func loadSelectedImages(from items: [PhotosPickerItem]) {
        previewLoadTask?.cancel()

        guard !items.isEmpty else {
            selectedImages = []
            return
        }

        previewLoadTask = Task {
            var images: [UIImage] = []
            for item in items {
                if Task.isCancelled { return }

                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            if Task.isCancelled { return }

            await MainActor.run {
                selectedImages = images
            }
        }
    }
    
    // MARK: - 移除指定位置的图片
    private func removeItem(at index: Int) {
        guard index < selectedItems.count && index < selectedImages.count else { return }
        selectedItems.remove(at: index)
        selectedImages.remove(at: index)
    }
    
    // MARK: - 顶部提示视图
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "scissors.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("批量抠图".appLocalized)
                        .font(.headline)
                    Text("选择照片后将自动抠图并添加到画布".appLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color.pink.opacity(0.1))
            
            // 选择数量指示
            HStack {
                Text("已选择 %d 张照片".appLocalized(selectedItems.count))
                    .font(.subheadline)
                
                Spacer()
                
                if !selectedItems.isEmpty {
                    Button {
                        selectedItems.removeAll()
                    } label: {
                        Label("清空".appLocalized, systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - 底部操作栏
    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                // 快速清空按钮
                Button {
                    selectedItems.removeAll()
                } label: {
                    Label("清空".appLocalized, systemImage: "xmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(selectedItems.isEmpty)
                
                Spacer()
                
                // 确认按钮
                Button {
                    showConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("确认选择 (%d)".appLocalized(selectedItems.count))
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedItems.isEmpty ? Color.gray : Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedItems.isEmpty)
            }
            .padding()
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - 确认视图
    private var confirmationView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "photo.stack")
                .font(.system(size: 80))
                .foregroundStyle(.pink.opacity(0.8))
            
            VStack(spacing: 8) {
                Text("确认抠图 %d 张照片？".appLocalized(selectedItems.count))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("处理过程可能需要一些时间".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    startProcessing()
                } label: {
                    HStack {
                        Image(systemName: "scissors")
                        Text("开始抠图".appLocalized)
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button {
                    showConfirmation = false
                } label: {
                    Text("返回修改".appLocalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .padding()
    }
    
    // MARK: - 处理中视图
    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 进度指示器
            ZStack {
                Circle()
                    .stroke(Color.pink.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: CGFloat(processingProgress) / CGFloat(selectedItems.count))
                    .stroke(Color.pink, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: processingProgress)
                
                VStack {
                    Text("\(processingProgress)/\(selectedItems.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("处理中".appLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(spacing: 8) {
                Text(processingMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text("正在使用 Vision 框架进行智能抠图...".appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - 处理方法
    private func startProcessing() {
        isProcessing = true
        processingProgress = 0
        cutoutResults.removeAll()
        
        Task {
            await processSelectedItems()
        }
    }
    
    private func processSelectedItems() async {
        for (index, item) in selectedItems.enumerated() {
            await MainActor.run {
                processingProgress = index
                processingMessage = "正在处理第 %d 张...".appLocalized(index + 1)
            }
            
            do {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    
                    if let cutout = try? await CutoutService.shared.processImage(
                        image: image,
                        category: "导入",
                        clothing: nil,
                        context: modelContext
                    ) {
                        await MainActor.run {
                            cutoutResults.append(cutout)
                        }
                    }
                }
            } catch {
                print("处理第 \(index + 1) 张照片失败: \(error)")
            }
            
            // 小延迟以允许 UI 更新
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        await MainActor.run {
            processingProgress = selectedItems.count
            processingMessage = "完成！".appLocalized
            
            // 短暂延迟后关闭并回调
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onComplete(cutoutResults)
                dismiss()
            }
        }
    }
}

// MARK: - 预览
#Preview {
    MultiPhotoPickerView { cutouts in
        print("完成抠图: \(cutouts.count) 张")
    }
    .modelContainer(for: [CutoutItem.self, Clothing.self], inMemory: true)
}
