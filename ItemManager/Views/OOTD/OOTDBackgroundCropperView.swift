
import SwiftUI

struct OOTDBackgroundCropperView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    
    // Target Aspect Ratio 3:4
    private let targetAspectRatio: CGFloat = 0.75
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack {
                        Spacer()
                        
                        // Container for the crop area
                        // We want it to be as wide as possible (with padding)
                        let width = geometry.size.width - 40
                        let height = width / targetAspectRatio
                        
                        ZStack {
                            // Mask to clip content visually
                            Color.black // Background behind image
                            
                            // The Image
                            Image(uiImage: image)
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
                        .frame(width: width, height: height)
                        .clipShape(Rectangle())
                        .overlay(
                            Rectangle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .contentShape(Rectangle()) // Ensure gestures work within the frame
                        
                        Spacer()
                        
                        Text("双指缩放，单指拖动")
                            .foregroundStyle(.gray)
                            .padding(.bottom)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: onCancel)
                            .foregroundStyle(.white)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            // Calculate multiplier based on current geometry
                            let visibleWidth = geometry.size.width - 40
                            let multiplier = 1080.0 / visibleWidth
                            cropImage(multiplier: multiplier)
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }
    
    @MainActor
    private func cropImage(multiplier: CGFloat) {
        // Render the view at high resolution (1080x1440)
        let renderer = ImageRenderer(content:
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(scale)
                .offset(x: offset.width * multiplier, y: offset.height * multiplier)
                .frame(width: 1080, height: 1440)
                .clipped()
        )
        
        // Ensure we get a good quality image
        renderer.scale = 1.0 
        
        if let cropped = renderer.uiImage {
            onCrop(cropped)
        } else {
            // Fallback (shouldn't happen usually)
            onCancel()
        }
    }
}
