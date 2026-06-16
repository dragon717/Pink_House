import SwiftUI
import UIKit

// MARK: - 像素画布视图
struct PixelCanvasView: View {
    @Bindable var canvasModel: PixelCanvasModel

    // 视图状态 - 使用 @GestureState 优化手势性能
    @State private var scale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    @State private var isDragging = false
    
    // 编辑手势状态
    @State private var lastDrawLocation: CGPoint? = nil
    @State private var isDrawing = false
    
    // 填充工具防抖状态
    @State private var isFillInProgress = false

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
            let totalScale = scale * gestureScale
            let totalOffset = CGSize(
                width: offset.width + gestureOffset.width,
                height: offset.height + gestureOffset.height
            )
            
            ZStack {
                // 画布内容 - 使用 drawingGroup 优化渲染性能
                Canvas { context, size in
                    drawCanvas(context: context, size: size)
                }
                .frame(width: canvasSize, height: canvasSize)
                .background(Color.white)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .scaleEffect(totalScale)
                .offset(totalOffset)
                // 使用 drawingGroup 将画布内容渲染到离屏缓冲区，大幅提升性能
                .drawingGroup(opaque: false, colorMode: .linear)
                
                // 手势识别层
                CanvasGestureView(
                    isEditMode: isEditMode,
                    isEditable: isEditable,
                    canvasSize: canvasSize,
                    scale: totalScale,
                    offset: $offset,
                    onPan: { newOffset in
                        // 更新 offset
                        offset = newOffset
                    },
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
            // 双指缩放（所有模式都支持）- 使用 @GestureState 优化
            .gesture(
                MagnificationGesture()
                    .updating($gestureScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        let newScale = scale * value
                        scale = min(max(newScale, PerlerBeadsConfig.minZoomScale), PerlerBeadsConfig.maxZoomScale)
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
        
        // 使用更高效的批量绘制
        if canvasModel.isIronMode {
            // 熨斗模式：批量绘制矩形
            drawIronModePixels(context: context, resolution: resolution, pixelSize: pixelSize)
        } else {
            // 正常模式：批量绘制圆形
            drawBeadModePixels(context: context, resolution: resolution, pixelSize: pixelSize)
        }
    }
    
    // MARK: - 熨斗模式绘制（批量矩形）
    private func drawIronModePixels(context: GraphicsContext, resolution: Int, pixelSize: CGFloat) {
        for y in 0..<resolution {
            for x in 0..<resolution {
                let colorIndex = canvasModel.getPixel(at: x, y: y)
                guard colorIndex >= 0 && colorIndex < canvasModel.palette.count else { continue }
                
                let beadColor = canvasModel.palette[colorIndex]
                let rect = CGRect(
                    x: CGFloat(x) * pixelSize,
                    y: CGFloat(y) * pixelSize,
                    width: pixelSize,
                    height: pixelSize
                )
                
                context.fill(Path(rect), with: .color(beadColor.color))
            }
        }
    }
    
    // MARK: - 拼豆模式绘制（批量圆形）
    private func drawBeadModePixels(context: GraphicsContext, resolution: Int, pixelSize: CGFloat) {
        let drawSize = pixelSize * 0.85
        let holeSize = drawSize * 0.25
        let showText = pixelSize > 16
        
        for y in 0..<resolution {
            for x in 0..<resolution {
                let colorIndex = canvasModel.getPixel(at: x, y: y)
                guard colorIndex >= 0 && colorIndex < canvasModel.palette.count else { continue }
                
                let beadColor = canvasModel.palette[colorIndex]
                let rect = CGRect(
                    x: CGFloat(x) * pixelSize,
                    y: CGFloat(y) * pixelSize,
                    width: pixelSize,
                    height: pixelSize
                )
                
                // 绘制拼豆圆形
                let beadRect = CGRect(
                    x: rect.midX - drawSize / 2,
                    y: rect.midY - drawSize / 2,
                    width: drawSize,
                    height: drawSize
                )
                context.fill(Path(ellipseIn: beadRect), with: .color(beadColor.color))
                
                // 绘制中心孔
                let holeRect = CGRect(
                    x: rect.midX - holeSize / 2,
                    y: rect.midY - holeSize / 2,
                    width: holeSize,
                    height: holeSize
                )
                context.fill(Path(ellipseIn: holeRect), with: .color(.white.opacity(0.6)))
                
                // 绘制颜色编号
                if showText {
                    let text = pixelSize > 24 ? beadColor.id : String(beadColor.id.dropFirst())
                    let textColor = textColorForBackground(beadColor.color)
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

        // 打印详细的坐标转换日志
        print("[PerlerBeads][Draw] ========== 坐标转换日志 ==========")
        print("[PerlerBeads][Draw] 手指触摸坐标: location=(\(String(format: "%.2f", location.x)), \(String(format: "%.2f", location.y)))")
        print("[PerlerBeads][Draw] 画布尺寸: size=(\(String(format: "%.2f", size.width)), \(String(format: "%.2f", size.height)))")
        print("[PerlerBeads][Draw] 像素大小: pixelSize=\(String(format: "%.4f", pixelSize))")
        print("[PerlerBeads][Draw] 分辨率: resolution=\(resolution)x\(resolution)")
        print("[PerlerBeads][Draw] 计算后的网格坐标: x=\(x), y=\(y)")
        print("[PerlerBeads][Draw] 当前工具模式: toolMode=\(toolMode)")
        print("[PerlerBeads][Draw] 当前偏移量: offset=(\(String(format: "%.2f", offset.width)), \(String(format: "%.2f", offset.height)))")
        print("[PerlerBeads][Draw] 当前缩放: scale=\(String(format: "%.2f", scale))")

        // 检查坐标是否有效
        guard x >= 0, x < resolution, y >= 0, y < resolution else {
            print("[PerlerBeads][Draw] 坐标超出范围，忽略绘制")
            return
        }

        print("[PerlerBeads][Draw] 坐标有效，执行绘制操作")

        switch toolMode {
        case .brush:
            print("[PerlerBeads][Draw] 执行: 画笔绘制 at (\(x), \(y))")
            canvasModel.drawPixel(at: x, y: y)

        case .eraser:
            print("[PerlerBeads][Draw] 执行: 橡皮擦除 at (\(x), \(y))")
            canvasModel.erasePixel(at: x, y: y)

        case .picker:
            print("[PerlerBeads][Draw] 执行: 取色器 at (\(x), \(y))")
            let colorIndex = canvasModel.getPixel(at: x, y: y)
            print("[PerlerBeads][Draw] 取色结果: colorIndex=\(colorIndex)")
            if colorIndex >= 0 {
                canvasModel.selectedColorIndex = colorIndex
            }
            
        case .fill:
            // 防抖检查：防止填充操作被多次触发
            guard !isFillInProgress else {
                print("[PerlerBeads][Draw] 填充操作正在进行中，忽略重复触发")
                return
            }
            
            print("[PerlerBeads][Draw] 执行: 填充工具 at (\(x), \(y))")
            isFillInProgress = true
            
            // 填充连通区域
            canvasModel.floodFill(at: x, at: y)
            
            // 延迟重置防抖状态并通知父视图切换回画笔
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFillInProgress = false
                // 通知父视图切换回画笔模式
                NotificationCenter.default.post(name: .fillToolCompleted, object: nil)
            }
        }
        print("[PerlerBeads][Draw] =================================")
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
    let scale: CGFloat
    @Binding var offset: CGSize
    let onPan: ((CGSize) -> Void)?
    let handleDraw: (CGPoint, CGSize) -> Void
    let saveHistory: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // 单指点击手势（用于轻点绘制）
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.numberOfTouchesRequired = 1
        tapGesture.delegate = context.coordinator
        view.addGestureRecognizer(tapGesture)
        
        // 单指拖动手势（绘制或移动）
        let singlePan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSinglePan(_:)))
        singlePan.minimumNumberOfTouches = 1
        singlePan.maximumNumberOfTouches = 1
        singlePan.delegate = context.coordinator
        view.addGestureRecognizer(singlePan)
        
        // 长按手势（用于更灵敏的绘制触发）
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.01 // 非常短的按压时间，几乎立即触发
        longPress.numberOfTouchesRequired = 1
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)
        
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
        context.coordinator.scale = scale
        context.coordinator.offset = offset
        context.coordinator.handleDraw = handleDraw
        context.coordinator.saveHistory = saveHistory
        context.coordinator.onPan = onPan
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CanvasGestureView
        var isEditMode: Bool = false
        var isEditable: Bool = false
        var canvasSize: CGFloat = 0
        var scale: CGFloat = 1.0
        var offset: CGSize = .zero
        var handleDraw: ((CGPoint, CGSize) -> Void)?
        var saveHistory: (() -> Void)?
        var onPan: ((CGSize) -> Void)?
        private var lastDrawLocation: CGPoint?
        private var panStartOffset: CGSize = .zero
        
        init(_ parent: CanvasGestureView) {
            self.parent = parent
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        /// 将手势坐标转换为画布坐标（考虑缩放和偏移）
        private func convertToCanvasCoordinates(_ location: CGPoint) -> CGPoint {
            // 手势视图的中心点
            let centerX = canvasSize / 2
            let centerY = canvasSize / 2
            
            // 1. 将坐标转换为相对于中心的坐标
            let relativeX = location.x - centerX
            let relativeY = location.y - centerY
            
            // 2. 考虑缩放：将缩放后的坐标转换为原始坐标
            let scaledX = relativeX / scale
            let scaledY = relativeY / scale
            
            // 3. 考虑偏移：减去偏移量
            let finalX = scaledX - (offset.width / scale)
            let finalY = scaledY - (offset.height / scale)
            
            // 4. 转换回左上角坐标系
            let canvasX = finalX + centerX
            let canvasY = finalY + centerY
            
            print("[PerlerBeads][Coordinate] 坐标转换: input=(\(String(format: "%.2f", location.x)), \(String(format: "%.2f", location.y))) -> output=(\(String(format: "%.2f", canvasX)), \(String(format: "%.2f", canvasY)))")
            print("[PerlerBeads][Coordinate] 参数: scale=\(String(format: "%.2f", scale)), offset=(\(String(format: "%.2f", offset.width)), \(String(format: "%.2f", offset.height)))")
            
            return CGPoint(x: canvasX, y: canvasY)
        }
        
        // MARK: - 点击手势处理（单指轻点）
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let size = CGSize(width: canvasSize, height: canvasSize)
            
            print("[PerlerBeads][Tap] 单指点击手势触发，location=(\(String(format: "%.2f", location.x)), \(String(format: "%.2f", location.y)))")
            print("[PerlerBeads][Tap] isEditMode=\(isEditMode), isEditable=\(isEditable)")
            
            guard isEditMode && isEditable else {
                print("[PerlerBeads][Tap] 非编辑模式或不可编辑，忽略点击")
                return
            }
            
            // 将手势坐标转换为画布坐标
            let canvasLocation = convertToCanvasCoordinates(location)
            
            print("[PerlerBeads][Tap] 触发绘制操作")
            handleDraw?(canvasLocation, size)
            
            // 填充工具在手势结束时自动保存历史，其他工具立即保存
            // 注意：填充工具的 saveHistory 在 floodFill 内部已经调用
        }
        
        // MARK: - 长按手势处理（用于快速响应）
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let size = CGSize(width: canvasSize, height: canvasSize)
            
            print("[PerlerBeads][LongPress] 长按手势 state=\(gesture.state.rawValue), location=(\(String(format: "%.2f", location.x)), \(String(format: "%.2f", location.y)))")
            
            guard isEditMode && isEditable else { return }
            
            // 将手势坐标转换为画布坐标
            let canvasLocation = convertToCanvasCoordinates(location)
            
            switch gesture.state {
            case .began:
                print("[PerlerBeads][LongPress] 长按开始，触发绘制")
                handleDraw?(canvasLocation, size)
                lastDrawLocation = canvasLocation
            case .changed:
                // 长按移动时也可以绘制（仅适用于画笔和橡皮，不适用于填充）
                if lastDrawLocation == nil || distance(canvasLocation, lastDrawLocation!) > 3 {
                    print("[PerlerBeads][LongPress] 长按移动中，触发绘制")
                    handleDraw?(canvasLocation, size)
                    lastDrawLocation = canvasLocation
                }
            case .ended, .cancelled:
                print("[PerlerBeads][LongPress] 长按结束")
                lastDrawLocation = nil
                // 注意：填充工具的历史记录在其内部已经保存，其他工具在这里保存
            default:
                break
            }
        }
        
        // MARK: - 单指拖动手势处理
        @objc func handleSinglePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let size = CGSize(width: canvasSize, height: canvasSize)
            
            // 打印手势识别日志
            if gesture.state == .began || gesture.state == .changed {
                print("[PerlerBeads][Pan] 单指拖动手势 state=\(gesture.state == .began ? "began" : "changed"), rawLocation=(\(String(format: "%.2f", location.x)), \(String(format: "%.2f", location.y)))")
                print("[PerlerBeads][Pan] isEditMode=\(isEditMode), isEditable=\(isEditable)")
            }
            
            if isEditMode && isEditable {
                // 编辑模式：单指使用工具
                
                // 将手势坐标转换为画布坐标
                let canvasLocation = convertToCanvasCoordinates(location)
                
                switch gesture.state {
                case .began:
                    // 手势开始时触发一次绘制（适用于所有工具，包括填充）
                    print("[PerlerBeads][Pan] 手势开始，触发绘制")
                    handleDraw?(canvasLocation, size)
                    lastDrawLocation = canvasLocation
                case .changed:
                    // 手势移动时连续绘制（仅适用于画笔和橡皮，不适用于填充和取色）
                    // 限制绘制频率以提高性能但保持跟手
                    if lastDrawLocation == nil || distance(canvasLocation, lastDrawLocation!) > 3 {
                        print("[PerlerBeads][Pan] 触发绘制，距离过滤通过")
                        handleDraw?(canvasLocation, size)
                        lastDrawLocation = canvasLocation
                    } else {
                        print("[PerlerBeads][Pan] 绘制被距离过滤跳过，lastDrawLocation=(\(String(format: "%.2f", lastDrawLocation?.x ?? 0)), \(String(format: "%.2f", lastDrawLocation?.y ?? 0)))")
                    }
                case .ended, .cancelled:
                    print("[PerlerBeads][Pan] 单指拖动结束/取消")
                    lastDrawLocation = nil
                    // 注意：填充工具的历史记录在其内部已经保存，其他工具需要在这里保存
                default:
                    break
                }
            } else {
                // 非编辑模式：单指移动画布
                let translation = gesture.translation(in: gesture.view)
                switch gesture.state {
                case .began:
                    panStartOffset = parent.offset
                    print("[PerlerBeads][Pan] 开始移动画布，panStartOffset=(\(String(format: "%.2f", panStartOffset.width)), \(String(format: "%.2f", panStartOffset.height)))")
                case .changed:
                    // 实时更新 offset
                    let newOffset = CGSize(
                        width: panStartOffset.width + translation.x,
                        height: panStartOffset.height + translation.y
                    )
                    print("[PerlerBeads][Pan] 移动画布中，translation=(\(String(format: "%.2f", translation.x)), \(String(format: "%.2f", translation.y))), newOffset=(\(String(format: "%.2f", newOffset.width)), \(String(format: "%.2f", newOffset.height)))")
                    parent.offset = newOffset
                    onPan?(newOffset)
                case .ended, .cancelled:
                    print("[PerlerBeads][Pan] 移动画布结束")
                    panStartOffset = .zero
                default:
                    break
                }
            }
        }
        
        @objc func handleDoublePan(_ gesture: UIPanGestureRecognizer) {
            guard isEditMode && isEditable else { 
                print("[PerlerBeads][DoublePan] 非编辑模式或不可编辑，忽略双指手势")
                return 
            }
            
            // 编辑模式：双指移动画布
            let translation = gesture.translation(in: gesture.view)
            print("[PerlerBeads][DoublePan] 双指手势 state=\(gesture.state.rawValue), translation=(\(String(format: "%.2f", translation.x)), \(String(format: "%.2f", translation.y)))")
            
            switch gesture.state {
            case .began:
                panStartOffset = parent.offset
                print("[PerlerBeads][DoublePan] 开始双指移动画布，panStartOffset=(\(String(format: "%.2f", panStartOffset.width)), \(String(format: "%.2f", panStartOffset.height)))")
            case .changed:
                let newOffset = CGSize(
                    width: panStartOffset.width + translation.x,
                    height: panStartOffset.height + translation.y
                )
                print("[PerlerBeads][DoublePan] 双指移动画布中，newOffset=(\(String(format: "%.2f", newOffset.width)), \(String(format: "%.2f", newOffset.height)))")
                parent.offset = newOffset
                onPan?(newOffset)
            case .ended, .cancelled:
                print("[PerlerBeads][DoublePan] 双指移动画布结束")
                panStartOffset = .zero
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
    var onSaveToCollection: () -> Void
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
                Text(isEditMode ? "编辑中".appLocalized : "编辑".appLocalized)
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
                    Text("画笔".appLocalized)
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
                action: { 
                    withAnimation(.spring(response: 0.2)) {
                        toolMode = .fill 
                    }
                }
            )
            .help("点击画布填充连通区域".appLocalized)
            
            Divider().frame(height: 24)
            
            // 保存菜单按钮
            Menu {
                Button {
                    onSaveToCollection()
                } label: {
                    Label("保存到作品集".appLocalized, systemImage: "folder")
                }
                
                Button {
                    onSave()
                } label: {
                    Label("保存图片".appLocalized, systemImage: "photo")
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .medium))
                    Text("保存".appLocalized)
                        .font(.system(size: 9))
                }
                .foregroundColor(.pink)
                .frame(width: 50, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.pink.opacity(0.15))
                )
            }
            
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
                Text(label.appLocalized)
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
            .navigationTitle("颜色信息".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成".appLocalized) {
                        dismiss()
                    }
                }
            }
        }
    }
}
