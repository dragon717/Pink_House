import SwiftUI
import Combine

// MARK: - 手势状态枚举

enum PetGestureState {
    case idle
    case pressing(startTime: Date)
    case dragging(startLocation: CGPoint)
}

// MARK: - 手势事件枚举

enum PetGestureEvent {
    case tap(location: CGPoint)
    case dragStart(location: CGPoint)
    case dragMove(location: CGPoint)
    case dragEnd(location: CGPoint, isCircleTriggered: Bool, circleBoundingBox: CGRect?)
}

// MARK: - 手势处理器

class PetGestureHandler: ObservableObject {
    // MARK: - Published Properties
    
    @Published var state: PetGestureState = .idle
    @Published var dragPosition: CGPoint = .zero
    @Published var dragPoints: [CGPoint] = []
    @Published var isCircleTriggered: Bool = false
    @Published var circleBoundingBox: CGRect?
    
    // MARK: - Callbacks
    
    var onGestureEvent: ((PetGestureEvent) -> Void)?
    var onCircleDetected: (() -> Void)?
    
    // MARK: - Configuration
    
    private let dragThreshold: CGFloat = 10.0
    private let tapDurationThreshold: TimeInterval = 0.3
    private let maxDragPoints: Int = 300
    
    // MARK: - Dependencies
    
    private let circleDetector = CircleDetector.shared
    private let hapticManager = HapticEngineManager.shared
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Gesture Handling
    
    func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
        switch state {
        case .idle:
            // 开始按压
            let distance = hypot(value.translation.width, value.translation.height)
            if distance > dragThreshold {
                // 移动距离超过阈值，转为拖拽
                startDragging(at: value.location)
            } else {
                // 保持在按压状态
                state = .pressing(startTime: Date())
            }
            
        case .pressing:
            // 检查是否转为拖拽
            let distance = hypot(value.translation.width, value.translation.height)
            if distance > dragThreshold {
                startDragging(at: value.location)
            }
            
        case .dragging:
            // 继续拖拽
            updateDragging(at: value.location)
        }
    }
    
    func handleDragEnded(_ value: DragGesture.Value, in size: CGSize) {
        switch state {
        case .pressing(let startTime):
            // 检查是否是点击
            let duration = Date().timeIntervalSince(startTime)
            if duration < tapDurationThreshold {
                onGestureEvent?(.tap(location: value.location))
            }
            reset()
            
        case .dragging:
            // 结束拖拽
            endDragging(at: value.location)
            
        case .idle:
            break
        }
    }
    
    // MARK: - Private Methods
    
    private func startDragging(at location: CGPoint) {
        state = .dragging(startLocation: location)
        dragPosition = location
        dragPoints = [location]
        isCircleTriggered = false
        circleBoundingBox = nil
        
        // 触发触觉反馈
        hapticManager.playUIFeedback(intensity: 0.6, sharpness: 0.7, fallbackStyle: .medium)
        
        // 通知开始拖拽
        onGestureEvent?(.dragStart(location: location))
    }
    
    private func updateDragging(at location: CGPoint) {
        dragPosition = location
        dragPoints.append(location)
        
        // 限制拖拽点数量
        if dragPoints.count > maxDragPoints {
            dragPoints.removeFirst(dragPoints.count - maxDragPoints)
        }
        
        // 检测圆圈
        let (isCircle, bbox) = circleDetector.detectCircle(in: dragPoints)
        
        if isCircle && !isCircleTriggered {
            // 首次检测到圆圈，触发反馈
            hapticManager.playUIFeedback(intensity: 1.0, sharpness: 1.0, fallbackStyle: .heavy)
            onCircleDetected?()
        }
        
        isCircleTriggered = isCircle
        circleBoundingBox = bbox
        
        // 通知拖拽移动
        onGestureEvent?(.dragMove(location: location))
    }
    
    private func endDragging(at location: CGPoint) {
        // 通知拖拽结束
        onGestureEvent?(.dragEnd(
            location: location,
            isCircleTriggered: isCircleTriggered,
            circleBoundingBox: circleBoundingBox
        ))
        
        reset()
    }
    
    func reset() {
        state = .idle
        dragPoints.removeAll()
        isCircleTriggered = false
        circleBoundingBox = nil
    }
}

// MARK: - 拖拽手势修饰符

struct PetDragGestureModifier: ViewModifier {
    @StateObject private var handler: PetGestureHandler
    let onGestureEvent: (PetGestureEvent) -> Void
    let onCircleDetected: () -> Void
    
    init(
        handler: PetGestureHandler = PetGestureHandler(),
        onGestureEvent: @escaping (PetGestureEvent) -> Void,
        onCircleDetected: @escaping () -> Void
    ) {
        _handler = StateObject(wrappedValue: handler)
        self.onGestureEvent = onGestureEvent
        self.onCircleDetected = onCircleDetected
    }
    
    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("PetOverlaySpace"))
                    .onChanged { value in
                        handler.handleDragChanged(value, in: CGSize.zero)
                    }
                    .onEnded { value in
                        handler.handleDragEnded(value, in: CGSize.zero)
                    }
            )
            .onAppear {
                handler.onGestureEvent = onGestureEvent
                handler.onCircleDetected = onCircleDetected
            }
    }
}

// MARK: - View Extension

extension View {
    func petDragGesture(
        handler: PetGestureHandler = PetGestureHandler(),
        onGestureEvent: @escaping (PetGestureEvent) -> Void,
        onCircleDetected: @escaping () -> Void = {}
    ) -> some View {
        modifier(PetDragGestureModifier(
            handler: handler,
            onGestureEvent: onGestureEvent,
            onCircleDetected: onCircleDetected
        ))
    }
}
