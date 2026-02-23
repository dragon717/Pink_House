import SwiftUI
import UIKit

// MARK: - 像素画布视图
struct PixelCanvasView: View {
    @Bindable var canvasModel: PixelCanvasModel

    // 视图状态
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isDragging = false
    
    // 编辑手势状态
    @State private var lastDrawLocation: CGPoint? = nil
    @State private var isDrawing = false

    // 配置
    var showGrid: Bool = true
    var isEditable: Bool = false
    var isEditMode: Bool = false

    // 工具模式
    var toolMode: ToolMode = .brush

    enum ToolMode {
        case brush      // 画笔
        case eraser     // 橡皮擦
        case picker     // 取色器
        case fill       // 填充刷
    }

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = min(geometry.size.width, geometry.size.height) * 0.9
            
            ZStack {
                // 画布内容
                Canvas { context, size in
                    drawCanvas(context: context, size: size)
                }
                .frame(width: canvasSize, height: canvasSize)
                .background(Color.white)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .scaleEffect(scale)
                .offset(offset)
                
                // 手势识别层
                CanvasGestureView(
                    isEditMode: isEditMode,
                    isEditable: isEditable,
                    canvasSize: canvasSize,
                    offset: $offset,
                    lastOffset: $lastOffset,
                    handleDraw: { location, size in
                        handleDraw(at: location, in: size)
                    },
                    saveHistory: {
                        canvasModel.saveToHistory()
                    }
                )
                .frame(width: canvasSize, height: canvasSize)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            // 双指缩放（所有模式都支持）
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, PerlerBeadsConfig.minZoomScale), PerlerBeadsConfig.maxZoomScale)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                    }
            )
        }
    }

    // MARK: - 绘制画布
    private func drawCanvas(context: GraphicsContext, size: CGSize) {
        let resolution = canvasModel.resolution.rawValue
        let pixelSize = size.width / CGFloat(resolution)
        
        // 绘制背景网格
        if showGrid {
            drawGrid(context: context, size: size, pixelSize: pixelSize)
        }
        
        // 绘制像素
        for y in 0..<resolution {
            for x in 0..<resolution {
                let colorIndex = canvasModel.getPixel(at: x, y: y)
                
                if colorIndex >= 0 && colorIndex < canvasModel.palette.count {
                    let beadColor = canvasModel.palette[colorIndex]
                    let color = beadColor.color
                    
                    let rect = CGRect(
                        x: CGFloat(x) * pixelSize,
                        y: CGFloat(y) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    
                    if canvasModel.isIronMode {
                        // 熨斗模式：填充整个格子的纯色块
                        context.fill(
                            Path(rect),
                            with: .color(color)
                        )
                    } else {
                        // 正常模式：绘制拼豆风格圆形
                        let drawSize = pixelSize * 0.85
                        let beadRect = CGRect(
                            x: rect.midX - drawSize / 2,
                            y: rect.midY - drawSize / 2,
                            width: drawSize,
                            height: drawSize
                        )
                        context.fill(
                            Path(ellipseIn: beadRect),
                            with: .color(color)
                        )
                        
                        // 绘制中心孔（小圆点）
                        let holeSize = drawSize * 0.25
                        let holeRect = CGRect(
                            x: rect.midX - holeSize / 2,
                            y: rect.midY - holeSize / 2,
                            width: holeSize,
                            height: holeSize
                        )
                        context.fill(
                            Path(ellipseIn: holeRect),
                            with: .color(.white.opacity(0.6))
                        )
                        
                        // 绘制颜色编号（当格子足够大时显示完整编号，否则只显示数字）
                        if pixelSize > 16 {
                            let text = pixelSize > 24 ? beadColor.id : String(beadColor.id.dropFirst())
                            let textColor = textColorForBackground(color)
                            let fontSize = pixelSize > 24 ? min(pixelSize * 0.35, 10) : min(pixelSize * 0.4, 8)
                            
                            var textRenderer = Text(text)
                                .font(.system(size: fontSize, weight: .bold))
                                .foregroundColor(textColor)
                            
                            let resolvedText = context.resolve(textRenderer)
                            let textSize = resolvedText.measure(in: CGSize(width: pixelSize, height: pixelSize))
                            let textRect = CGRect(
                                x: rect.midX - textSize.width / 2,
                                y: rect.midY - textSize.height / 2,
                                width: textSize.width,
                                height: textSize.height
                            )
                            
                            context.draw(resolvedText, in: textRect)
                        }
                    }
                }
            }
        }
    }
    
    // 绘制网格
    private func drawGrid(context: GraphicsContext, size: CGSize, pixelSize: CGFloat) {
        let resolution = canvasModel.resolution.rawValue
        
        // 绘制网格线
        for i in 0...resolution {
            // 垂直线
            let x = CGFloat(i) * pixelSize
            var vPath = Path()
            vPath.move(to: CGPoint(x: x, y: 0))
            vPath.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vPath, with: .color(Color.gray.opacity(0.3)), lineWidth: 0.5)
            
            // 水平线
            let y = CGFloat(i) * pixelSize
            var hPath = Path()
            hPath.move(to: CGPoint(x: 0, y: y))
            hPath.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(hPath, with: .color(Color.gray.opacity(0.3)), lineWidth: 0.5)
        }
    }

    // MARK: - 辅助方法
    
    /// 根据背景色计算文本颜色（黑或白）
    private func textColorForBackground(_ color: Color) -> Color {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // 计算亮度 (YIQ 公式)
        let brightness = (red * 299 + green * 587 + blue * 114) / 1000
        
        // 亮度大于 0.5 用黑色文字，否则用白色
        return brightness > 0.5 ? .black : .white
    }

    // MARK: - 处理绘制
    private func handleDraw(at location: CGPoint, in size: CGSize) {
        let resolution = canvasModel.resolution.rawValue
        let pixelSize = size.width / CGFloat(resolution)

        // 将触摸坐标转换为网格坐标
        let x = Int(location.x / pixelSize)
        let y = Int(location.y / pixelSize)

        // 检查坐标是否有效
        guard x >= 0, x < resolution, y >= 0, y < resolution else { return }

        switch toolMode {
        case .brush:
            canvasModel.drawPixel(at: x, y: y)

        case .eraser:
            canvasModel.erasePixel(at: x, y: y)

        case .picker:
            let colorIndex = canvasModel.getPixel(at: x, y: y)
            if colorIndex >= 0 {
                canvasModel.selectedColorIndex = colorIndex
            }
            
        case .fill:
            // 填充连通区域，然后自动切换回画笔
            canvasModel.floodFill(at: x, y: y)
            // 通知父视图切换回画笔模式
            NotificationCenter.default.post(name: .fillToolCompleted, object: nil)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let fillToolCompleted = Notification.Name("fillToolCompleted")
}

// MARK: - 手势识别器包装器
struct CanvasGestureView: UIViewRepresentable {
    let isEditMode: Bool
    let isEditable: Bool
    let canvasSize: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    let handleDraw: (CGPoint, CGSize) -> Void
    let saveHistory: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // 单指手势（绘制或移动）
        let singlePan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSinglePan(_:)))
        singlePan.minimumNumberOfTouches = 1
        singlePan.maximumNumberOfTouches = 1
        singlePan.delegate = context.coordinator
        view.addGestureRecognizer(singlePan)
        
        // 双指手势（移动画布）
        let doublePan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoublePan(_:)))
        doublePan.minimumNumberOfTouches = 2
        doublePan.maximumNumberOfTouches = 2
        doublePan.delegate = context.coordinator
        view.addGestureRecognizer(doublePan)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEditMode = isEditMode
        context.coordinator.isEditable = isEditable
        context.coordinator.canvasSize = canvasSize
        context.coordinator.handleDraw = handleDraw
        context.coordinator.saveHistory = saveHistory
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CanvasGestureView
        var isEditMode: Bool = false
        var isEditable: Bool = false
        var canvasSize: CGFloat = 0
        var handleDraw: ((CGPoint, CGSize) -> Void)?
        var saveHistory: (() -> Void)?
        private var lastDrawLocation: CGPoint?
        
        init(_ parent: CanvasGestureView) {
            self.parent = parent
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        @objc func handleSinglePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let size = CGSize(width: canvasSize, height: canvasSize)
            
            if isEditMode && isEditable {
                // 编辑模式：单指使用工具
                switch gesture.state {
                case .began, .changed:
                    // 限制绘制频率以提高性能但保持跟手
                    if lastDrawLocation == nil || distance(location, lastDrawLocation!) > 3 {
                        handleDraw?(location, size)
                        lastDrawLocation = location
                    }
                case .ended, .cancelled:
                    lastDrawLocation = nil
                    saveHistory?()
                default:
                    break
                }
            } else {
                // 非编辑模式：单指移动画布
                let translation = gesture.translation(in: gesture.view)
                switch gesture.state {
                case .changed:
                    parent.offset = CGSize(
                        width: parent.lastOffset.width + translation.x,
                        height: parent.lastOffset.height + translation.y
                    )
                case .ended, .cancelled:
                    parent.lastOffset = parent.offset
                default:
                    break
                }
            }
        }
        
        @objc func handleDoublePan(_ gesture: UIPanGestureRecognizer) {
            guard isEditMode && isEditable else { return }
            
            // 编辑模式：双指移动画布
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .changed:
                parent.offset = CGSize(
                    width: parent.lastOffset.width + translation.x,
                    height: parent.lastOffset.height + translation.y
                )
            case .ended, .cancelled:
                parent.lastOffset = parent.offset
            default:
                break
            }
        }
        
        private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
            sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
        }
    }
}

// MARK: - 拼豆工具栏视图
struct PerlerCanvasToolbar: View {
    @Bindable var canvasModel: PixelCanvasModel
    @Binding var toolMode: PixelCanvasView.ToolMode
    @Binding var showGrid: Bool
    @Binding var isEditMode: Bool
    @Binding var showPalette: Bool

    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClear: () -> Void
    var onFill: () -> Void
    var onSave: () -> Void
    var onShare: () -> Void
    var onIron: () -> Void = {} // 熨斗功能回调

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // 判断是否足够宽以显示为一排（每个按钮约50pt + 间距）
            let isWide = width > 500
            
            VStack(spacing: 8) {
                if isWide {
                    // 宽屏：一排显示所有按钮
                    HStack(spacing: 12) {
                        toolbarContent()
                    }
                } else {
                    // 窄屏：两排显示
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            editModeButton()
                            Divider().frame(height: 32)
                            undoRedoButtons()
                            Divider().frame(height: 32)
                            toolButtons()
                        }
                        HStack(spacing: 12) {
                            paletteAndActionButtons()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
            )
        }
    }
    
    // 宽屏时使用的整体内容
    @ViewBuilder
    private func toolbarContent() -> some View {
        editModeButton()
        Divider().frame(height: 32)
        undoRedoButtons()
        Divider().frame(height: 32)
        toolButtons()
        Divider().frame(height: 32)
        paletteAndActionButtons()
    }
    
    // 编辑模式按钮
    private func editModeButton() -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                isEditMode.toggle()
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isEditMode ? "pencil.circle.fill" : "pencil.circle")
                    .font(.system(size: 22))
                Text(isEditMode ? "编辑中" : "编辑")
                    .font(.system(size: 9))
            }
            .foregroundColor(isEditMode ? .pink : .primary)
            .frame(width: 50)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEditMode ? Color.pink.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // 撤销重做按钮
    private func undoRedoButtons() -> some View {
        HStack(spacing: 8) {
            PerlerToolbarButtonWithLabel(
                icon: "arrow.uturn.backward",
                label: "撤销",
                isEnabled: canvasModel.canUndo(),
                action: onUndo
            )
            PerlerToolbarButtonWithLabel(
                icon: "arrow.uturn.forward",
                label: "重做",
                isEnabled: canvasModel.canRedo(),
                action: onRedo
            )
        }
    }
    
    // 工具按钮（画笔、橡皮、取色）
    private func toolButtons() -> some View {
        HStack(spacing: 8) {
            // 画笔 + 当前选中颜色
            Button {
                toolMode = .brush
            } label: {
                VStack(spacing: 2) {
                    ZStack {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 20))
                        Circle()
                            .fill(canvasModel.selectedColorIndex < canvasModel.palette.count ? 
                                  canvasModel.palette[canvasModel.selectedColorIndex].color : Color.clear)
                            .frame(width: 8, height: 8)
                            .offset(x: 8, y: -8)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 8, y: -8)
                            )
                    }
                    Text("画笔")
                        .font(.system(size: 9))
                }
                .foregroundColor(toolMode == .brush ? .pink : (isEditMode ? .primary : .gray.opacity(0.5)))
                .frame(width: 50, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(toolMode == .brush ? Color.pink.opacity(0.15) : Color.clear)
                )
            }
            .disabled(!isEditMode)
            .buttonStyle(PlainButtonStyle())
            
            PerlerToolbarButtonWithLabel(
                icon: "eraser",
                label: "橡皮",
                isSelected: toolMode == .eraser,
                isEnabled: isEditMode,
                action: { toolMode = .eraser }
            )
            
            PerlerToolbarButtonWithLabel(
                icon: "eyedropper",
                label: "取色",
                isSelected: toolMode == .picker,
                isEnabled: isEditMode,
                action: { toolMode = .picker }
            )
        }
    }
    
    // 调色板和操作按钮
    private func paletteAndActionButtons() -> some View {
        HStack(spacing: 8) {
            PerlerToolbarButtonWithLabel(
                icon: "paintpalette",
                label: "色卡",
                isSelected: showPalette,
                action: { 
                    withAnimation(.spring(response: 0.3)) {
                        showPalette.toggle()
                    }
                }
            )
            
            PerlerToolbarButtonWithLabel(
                icon: "grid",
                label: "网格",
                isSelected: showGrid,
                action: { showGrid.toggle() }
            )
            
            PerlerToolbarButtonWithLabel(
                icon: "xmark.square",
                label: "清空",
                isEnabled: isEditMode,
                action: onClear
            )
            
            PerlerToolbarButtonWithLabel(
                icon: "paintbrush.fill",
                label: "填充",
                isSelected: toolMode == .fill,
                isEnabled: isEditMode,
                action: { toolMode = .fill }
            )
            
            Divider().frame(height: 24)
            
            PerlerToolbarButtonWithLabel(
                icon: "square.and.arrow.down",
                label: "保存",
                isPrimary: true,
                action: onSave
            )
            
            PerlerToolbarButtonWithLabel(
                icon: "square.and.arrow.up",
                label: "分享",
                isPrimary: false,
                action: onShare
            )
            
            // 熨斗按钮 - 拼豆特有功能
            PerlerToolbarButtonWithLabel(
                icon: "wand.and.stars",
                label: "熨斗",
                isSelected: canvasModel.isIronMode,
                action: onIron
            )
        }
    }
}

// MARK: - 拼豆工具栏按钮（纯图标）
struct PerlerToolbarButton: View {
    let icon: String
    var isSelected: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isSelected ? .pink : (isEnabled ? .primary : .gray.opacity(0.5)))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isSelected ? Color.pink.opacity(0.15) : Color.clear)
                )
        }
        .disabled(!isEnabled)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 拼豆工具栏按钮（图标+文字）
struct PerlerToolbarButtonWithLabel: View {
    let icon: String
    let label: String
    var isSelected: Bool = false
    var isPrimary: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundColor(
                isSelected ? .pink : 
                (isPrimary ? .pink : 
                 (isEnabled ? .primary : .gray.opacity(0.5)))
            )
            .frame(width: 50, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected ? Color.pink.opacity(0.15) :
                        (isPrimary ? Color.pink.opacity(0.15) : Color.clear)
                    )
            )
        }
        .disabled(!isEnabled)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 颜色选择器视图
struct ColorPaletteView: View {
    @Bindable var canvasModel: PixelCanvasModel
    @State private var showColorInfo = false
    var scale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let totalHeight = geometry.size.height
            
            // 左侧固定宽度，右侧自适应
            let leftWidth: CGFloat = min(60 * scale, 70)
            let rightWidth = totalWidth - leftWidth - 24 * scale // 24 = spacing + padding
            
            // 根据右侧宽度动态计算列数
            let minCellWidth: CGFloat = 36 * scale
            let spacing: CGFloat = 4 * scale
            let columns = max(4, Int((rightWidth - 16) / (minCellWidth + spacing)))
            
            // 根据总高度计算行数（至少2行，最多4行）
            let minCellHeight: CGFloat = 36 * scale
            let maxRows = min(4, max(2, Int((totalHeight - 16) / (minCellHeight + spacing))))
            let gridHeight = CGFloat(maxRows) * (minCellHeight + spacing) + spacing
            
            HStack(spacing: 12 * scale) {
                // 左侧：当前选中颜色（色在上，名在下）
                if canvasModel.selectedColorIndex < canvasModel.palette.count {
                    let selectedColor = canvasModel.palette[canvasModel.selectedColorIndex]
                    VStack(spacing: 4 * scale) {
                        Circle()
                            .fill(selectedColor.color)
                            .frame(width: min(44 * scale, 50), height: min(44 * scale, 50))
                            .overlay(
                                Circle()
                                    .stroke(Color.pink.opacity(0.5), lineWidth: 2 * scale)
                            )
                        
                        Text(selectedColor.name)
                            .font(.system(size: 10 * scale, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        Text(selectedColor.id)
                            .font(.system(size: 9 * scale))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: leftWidth)
                    .padding(.vertical, 4)
                }
                
                Divider()
                    .frame(width: 1)
                
                // 右侧：颜色网格（自适应列数和高度，支持滚动）
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                        spacing: spacing
                    ) {
                        ForEach(canvasModel.palette.indices, id: \.self) { index in
                            let color = canvasModel.palette[index]
                            ColorCell(
                                color: color,
                                isSelected: canvasModel.selectedColorIndex == index,
                                scale: scale * 0.85,
                                onTap: {
                                    canvasModel.selectedColorIndex = index
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(width: rightWidth, height: gridHeight)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showColorInfo) {
            ColorInfoSheet(palette: canvasModel.palette)
        }
    }
}

// MARK: - 颜色单元格
struct ColorCell: View {
    let color: BeadColor
    let isSelected: Bool
    var scale: CGFloat = 1.0
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(color.color)
                    .frame(width: 36 * scale, height: 36 * scale)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.pink : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 * scale : 1)
                    )
                    .shadow(
                        color: isSelected ? Color.pink.opacity(0.4) : Color.clear,
                        radius: 3 * scale,
                        x: 0,
                        y: 1
                    )

                // 显示颜色编号
                Text(color.id)
                    .font(.system(size: 7 * scale, weight: .bold))
                    .foregroundColor(textColorForCell(color.color))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // 根据背景色计算对比文字颜色
    private func textColorForCell(_ color: Color) -> Color {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // 计算亮度 (YIQ 公式)
        let brightness = (red * 299 + green * 587 + blue * 114) / 1000
        
        // 亮度大于 0.5 用黑色文字，否则用白色
        return brightness > 0.5 ? .black : .white
    }
}

// MARK: - 颜色信息表
struct ColorInfoSheet: View {
    let palette: [BeadColor]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(palette) { color in
                    HStack {
                        Circle()
                            .fill(color.color)
                            .frame(width: 30, height: 30)

                        VStack(alignment: .leading) {
                            Text(color.name)
                                .font(.headline)
                            Text(color.id)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("颜色信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}
