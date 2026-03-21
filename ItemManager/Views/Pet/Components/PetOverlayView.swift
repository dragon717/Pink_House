import SwiftUI
import UIKit
import Vision
import AVKit

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
    @StateObject private var guideManager = NewbieGuideManager.shared
    
    // MARK: - 状态管理（精简后的核心状态）
    
    @State private var isBreathing: Bool = false
    @State private var idleX: CGFloat? = nil
    @State private var isHiddenForSnapshot: Bool = false
    @State private var showingAnalysisResult: Bool = false
    @State private var capturedImage: UIImage?
    @State private var analysisResult: PetAIAnalysisResult?
    
    // MARK: - iOS 26 TabBar 收起行走动画状态
    
    @State private var isTabBarCollapsed: Bool = false
    @State private var walkingDirection: WalkingDirection = .right
    @State private var walkingProgress: CGFloat = 0
    @State private var walkingY: CGFloat = 0
    
    enum WalkingDirection {
        case left, right
    }
    
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
    private let walkingDuration: Double = 10.0 // 单程行走10秒
    private let walkingAmplitude: CGFloat = 15.0 // 波浪振幅
    
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
            .gesture(dragGesture(in: geometry))
            .coordinateSpace(name: "PetOverlaySpace")
            .animation(getAnimation(for: interactionManager.state), value: interactionManager.state)
            .onAppear { 
                isBreathing = true
            }
            .onChange(of: gestureHandler.dragPosition) { newPosition in
                interactionManager.updateDragPosition(newPosition)
            }
            // 使用onReceive处理TabBar收起通知，避免在struct中使用weak self
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TabBarCollapseStateChanged"))) { notification in
                if let isCollapsed = notification.userInfo?["isCollapsed"] as? Bool {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.isTabBarCollapsed = isCollapsed
                    }
                    if isCollapsed {
                        self.startWalkingAnimation()
                    } else {
                        self.stopWalkingAnimation()
                    }
                }
            }
        }
    }
    
    // MARK: - iOS 26 TabBar 收起检测
    
    private func startWalkingAnimation() {
        // 重置行走进度
        walkingProgress = 0
        walkingDirection = .right
        
        // 开始行走动画循环
        animateWalking()
    }
    
    private func stopWalkingAnimation() {
        // 停止动画，重置状态
        withAnimation(.easeOut(duration: 0.3)) {
            walkingProgress = 0
            walkingY = 0
        }
    }
    
    private func animateWalking() {
        guard isTabBarCollapsed else { return }
        
        // 使用线性动画，单程10秒
        withAnimation(.linear(duration: walkingDuration)) {
            walkingProgress = (walkingDirection == .right) ? 1 : 0
        }
        
        // 10秒后切换方向
        // 使用捕获列表捕获当前状态的副本，避免在值类型中使用weak self
        let currentDirection = walkingDirection
        let currentIsCollapsed = isTabBarCollapsed
        DispatchQueue.main.asyncAfter(deadline: .now() + walkingDuration) {
            // 检查状态是否仍然有效
            guard currentIsCollapsed else { return }
            
            // 切换方向
            self.walkingDirection = (currentDirection == .right) ? .left : .right
            
            // 继续动画
            self.animateWalking()
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

        // TabBar 收起时使用行走动画视图
        if isTabBarCollapsed && interactionManager.state == .idle {
            WalkingPetView(
                petImagePrefix: petImagePrefix,
                catWidth: catWidth,
                position: calculateWalkingPosition(geometry: geometry),
                walkingY: walkingY,
                isMovingRight: walkingDirection == .right
            )
            .opacity(isHiddenForSnapshot || shouldHide ? 0 : 1)
        } else {
            PetImageView(
                petImagePrefix: petImagePrefix,
                state: interactionManager.state,
                isBreathing: isBreathing,
                catWidth: catWidth,
                position: calculatePosition(geometry: geometry),
                rotation: getRotationAngle()
            )
            .opacity(isHiddenForSnapshot || shouldHide ? 0 : 1)
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
        // TabBar 收起时，小猫移动到屏幕底部（不受安全区域限制）
        let y = isTabBarCollapsed
            ? geometry.size.height - (catWidth / 2) + 10 // 稍微超出屏幕底部
            : geometry.size.height - geometry.safeAreaInsets.bottom - (catWidth / 2)
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - 行走位置计算
    
    private func calculateWalkingPosition(geometry: GeometryProxy) -> CGPoint {
        let safeMargin: CGFloat = 40
        let minX = safeMargin
        let maxX = geometry.size.width - safeMargin
        
        // 根据进度计算X位置
        let currentX = minX + (maxX - minX) * walkingProgress
        
        // 计算波浪Y偏移（正弦波）
        // 使用 walkingProgress * 2π 来完成一个完整的波浪周期
        let wavePhase = walkingProgress * 2 * .pi
        let waveOffset = sin(wavePhase) * walkingAmplitude
        
        // 更新 walkingY 用于视图
        DispatchQueue.main.async {
            self.walkingY = waveOffset
        }
        
        // Y位置：屏幕底部（不受安全区域限制）+ 波浪偏移
        let baseY = geometry.size.height - (catWidth / 2) + 10
        let y = baseY + waveOffset
        
        return CGPoint(x: currentX, y: y)
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

// MARK: - 行走宠物视图（TabBar收起时使用）

struct WalkingPetView: View {
    let petImagePrefix: String
    let catWidth: CGFloat
    let position: CGPoint
    let walkingY: CGFloat
    let isMovingRight: Bool
    
    var body: some View {
        // 使用视频播放器显示行走动画
        PetWalkingVideoPlayer(
            videoName: "\(petImagePrefix)_right_run",
            isMovingRight: isMovingRight,
            catWidth: catWidth
        )
        .frame(width: catWidth, height: catWidth)
        .position(position)
        .offset(y: walkingY)
    }
}

// MARK: - 宠物行走视频播放器

struct PetWalkingVideoPlayer: UIViewRepresentable {
    let videoName: String
    let isMovingRight: Bool
    let catWidth: CGFloat
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        // 创建视频播放器
        let playerView = PetVideoPlayerUIView(
            videoName: videoName,
            isMovingRight: isMovingRight
        )
        playerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(playerView)
        
        NSLayoutConstraint.activate([
            playerView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            playerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            playerView.widthAnchor.constraint(equalToConstant: catWidth),
            playerView.heightAnchor.constraint(equalToConstant: catWidth)
        ])
        
        context.coordinator.playerView = playerView
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // 更新方向（镜像）
        context.coordinator.playerView?.updateDirection(isMovingRight: isMovingRight)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var playerView: PetVideoPlayerUIView?
    }
}

// MARK: - 宠物视频播放器 UIView

class PetVideoPlayerUIView: UIView {
    private var playerLayer: AVPlayerLayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var isMovingRight: Bool = true
    
    init(videoName: String, isMovingRight: Bool) {
        self.isMovingRight = isMovingRight
        super.init(frame: .zero)
        setupPlayer(videoName: videoName)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPlayer(videoName: String) {
        // 查找视频资源
        var url: URL?
        
        // 尝试从 asserts/naicha 目录加载
        if videoName.hasPrefix("naicha_") {
            url = Bundle.main.url(forResource: videoName, withExtension: "mov", subdirectory: "asserts/naicha")
        }
        
        // 回退到主 bundle
        if url == nil {
            url = Bundle.main.url(forResource: videoName, withExtension: "mov")
        }
        
        guard let validUrl = url else {
            print("Error: Could not find video resource: \(videoName)")
            return
        }
        
        // 创建播放器
        let player = AVQueuePlayer()
        self.player = player
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.clear.cgColor
        layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer
        
        // 设置循环播放
        let playerItem = AVPlayerItem(url: validUrl)
        looper = AVPlayerLooper(player: player, templateItem: playerItem)
        
        // 更新方向（镜像）
        updateDirection(isMovingRight: isMovingRight)
        
        // 开始播放
        player.play()
    }
    
    func updateDirection(isMovingRight: Bool) {
        self.isMovingRight = isMovingRight
        
        // 向左走时镜像视频
        if isMovingRight {
            playerLayer?.setAffineTransform(.identity)
        } else {
            playerLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
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
            Image("\(petImagePrefix)_dragging")
                .resizable()
                .scaledToFit()
                .frame(width: catWidth)
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
