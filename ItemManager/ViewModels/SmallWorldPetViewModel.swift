import SwiftUI
import Combine

class SmallWorldPetViewModel: ObservableObject {
    @Published var config = SmallWorldPetConfig()
    
    // State
    @Published var activePathId: UUID? = nil
    @Published var currentProgress: CGFloat = 0.0 // 0.0 to 1.0 (entire path)
    @Published var currentPosition: CGPoint = .zero
    @Published var isMovingRight: Bool = true
    @Published var isMovingUp: Bool = false
    @Published var isVisible: Bool = false
    
    // Configuration
    @Published var petName: String = "naicha"
    
    // Debug
    @Published var isDebugMode: Bool = false
    @Published var selectedPathId: UUID? = nil // For editing
    @Published var draggingNodeId: UUID? = nil
    
    private var timer: Timer?
    private var startTime: Date?
    
    // Sequence Management
    private struct SequenceStep {
        let pathIndex: Int
        let reversed: Bool
    }
    private var sequence: [SequenceStep] = []
    private var currentStepIndex: Int = 0
    
    init() {
        startRandomMovementLoop()
    }
    
    func startRandomMovementLoop() {
        // Try to start movement every few seconds if not active
        // Initial delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkAndStart()
        }
    }
    
    private func checkAndStart() {
        if activePathId == nil {
            // 50% chance to start if idle
            if Bool.random() {
                startMovement()
            }
        }
        
        // Schedule next check
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 5...15)) { [weak self] in
            self?.checkAndStart()
        }
    }
    
    func startMovement(pathId: UUID? = nil) {
        // 1. Set Pet Name from Global State
        if let selectedId = PetDataManager.shared.status.selectedPetId {
             self.petName = selectedId
        } else {
             self.petName = "naicha" // Fallback
        }
        
        // 2. Define Sequence
        // Ensure paths exist
        guard config.paths.count >= 2 else { return }
        
        // If a specific pathId is provided (debug), just run that one forward
        if let debugId = pathId, let index = config.paths.firstIndex(where: { $0.id == debugId }) {
            sequence = [SequenceStep(pathIndex: index, reversed: false)]
        } else {
            // Standard Sequence:
            // Path 1 (Forward) -> Path 2 (Forward) -> Path 2 (Backward) -> Path 1 (Backward)
            sequence = [
                SequenceStep(pathIndex: 0, reversed: false), // Room 1: Start -> End
                SequenceStep(pathIndex: 1, reversed: false), // Room 2: Start -> End
                SequenceStep(pathIndex: 1, reversed: true),  // Room 2: End -> Start
                SequenceStep(pathIndex: 0, reversed: true)   // Room 1: End -> Start
            ]
        }
        
        currentStepIndex = 0
        startStep(index: 0)
    }
    
    private func startStep(index: Int) {
        guard index < sequence.count else {
            stopMovement()
            return
        }
        
        let step = sequence[index]
        // Safety check for index
        guard step.pathIndex < config.paths.count else {
            stopMovement()
            return
        }
        
        let path = config.paths[step.pathIndex]
        
        activePathId = path.id
        isVisible = true
        startTime = Date()
        
        // Set initial position immediately to avoid flicker
        if step.reversed {
            currentProgress = 1.0
            if let last = path.nodes.last {
                currentPosition = CGPoint(x: last.x, y: last.y)
            }
        } else {
            currentProgress = 0.0
            if let first = path.nodes.first {
                currentPosition = CGPoint(x: first.x, y: first.y)
            }
        }
        
        // Start/Restart Timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateLoop()
        }
    }
    
    private func updateLoop() {
        guard let activePathId = activePathId,
              let path = config.paths.first(where: { $0.id == activePathId }) else {
            stopMovement()
            return
        }
        
        let step = sequence[currentStepIndex]
        let elapsed = Date().timeIntervalSince(startTime ?? Date())
        let duration = path.duration
        
        if elapsed >= duration {
            // Step finished
            currentStepIndex += 1
            startStep(index: currentStepIndex)
            return
        }
        
        // Calculate Progress
        if step.reversed {
            // 1.0 -> 0.0
            currentProgress = CGFloat(1.0 - (elapsed / duration))
        } else {
            // 0.0 -> 1.0
            currentProgress = CGFloat(elapsed / duration)
        }
        
        updatePosition(along: path, at: currentProgress)
    }
    
    func stopMovement() {
        timer?.invalidate()
        timer = nil
        isVisible = false
        activePathId = nil
    }
    
    private func updatePosition(along path: PetPath, at progress: CGFloat) {
        let nodes = path.nodes
        guard nodes.count > 1 else { return }
        
        let totalDistance = calculateTotalDistance(nodes: nodes)
        let targetDistance = totalDistance * progress
        
        var currentDist: CGFloat = 0
        
        for i in 0..<nodes.count-1 {
            let p1 = CGPoint(x: nodes[i].x, y: nodes[i].y)
            let p2 = CGPoint(x: nodes[i+1].x, y: nodes[i+1].y)
            let dist = hypot(p2.x - p1.x, p2.y - p1.y)
            
            if currentDist + dist >= targetDistance {
                let segmentProgress = dist > 0 ? (targetDistance - currentDist) / dist : 0
                let newX = p1.x + (p2.x - p1.x) * segmentProgress
                let newY = p1.y + (p2.y - p1.y) * segmentProgress
                let newPos = CGPoint(x: newX, y: newY)
                
                // Determine direction
                // Only update direction if movement is significant to avoid jitter
                if abs(newX - currentPosition.x) > 0.0001 || abs(newY - currentPosition.y) > 0.0001 {
                    if abs(newX - currentPosition.x) > 0.0001 {
                        isMovingRight = newX > currentPosition.x
                    }
                    if abs(newY - currentPosition.y) > 0.0001 {
                        isMovingUp = newY < currentPosition.y // Y is inverted in screen coords (0 at top)
                    }
                }
                
                currentPosition = newPos
                return
            }
            
            currentDist += dist
        }
        
        // End of path
        if let last = nodes.last {
            currentPosition = CGPoint(x: last.x, y: last.y)
        }
    }
    
    private func calculateTotalDistance(nodes: [PathNode]) -> CGFloat {
        var dist: CGFloat = 0
        for i in 0..<nodes.count-1 {
            let p1 = CGPoint(x: nodes[i].x, y: nodes[i].y)
            let p2 = CGPoint(x: nodes[i+1].x, y: nodes[i+1].y)
            dist += hypot(p2.x - p1.x, p2.y - p1.y)
        }
        return dist
    }
    
    // MARK: - Debug
    
    func updateNodePosition(nodeId: UUID, x: CGFloat, y: CGFloat) {
        guard let pathId = selectedPathId else { return }
        config.updateNode(pathId: pathId, nodeId: nodeId, newX: x, newY: y)
        
        // Print updated path for copy-pasting
        if let path = config.paths.first(where: { $0.id == pathId }) {
            print("\n--- Updated Path: \(path.name) ---")
            print("let nodes = [")
            for node in path.nodes {
                print(String(format: "    PathNode(x: %.3f, y: %.3f),", node.x, node.y))
            }
            print("]")
            print("-----------------------------------")
        }
    }
    
    func addNode(to pathId: UUID, x: CGFloat, y: CGFloat) {
        if let index = config.paths.firstIndex(where: { $0.id == pathId }) {
            config.paths[index].nodes.append(PathNode(x: x, y: y))
        }
    }
}
