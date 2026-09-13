//
//  ImageViewer.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/4/26.
//

import SwiftUI
import UIKit

struct ImageViewer: View {
    let imagePaths: [String]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss
    
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var showSaveAlert = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $selectedIndex) {
                if imagePaths.isEmpty {
                    // 空状态占位
                    Color.black
                        .tag(0)
                } else {
                    // 使用 enumerated 避免索引问题
                    ForEach(Array(imagePaths.enumerated()), id: \.element) { index, imagePath in
                        ZoomableImageView(imagePath: imagePath)
                            .tag(index)
                    }
                }
            }
            .id("viewer-\(imagePaths.count)") // 强制刷新当图片数量变化
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .onChange(of: imagePaths) { _, newPaths in
                // 当图片路径变化时，验证 selectedIndex
                if newPaths.isEmpty {
                    selectedIndex = 0
                } else if selectedIndex >= newPaths.count {
                    selectedIndex = max(0, newPaths.count - 1)
                }
            }
            
            // Overlay controls
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    
                    Spacer()
                    
                    if imagePaths.count > 1 {
                        Text("\(min(selectedIndex + 1, imagePaths.count)) / \(imagePaths.count)")
                            .foregroundStyle(.white)
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    Button {
                        saveCurrentImage()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .disabled(isSaving)
                }
                .padding()
                .padding(.top, 40) // Status bar spacing
                
                Spacer()
            }
        }
        .alert("保存结果".appLocalized, isPresented: $showSaveAlert) {
            Button("确定".appLocalized, role: .cancel) { }
        } message: {
            Text(saveMessage ?? "")
        }
    }
    
    private func saveCurrentImage() {
        guard selectedIndex < imagePaths.count else { return }
        isSaving = true
        let fileName = imagePaths[selectedIndex]
        
        Task {
            if let image = await ImageManager.shared.loadImageAsync(fileName: fileName) {
                let saver = ImageSaver()
                do {
                    try await saver.saveImage(image)
                    saveMessage = "图片已保存到相册".appLocalized
                } catch {
                    saveMessage = "保存失败: %@".appLocalized(error.localizedDescription)
                }
            } else {
                saveMessage = "无法加载图片".appLocalized
            }
            showSaveAlert = true
            isSaving = false
        }
    }
}

// Helper for saving to album with async/await
class ImageSaver: NSObject {
    private var continuation: CheckedContinuation<Void, Error>?
    
    func saveImage(_ image: UIImage) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted), nil)
        }
    }
    
    @objc func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let imagePath: String

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        // 用 Auto Layout 而不是 autoresizingMask：
        // 旧实现 `imageView.frame = scrollView.bounds` 在 makeUIView 时
        // 把 frame 设成 (0,0,0,0)，依赖 SwiftUI 后续 layout 把 imageView
        // 撑大。如果 image 是异步加载完才赋到 imageView 上的，首帧 layout
        // 已经过去，imageView 在 (0,0) 状态下被 setNeedsDisplay → 黑屏，
        // 直到下一次 bounds 变化才重绘。
        // 用 layout guide + width/height constraints 后，imageView 从第
        // 一次 layout pass 起就是正确的尺寸。
        imageView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let frameGuide = scrollView.frameLayoutGuide
        let contentGuide = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: frameGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: frameGuide.heightAnchor),
        ])

        // 父级缩略图（ChartImagePicker / sizeChartThumbnail）通常已经在
        // 内存 cache 里同步加载过这张图，这里同步取出直接 set，避免异步
        // loadImageAsync 走磁盘/iCloud 时的黑屏窗口。
        if let image = ImageManager.shared.loadImage(fileName: imagePath) {
            imageView.image = image
            context.coordinator.currentPath = imagePath
        }

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.currentPath != imagePath {
            context.coordinator.currentPath = imagePath
            uiView.zoomScale = 1.0

            // 快路径：缓存命中就同步 set，避免 async set 跟 layout 抢时序。
            if let image = ImageManager.shared.loadImage(fileName: imagePath) {
                context.coordinator.imageView?.image = image
                return
            }

            // 慢路径：磁盘 / iCloud 下载，仍交给异步加载。
            Task {
                if let image = await ImageManager.shared.loadImageAsync(fileName: imagePath) {
                    await MainActor.run {
                        context.coordinator.imageView?.image = image
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var currentPath: String?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }

            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scrollSize = scrollView.frame.size
                let size = CGSize(width: scrollSize.width / 3,
                                  height: scrollSize.height / 3)
                let origin = CGPoint(x: point.x - size.width / 2,
                                     y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}
