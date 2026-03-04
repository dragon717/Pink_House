import SwiftUI
import PhotosUI

// MARK: - 通知名称扩展
extension Notification.Name {
    static let imageCropCompleted = Notification.Name("imageCropCompleted")
}

// MARK: - 拼豆工坊入口视图
struct PerlerBeadsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var showImagePicker = false
    @State private var showNewCanvasSheet = false
    @State private var showCropPreview = false
    @State private var showEditor = false
    @State private var selectedImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    @State private var newCanvasModel: PixelCanvasModel?
    @State private var croppedImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 顶部标题区
                    VStack(spacing: 16) {
                        // 图标
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.55, blue: 0.75),
                                            Color(red: 1.0, green: 0.41, blue: 0.71)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                                .shadow(color: Color(red: 1.0, green: 0.41, blue: 0.71).opacity(0.3), radius: 20, x: 0, y: 10)

                            Image(systemName: "circle.grid.2x2")
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                        }

                        // 标题
                        Text("拼豆工坊")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(themeManager.primaryTextColor)

                        Text("把照片变成拼豆图案")
                            .font(.system(size: 16))
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                    .padding(.top, 40)

                    Spacer()

                    // 主要功能选择区
                    VStack(spacing: 20) {
                        // 图片转拼豆
                        FeatureCard(
                            icon: "photo",
                            title: "图片转拼豆/像素画",
                            subtitle: "导入照片生成拼豆图案或像素画",
                            description: "支持 4x4 到 192x192 多种分辨率",
                            gradient: [Color(red: 1.0, green: 0.55, blue: 0.75), Color(red: 1.0, green: 0.41, blue: 0.71)],
                            action: {
                                showImagePicker = true
                            }
                        )

                        // 空白画布
                        FeatureCard(
                            icon: "pencil",
                            title: "自由绘制",
                            subtitle: "从零开始创作",
                            description: "手绘你的专属拼豆图案或像素画",
                            gradient: [Color(red: 0.4, green: 0.8, blue: 1.0), Color(red: 0.2, green: 0.6, blue: 0.9)],
                            action: {
                                showNewCanvasSheet = true
                            }
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // 底部提示
                    Text("选择一种方式开始创作吧")
                        .font(.system(size: 14))
                        .foregroundStyle(themeManager.tertiaryTextColor)
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle("拼豆工坊")
            .navigationBarTitleDisplayMode(.inline)
            // 图片选择器
            .photosPicker(
                isPresented: $showImagePicker,
                selection: $selectedItem,
                matching: .images
            )
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    // 重置之前裁剪的图片，避免使用缓存
                    await MainActor.run {
                        croppedImage = nil
                    }
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            selectedImage = image
                            showCropPreview = true
                        }
                    }
                }
            }
            // 图片裁剪预览
            .sheet(isPresented: $showCropPreview, onDismiss: {
                // 关闭裁剪页面时重置选择，允许重新选择同一张图片
                selectedItem = nil
                selectedImage = nil
            }) {
                if let image = selectedImage {
                    ImageCropPreviewView(
                        sourceImage: image,
                        isPresented: $showCropPreview,
                        onConfirm: { croppedImage, resolution, paletteSize, style in
                            // 直接接收裁剪后的图片，创建画布模型
                            self.croppedImage = croppedImage
                            let canvasModel = PixelCanvasModel(
                                resolution: resolution,
                                paletteSize: paletteSize,
                                canvasStyle: style
                            )
                            newCanvasModel = canvasModel
                            // 先触发导航，再清空选择
                            showEditor = true
                            // 延迟清空，确保导航完成
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                selectedItem = nil
                                selectedImage = nil
                            }
                        }
                    )
                }
            }
            // 新建画布配置
            .sheet(isPresented: $showNewCanvasSheet) {
                NewCanvasConfigSheet { resolution, paletteSize, style in
                    let canvasModel = PixelCanvasModel(
                        resolution: resolution,
                        paletteSize: paletteSize,
                        canvasStyle: style
                    )
                    newCanvasModel = canvasModel
                    showEditor = true
                }
            }
            // 编辑器
            .navigationDestination(isPresented: $showEditor) {
                if let canvasModel = newCanvasModel {
                    PerlerBeadsEditorView(
                        sourceImage: croppedImage,
                        initialCanvasModel: canvasModel
                    )
                } else {
                    PerlerBeadsEditorView()
                }
            }
        }
    }
}

// MARK: - 功能卡片
struct FeatureCard: View {
    @Environment(ThemeManager.self) private var themeManager
    
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // 图标
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }

                // 文字
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(themeManager.primaryTextColor)

                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(themeManager.secondaryTextColor)

                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(themeManager.tertiaryTextColor)
                }

                Spacer()

                // 箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(themeManager.tertiaryTextColor)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 新建画布配置面板
struct NewCanvasConfigSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedResolution: PerlerBeadsConfig.Resolution = .x64
    @State private var selectedPaletteSize: PerlerBeadsConfig.PaletteSize = .c48
    @State private var selectedStyle: PerlerBeadsConfig.CanvasStyle = .perlerBeads

    var onCreate: (PerlerBeadsConfig.Resolution, PerlerBeadsConfig.PaletteSize, PerlerBeadsConfig.CanvasStyle) -> Void

    var body: some View {
        NavigationStack {
            Form {
                // 画布样式
                Section("画布样式") {
                    Picker("样式", selection: $selectedStyle) {
                        Text("像素风格").tag(PerlerBeadsConfig.CanvasStyle.pixelArt)
                        Text("拼豆图纸").tag(PerlerBeadsConfig.CanvasStyle.perlerBeads)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Image(systemName: selectedStyle == .pixelArt ? "square.grid.2x2" : "circle.grid.2x2")
                            .font(.title2)
                            .foregroundColor(.pink)
                            .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedStyle.displayName)
                                .font(.body)
                            Text(selectedStyle == .pixelArt ? "方形像素，适合头像制作" : "圆形拼豆，带中心孔效果")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 分辨率选择
                Section("分辨率") {
                    Picker("分辨率", selection: $selectedResolution) {
                        ForEach(PerlerBeadsConfig.Resolution.allCases) { resolution in
                            Text(resolution.description)
                                .tag(resolution)
                        }
                    }
                    .pickerStyle(.wheel)

                    HStack {
                        Text("总像素数")
                        Spacer()
                        Text("\(selectedResolution.pixelCount)")
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                }

                // 颜色数量
                Section("颜色限制") {
                    Picker("颜色数量", selection: $selectedPaletteSize) {
                        ForEach(PerlerBeadsConfig.PaletteSize.allCases) { size in
                            Text(size.description)
                                .tag(size)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("限制颜色数量可以简化制作难度，降低材料成本")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 预览
                Section("预览") {
                    CanvasPreview(
                        resolution: selectedResolution,
                        paletteSize: selectedPaletteSize,
                        style: selectedStyle
                    )
                    .frame(height: 200)
                }
            }
            .navigationTitle("新建画布")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        onCreate(selectedResolution, selectedPaletteSize, selectedStyle)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.pink)
                }
            }
        }
    }
}

// MARK: - 画布预览
struct CanvasPreview: View {
    let resolution: PerlerBeadsConfig.Resolution
    let paletteSize: PerlerBeadsConfig.PaletteSize
    let style: PerlerBeadsConfig.CanvasStyle

    // 获取当前调色板
    private var palette: [BeadColor] {
        BeadColorPalette.colors(for: paletteSize)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.8
            let gridSize = resolution.rawValue
            let cellSize = size / CGFloat(gridSize)
            let gap = cellSize * 0.1

            Canvas { context, _ in
                // 背景
                context.fill(
                    Path(CGRect(origin: .zero, size: CGSize(width: size, height: size))),
                    with: .color(.white)
                )

                // 绘制示例图案（使用实际调色板颜色）
                for y in 0..<gridSize {
                    for x in 0..<gridSize {
                        let rect = CGRect(
                            x: CGFloat(x) * cellSize + gap / 2,
                            y: CGFloat(y) * cellSize + gap / 2,
                            width: cellSize - gap,
                            height: cellSize - gap
                        )

                        // 根据位置计算调色板索引，实现颜色量化效果
                        let colorIndex = colorIndexAt(x: x, y: y, gridSize: gridSize)
                        let color = palette[colorIndex]

                        switch style {
                        case .pixelArt:
                            context.fill(Path(rect), with: .color(color.color))
                        case .perlerBeads:
                            context.fill(Path(ellipseIn: rect), with: .color(color.color))
                        }

                        // 网格线
                        let gridRect = CGRect(
                            x: CGFloat(x) * cellSize,
                            y: CGFloat(y) * cellSize,
                            width: cellSize,
                            height: cellSize
                        )
                        context.stroke(
                            Path(gridRect),
                            with: .color(Color.gray.opacity(0.2)),
                            lineWidth: 0.5
                        )
                    }
                }

                // 边框
                context.stroke(
                    Path(CGRect(origin: .zero, size: CGSize(width: size, height: size))),
                    with: .color(Color.gray.opacity(0.5)),
                    lineWidth: 1
                )
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }

    /// 根据坐标计算调色板索引，展示颜色量化效果
    private func colorIndexAt(x: Int, y: Int, gridSize: Int) -> Int {
        let paletteCount = palette.count

        // 使用对角线渐变模式，将连续颜色映射到有限的调色板索引
        let position = Double(x + y) / Double(gridSize * 2)
        let index = Int(position * Double(paletteCount - 1))

        return min(max(index, 0), paletteCount - 1)
    }
}

// MARK: - 预览
#Preview {
    PerlerBeadsView()
}
