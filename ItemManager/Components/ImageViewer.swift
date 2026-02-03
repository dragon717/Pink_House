//
//  ImageViewer.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/4/26.
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
                ForEach(0..<imagePaths.count, id: \.self) { index in
                    ZoomableImageView(imagePath: imagePaths[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            
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
                        Text("\(selectedIndex + 1) / \(imagePaths.count)")
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
        .alert("保存结果", isPresented: $showSaveAlert) {
            Button("确定", role: .cancel) { }
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
                    saveMessage = "图片已保存到相册"
                } catch {
                    saveMessage = "保存失败: \(error.localizedDescription)"
                }
            } else {
                saveMessage = "无法加载图片"
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
        // Important: contentInsetAdjustmentBehavior = .never to avoid safe area insets messing up zoom
        scrollView.contentInsetAdjustmentBehavior = .never
        
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.frame = scrollView.bounds
        
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        
        // Double tap to zoom
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.currentPath != imagePath {
            context.coordinator.currentPath = imagePath
            uiView.zoomScale = 1.0
            
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
