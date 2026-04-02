import SwiftUI
import UIKit
import Vision

// MARK: - 重构后的 PetOverlayView
// 职责：只负责布局和状态协调，将具体逻辑委托给专门的组件

struct PetOverlayView: View {
    // MARK: - 配置属性
    
    var action: () -> Void
    var petName: String = "小伙伴"
    
    // MARK: - 依赖管理器
    
    @StateObject private var interactionManager = PetInteractionManager.shared
    @StateObject private var visionManager = VisionManager.shared
    @StateObject private var gestureHandler = PetGestureHandler()
    @StateObject private var aiAnalysisService = PetAIAnalysisService.shared
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    
    // MARK: - 状态管理（精简后的核心状态）
    
    @State private var isBreathing: Bool = false
    @State private var idleX: CGFloat? = nil
    @State private var isHiddenForSnapshot: Bool = false
    @State private var showingAnalysisResult: Bool = false
    @State private var capturedImage: UIImage?
    @State private var analysisResult: PetAIAnalysisResult?
    
    // MARK: - 轨迹效果状态
    
    @AppStorage("petTrailTheme") private var trailTheme: PetTrailTheme = .defaultPink
    @AppStorage("petTrailCustomColor1") private var customColor1Hex: String = "FFC0CB"
    @AppStorage("petTrailCustomColor2") private var customColor2Hex: String = "D87093"
    @AppStorage("petTrailCustomColor3") private var customColor3Hex: String = "F5F5DC"
    
    // MARK: - 配置参数
    
    private let catWidth: CGFloat = 70
    private let visionROISize: CGFloat = 400
    private let screenshotScale: CGFloat = 0.5
    private let visionCheckInterval: TimeInterval = 0.3
    
    // MARK: - 计算属性
    
    private var petImagePrefix: String {
        interactionManager.currentPetId
    }
    
    private var isDragging: Bool {
        if case .dragging = gestureHandler.state {
            return true
        }
        return false
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 轨迹效果层
                trailEffectLayer
                
                // 圆圈检测提示层
                circleDetectionLayer
                
                // 宠物视图层
                petViewLayer(geometry: geometry)
                
                // AI分析中提示层
                analyzingLayer(geometry: geometry)
                
                // AI分析结果层
                analysisResultLayer
            }
            .coordinateSpace(name: "PetOverlaySpace")
            .animation(getAnimation(for: interactionManager.state), value: interactionManager.state)
            .onAppear { isBreathing = true }
            .onChange(of: gestureHandler.dragPosition) { newPosition in
                interactionManager.updateDragPosition(newPosition)
            }
        }
    }
    
    // MARK: - 视图层组件
    
    @ViewBuilder
    private var trailEffectLayer: some View {
        if isDragging {
            PetTrailEffectView(
                trailPoints: gestureHandler.dragPoints.map { point in
                    TrailPoint(location: point, timestamp: Date())
                },
                theme: trailTheme,
                customColors: (customColor1Hex, customColor2Hex, customColor3Hex)
            )
        }
    }
    
    @ViewBuilder
    private var circleDetectionLayer: some View {
        if isDragging {
            CircleDetectionOverlay(
                isTriggered: gestureHandler.isCircleTriggered,
                boundingBox: gestureHandler.circleBoundingBox
            )
        }
    }
    
    @ViewBuilder
    private func petViewLayer(geometry: GeometryProxy) -> some View {
        // 新手引导跑步动画期间隐藏原悬浮小猫
        let shouldHide = guideManager.isRunningAnimation ||
            (guideManager.currentStep == .pointing && guideManager.showPointingVideo)
        let petPosition = calculatePosition(geometry: geometry)

        ZStack {
            PetImageView(
                petImagePrefix: petImagePrefix,
                state: interactionManager.state,
                isBreathing: isBreathing,
                catWidth: catWidth,
                position: petPosition,
                rotation: getRotationAngle()
            )
            .opacity(isHiddenForSnapshot || shouldHide ? 0 : 1)

            // 将拖拽起点限制在宠物附近，避免整屏手势覆盖底层热区。
            Color.clear
                .frame(width: catWidth + 28, height: catWidth + 44)
                .contentShape(Rectangle())
                .position(petPosition)
                .gesture(dragGesture(in: geometry))
                .allowsHitTesting(!(isHiddenForSnapshot || shouldHide))
        }
    }
    
    @ViewBuilder
    private func analyzingLayer(geometry: GeometryProxy) -> some View {
        if aiAnalysisService.isAnalyzing {
            PetAIAnalyzingView(petName: petName)
                .position(
                    x: interactionManager.dragPosition.x,
                    y: interactionManager.dragPosition.y - 100
                )
                .transition(.scale.combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var analysisResultLayer: some View {
        if showingAnalysisResult, let result = analysisResult {
            PetAIAnalysisResultView(result: result, onClose: {
                withAnimation {
                    showingAnalysisResult = false
                    interactionManager.endAnalyzing()
                }
            })
            .transition(.opacity)
            .zIndex(100)
        }
    }
    
    // MARK: - 手势处理
    
    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("PetOverlaySpace"))
            .onChanged { value in
                handleDragChanged(value, in: geometry)
            }
            .onEnded { value in
                handleDragEnded(value, in: geometry)
            }
    }
    
    private func handleDragChanged(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        gestureHandler.handleDragChanged(value, in: geometry.size)
        
        // 检查是否需要开始拖拽（从按压状态转为拖拽状态）
        if case .dragging = gestureHandler.state {
            // 如果 interactionManager 还没有进入拖拽状态，则开始拖拽
            if interactionManager.state != .dragging {
                interactionManager.startDragging(at: value.location)
            }
            // Vision线检测
            performVisionCheck(at: value.location, in: geometry)
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        // 先检查是否是点击（按压状态且移动距离很小）
        if case .pressing = gestureHandler.state {
            // 这是一个点击事件
            handleTap(at: value.location)
            gestureHandler.reset()
            return
        }
        
        // 处理拖拽结束
        gestureHandler.handleDragEnded(value, in: geometry.size)
        
        // 检查是否有圆圈触发
        if gestureHandler.isCircleTriggered, let boundingBox = gestureHandler.circleBoundingBox {
            handleCircleTriggered(at: boundingBox, in: geometry)
        } else {
            handleDragEnded(at: value.location, in: geometry)
        }
    }
    
    // MARK: - 事件处理
    
    private func handleTap(at location: CGPoint) {
        guard interactionManager.state == .idle else { return }
        HapticEngineManager.shared.playUIFeedback(intensity: 0.5, sharpness: 0.5, fallbackStyle: .medium)
        
        // 执行传入的 action（切换到萌宠对话 Tab）
        action()
        
        // 发送通知自动展开搜索栏（iOS 18+ 兼容）
        NotificationCenter.default.post(name: .autoExpandPetChatSearch, object: nil)
    }
    
    private func handleDragEnded(at location: CGPoint, in geometry: GeometryProxy) {
        // 更新idle位置
        let safeMargin: CGFloat = 40
        let minX = safeMargin
        let maxX = geometry.size.width - safeMargin
        self.idleX = min(maxX, max(minX, location.x))
        
        interactionManager.endDragging(at: location, screenSize: geometry.size)
    }
    
    private func handleCircleTriggered(at rect: CGRect, in geometry: GeometryProxy) {
        interactionManager.startAnalyzing()
        
        Task {
            do {
                isHiddenForSnapshot = true
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                let result = try await aiAnalysisService.analyzeArea(
                    rect: rect,
                    screenSize: geometry.size,
                    captureBlock: { rect, scale in
                        captureCroppedImage(rect: rect, scale: scale)
                    }
                )
                
                await MainActor.run {
                    self.capturedImage = result.image
                    self.analysisResult = result
                    self.isHiddenForSnapshot = false
                    self.showingAnalysisResult = true
                }
                
            } catch {
                await MainActor.run {
                    self.isHiddenForSnapshot = false
                    self.interactionManager.endAnalyzing()
                }
            }
        }
    }
    
    // MARK: - Vision检测
    
    private func performVisionCheck(at location: CGPoint, in geometry: GeometryProxy) {
        // 节流控制
        let now = Date()
        guard now.timeIntervalSince(lastVisionCheckTime) >= visionCheckInterval else { return }
        
        guard let image = captureScreen(scale: screenshotScale) else { return }
        
        lastVisionCheckTime = now
        let roi = calculateVisionROI(center: location, screenSize: geometry.size)
        visionManager.detectLines(in: image, roi: roi)
    }
    
    @State private var lastVisionCheckTime: Date = .distantPast
    
    // MARK: - 位置计算
    
    private func calculatePosition(geometry: GeometryProxy) -> CGPoint {
        switch interactionManager.state {
        case .dragging:
            return interactionManager.dragPosition
        case .snapping:
            return getSnapPosition(in: geometry.size)
        case .returning, .analyzing:
            return getIdlePosition(geometry: geometry)
        case .idle:
            return getIdlePosition(geometry: geometry)
        }
    }
    
    private func getIdlePosition(geometry: GeometryProxy) -> CGPoint {
        let x = idleX ?? (geometry.size.width / 2)
        let y = geometry.size.height - geometry.safeAreaInsets.bottom - (catWidth / 2)
        return CGPoint(x: x, y: y)
    }
    
    private func getSnapPosition(in size: CGSize) -> CGPoint {
        guard let line = interactionManager.snappedLine else { return .zero }
        
        let rect = CGRect(
            x: line.origin.x * size.width,
            y: (1 - line.origin.y - line.height) * size.height,
            width: line.width * size.width,
            height: line.height * size.height
        )
        
        let isHorizontal = interactionManager.isHorizontalSnap
        
        if isHorizontal {
            let minX = rect.minX
            let maxX = rect.maxX
            let currentX = interactionManager.dragPosition.x
            let clampedX = max(minX, min(maxX, currentX))
            let snapY = rect.minY + (catWidth / 2)
            return CGPoint(x: clampedX, y: snapY)
        } else {
            let minY = rect.minY
            let maxY = rect.maxY
            let currentY = interactionManager.dragPosition.y
            let clampedY = max(minY, min(maxY, currentY))
            let isLeft = interactionManager.dragPosition.x < rect.midX
            let snapX = isLeft ? rect.minX - (catWidth / 2) + 10 : rect.maxX + (catWidth / 2) - 10
            return CGPoint(x: snapX, y: clampedY)
        }
    }
    
    private func getRotationAngle() -> Angle {
        if interactionManager.state == .snapping {
            return interactionManager.isHorizontalSnap ? .degrees(90) : .degrees(0)
        }
        return .degrees(0)
    }
    
    private func getAnimation(for state: FloatingPetState) -> Animation {
        switch state {
        case .dragging:
            return .spring(response: 0.3, dampingFraction: 0.8)
        case .snapping:
            return .spring(response: 0.5, dampingFraction: 0.6)
        case .returning:
            return .easeInOut(duration: 1.0)
        case .idle, .analyzing:
            return .easeOut(duration: 0.3)
        }
    }
    
    // MARK: - 截图功能
    
    func captureScreen(scale: CGFloat) -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return nil }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { ctx in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
    
    private func captureCroppedImage(rect: CGRect, scale: CGFloat = 1.0) -> UIImage? {
        guard let fullScreen = captureScreen(scale: scale), let cgImage = fullScreen.cgImage else { return nil }
        
        let scale = fullScreen.scale
        let cropRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage, scale: scale, orientation: fullScreen.imageOrientation)
    }
    
    private func calculateVisionROI(center: CGPoint, screenSize: CGSize) -> CGRect {
        let sideLength: CGFloat = visionROISize
        let minX = max(0, center.x - sideLength / 2)
        let minY = max(0, center.y - sideLength / 2)
        
        let actualW = min(sideLength, screenSize.width - minX)
        let actualH = min(sideLength, screenSize.height - minY)
        
        let normX = minX / screenSize.width
        let normW = actualW / screenSize.width
        let normH = actualH / screenSize.height
        let normY = 1.0 - (minY + actualH) / screenSize.height
        
        return CGRect(x: normX, y: max(0, normY), width: normW, height: normH)
    }
}

// MARK: - 宠物图片视图组件

struct PetImageView: View {
    let petImagePrefix: String
    let state: FloatingPetState
    let isBreathing: Bool
    let catWidth: CGFloat
    let position: CGPoint
    let rotation: Angle
    
    var body: some View {
        ZStack {
            // 静止/呼吸状态
            Image("\(petImagePrefix)_peeking")
                .resizable()
                .scaledToFit()
                .frame(width: catWidth)
                .scaleEffect(isBreathing ? 1.05 : 1.0, anchor: .bottom)
                .opacity(shouldShowPeeking ? 1 : 0)
                .animation(breathingAnimation, value: isBreathing)
            
            // 拖拽/吸附状态
            SeamlessVideoPlayer(
                videoName: "\(petImagePrefix)_dragging",
                isLooping: true,
                isMuted: true,
                volume: 0
            )
            .frame(width: catWidth, height: catWidth)
            .scaleEffect(getDraggingScale(), anchor: .top)
            .rotationEffect(rotation)
            .offset(y: state == .snapping ? 0 : 30)
            .opacity(shouldShowDragging ? 1 : 0)
        }
        .position(position)
    }
    
    private var shouldShowPeeking: Bool {
        switch state {
        case .dragging, .snapping, .analyzing:
            return false
        case .idle, .returning:
            return true
        }
    }
    
    private var shouldShowDragging: Bool {
        switch state {
        case .dragging, .snapping:
            return true
        case .returning:
            return false
        case .idle, .analyzing:
            return false
        }
    }
    
    private var breathingAnimation: Animation {
        Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
    }
    
    private func getDraggingScale() -> CGFloat {
        state == .snapping ? 1.5 : 2.5
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.white
        VStack {
            Spacer()
            Color.gray.frame(height: 83)
        }
        PetOverlayView(action: {})
    }
}
