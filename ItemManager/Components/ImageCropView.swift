import SwiftUI
import UIKit

struct ImageCropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void
    
    init(image: UIImage, onCrop: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.onCrop = onCrop
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("取消", action: onCancel)
                    .foregroundStyle(.white)
                Spacer()
                Text("移动和缩放")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button("使用") {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerCrop"), object: nil)
                }
                .fontWeight(.bold)
                .foregroundStyle(.white)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .zIndex(1)
            
            // Crop Area
            GeometryReader { geometry in
                CropScrollView(image: image, viewSize: geometry.size) { croppedImage in
                    onCrop(croppedImage)
                }
                .edgesIgnoringSafeArea(.all)
            }
        }
        .background(Color.black)
    }
}

struct CropScrollView: UIViewRepresentable {
    let image: UIImage
    let viewSize: CGSize
    let onCrop: (UIImage) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 0.1
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        
        // Ensure image is valid before creating view
        if image.size.width > 0 && image.size.height > 0 {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.frame = CGRect(origin: .zero, size: image.size)
            scrollView.addSubview(imageView)
            scrollView.contentSize = image.size
            context.coordinator.imageView = imageView
            
            // Force initial layout
            // We can't do full layout here because we don't know viewSize yet (it might be zero initially)
            // But we can ensure imageView is ready
        }
        
        // Setup crop trigger
        NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerCrop"), object: nil, queue: .main) { _ in
            context.coordinator.cropImage(scrollView: scrollView)
        }
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        
        // Always try to set image view if it's missing (shouldn't happen but safe)
        if context.coordinator.imageView == nil && image.size.width > 0 {
             let imageView = UIImageView(image: image)
             imageView.contentMode = .scaleAspectFit
             imageView.frame = CGRect(origin: .zero, size: image.size)
             uiView.addSubview(imageView)
             uiView.contentSize = image.size
             context.coordinator.imageView = imageView
        }
 
        // Only layout if size changed and is valid
        // Also force layout if we haven't done it yet (lastViewSize is zero) AND we have a valid viewSize
        if viewSize != .zero && (viewSize != context.coordinator.lastViewSize || uiView.zoomScale == 1.0) {
            // Update last view size
            context.coordinator.lastViewSize = viewSize
            
            guard let imageView = context.coordinator.imageView else {
                 return 
            }
            
            // Calculate scales
            let widthRatio = viewSize.width / image.size.width
            let heightRatio = viewSize.height / image.size.height
            
            // Aspect Fill scale (ensure image covers the screen)
            let fillScale = max(widthRatio, heightRatio)
            
            // Update constraints
            uiView.minimumZoomScale = fillScale
            uiView.maximumZoomScale = max(fillScale * 5.0, 5.0)
            
            // Only set initial zoom if we haven't laid out before or if explicitly needed
            // For now, we reset to fill on rotation/resize to ensure coverage
            // OR if zoomScale is currently default (1.0), which might be wrong for large images
            if uiView.zoomScale == 1.0 || uiView.zoomScale < fillScale {
                uiView.zoomScale = fillScale
            }
            
            // Center the image
            let contentWidth = image.size.width * fillScale
            let contentHeight = image.size.height * fillScale
            
            let offsetX = (contentWidth - viewSize.width) / 2
            let offsetY = (contentHeight - viewSize.height) / 2
            
            // Only adjust offset if it seems off (e.g. at 0,0)
            if uiView.contentOffset == .zero {
                 uiView.contentOffset = CGPoint(x: max(0, offsetX), y: max(0, offsetY))
            }
        }
    }
    
    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: CropScrollView
        var imageView: UIImageView?
        var lastViewSize: CGSize = .zero
        
        init(_ parent: CropScrollView) {
            self.parent = parent
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
        
        func cropImage(scrollView: UIScrollView) {
            guard let image = imageView?.image else { return }
            
            // Calculate visible rect in image coordinates (points)
            let scale = 1.0 / scrollView.zoomScale
            let visibleRect = CGRect(
                x: scrollView.contentOffset.x * scale,
                y: scrollView.contentOffset.y * scale,
                width: scrollView.bounds.width * scale,
                height: scrollView.bounds.height * scale
            )
            
            // Convert to pixels for CGImage cropping
            let imageScale = image.scale
            let pixelRect = CGRect(
                x: visibleRect.origin.x * imageScale,
                y: visibleRect.origin.y * imageScale,
                width: visibleRect.width * imageScale,
                height: visibleRect.height * imageScale
            )
            
            if let cgImage = image.cgImage?.cropping(to: pixelRect) {
                // Create new UIImage. Note: The new image will have the same scale as original
                // but its size will match the screen bounds (in points).
                let cropped = UIImage(cgImage: cgImage, scale: imageScale, orientation: image.imageOrientation)
                parent.onCrop(cropped)
            } else {
                // Fallback
                parent.onCrop(image)
            }
        }
    }
}
