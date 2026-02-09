import SwiftUI
import UIKit

struct CropRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let isNewSelection: Bool
}

enum CropOverlayType: Equatable {
    case rectangle
    case circle
    case roundedRectangle(cornerRadius: CGFloat)
    case none
}

struct ImageCropView: View {
    let image: UIImage
    let aspectRatio: CGFloat? // Width / Height
    let targetWidth: CGFloat? // Optional target width for output
    let overlayType: CropOverlayType
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    
    // Optimization states
    @State private var displayedImage: UIImage?
    @State private var isPreparing = true
    
    init(image: UIImage, 
         aspectRatio: CGFloat? = nil, 
         targetWidth: CGFloat? = nil, 
         overlayType: CropOverlayType = .rectangle,
         onCrop: @escaping (UIImage) -> Void, 
         onCancel: @escaping () -> Void) {
        self.image = image
        self.aspectRatio = aspectRatio
        self.targetWidth = targetWidth
        self.overlayType = overlayType
        self.onCrop = onCrop
        self.onCancel = onCancel
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    if isPreparing {
                        VStack {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                            Text("正在准备图片...")
                                .foregroundStyle(.white)
                                .padding(.top)
                        }
                    } else if let displayImg = displayedImage {
                        VStack {
                            Spacer()
                            
                            // Calculate crop area dimensions
                            let cropSize: CGSize = {
                                if let ratio = aspectRatio {
                                    // With padding for specific aspect ratio
                                    let width = geometry.size.width - 40
                                    let height = width / ratio
                                    
                                    // Check if height fits
                                    if height > geometry.size.height - 100 { // Allow some vertical padding
                                        let h = geometry.size.height - 100
                                        let w = h * ratio
                                        return CGSize(width: w, height: h)
                                    }
                                    
                                    return CGSize(width: width, height: height)
                                } else {
                                    // Full screen for nil aspect ratio
                                    return geometry.size
                                }
                            }()
                            
                            ZStack {
                                // Mask to clip content visually
                                Color.black // Background behind image
                                
                                // The Image
                                Image(uiImage: displayImg)
                                    .resizable()
                                    .scaledToFill()
                                    .scaleEffect(scale)
                                    .offset(offset)
                                    .gesture(
                                        SimultaneousGesture(
                                            MagnificationGesture()
                                                .onChanged { value in
                                                    let delta = value / lastScale
                                                    lastScale = value
                                                    scale *= delta
                                                }
                                                .onEnded { _ in
                                                    lastScale = 1.0
                                                    // Optional: Add bounds check or bounce back here
                                                    if scale < 0.5 { withAnimation { scale = 0.5 } }
                                                    if scale > 5.0 { withAnimation { scale = 5.0 } }
                                                },
                                            DragGesture()
                                                .onChanged { value in
                                                    let delta = CGSize(
                                                        width: value.translation.width - lastOffset.width,
                                                        height: value.translation.height - lastOffset.height
                                                    )
                                                    offset.width += delta.width
                                                    offset.height += delta.height
                                                    lastOffset = value.translation
                                                }
                                                .onEnded { _ in
                                                    lastOffset = .zero
                                                }
                                        )
                                    )
                            }
                            .frame(width: cropSize.width, height: cropSize.height)
                            // Apply clip shape based on overlay type
                            .clipShape(AnyShape(shapeForOverlay()))
                            .overlay(
                                overlayView()
                            )
                            .contentShape(Rectangle()) // Ensure gestures work within the frame
                            
                            Spacer()
                            
                            Text("双指缩放，单指拖动")
                                .foregroundStyle(.gray)
                                .padding(.bottom)
                                .opacity(aspectRatio == nil ? 0 : 1)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: onCancel)
                            .foregroundStyle(.white)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            guard let displayImg = displayedImage else { return }
                            
                            // Calculate crop dimensions again for consistency
                            let cropSize: CGSize = {
                                if let ratio = aspectRatio {
                                    let width = geometry.size.width - 40
                                    let height = width / ratio
                                    if height > geometry.size.height - 100 {
                                        let h = geometry.size.height - 100
                                        let w = h * ratio
                                        return CGSize(width: w, height: h)
                                    }
                                    return CGSize(width: width, height: height)
                                } else {
                                    return geometry.size
                                }
                            }()
                            
                            // Determine output size
                            // If targetWidth is provided, use it.
                            // Otherwise, if we downsampled, maybe we should try to be smart, 
                            // but simpler is to output at the "display resolution" scaled up to match original if needed?
                            // No, let's keep it simple:
                            // If targetWidth is set (e.g. 1080), we output at that width.
                            // If not, we output at the cropSize * screenScale (basically screen res crop).
                            
                            let outputWidth: CGFloat
                            let outputHeight: CGFloat
                            let multiplier: CGFloat
                            
                            if let targetW = targetWidth {
                                outputWidth = targetW
                                outputHeight = outputWidth / (cropSize.width / cropSize.height)
                                multiplier = outputWidth / cropSize.width
                            } else {
                                // Default to 2x or 3x screen scale for good quality
                                let screenScale = UIScreen.main.scale
                                outputWidth = cropSize.width * screenScale
                                outputHeight = cropSize.height * screenScale
                                multiplier = screenScale
                            }
                            
                            cropImage(image: displayImg, width: outputWidth, height: outputHeight, multiplier: multiplier)
                        }
                        .foregroundStyle(.white)
                        .disabled(isPreparing)
                    }
                }
            }
        }
        .task {
            // Optimization: Prepare image in background
            await prepareImage()
        }
    }
    
    private func shapeForOverlay() -> any Shape {
        switch overlayType {
        case .rectangle:
            return Rectangle()
        case .circle:
            return Circle()
        case .roundedRectangle(let radius):
            return RoundedRectangle(cornerRadius: radius)
        case .none:
            return Rectangle() // Default clip to rectangle for none
        }
    }
    
    @ViewBuilder
    private func overlayView() -> some View {
        switch overlayType {
        case .rectangle:
            Rectangle().stroke(Color.white, lineWidth: 2)
        case .circle:
            Circle().stroke(Color.white, lineWidth: 2)
        case .roundedRectangle(let radius):
            RoundedRectangle(cornerRadius: radius).stroke(Color.white, lineWidth: 2)
        case .none:
            EmptyView()
        }
    }
    
    private func prepareImage() async {
        // Max dimension to keep in memory for display
        // 2560px is good enough for any phone screen (even Pro Max is ~1290pt @3x ~> 4000px, but 2560 is safe for memory)
        // Actually, for "Low Memory", let's be conservative. 2048 is a standard texture size.
        let maxDimension: CGFloat = 2048 
        
        let originalSize = image.size
        
        if max(originalSize.width, originalSize.height) > maxDimension {
            // Resize needed
            let scale = maxDimension / max(originalSize.width, originalSize.height)
            let newSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
            
            // Perform resize on background thread
            let resized = await image.byPreparingThumbnail(ofSize: newSize)
            
            await MainActor.run {
                self.displayedImage = resized ?? image // Fallback to original if fail
                self.isPreparing = false
            }
        } else {
            await MainActor.run {
                self.displayedImage = image
                self.isPreparing = false
            }
        }
    }
    
    @MainActor
    private func cropImage(image: UIImage, width: CGFloat, height: CGFloat, multiplier: CGFloat) {
        // Render the view at high resolution
        let renderer = ImageRenderer(content:
            ZStack {
                Color.clear // Ensure background is transparent
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale)
                    .offset(x: offset.width * multiplier, y: offset.height * multiplier)
                    .frame(width: width, height: height)
                    .clipped()
            }
            .frame(width: width, height: height)
        )
        
        // Ensure we get a good quality image
        renderer.scale = 1.0 
        renderer.isOpaque = false // Enable transparency support
        
        if let cropped = renderer.uiImage {
            onCrop(cropped)
        } else {
            // Fallback (shouldn't happen usually)
            onCancel()
        }
    }
}
