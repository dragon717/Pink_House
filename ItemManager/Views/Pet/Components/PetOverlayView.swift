import SwiftUI
import UIKit
import Vision

struct PetOverlayView: View {
    // 点击动作
    var action: () -> Void
    var petName: String = "萌宠" // Add petName property
    
    // Managers
    @StateObject private var interactionManager = PetInteractionManager.shared
    @StateObject private var visionManager = VisionManager.shared
    
    // 位置状态
    @State private var positionX: CGFloat = 0
    @State private var positionY: CGFloat = 0
    @GestureState private var dragOffset: CGSize = .zero
    
    // 动画状态
    @State private var isBreathing: Bool = false
    
    // 交互状态
    @State private var isDragging: Bool = false
    @State private var hasSetInitialPosition: Bool = false
    @State private var idleX: CGFloat? = nil // Record last idle X position
    
    // Analysis State
    @State private var analysisHoldTimer: Timer?
    @State private var holdStartTime: Date?
    @State private var holdProgress: Double = 0.0
    @State private var isHoldTriggered: Bool = false
    
    // Config
    private let analysisHoldDuration: TimeInterval = 2.0
    
    // ... (keep existing properties) ...
    // Analysis Result State
    @State private var showingAnalysisResult: Bool = false
    @State private var analysisResultText: String = ""
    @State private var analysisUserQuestion: String = "这是什么？" // Store user question
    @State private var capturedImage: UIImage? = nil
    
    // Snapshot Hiding State
    @State private var isHiddenForSnapshot: Bool = false
    
    // State for tap handling logic (to distinguish from drag)
    @State private var isPressing = false
    @State private var dragStartTime: Date?
    
    // 触觉反馈管理器
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    
    // Debug State
    @State private var currentROI: CGRect? = nil
    // Set to true to enable debug visualization (red/blue lines, green ROI)
    private let showDebugVisuals = false
    
    // 配置参数
    private let catWidth: CGFloat = 70 // 小猫图片宽度
    private let visionROISize: CGFloat = 400 // Vision 识别区域大小 (Increased for better vertical line detection)
    
    // Performance: Downsampling scale for screenshot
    // 0.5 means detecting on half resolution, which is 4x faster and uses 4x less memory
    // Vision works well on lower resolutions for line detection
    private let screenshotScale: CGFloat = 0.5
    
    // 获取当前宠物图片前缀
    private var petImagePrefix: String {
        return interactionManager.currentPetId
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Player Layer (When Snapping & Video Enabled)
                if interactionManager.state == .snapping, 
                   interactionManager.isPlayingVideo, // Check explicit flag
                   let videoName = interactionManager.currentVideoName {
                    PetVideoPlayer(
                        videoName: videoName,
                        isLooping: true,
                        isMuted: false,
                        onFinished: {
                            // Video finished logic if not looping, 
                            // or handled by tap/timeout
                        }
                    )
                    .frame(width: 150, height: 150) // Adjust size as needed
                    .position(getSnapPosition(in: geometry.size))
                    .onTapGesture {
                        interactionManager.onVideoFinished()
                    }
                    .transition(.opacity)
                    .opacity(isHiddenForSnapshot ? 0 : 1)
                }
                
                // Cat Image Layer (Handles dragging, returning, and snapping fallback)
                // Show if NOT snapping OR if snapping but video is disabled
                if interactionManager.state != .snapping || !interactionManager.isPlayingVideo {
                    petView(geometry: geometry)
                        .opacity(isHiddenForSnapshot ? 0 : 1)
                }
                if isDragging && !isHoldTriggered && holdProgress > 0 {
                    ZStack {
                        // Ring Background
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        // Ring Progress
                        Circle()
                            .trim(from: 0, to: holdProgress)
                            .stroke(
                                LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: holdProgress)
                        
                        // Magnifying Glass Icon
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                        
                        // Cat Paw (Small decoration)
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.pink)
                            .offset(x: 15, y: -15)
                            .opacity(holdProgress > 0.5 ? 1 : 0)
                            .animation(.spring(), value: holdProgress)
                    }
                    .position(interactionManager.dragPosition)
                    .offset(y: -80) // Above finger
                }
                
                // Thinking Bubble
                if isAnalyzing {
                    VStack(spacing: 8) {
                        // Thinking Cat Image
                        Image("thinking_cat")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .shadow(radius: 4)
                        
                        HStack(spacing: 4) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text("思考中，可以操作别的...")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                    }
                    .position(
                        x: interactionManager.dragPosition.x,
                        y: interactionManager.dragPosition.y - 100
                    )
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Debug Layer for Vision Lines
                #if DEBUG
                if isDragging && showDebugVisuals {
                    // ... (keep existing debug code) ...
                }
                #endif
                
                // Analysis Result Overlay
                if showingAnalysisResult {
                    AIAnalysisResultView(
                        resultText: analysisResultText,
                        analyzedImage: capturedImage,
                        userQuestion: analysisUserQuestion,
                        petName: petName,
                        onClose: {
                            withAnimation {
                                showingAnalysisResult = false
                                capturedImage = nil
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("PetOverlaySpace"))
                    .onChanged { value in
                        if !isDragging {
                            // Start Drag
                            if !isPressing {
                                isPressing = true
                                dragStartTime = Date()
                            }
                            
                            if value.translation.width * value.translation.width + value.translation.height * value.translation.height > 100 {
                                isDragging = true
                                isPressing = false
                                interactionManager.startDragging(at: value.location)
                                hapticManager.playUIFeedback(intensity: 0.6, sharpness: 0.7, fallbackStyle: .medium)
                                
                                // Reset Hold Logic
                                resetHoldTimer()
                                startHoldTimer(at: value.location)
                            }
                        } else {
                            // Continuing Drag
                            interactionManager.updateDragPosition(value.location)
                            
                            // Check if moved significantly to reset hold timer?
                            // User requirement: "Drag pet, hold at some place for 2s"
                            // So if moving too much, reset.
                            // But user might jitter finger.
                            // Let's reset if moved > threshold from last "hold start" pos?
                            // Simpler: Just restart timer on every move? No, that makes it impossible to trigger unless 100% still.
                            // Better: Update position, but only reset timer if velocity is high?
                            // Or: Just keep updating the timer logic.
                            
                            // Let's implement "Hold at a place":
                            // We need to track the position where the hold "started".
                            // If current position deviates too much, reset.
                            checkHoldPosition(currentLocation: value.location)
                        }
                    }
                    .onEnded { value in
                        resetHoldTimer() // Cancel timer
                        
                        if isDragging {
                            isDragging = false
                            self.currentROI = nil
                            
                            if interactionManager.state != .snapping {
                                // Only analyze if explicitly triggered by hold
                                if isHoldTriggered {
                                    analyzeDrop(at: value.location, screenSize: geometry.size)
                                } else {
                                    // Update idle position (Drop)
                                    // Clamp to safe area (avoid edges)
                                    let safeMargin: CGFloat = 40
                                    let minX = safeMargin
                                    let maxX = geometry.size.width - safeMargin
                                    self.idleX = min(maxX, max(minX, value.location.x))
                                }
                            }
                            
                            interactionManager.endDragging(at: value.location, screenSize: geometry.size)
                            
                            // Reset trigger state
                            isHoldTriggered = false
                            holdProgress = 0
                            
                        } else if isPressing {
                            // ... (Tap logic) ...
                            if let start = dragStartTime, Date().timeIntervalSince(start) < 0.3 {
                                if interactionManager.state == .idle {
                                    hapticManager.playUIFeedback(intensity: 0.5, sharpness: 0.5, fallbackStyle: .medium)
                                    withAnimation {
                                        action()
                                    }
                                }
                            }
                        }
                        isPressing = false
                        dragStartTime = nil
                    }
            )
            .coordinateSpace(name: "PetOverlaySpace")
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: interactionManager.state) // Animate state changes
            .allowsHitTesting(true)
            .onAppear {
                isBreathing = true
            }
            .onChange(of: geometry.size) { newSize in
                if !hasSetInitialPosition {
                    // Initialize position at bottom center
                    // This logic might need adjustment based on exact design requirements
                    hasSetInitialPosition = true
                }
            }
        }
    }
    
    // MARK: - Hold Logic
    @State private var holdStartLocation: CGPoint = .zero
    
    private func startHoldTimer(at location: CGPoint) {
        holdStartLocation = location
        holdStartTime = Date()
        holdProgress = 0
        isHoldTriggered = false
        
        analysisHoldTimer?.invalidate()
        analysisHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let start = holdStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            
            withAnimation {
                holdProgress = min(elapsed / analysisHoldDuration, 1.0)
            }
            
            if elapsed >= analysisHoldDuration {
                triggerAnalysisReady()
            }
        }
    }
    
    private func checkHoldPosition(currentLocation: CGPoint) {
        // Distance check
        let dx = currentLocation.x - holdStartLocation.x
        let dy = currentLocation.y - holdStartLocation.y
        let distanceSquared = dx*dx + dy*dy
        
        // Increase tolerance to 60pt radius (3600 squared) to allow for shaky fingers
        if distanceSquared > 3600 {
            // Moved too far, reset hold
            resetHoldTimer()
            startHoldTimer(at: currentLocation)
        }
    }
    
    private func resetHoldTimer() {
        analysisHoldTimer?.invalidate()
        analysisHoldTimer = nil
        holdStartTime = nil
        // Only reset progress if not triggered. 
        // If triggered, we might want to keep showing "Ready" state until drop?
        // But user said "if drag < 2s, normal move".
        // If we reset here, the visual feedback disappears.
        // Let's reset progress to 0 unless triggered.
        if !isHoldTriggered {
            withAnimation {
                holdProgress = 0
            }
        }
    }
    
    private func triggerAnalysisReady() {
        guard !isHoldTriggered else { return }
        isHoldTriggered = true
        resetHoldTimer() // Stop timer, but keep isHoldTriggered true
        
        // Haptic Feedback
        hapticManager.playUIFeedback(intensity: 1.0, sharpness: 1.0, fallbackStyle: .heavy) // Strong vibration
        
        // Visual Feedback (Maybe change the ring to "Ready" state or just keep it full?)
        // For now, progress stays at 1.0 (via isHoldTriggered logic if we want)
    }
    
    // MARK: - Vision Analysis
    
    @ObservedObject private var visionAnalysis = VisionAnalysisService.shared
    @State private var isAnalyzing = false // Visual state for analysis
    
    private func analyzeDrop(at location: CGPoint, screenSize: CGSize) {
        // 1. Hide pet for snapshot
        isHiddenForSnapshot = true
        
        // 2. Delay capture to allow UI update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let roiSize: CGFloat = 300
            
            // Capture
            guard let croppedImage = self.captureCroppedImage(at: location, size: CGSize(width: roiSize, height: roiSize)) else {
                self.isHiddenForSnapshot = false
                return
            }
            
            // Save image for display
            self.capturedImage = croppedImage
            
            // 3. Restore pet visibility
            self.isHiddenForSnapshot = false
            
            // 触发触觉反馈表示开始思考
            self.hapticManager.playUIFeedback(intensity: 1.0, sharpness: 0.5, fallbackStyle: .heavy)
            
            withAnimation { self.isAnalyzing = true }
            
            self.visionAnalysis.recognizeContent(from: croppedImage) { result in
                Task {
                    // 如果识别内容太少，尝试全屏
                    if result.context.contains("似乎是一张没有文字的图片") || result.context.count < 10 {
                        
                        await MainActor.run {
                            self.isHiddenForSnapshot = true
                        }
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                        
                        let fullScreen = await MainActor.run { return self.captureScreen(scale: self.screenshotScale) }
                        
                        await MainActor.run {
                            self.isHiddenForSnapshot = false
                        }

                        if let fullScreen = fullScreen {
                             self.visionAnalysis.recognizeContent(from: fullScreen) { fullResult in
                                 Task {
                                     // 使用 AI 建议的问题，而不是固定的"这是什么？"
                                     let question = fullResult.suggestedQuestion
                                     let msg = await PetAIService.shared.sendImageAnalysisRequest(text: question, imageContext: fullResult.context, image: fullScreen)
                                     await MainActor.run { 
                                         self.analysisUserQuestion = question
                                         self.analysisResultText = msg.text
                                         withAnimation { 
                                             self.isAnalyzing = false 
                                             self.showingAnalysisResult = true
                                         }
                                     }
                                 }
                             }
                        } else {
                            await MainActor.run { withAnimation { self.isAnalyzing = false } }
                        }
                    } else {
                        // 使用 AI 建议的问题，而不是固定的"这是什么？"
                        let question = result.suggestedQuestion
                        let msg = await PetAIService.shared.sendImageAnalysisRequest(text: question, imageContext: result.context, image: croppedImage)
                        await MainActor.run { 
                            self.analysisUserQuestion = question
                            self.analysisResultText = msg.text
                            withAnimation { 
                                self.isAnalyzing = false 
                                self.showingAnalysisResult = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func captureCroppedImage(at center: CGPoint, size: CGSize) -> UIImage? {
        guard let fullScreen = captureScreen(scale: 1.0), let cgImage = fullScreen.cgImage else { return nil }
        
        let scale = fullScreen.scale
        let x = (center.x - size.width/2) * scale
        let y = (center.y - size.height/2) * scale
        let width = size.width * scale
        let height = size.height * scale
        
        let cropRect = CGRect(x: x, y: y, width: width, height: height)
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        
        return UIImage(cgImage: croppedCGImage, scale: scale, orientation: fullScreen.imageOrientation)
    }

    private func getSnapPosition(in size: CGSize) -> CGPoint {
        guard let line = interactionManager.snappedLine else { return .zero }
        
        // Convert normalized line to screen coordinates
        let rect = CGRect(
            x: line.origin.x * size.width,
            y: (1 - line.origin.y - line.height) * size.height, // Vision Y is inverted
            width: line.width * size.width,
            height: line.height * size.height
        )
        
        // Calculate snap position
        // Instead of center, we want to align the cat's edge to the line
        
        let isHorizontal = interactionManager.isHorizontalSnap
        
        if isHorizontal {
            // Horizontal Line: Cat sits ON TOP of the line
            // X: Center of the drag position (or clamped to line segment)
            // Y: Line's Top Y - Cat Height / 2 (since position is center)
            
            // We clamp X to be within the line segment
            let minX = rect.minX
            let maxX = rect.maxX
            let currentX = interactionManager.dragPosition.x
            let clampedX = max(minX, min(maxX, currentX))
            
            // 趴在横线上：猫的底部对齐线的顶部
            // Position is center, so Y = LineMinY - (CatHeight / 2)
            // Visual adjustment: +15 to make it look like it's gripping/sitting
            // Update: User requested "down half width", because cat is "held up" (hanging down?)
            // If "held up", the cat body is below the pivot point.
            // If cat is "sitting", body is above pivot.
            // "小猫是被拎着的" -> Implies hanging down from the line?
            // "往下移动一半宽度" -> Y + CatWidth/2
            
            // Let's adjust based on user feedback: "往下移动一半宽度"
            // Original: rect.minY - (catWidth / 2) + 15
            // New: rect.minY + (catWidth / 2)
            let snapY = rect.minY + (catWidth / 2) 
            
            return CGPoint(x: clampedX, y: snapY)
            
        } else {
            // Vertical Line: Cat hangs ON THE SIDE of the line
            // Y: Center of drag position (clamped)
            // X: Line's X +/- Cat Width / 2
            
            let minY = rect.minY
            let maxY = rect.maxY
            let currentY = interactionManager.dragPosition.y
            let clampedY = max(minY, min(maxY, currentY))
            
            // Determine side based on drag approach direction or relative position
            // For now, let's snap to the left side if drag is on left, right if on right
            let isLeft = interactionManager.dragPosition.x < rect.midX
            
            let snapX: CGFloat
            if isLeft {
                 // Hang on left side: X = LineMinX - (CatWidth / 2)
                 // Visual adjustment: +10 to make it overlap slightly
                 snapX = rect.minX - (catWidth / 2) + 10
            } else {
                 // Hang on right side
                 snapX = rect.maxX + (catWidth / 2) - 10
            }
            
            return CGPoint(x: snapX, y: clampedY)
        }
    }
    
    private func petView(geometry: GeometryProxy) -> some View {
        let safeAreaBottom = geometry.safeAreaInsets.bottom
        
        // Calculate current position
        // If dragging, use drag location
        // If idle, use fixed bottom position
        // If returning, use animation (handled by transition/animation modifier)
        
        let isReturning = interactionManager.state == .returning
        let isSnapping = interactionManager.state == .snapping
        let isDraggingActive = interactionManager.state == .dragging // Explicit dragging check from manager
        
        return ZStack {
            // 1. 静止/呼吸状态的猫 (趴着) - 也就是"悬浮猫头"
            // 显示条件：静止态 OR 归位态 (归位时渐显)
            Image("\(petImagePrefix)_peeking") // 动态图片名: naicha_peeking / maomao_peeking
                .resizable()
                .scaledToFit()
                .frame(width: catWidth)
                .scaleEffect(isBreathing ? 1.05 : 1.0, anchor: .bottom)
                // 归位时: opacity 从 0 -> 1 (渐显)
                // 拖拽/吸附时: opacity 0
                .opacity((isDraggingActive || isSnapping) ? 0 : 1)
                .animation(
                    isDraggingActive ? .easeOut(duration: 0.15) : Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                    value: isBreathing
                )
            
            // 2. 拖拽/吸附状态的猫 (拎起/旋转) - 也就是"表演图片"
            // 显示条件：拖拽态 OR 吸附态 OR 归位态 (归位时渐隐)
            Image("\(petImagePrefix)_dragging") // 动态图片名: naicha_dragging / maomao_dragging
                .resizable()
                .scaledToFit()
                .frame(width: catWidth)
                .scaleEffect(isSnapping ? 1.5 : 2.5, anchor: .top) // Snapping 时稍微小一点
                .rotationEffect(getRotationAngle()) // 根据吸附状态旋转
                .offset(y: isSnapping ? 0 : 30) // Visual offset for "picking up"
                // 归位时: opacity 从 1 -> 0 (渐隐)
                // 静止时: opacity 0
                // 拖拽/吸附时: opacity 1
                .opacity((isDraggingActive || isSnapping) ? 1 : (isReturning ? 0 : 0))
        }
        // 状态切换动画配置
        .animation(getAnimation(for: interactionManager.state), value: interactionManager.state)
        .position(calculatePosition(geometry: geometry, safeAreaBottom: safeAreaBottom))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("PetOverlaySpace"))
                .onChanged { value in
                    if !isDragging {
                        // Potential tap or start of drag
                        if !isPressing {
                            isPressing = true
                            dragStartTime = Date()
                        }
                        
                        // Check if movement exceeds threshold to be considered a drag
                        // Small movements are ignored to allow for tap detection
                        if value.translation.width * value.translation.width + value.translation.height * value.translation.height > 100 { // > 10pt distance squared
                            isDragging = true
                            isPressing = false // It's confirmed as drag, not tap
                            interactionManager.startDragging(at: value.location)
                            hapticManager.playUIFeedback(intensity: 0.6, sharpness: 0.7, fallbackStyle: .medium)
                            
                            // Initial Vision detection
                            if let image = captureScreen(scale: screenshotScale) {
                                 let roi = calculateVisionROI(center: value.location, screenSize: geometry.size)
                                 self.currentROI = roi
                                 visionManager.detectLines(in: image, roi: roi)
                            }
                        }
                    } else {
                        // Continuing drag
                        interactionManager.updateDragPosition(value.location)
                        
                        // Throttle vision detection
                        if let image = captureScreen(scale: screenshotScale) {
                            let roi = calculateVisionROI(center: value.location, screenSize: geometry.size)
                            self.currentROI = roi
                            visionManager.detectLines(in: image, roi: roi)
                        }
                    }
                }
                .onEnded { value in
                    if isDragging {
                        // Drag ended
                        isDragging = false
                        self.currentROI = nil
                        // Check if we are snapping. If so, let interactionManager handle it.
                        // If NOT snapping, it means we dropped it somewhere else -> Analyze!
                        if interactionManager.state != .snapping {
                             analyzeDrop(at: value.location, screenSize: geometry.size)
                        }
                        
                        interactionManager.endDragging(at: value.location, screenSize: geometry.size)
                    } else if isPressing {
                        // Tap confirmed (drag didn't start)
                        // Verify duration to ensure it's a tap, not a held press without movement
                        if let start = dragStartTime, Date().timeIntervalSince(start) < 0.3 {
                            if interactionManager.state == .idle {
                                hapticManager.playUIFeedback(intensity: 0.5, sharpness: 0.5, fallbackStyle: .medium)
                                withAnimation {
                                    action()
                                }
                            }
                        }
                    }
                    isPressing = false
                    dragStartTime = nil
                }
        )
    }
    
    private func calculateVisionROI(center: CGPoint, screenSize: CGSize) -> CGRect {
        let sideLength: CGFloat = visionROISize
        let minX = max(0, center.x - sideLength / 2)
        // SwiftUI top-left origin. ROI top edge.
        let minY = max(0, center.y - sideLength / 2)
        
        let actualW = min(sideLength, screenSize.width - minX)
        let actualH = min(sideLength, screenSize.height - minY) // Height downwards
        
        // Convert to Vision ROI (Normalized, Origin Bottom-Left)
        // ROI x = minX / W
        // ROI w = actualW / W
        // ROI h = actualH / H
        // ROI y (bottom of rect) = 1.0 - (minY + actualH) / H
        
        let normX = minX / screenSize.width
        let normW = actualW / screenSize.width
        let normH = actualH / screenSize.height
        let normY = 1.0 - (minY + actualH) / screenSize.height
        
        return CGRect(x: normX, y: max(0, normY), width: normW, height: normH)
    }
    
    private func calculatePosition(geometry: GeometryProxy, safeAreaBottom: CGFloat) -> CGPoint {
        if isDragging {
            return interactionManager.dragPosition
        } else if interactionManager.state == .snapping {
             return getSnapPosition(in: geometry.size)
        } else if interactionManager.state == .returning {
             // Return to bottom center (idle position)
             // Animation is handled by the view transition to this state
             return getIdlePosition(geometry: geometry, safeAreaBottom: safeAreaBottom)
        } else {
            return getIdlePosition(geometry: geometry, safeAreaBottom: safeAreaBottom)
        }
    }
    
    private func getRotationAngle() -> Angle {
        if interactionManager.state == .snapping {
            // Horizontal line (isHorizontalSnap = true) -> Rotate 90 deg
            // Vertical line (isHorizontalSnap = false) -> Rotate 0 deg (Normal dragging icon)
            return interactionManager.isHorizontalSnap ? .degrees(90) : .degrees(0)
        }
        return .degrees(0)
    }
    
    private func getIdlePosition(geometry: GeometryProxy, safeAreaBottom: CGFloat) -> CGPoint {
        // Bottom center position
        // x: center
        // y: bottom - offset
        // Use stored idleX if available, otherwise center
        let x = idleX ?? (geometry.size.width / 2)
        let y = geometry.size.height - safeAreaBottom - (catWidth / 2) // Adjust as needed
        return CGPoint(x: x, y: y)
    }

    private func getVerticalOffset(safeAreaBottom: CGFloat) -> CGFloat {
         return 0 // Deprecated helper, using absolute position now
    }

    // Helper to take a screenshot of the window
    func captureScreen(scale: CGFloat) -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return nil }
        
        // Use custom format to control scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        
        // Calculate the crop rect based on current ROI if available
        // This is a further optimization: only render the part of the screen we care about
        // But UIGraphicsImageRenderer renders the whole context first, so cropping might not save GPU time
        // However, rendering at lower scale (0.5) already saves 75% pixel processing
        
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { ctx in
             window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
    
    private func getAnimation(for state: FloatingPetState) -> Animation {
        switch state {
        case .dragging:
            return .spring(response: 0.3, dampingFraction: 0.8)
        case .snapping:
            return .spring(response: 0.5, dampingFraction: 0.6)
        case .returning:
            // 使用 easeInOut 让变化更平滑自然，持续 1.0 秒配合 Manager 的逻辑
            return .easeInOut(duration: 1.0)
        case .idle:
            return .easeOut(duration: 0.3)
        }
    }
}

#Preview {
    ZStack {
        Color.white
        VStack {
            Spacer()
            Color.gray.frame(height: 83) // 模拟 TabBar
        }
        PetOverlayView(action: {})
    }
}
