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
    let aspectRatio: CGFloat?
    let targetWidth: CGFloat?
    let overlayType: CropOverlayType
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    @State private var displayedImage: UIImage?
    @State private var isPreparing = true

    private let maxDisplayDimension: CGFloat = 2560

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

    private func prepareImageDisplay() async -> UIImage? {
        let originalSize = image.size

        if aspectRatio == nil {
            if max(originalSize.width, originalSize.height) <= maxDisplayDimension {
                return image
            }

            let aspect = originalSize.width / originalSize.height
            let targetSize: CGSize

            if aspect > 1 {
                targetSize = CGSize(width: maxDisplayDimension, height: maxDisplayDimension / aspect)
            } else {
                targetSize = CGSize(width: maxDisplayDimension * aspect, height: maxDisplayDimension)
            }

            return await image.byPreparingThumbnail(ofSize: targetSize) ?? image
        } else {
            if max(originalSize.width, originalSize.height) <= maxDisplayDimension {
                return image
            }

            let scaleValue = maxDisplayDimension / max(originalSize.width, originalSize.height)
            let newSize = CGSize(width: originalSize.width * scaleValue, height: originalSize.height * scaleValue)
            return await image.byPreparingThumbnail(ofSize: newSize) ?? image
        }
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

                            ZStack {
                                Color.black

                                Image(uiImage: displayImg)
                                    .resizable()
                                    .scaledToFit()
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
                            .clipped()
                            .overlay(overlayView())

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

                            let outputWidth: CGFloat
                            let outputHeight: CGFloat
                            let multiplier: CGFloat

                            if let targetW = targetWidth {
                                outputWidth = targetW
                                outputHeight = outputWidth / (cropSize.width / cropSize.height)
                                multiplier = outputWidth / cropSize.width
                            } else {
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
            displayedImage = await prepareImageDisplay()
            isPreparing = false
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
            return Rectangle()
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

    @MainActor
    private func cropImage(image: UIImage, width: CGFloat, height: CGFloat, multiplier: CGFloat) {
        let renderer = ImageRenderer(content:
            ZStack {
                Color.clear
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(x: offset.width * multiplier, y: offset.height * multiplier)
                    .frame(width: width, height: height)
            }
            .frame(width: width, height: height)
        )

        renderer.scale = 1.0
        renderer.isOpaque = false

        if let cropped = renderer.uiImage {
            onCrop(cropped)
        } else {
            onCancel()
        }
    }
}
