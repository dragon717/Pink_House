import SwiftUI

// MARK: - 裁剪比例
enum CropAspectRatio: String, CaseIterable {
    case oneToOne = "1:1"
    case fourToThree = "4:3"
    case threeToFour = "3:4"
    case twoToOne = "2:1"
    case oneToTwo = "1:2"
    
    var ratio: CGFloat {
        switch self {
        case .oneToOne: return 1.0
        case .fourToThree: return 4.0 / 3.0
        case .threeToFour: return 3.0 / 4.0
        case .twoToOne: return 2.0
        case .oneToTwo: return 1.0 / 2.0
        }
    }
    
    var displayName: String {
        return rawValue
    }
}

// MARK: - 图片裁剪预览视图
struct ImageCropPreviewView: View {
    let sourceImage: UIImage
    @Binding var isPresented: Bool
    var onConfirm: (PerlerBeadsConfig.Resolution, PerlerBeadsConfig.PaletteSize, PerlerBeadsConfig.CanvasStyle) -> Void

    @State private var selectedResolution: PerlerBeadsConfig.Resolution = .x64
    @State private var selectedPaletteSize: PerlerBeadsConfig.PaletteSize = .c48
    @State private var selectedStyle: PerlerBeadsConfig.CanvasStyle = .perlerBeads
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var isGenerating = false
    
    // 图片变换状态
    @State private var rotation: CGFloat = 0
    @State private var isFlippedHorizontally: Bool = false
    @State private var isFlippedVertically: Bool = false

    // 裁剪区域比例选择
    @State private var selectedAspectRatio: CropAspectRatio = .oneToOne
    
    // 变换后的图片缓存
    @State private var transformedImage: UIImage
    
    init(sourceImage: UIImage, isPresented: Binding<Bool>, onConfirm: @escaping (PerlerBeadsConfig.Resolution, PerlerBeadsConfig.PaletteSize, PerlerBeadsConfig.CanvasStyle) -> Void) {
        self.sourceImage = sourceImage
        self._isPresented = isPresented
        self.onConfirm = onConfirm
        self._transformedImage = State(initialValue: sourceImage)
        print("[ImageCropPreviewView] Initialized with image size: \(sourceImage.size)")
    }
    
    // 应用变换并更新缓存
    private func applyTransformations() {
        DispatchQueue.global(qos: .userInitiated).async {
            var image = sourceImage
            
            // 应用水平翻转
            if isFlippedHorizontally {
                image = image.flippedHorizontally()
            }
            
            // 应用垂直翻转
            if isFlippedVertically {
                image = image.flippedVertically()
            }
            
            // 应用旋转
            if rotation != 0 {
                image = image.rotated(by: rotation)
            }
            
            DispatchQueue.main.async {
                transformedImage = image
            }
        }
    }

    var body: some View {
        print("[ImageCropPreviewView] Body rendering")
        return NavigationStack {
            VStack(spacing: 0) {
                // 图片预览区域
                GeometryReader { geometry in
                    let containerSize = geometry.size
                    let cropSize = calculateCropSize(in: containerSize)

                    ZStack {
                        // 暗色遮罩
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()

                        // 可拖动的图片（应用变换）
                        Image(uiImage: transformedImage)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        scale = min(max(scale * delta, 0.5), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )

                        // 裁剪框遮罩 - 使用统一容器确保对齐
                        GeometryReader { cropGeometry in
                            let containerWidth = cropGeometry.size.width
                            let containerHeight = cropGeometry.size.height
                            let cropSize = calculateCropSize(in: CGSize(width: containerWidth, height: containerHeight))
                            
                            ZStack {
                                // 半透明遮罩 - 挖空中间区域
                                Rectangle()
                                    .fill(Color.black.opacity(0.6))
                                    .mask(
                                        Rectangle()
                                            .overlay(
                                                Rectangle()
                                                    .frame(width: cropSize.width, height: cropSize.height)
                                                    .position(x: containerWidth / 2, y: containerHeight / 2)
                                                    .blendMode(.destinationOut)
                                            )
                                    )
                                
                                // 裁剪框边框
                                Rectangle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .frame(width: cropSize.width, height: cropSize.height)
                                    .position(x: containerWidth / 2, y: containerHeight / 2)
                                
                                // 网格线
                                GridOverlay(size: min(cropSize.width, cropSize.height), divisions: 3)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                                    .frame(width: cropSize.width, height: cropSize.height)
                                    .position(x: containerWidth / 2, y: containerHeight / 2)
                                
                                // 角标 - 适配实际裁剪框尺寸
                                CropCornerMarkers(width: cropSize.width, height: cropSize.height, length: 20)
                                    .stroke(Color.pink, lineWidth: 3)
                                    .frame(width: cropSize.width, height: cropSize.height)
                                    .position(x: containerWidth / 2, y: containerHeight / 2)
                            }
                        }
                        // 允许手势穿透到下层图片
                        .allowsHitTesting(false)
                    }
                }
                .frame(height: UIScreen.main.bounds.width)

                // 图片变换工具栏
                HStack(spacing: 0) {
                    // 镜像翻转
                    TransformButton(
                        icon: "flip.horizontal",
                        title: "镜像",
                        isActive: isFlippedHorizontally
                    ) {
                        isFlippedHorizontally.toggle()
                        applyTransformations()
                    }

                    Divider()
                        .frame(height: 30)

                    // 旋转
                    TransformButton(
                        icon: "rotate.right",
                        title: "旋转",
                        isActive: false
                    ) {
                        rotation += 90
                        if rotation >= 360 {
                            rotation = 0
                        }
                        applyTransformations()
                    }

                    Divider()
                        .frame(height: 30)

                    // 比例选择
                    AspectRatioPicker(selectedRatio: $selectedAspectRatio)

                    Divider()
                        .frame(height: 30)

                    // 重置
                    TransformButton(
                        icon: "arrow.counterclockwise",
                        title: "重置",
                        isActive: false
                    ) {
                        resetTransform()
                        applyTransformations()
                    }
                }
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                
                // 配置面板
                ScrollView {
                    VStack(spacing: 20) {
                        // 画布样式
                        VStack(alignment: .leading, spacing: 8) {
                            Text("画布样式")
                                .font(.headline)

                            Picker("样式", selection: $selectedStyle) {
                                Text("像素风格").tag(PerlerBeadsConfig.CanvasStyle.pixelArt)
                                Text("拼豆图纸").tag(PerlerBeadsConfig.CanvasStyle.perlerBeads)
                            }
                            .pickerStyle(.segmented)
                        }

                        // 分辨率选择
                        VStack(alignment: .leading, spacing: 8) {
                            Text("分辨率")
                                .font(.headline)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                                ForEach(PerlerBeadsConfig.Resolution.allCases) { resolution in
                                    ResolutionButton(
                                        resolution: resolution,
                                        isSelected: selectedResolution == resolution
                                    ) {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedResolution = resolution
                                        }
                                    }
                                }
                            }
                        }

                        // 颜色数量
                        VStack(alignment: .leading, spacing: 8) {
                            Text("颜色限制")
                                .font(.headline)

                            Picker("颜色数量", selection: $selectedPaletteSize) {
                                ForEach(PerlerBeadsConfig.PaletteSize.allCases) { size in
                                    Text(size.description)
                                        .tag(size)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // 预览信息
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("预计生成")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(selectedResolution.pixelCount) 颗拼豆")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("使用颜色")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("最多 \(selectedPaletteSize.rawValue) 色")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding()
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle("裁剪与设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: generatePattern) {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("生成")
                                .fontWeight(.bold)
                                .foregroundColor(.pink)
                        }
                    }
                    .disabled(isGenerating)
                }
            }
        }
    }

    private func generatePattern() {
        isGenerating = true

        // 在后台执行裁剪
        DispatchQueue.global(qos: .userInitiated).async {
            let croppedImage = self.cropImage()

            DispatchQueue.main.async {
                self.isGenerating = false
                self.isPresented = false
                // 将裁剪后的图片传递给回调
                self.onConfirmWithCroppedImage(croppedImage)
            }
        }
    }

    private func onConfirmWithCroppedImage(_ croppedImage: UIImage?) {
        // 创建一个回调闭包来传递裁剪后的图片
        // 这里通过通知中心发送裁剪后的图片
        if let image = croppedImage {
            NotificationCenter.default.post(
                name: .imageCropCompleted,
                object: nil,
                userInfo: ["croppedImage": image]
            )
        }
        onConfirm(selectedResolution, selectedPaletteSize, selectedStyle)
    }

    // 重置所有变换
    private func resetTransform() {
        withAnimation(.spring(response: 0.3)) {
            rotation = 0
            isFlippedHorizontally = false
            isFlippedVertically = false
            scale = 1.0
            offset = .zero
            lastScale = 1.0
            lastOffset = .zero
            selectedAspectRatio = .oneToOne
            transformedImage = sourceImage
        }
    }

    // 计算裁剪框尺寸
    private func calculateCropSize(in containerSize: CGSize) -> CGSize {
        let maxSize = min(containerSize.width, containerSize.height) * 0.85
        let ratio = selectedAspectRatio.ratio

        if ratio >= 1.0 {
            // 横向比例，宽度为基准
            let width = maxSize
            let height = width / ratio
            return CGSize(width: width, height: height)
        } else {
            // 纵向比例，高度为基准
            let height = maxSize
            let width = height * ratio
            return CGSize(width: width, height: height)
        }
    }

    // 裁剪图片
    private func cropImage() -> UIImage? {
        let image = transformedImage
        let imageSize = image.size

        // 容器尺寸（预览区域）
        let containerWidth = UIScreen.main.bounds.width
        let containerHeight = UIScreen.main.bounds.width

        // 计算裁剪框在容器中的尺寸
        let cropSize = calculateCropSize(in: CGSize(width: containerWidth, height: containerHeight))

        // 计算图片在容器中的实际显示尺寸（scaledToFill 模式）
        // scaledToFill 会保持图片比例，让图片填满整个容器
        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerWidth / containerHeight

        var displayImageSize: CGSize
        if imageAspectRatio > containerAspectRatio {
            // 图片比容器更宽，以容器高度为基准，宽度会超出
            displayImageSize = CGSize(
                width: containerHeight * imageAspectRatio,
                height: containerHeight
            )
        } else {
            // 图片比容器更高，以容器宽度为基准，高度会超出
            displayImageSize = CGSize(
                width: containerWidth,
                height: containerWidth / imageAspectRatio
            )
        }

        // 应用用户缩放
        displayImageSize.width *= scale
        displayImageSize.height *= scale

        // 计算图片中心点在容器中的位置（考虑用户偏移）
        let containerCenterX = containerWidth / 2
        let containerCenterY = containerHeight / 2
        let imageCenterX = containerCenterX + offset.width
        let imageCenterY = containerCenterY + offset.height

        // 计算裁剪框中心点
        let cropCenterX = containerCenterX
        let cropCenterY = containerCenterY

        // 计算裁剪框相对于图片的位置（在显示坐标系中）
        let cropXInDisplay = cropCenterX - cropSize.width / 2
        let cropYInDisplay = cropCenterY - cropSize.height / 2

        // 计算图片左上角在显示坐标系中的位置
        let imageXInDisplay = imageCenterX - displayImageSize.width / 2
        let imageYInDisplay = imageCenterY - displayImageSize.height / 2

        // 计算裁剪框相对于图片左上角的偏移（在显示坐标系中）
        let relativeX = cropXInDisplay - imageXInDisplay
        let relativeY = cropYInDisplay - imageYInDisplay

        // 将显示坐标系中的偏移转换为图片坐标系
        let scaleX = imageSize.width / displayImageSize.width
        let scaleY = imageSize.height / displayImageSize.height

        let cropXInImage = relativeX * scaleX
        let cropYInImage = relativeY * scaleY
        let cropWidthInImage = cropSize.width * scaleX
        let cropHeightInImage = cropSize.height * scaleY

        // 确保裁剪区域在图片范围内
        let finalCropRect = CGRect(
            x: max(0, min(cropXInImage, imageSize.width - 1)),
            y: max(0, min(cropYInImage, imageSize.height - 1)),
            width: min(cropWidthInImage, imageSize.width - max(0, cropXInImage)),
            height: min(cropHeightInImage, imageSize.height - max(0, cropYInImage))
        )

        // 执行裁剪
        guard let cgImage = image.cgImage?.cropping(to: finalCropRect) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - 变换按钮
struct TransformButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundColor(isActive ? .pink : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 比例选择器
struct AspectRatioPicker: View {
    @Binding var selectedRatio: CropAspectRatio
    @State private var showPicker = false

    var body: some View {
        Button(action: { showPicker = true }) {
            VStack(spacing: 4) {
                Image(systemName: "aspectratio")
                    .font(.system(size: 20))
                Text(selectedRatio.displayName)
                    .font(.system(size: 11))
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("选择裁剪比例", isPresented: $showPicker, titleVisibility: .visible) {
            ForEach(CropAspectRatio.allCases, id: \.self) { ratio in
                Button(ratio.displayName) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedRatio = ratio
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - 分辨率按钮
struct ResolutionButton: View {
    let resolution: PerlerBeadsConfig.Resolution
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(resolution.rawValue)")
                    .font(.system(size: 16, weight: .semibold))

                Text("x\(resolution.rawValue)")
                    .font(.system(size: 10))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .frame(width: 70, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.pink : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 网格覆盖层
struct GridOverlay: Shape {
    let size: CGFloat
    let divisions: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = size / CGFloat(divisions)

        // 垂直线
        for i in 1..<divisions {
            let x = CGFloat(i) * step
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size))
        }

        // 水平线
        for i in 1..<divisions {
            let y = CGFloat(i) * step
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size, y: y))
        }

        return path
    }
}

// MARK: - 裁剪框角标
struct CropCornerMarkers: Shape {
    let width: CGFloat
    let height: CGFloat
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 左上角
        path.move(to: CGPoint(x: 0, y: length))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: length, y: 0))

        // 右上角
        path.move(to: CGPoint(x: width - length, y: 0))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: length))

        // 右下角
        path.move(to: CGPoint(x: width, y: height - length))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: width - length, y: height))

        // 左下角
        path.move(to: CGPoint(x: length, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: height - length))

        return path
    }
}

// MARK: - UIImage 扩展
extension UIImage {
    /// 水平翻转
    func flippedHorizontally() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return self }
        
        context.translateBy(x: size.width, y: 0)
        context.scaleBy(x: -1, y: 1)
        
        draw(in: CGRect(origin: .zero, size: size))
        let flippedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return flippedImage ?? self
    }
    
    /// 垂直翻转
    func flippedVertically() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return self }
        
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        
        draw(in: CGRect(origin: .zero, size: size))
        let flippedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return flippedImage ?? self
    }
    
    /// 旋转图片
    func rotated(by degrees: CGFloat) -> UIImage {
        let radians = degrees * .pi / 180
        
        // 计算旋转后的尺寸
        let rotatedViewBox = UIView(frame: CGRect(origin: .zero, size: size))
        let t = CGAffineTransform(rotationAngle: radians)
        rotatedViewBox.transform = t
        let rotatedSize = rotatedViewBox.frame.size
        
        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return self }
        
        // 移动原点到中心并旋转
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: radians)
        
        // 绘制图片
        draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return rotatedImage ?? self
    }
}

// MARK: - 预览
#Preview {
    ImageCropPreviewView(
        sourceImage: UIImage(systemName: "photo")!,
        isPresented: .constant(true),
        onConfirm: { _, _, _ in }
    )
}
