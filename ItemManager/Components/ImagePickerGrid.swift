//
//  ImagePickerGrid.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import PhotosUI
import SwiftData

struct ImagePickerGrid: View {
    @Binding var imagePaths: [String]
    let maxCount: Int = 9
    
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingPermissionAlert = false
    @State private var showingEditSheet = false
    @State private var editingIndex: Int?
    @State private var isProcessingImages = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择图片 (最多\(maxCount)张，第一张为主图)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Add Button
                    if imagePaths.count < maxCount {
                        PhotosPicker(selection: $selectedItems, 
                                   maxSelectionCount: maxCount - imagePaths.count,
                                   matching: .images) {
                            VStack {
                                if isProcessingImages {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus")
                                        .font(.title)
                                    Text("添加")
                                        .font(.caption)
                                }
                            }
                            .frame(width: 100, height: 100)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(12)
                            .foregroundStyle(.secondary)
                        }
                        .disabled(isProcessingImages)
                        .onChange(of: selectedItems) { _, newItems in
                            guard !newItems.isEmpty else { return }
                            
                            isProcessingImages = true
                            Task {
                                for item in newItems {
                                    if let data = try? await item.loadTransferable(type: Data.self),
                                       let uiImage = UIImage(data: data) {
                                        // 压缩图片以节省空间
                                        let compressedImage = uiImage.jpegData(compressionQuality: 0.7).flatMap { UIImage(data: $0) } ?? uiImage
                                        saveImage(compressedImage)
                                    }
                                }
                                await MainActor.run {
                                    selectedItems = []
                                    isProcessingImages = false
                                }
                            }
                        }
                    }
                    
                    // Image List
                    ForEach(Array(imagePaths.enumerated()), id: \.offset) { index, path in
                        ZStack(alignment: .topTrailing) {
                            // Image Display
                            if let image = ImageManager.shared.loadImage(fileName: path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .onTapGesture {
                                        editingIndex = index
                                        showingEditSheet = true
                                    }
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 100, height: 100)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            
                            // Delete Button
                            Button(action: {
                                deleteImage(at: index)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .padding(4)
                        }
                    }
                }
            }
        }
        .alert("需要相册权限", isPresented: $showingPermissionAlert) {
            Button("去设置", role: .cancel) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .destructive) {}
        } message: {
            Text("请在设置中允许访问相册以选择图片")
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                if let index = editingIndex, index < imagePaths.count,
                   let image = ImageManager.shared.loadImage(fileName: imagePaths[index]) {
                    VStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        
                        HStack(spacing: 20) {
                            if index > 0 {
                                Button(action: {
                                    moveImageToFront(from: index)
                                    showingEditSheet = false
                                }) {
                                    Label("设为封面", systemImage: "star.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.pink)
                            }
                            
                            Button(role: .destructive, action: {
                                deleteImage(at: index)
                                showingEditSheet = false
                            }) {
                                Label("删除图片", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .padding(.bottom, 20)
                    }
                    .navigationTitle("图片预览")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showingEditSheet = false
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("图片无法加载", systemImage: "photo.badge.exclamationmark")
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    private func saveImage(_ image: UIImage) {
        if let fileName = ImageManager.shared.saveImage(image, context: modelContext) {
            imagePaths.append(fileName)
        }
    }
    
    private func deleteImage(at index: Int) {
        let fileName = imagePaths[index]
        ImageManager.shared.deleteImage(fileName: fileName, context: modelContext)
        imagePaths.remove(at: index)
    }
    
    private func moveImageToFront(from index: Int) {
        let item = imagePaths.remove(at: index)
        imagePaths.insert(item, at: 0)
    }
}
