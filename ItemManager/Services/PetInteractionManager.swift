
import SwiftUI
import Combine

enum FloatingPetState {
    case idle           // Resting in TabBar
    case dragging       // Being dragged by user
    case snapping       // Snapped to a line (video playing)
    case returning      // Animating back to TabBar
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
        
        // Select video based on orientation
        currentVideoName = isHorizontal ? "cat_horizontal_interaction" : "cat_vertical_interaction"
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
