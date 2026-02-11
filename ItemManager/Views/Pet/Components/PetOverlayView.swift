import SwiftUI
import UIKit
import Vision

struct PetOverlayView: View {
    // 点击动作
    var action: () -> Void
    
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
                }
                
                // Cat Image Layer (Handles dragging, returning, and snapping fallback)
                // Show if NOT snapping OR if snapping but video is disabled
                if interactionManager.state != .snapping || !interactionManager.isPlayingVideo {
                    petView(geometry: geometry)
                }
                
                // Debug Layer for Vision Lines
                #if DEBUG
                if isDragging && showDebugVisuals {
                    // Draw ROI Box (Green)
                    if let roi = currentROI {
                        Rectangle()
                            .stroke(Color.green, lineWidth: 2)
                            .frame(
                                width: roi.width * geometry.size.width,
                                height: roi.height * geometry.size.height
                            )
                            .position(
                                x: roi.midX * geometry.size.width,
                                y: (1 - roi.midY) * geometry.size.height
                            )
                            .allowsHitTesting(false)
                    }

                    ForEach(visionManager.detectedLines.indices, id: \.self) { index in
                        let rect = visionManager.detectedLines[index]
                        let width = rect.width * geometry.size.width
                        let height = rect.height * geometry.size.height
                        let x = rect.minX * geometry.size.width
                        // Vision Y is bottom-left, SwiftUI is top-left
                        let y = (1 - rect.maxY) * geometry.size.height
                        
                        let isHorizontal = rect.width > rect.height
                        let color = isHorizontal ? Color.red : Color.blue
                        
                        ZStack {
                            Rectangle()
                                .stroke(color, lineWidth: 2)
                                .frame(width: width, height: height)
                            
                            VStack(spacing: 2) {
                                Text("\(isHorizontal ? "H" : "V") (\(Int(x)), \(Int(y)))")
                                Text("\(Int(width))x\(Int(height))")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(color.opacity(0.8))
                            .cornerRadius(4)
                            .offset(y: -height/2 - 20)
                        }
                        .position(
                            x: rect.midX * geometry.size.width,
                            y: (1 - rect.midY) * geometry.size.height
                        )
                        .allowsHitTesting(false)
                        // Removed print to reduce console spam, rely on visual overlay
                    }
                }
                #endif
            }
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
            Image("PetPeekingIcon")
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
            Image("PetDraggingIcon")
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
        let x = geometry.size.width / 2
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
