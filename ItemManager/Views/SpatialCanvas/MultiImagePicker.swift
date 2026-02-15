//
//  MultiImagePicker.swift
//  ItemManager
//
//  多选图片选择器 - 支持批量选择用于3DGS建模
//

import SwiftUI
import PhotosUI

struct MultiImagePicker: View {
    @Binding var selectedItems: [PhotosPickerItem]
    @Environment(\.dismiss) private var dismiss
    var onComplete: () -> Void
    
    @State private var selectedAssets: [PHAsset] = []
    @State private var isLoading = false
    @State private var previewImages: [UIImage] = []
    
    // 3DGS建议的最小图片数
    private let minRecommendedImages = 20
    private let maxImages = 200
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部提示
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "cube.transparent")
                            .font(.title2)
                            .foregroundStyle(.purple)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("3D高斯泼溅建模")
                                .font(.headline)
                            Text("选择 \(minRecommendedImages)+ 张图片以获得最佳效果")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    
                    // 已选数量指示
                    HStack {
                        Text("已选择 \(selectedAssets.count) 张图片")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        if selectedAssets.count < minRecommendedImages {
                            Text("建议至少 \(minRecommendedImages) 张")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("✓ 数量充足")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                // 图片网格
                PhotoGridView(
                    selectedAssets: $selectedAssets,
                    maxSelection: maxImages
                )
                
                // 底部操作栏
                VStack(spacing: 12) {
                    // 快速选择按钮
                    HStack(spacing: 12) {
                        Button {
                            selectRecentPhotos()
                        } label: {
                            Label("选择最近50张", systemImage: "photo.stack")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)
                        
                        Button {
                            clearSelection()
                        } label: {
                            Label("清空", systemImage: "xmark.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedAssets.isEmpty)
                        
                        Spacer()
                    }
                    
                    // 确认按钮
                    Button {
                        confirmSelection()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("确认选择 (\(selectedAssets.count))")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            selectedAssets.count >= minRecommendedImages ? Color.purple : Color.gray
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(selectedAssets.isEmpty || isLoading)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("选择图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func selectRecentPhotos() {
        // 实现选择最近照片逻辑
    }
    
    private func clearSelection() {
        selectedAssets.removeAll()
    }
    
    private func confirmSelection() {
        isLoading = true
        
        Task {
            // 将PHAsset转换为PhotosPickerItem
            // 这里需要实际实现转换逻辑
            await MainActor.run {
                isLoading = false
                onComplete()
                dismiss()
            }
        }
    }
}

// MARK: - 照片网格视图

struct PhotoGridView: View {
    @Binding var selectedAssets: [PHAsset]
    let maxSelection: Int
    
    @State private var allPhotos: [PHAsset] = []
    @State private var isLoading = true
    
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 4)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(allPhotos.enumerated()), id: \.element.localIdentifier) { index, asset in
                    PhotoGridCell(
                        asset: asset,
                        isSelected: isSelected(asset),
                        selectionIndex: selectionIndex(for: asset),
                        onTap: { toggleSelection(asset) }
                    )
                }
            }
            .padding(4)
        }
        .onAppear {
            loadPhotos()
        }
    }
    
    private func loadPhotos() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 500
            
            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            
            var assets: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            
            DispatchQueue.main.async {
                self.allPhotos = assets
                self.isLoading = false
            }
        }
    }
    
    private func isSelected(_ asset: PHAsset) -> Bool {
        selectedAssets.contains { $0.localIdentifier == asset.localIdentifier }
    }
    
    private func selectionIndex(for asset: PHAsset) -> Int? {
        selectedAssets.firstIndex { $0.localIdentifier == asset.localIdentifier }.map { $0 + 1 }
    }
    
    private func toggleSelection(_ asset: PHAsset) {
        if let index = selectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            selectedAssets.remove(at: index)
        } else if selectedAssets.count < maxSelection {
            selectedAssets.append(asset)
        }
    }
}

// MARK: - 照片网格单元

struct PhotoGridCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let selectionIndex: Int?
    let onTap: () -> Void
    
    @State private var image: UIImage?
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // 图片
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                
                // 选中遮罩
                if isSelected {
                    Color.black.opacity(0.3)
                    
                    // 选中标记
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 24, height: 24)
                                
                                if let index = selectionIndex {
                                    Text("\(index)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(4)
                        }
                        Spacer()
                    }
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
        
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            self.image = image
        }
    }
}

// MARK: - 连续拍照视图

struct ContinuousCameraCaptureView: View {
    @Binding var capturedImages: [UIImage]
    @Environment(\.dismiss) private var dismiss
    var onComplete: () -> Void
    
    @State private var session: AVCaptureSession?
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var isCapturing = false
    @State private var captureCount = 0
    @State private var showGuide = true
    
    // 3DGS拍摄指导
    @State private var captureGuide = CaptureGuide()
    
    var body: some View {
        ZStack {
            // 相机预览
            CameraPreviewView(session: $session)
                .ignoresSafeArea()
            
            // 拍摄指导层
            if showGuide {
                CaptureGuideOverlay(guide: $captureGuide)
            }
            
            // UI覆盖层
            VStack {
                // 顶部信息栏
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Text("\(captureCount) 张")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        if captureCount < 20 {
                            Text("建议至少20张")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("✓ 数量充足")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        showGuide.toggle()
                    } label: {
                        Image(systemName: showGuide ? "info.circle.fill" : "info.circle")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                .padding(.top, 40)
                
                Spacer()
                
                // 拍摄指导提示
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        GuideTip(icon: "arrow.left.and.right", text: "环绕拍摄")
                        GuideTip(icon: "arrow.up.and.down", text: "三层高度")
                        GuideTip(icon: "hand.tap.fill", text: "匀速移动")
                    }
                    
                    // 进度指示器
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)
                            
                            Rectangle()
                                .fill(Color.purple)
                                .frame(width: geo.size.width * min(CGFloat(captureCount) / 50.0, 1.0), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
                
                // 底部控制栏
                HStack(spacing: 40) {
                    // 相册按钮
                    Button {
                        // 打开相册选择
                    } label: {
                        VStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text("相册")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                    }
                    
                    // 拍摄按钮
                    Button {
                        capturePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .stroke(Color.purple, lineWidth: 4)
                                .frame(width: 70, height: 70)
                            
                            if isCapturing {
                                ProgressView()
                                    .scaleEffect(1.2)
                            }
                        }
                    }
                    .disabled(isCapturing)
                    
                    // 完成按钮
                    Button {
                        onComplete()
                        dismiss()
                    } label: {
                        VStack {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                            Text("完成")
                                .font(.caption)
                        }
                        .foregroundStyle(captureCount >= 20 ? .green : .gray)
                    }
                    .disabled(captureCount < 20)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            session?.stopRunning()
        }
    }
    
    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        self.session = session
        
        DispatchQueue.global(qos: .background).async {
            session.startRunning()
        }
    }
    
    private func capturePhoto() {
        isCapturing = true
        
        // 模拟拍摄
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 创建占位图片
            let placeholderImage = createPlaceholderImage()
            capturedImages.append(placeholderImage)
            captureCount += 1
            isCapturing = false
            
            // 更新拍摄指导
            updateCaptureGuide()
        }
    }
    
    private func createPlaceholderImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.purple.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
    
    private func updateCaptureGuide() {
        // 根据拍摄数量更新指导
        if captureCount < 10 {
            captureGuide.currentPhase = .lowOrbit
        } else if captureCount < 20 {
            captureGuide.currentPhase = .midOrbit
        } else {
            captureGuide.currentPhase = .highOrbit
        }
    }
}

// MARK: - 相机预览视图

struct CameraPreviewView: UIViewRepresentable {
    @Binding var session: AVCaptureSession?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let session = session else { return }
        
        // 移除旧的预览层
        uiView.layer.sublayers?.filter { $0 is AVCaptureVideoPreviewLayer }.forEach { $0.removeFromSuperlayer() }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = uiView.bounds
        previewLayer.videoGravity = .resizeAspectFill
        uiView.layer.addSublayer(previewLayer)
    }
}

// MARK: - 拍摄指导覆盖层

struct CaptureGuideOverlay: View {
    @Binding var guide: CaptureGuide
    
    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            // 中心聚焦框
            ZStack {
                // 轨道指示
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 200, height: 200)
                
                Circle()
                    .stroke(Color.purple.opacity(0.5), lineWidth: 2)
                    .frame(width: 150, height: 150)
                
                // 当前拍摄位置指示
                Circle()
                    .fill(Color.purple)
                    .frame(width: 12, height: 12)
                    .offset(x: 75, y: 0)
                    .rotationEffect(.degrees(guide.currentAngle))
                
                // 十字准星
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 20, height: 1)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 20, height: 1)
                }
                .frame(width: 100)
                
                VStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 1, height: 20)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 1, height: 20)
                }
                .frame(height: 100)
            }
            
            // 指导文字
            VStack {
                Spacer()
                
                VStack(spacing: 8) {
                    Text(guide.currentPhase.description)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text("保持匀速移动，避免抖动")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 200)
            }
        }
    }
}

// MARK: - 指导提示组件

struct GuideTip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

// MARK: - 拍摄指导模型

struct CaptureGuide {
    enum Phase: String {
        case lowOrbit = "低层环绕"
        case midOrbit = "中层环绕"
        case highOrbit = "高层环绕"
        case complete = "拍摄完成"
        
        var description: String {
            switch self {
            case .lowOrbit:
                return "低层环绕拍摄 - 蹲下视角"
            case .midOrbit:
                return "中层环绕拍摄 - 平视视角"
            case .highOrbit:
                return "高层环绕拍摄 - 俯视视角"
            case .complete:
                return "拍摄完成！"
            }
        }
    }
    
    var currentPhase: Phase = .lowOrbit
    var currentAngle: Double = 0
    var capturedAngles: [Double] = []
}

import AVFoundation
import Photos
