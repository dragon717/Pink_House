//
//  ImagePickerGrid.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import PhotosUI
import SwiftData
import UniformTypeIdentifiers

struct ImagePickerGrid: View {
    @Binding var imagePaths: [String]
    let maxCount: Int = 9
    
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingPermissionAlert = false
    @State private var showingEditSheet = false
    @State private var editingIndex: Int?
    @State private var isProcessingImages = false
    @State private var draggingIndex: Int?
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    
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
                        Menu {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    showingCamera = true
                                } label: {
                                    Label("拍照", systemImage: "camera")
                                }
                            }
                            
                            PhotosPicker(selection: $selectedItems, 
                                       maxSelectionCount: maxCount - imagePaths.count,
                                       matching: .images) {
                                Label("从相册选择", systemImage: "photo.on.rectangle")
                            }
                        } label: {
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
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(index == 0 ? Color.accentColor : Color.clear, lineWidth: 3)
                                    )
                                    .overlay(alignment: .bottom) {
                                        if index == 0 {
                                            Text("主图")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.8))
                                                .clipShape(Capsule())
                                                .padding(.bottom, 4)
                                        }
                                    }
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
                        .draggable(path) {
                            if let image = ImageManager.shared.loadImage(fileName: path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Text(path)
                            }
                        }
                        .dropDestination(for: String.self) { items, location in
                            draggingIndex = nil
                            return true
                        } isTargeted: { isTargeted in
                            if isTargeted, let fromIndex = draggingIndex, fromIndex != index {
                                withAnimation {
                                    let item = imagePaths.remove(at: fromIndex)
                                    imagePaths.insert(item, at: index)
                                    draggingIndex = index
                                }
                            }
                        }
                        .onDrag {
                            draggingIndex = index
                            return NSItemProvider(object: path as NSString)
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
                                    Label("设为主图", systemImage: "star.fill")
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
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, newImage in
            if let image = newImage {
                isProcessingImages = true
                Task {
                    let compressedImage = image.jpegData(compressionQuality: 0.7).flatMap { UIImage(data: $0) } ?? image
                    await MainActor.run {
                        saveImage(compressedImage)
                        cameraImage = nil
                        isProcessingImages = false
                    }
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
    
    private func moveImageToFront(from index: Int) {
        let item = imagePaths.remove(at: index)
        imagePaths.insert(item, at: 0)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
