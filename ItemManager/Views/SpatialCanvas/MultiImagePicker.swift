//
//  MultiImagePicker.swift
//  ItemManager
//
//  多选图片选择器 - 使用系统原生 PhotosPicker
//

import SwiftUI
import PhotosUI

struct MultiImagePicker: View {
    @Binding var selectedItems: [PhotosPickerItem]
    @Environment(\.dismiss) private var dismiss
    var onComplete: () -> Void
    
    @State private var isLoading = false
    
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
                        Text("已选择 \(selectedItems.count) 张图片")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        if selectedItems.count < minRecommendedImages {
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
                
                Spacer()
                
                // 系统 PhotosPicker 按钮
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: maxImages,
                    selectionBehavior: .ordered,
                    matching: .images,
                    preferredItemEncoding: .current
                ) {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.purple)
                        
                        Text("从图库选择")
                            .font(.headline)
                        
                        Text("最多可选择 \(maxImages) 张图片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
                    .padding()
                }
                
                Spacer()
                
                // 底部操作栏
                VStack(spacing: 12) {
                    // 快速清空按钮
                    HStack {
                        Button {
                            clearSelection()
                        } label: {
                            Label("清空选择", systemImage: "xmark.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedItems.isEmpty)
                        
                        Spacer()
                    }
                    
                    // 确认按钮
                    Button {
                        confirmSelection()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("确认选择 (\(selectedItems.count))")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            selectedItems.count >= minRecommendedImages ? Color.purple : Color.gray
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(selectedItems.isEmpty || isLoading)
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
    
    private func clearSelection() {
        selectedItems.removeAll()
    }
    
    private func confirmSelection() {
        isLoading = true
        
        Task {
            await MainActor.run {
                isLoading = false
                onComplete()
                dismiss()
            }
        }
    }
}

// MARK: - 连续拍照视图

import AVFoundation

// 视图修饰符：锁定屏幕方向
struct OrientationLockModifier: ViewModifier {
    let orientation: UIInterfaceOrientationMask
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                AppDelegate.orientationLock = orientation
            }
            .onDisappear {
                AppDelegate.orientationLock = .all
            }
    }
}

extension View {
    func lockOrientation(_ orientation: UIInterfaceOrientationMask) -> some View {
        modifier(OrientationLockModifier(orientation: orientation))
    }
}

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
    
    // 照片输出
    @State private var photoOutput: AVCapturePhotoOutput?
    @State private var captureDelegate: PhotoCaptureDelegate?
    
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
                
                // 拍摄按钮区域
                HStack(spacing: 40) {
                    // 完成按钮
                    Button {
                        onComplete()
                        dismiss()
                    } label: {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                            Text("完成")
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
                        }
                    }
                    .disabled(isCapturing)
                    
                    // 切换指导
                    Button {
                        withAnimation {
                            captureGuide.nextTip()
                        }
                    } label: {
                        VStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                            Text("下一步")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            if let session = session {
                if session.isRunning {
                    session.stopRunning()
                }
            }
        }
        .lockOrientation(.portrait)
    }

    private func setupCamera() {
        // 检查相机权限
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch authStatus {
        case .authorized:
            configureCameraSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [self] granted in
                if granted {
                    DispatchQueue.main.async {
                        configureCameraSession()
                    }
                } else {
                    print("相机权限被拒绝")
                }
            }
        case .denied, .restricted:
            print("相机权限被拒绝或受限")
        @unknown default:
            print("未知的相机权限状态")
        }
    }
    
    private func configureCameraSession() {
        // 在后台线程配置相机会话
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let newSession = AVCaptureSession()
            newSession.beginConfiguration()

            // 设置会话预设 - 使用 photo 预设以提高兼容性
            if newSession.canSetSessionPreset(.photo) {
                newSession.sessionPreset = .photo
            }

            // 获取后置摄像头
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("无法获取后置摄像头")
                return
            }

            do {
                // 配置摄像头设备
                try videoDevice.lockForConfiguration()
                if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                    videoDevice.focusMode = .continuousAutoFocus
                }
                if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                    videoDevice.exposureMode = .continuousAutoExposure
                }
                videoDevice.unlockForConfiguration()

                // 添加视频输入
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if newSession.canAddInput(videoInput) {
                    newSession.addInput(videoInput)
                } else {
                    print("无法添加视频输入")
                    return
                }

                // 创建照片输出
                let output = AVCapturePhotoOutput()
                if newSession.canAddOutput(output) {
                    newSession.addOutput(output)
                    DispatchQueue.main.async {
                        self.photoOutput = output
                    }
                } else {
                    print("无法添加照片输出")
                    return
                }

            } catch {
                print("相机设置错误: \(error.localizedDescription)")
                return
            }

            newSession.commitConfiguration()

            DispatchQueue.main.async {
                self.session = newSession
            }

            // 启动会话
            newSession.startRunning()
        }
    }
    
    private func capturePhoto() {
        guard let photoOutput = photoOutput else { return }
        
        isCapturing = true
        
        let settings = AVCapturePhotoSettings()
        let delegate = PhotoCaptureDelegate { [self] image in
            DispatchQueue.main.async {
                if let image = image {
                    capturedImages.append(image)
                    captureCount = capturedImages.count
                }
                isCapturing = false
            }
        }
        captureDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
}

// MARK: - 照片捕获委托

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    
    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("照片处理错误: \(error.localizedDescription)")
            completion(nil)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            completion(nil)
            return
        }
        
        completion(image)
    }
}

// MARK: - 相机预览视图

struct CameraPreviewView: UIViewRepresentable {
    @Binding var session: AVCaptureSession?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        if let session = session {
            previewLayer.session = session
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
            if let session = session, previewLayer.session !== session {
                previewLayer.session = session
            }
        }
    }
}

// MARK: - 拍摄指导

struct CaptureGuide {
    var currentTipIndex = 0
    
    let tips = [
        "从物体正前方开始拍摄",
        "缓慢向右移动，保持物体在中心",
        "继续环绕，拍摄不同角度",
        "降低高度，从下方拍摄",
        "升高高度，从上方拍摄",
        "确保覆盖物体的所有细节"
    ]
    
    var currentTip: String {
        tips[currentTipIndex % tips.count]
    }
    
    mutating func nextTip() {
        currentTipIndex = (currentTipIndex + 1) % tips.count
    }
}

struct CaptureGuideOverlay: View {
    @Binding var guide: CaptureGuide
    
    var body: some View {
        ZStack {
            // 移除灰色蒙版滤镜，让相机预览清晰可见
            // 使用渐变遮罩只在边缘显示提示信息
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.4), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
                
                Spacer()
                
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                Image(systemName: "viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                
                Text("拍摄指导")
                    .font(.title)
                    .foregroundStyle(.white)
                
                Text(guide.currentTip)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}

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
        .background(Color.white.opacity(0.2))
        .clipShape(Capsule())
    }
}
