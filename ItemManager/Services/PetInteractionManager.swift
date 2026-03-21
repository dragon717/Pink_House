
import SwiftUI
import Combine

enum FloatingPetState {
    case idle           // Resting in TabBar
    case dragging       // Being dragged by user
    case snapping       // Snapped to a line (video playing)
    case returning      // Animating back to TabBar
    case analyzing      // Analyzing image content (hidden/waiting)
}

class PetInteractionManager: ObservableObject {
    static let shared = PetInteractionManager()
    
    @Published var state: FloatingPetState = .idle
    @Published var dragPosition: CGPoint = .zero
    @Published var snappedLine: CGRect? = nil
    @Published var isTabBarIconHidden: Bool = false
    @Published var isHorizontalSnap: Bool = true // Add orientation state
    
    // Video playback
    @Published var isPlayingVideo: Bool = false
    @Published var currentVideoName: String? = nil
    
    // Configuration
    let snapThreshold: CGFloat = 50.0 // Points
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // 监听宠物切换通知
        NotificationCenter.default.publisher(for: Notification.Name("PetDidSwitch"))
            .sink { [weak self] _ in
                // 触发 UI 刷新
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // 获取当前宠物 ID (从 UserDefaults 读取，确保多处状态一致)
    var currentPetId: String {
        // 优化：直接从 PetDataManager 获取内存中的状态，避免频繁读取 UserDefaults 和 JSON 解码
        return PetDataManager.shared.status.selectedPetId ?? "naicha"
    }
    
    // Actions
    func startDragging(at location: CGPoint) {
        state = .dragging
        dragPosition = location
        isTabBarIconHidden = true
    }
    
    func updateDragPosition(_ location: CGPoint) {
        guard state == .dragging else { return }
        dragPosition = location
    }
    
    func startAnalyzing() {
        state = .analyzing
    }
    
    func endAnalyzing() {
        returnToTabBar()
    }
    
    func endDragging(at location: CGPoint, screenSize: CGSize) {
        guard state == .dragging else { return }
        
        // Convert location to normalized coordinates for Vision check
        let normalizedPoint = CGPoint(
            x: location.x / screenSize.width,
            // Vision Y is inverted (0 at bottom)
            y: 1.0 - (location.y / screenSize.height)
        )
        
        if let closestLine = VisionManager.shared.findClosestLine(to: normalizedPoint) {
            // Determine if horizontal or vertical
            let isHorizontal = closestLine.width > closestLine.height
            snapToLine(closestLine, isHorizontal: isHorizontal)
        } else {
            returnToTabBar()
        }
    }
    
    private func snapToLine(_ line: CGRect, isHorizontal: Bool) {
        state = .snapping
        snappedLine = line
        isHorizontalSnap = isHorizontal
        
        // Select video based on orientation and current pet
        let petPrefix = currentPetId
        currentVideoName = isHorizontal ? "\(petPrefix)_horizontal_interaction" : "\(petPrefix)_vertical_interaction"
        isPlayingVideo = false // TEMPORARY: Disable video, use image rotation
        
        // TEMPORARY: Auto return after delay since video is disabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.returnToTabBar()
        }
        
        // The view will handle video playback via PetVideoPlayer
        // and call onVideoFinished when done
    }
    
    func onVideoFinished() {
        isPlayingVideo = false
        returnToTabBar()
    }
    
    func returnToTabBar() {
        state = .returning
        // Animation duration should match the spring animation in view
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.resetToIdle()
        }
    }
    
    private func resetToIdle() {
        state = .idle
        isTabBarIconHidden = false
        snappedLine = nil
        currentVideoName = nil
    }
}
