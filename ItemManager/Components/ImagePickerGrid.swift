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
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingPermissionAlert = false
    @State private var showingEditSheet = false
    @State private var editingImage: UIImage?
    
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
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            VStack {
                                Image(systemName: "plus")
                                    .font(.title)
                                Text("添加")
                                    .font(.caption)
                            }
                            .frame(width: 100, height: 100)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(12)
                            .foregroundStyle(.secondary)
                        }
                        .onChange(of: selectedItem) { _, newItem in
                            if let newItem {
                                Task {
                                    if let data = try? await newItem.loadTransferable(type: Data.self),
                                       let uiImage = UIImage(data: data) {
                                        saveImage(uiImage)
                                    }
                                    selectedItem = nil
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
                                        // Tap to edit (placeholder)
                                        editingImage = image
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
            if let img = editingImage {
                VStack {
                    Text("编辑图片 (抠图功能开发中)")
                        .font(.headline)
                        .padding()
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                    Button("关闭") {
                        showingEditSheet = false
                    }
                    .padding()
                }
            }
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
}
