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
    @Published var currentMotionVideoName: String = "naicha_right_back"
    @Published var isMotionVideoLooping: Bool = true
    @Published var isMotionVideoMirrored: Bool = false
    @Published var motionPlaybackRate: Float = 1.0
    
    // Configuration
    @Published var petName: String = "naicha"
    
    // Debug
    @Published var isDebugMode: Bool = false
    @Published var selectedPathId: UUID? = nil // For editing
    @Published var draggingNodeId: UUID? = nil
    
    private var timer: Timer?
    private var movementElapsed: TimeInterval = 0
    private var lastMovementTick: Date?
    private var isMovementPausedForTurn: Bool = false
    private var playbackStage: MotionPlaybackStage = .idle
    private var latestDesiredLoop: LoopDescriptor?
    private var turnCommittedTarget: LoopDescriptor?
    private var currentClipPlaybackTime: Double = 0
    private var currentClipDuration: Double = 0
    private var isTranslationFrozenByClip = false
    private var currentRoomIndex: Int = 0
    private var isCrossRoomTransitionPhase: Bool = false
    private let crossRoomTransitionDuration: TimeInterval = 0.28
    private let crossRoomTransitionDistanceFraction: CGFloat = 0.035
    private let turnLeadTime: TimeInterval = 0.12
    private let isometricAxisAngleDegrees: CGFloat = 35.0
    private let maomaoLoopPlaybackRate: Float = 0.9
    private let maomaoMovementDurationScale: TimeInterval = 1.18
    
    // Sequence Management
    private struct SequenceStep {
        let pathIndex: Int
        let reversed: Bool
    }

    private enum LoopKind {
        case up
        case down
    }

    private struct LoopDescriptor: Equatable {
        let kind: LoopKind
        let mirrored: Bool
    }

    private enum MotionPlaybackStage {
        case idle
        case looping(kind: LoopKind)
        case waitingLoopFinish(currentKind: LoopKind)
        case turning
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
        resetMotionPlaybackState()
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
        currentRoomIndex = path.roomIndex
        isVisible = true
        movementElapsed = 0
        lastMovementTick = Date()
        
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
        isCrossRoomTransitionPhase = isCrossRoomTransitionStep(index)

        updateInitialDirection(for: path, reversed: step.reversed)
        updateMotionPlayback()
        
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
        
        if isMovementPausedForTurn {
            return
        }

        let step = sequence[currentStepIndex]
        let now = Date()
        if lastMovementTick == nil {
            lastMovementTick = now
        }
        let delta = now.timeIntervalSince(lastMovementTick ?? now)
        lastMovementTick = now

        if !isTranslationFrozenByClip {
            movementElapsed += max(delta, 0)
        }

        let elapsed = movementElapsed
        let duration = path.duration * movementDurationScale()
        isCrossRoomTransitionPhase = isCrossRoomTransitionStep(currentStepIndex) && elapsed < crossRoomTransitionDuration
        
        if elapsed >= duration {
            // Step finished
            currentStepIndex += 1
            startStep(index: currentStepIndex)
            return
        }
        
        currentProgress = progressForStep(step, elapsed: elapsed, duration: duration)
        
        updatePosition(along: path, at: currentProgress)
        let desired = desiredLoopDescriptor(path: path, step: step, elapsed: elapsed, duration: duration)
        updateMotionPlayback(desired: desired)
    }

    private func isCrossRoomTransitionStep(_ index: Int) -> Bool {
        guard index > 0, index < sequence.count else { return false }
        let current = sequence[index]
        let previous = sequence[index - 1]
        return previous.pathIndex != current.pathIndex && previous.reversed && current.reversed
    }

    private func progressForStep(_ step: SequenceStep, elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        let clampedDuration = max(duration, 0.001)
        let ratio = CGFloat(min(max(elapsed / clampedDuration, 0), 1))

        guard isCrossRoomTransitionStep(currentStepIndex), step.reversed else {
            return step.reversed ? (1.0 - ratio) : ratio
        }

        let transitionDuration = min(crossRoomTransitionDuration, clampedDuration * 0.5)
        let transitionDistance = min(max(crossRoomTransitionDistanceFraction, 0), 0.2)

        if elapsed <= transitionDuration {
            let t = CGFloat(min(max(elapsed / max(transitionDuration, 0.001), 0), 1))
            return 1.0 - t * transitionDistance
        }

        let remainingElapsed = elapsed - transitionDuration
        let remainingDuration = max(clampedDuration - transitionDuration, 0.001)
        let t = CGFloat(min(max(remainingElapsed / remainingDuration, 0), 1))
        return (1.0 - transitionDistance) - t * (1.0 - transitionDistance)
    }
    
    func stopMovement() {
        timer?.invalidate()
        timer = nil
        isVisible = false
        activePathId = nil
        movementElapsed = 0
        lastMovementTick = nil
        resetMotionPlaybackState()
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
                
        updateMovementDirection(from: currentPosition, to: newPos, roomIndex: currentRoomIndex)
                
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

    private func updateInitialDirection(for path: PetPath, reversed: Bool) {
        let nodes = path.nodes
        guard nodes.count > 1 else { return }

        let sourceNode: PathNode
        let targetNode: PathNode

        if reversed {
            sourceNode = nodes[nodes.count - 1]
            targetNode = nodes[nodes.count - 2]
        } else {
            sourceNode = nodes[0]
            targetNode = nodes[1]
        }
        let source = CGPoint(x: sourceNode.x, y: sourceNode.y)
        let target = CGPoint(x: targetNode.x, y: targetNode.y)
        updateMovementDirection(from: source, to: target, roomIndex: path.roomIndex)
    }

    private func updateMovementDirection(from source: CGPoint, to target: CGPoint, roomIndex: Int) {
        _ = roomIndex
        let fallback = isMovingUp
            ? (isMovingRight ? IsoDirection.rightUp : IsoDirection.leftUp)
            : (isMovingRight ? IsoDirection.rightDown : IsoDirection.leftDown)
        let direction = isoDirection(from: source, to: target, fallback: fallback)
        applyIsoDirection(direction)
    }

    private func loopDescriptorForCurrentDirection() -> LoopDescriptor {
        if isMovingUp {
            // Upward movement uses right_back. Moving left mirrors it.
            return LoopDescriptor(kind: .up, mirrored: !isMovingRight)
        } else {
            // Downward movement uses left_front. Moving right mirrors it.
            return LoopDescriptor(kind: .down, mirrored: isMovingRight)
        }
    }

    private func clipName(for kind: LoopKind) -> String {
        switch kind {
        case .up:
            return "\(petName)_right_back"
        case .down:
            return "\(petName)_left_front"
        }
    }

    private func updateMotionPlayback(desired override: LoopDescriptor? = nil) {
        let baseDesired = override ?? loopDescriptorForCurrentDirection()
        let desired: LoopDescriptor
        if let committed = turnCommittedTarget {
            if baseDesired.kind == .down {
                turnCommittedTarget = nil
                desired = baseDesired
            } else {
                desired = committed
            }
        } else {
            desired = baseDesired
        }
        latestDesiredLoop = desired

        switch playbackStage {
        case .idle:
            startLoop(descriptor: desired)
        case .looping(let currentKind):
            if currentKind == desired.kind {
                isMotionVideoMirrored = desired.mirrored
            } else if shouldPlayTurn(currentKind: currentKind, target: desired) {
                // 转向动画需要立即打断当前循环并播放
                startTurn(for: desired)
            } else {
                // 行进方向变化时，直接切到目标循环，避免被旧循环拖住
                startLoop(descriptor: desired)
            }
        case .waitingLoopFinish(let currentKind):
            if currentKind == desired.kind {
                // Desired state switched back; resume looping current clip.
                playbackStage = .looping(kind: currentKind)
                isMotionVideoLooping = true
                isMotionVideoMirrored = desired.mirrored
            }
        case .turning:
            // Keep tracking desired target; consume on turn finish.
            break
        }
    }

    private func desiredLoopDescriptor(path: PetPath, step: SequenceStep, elapsed: TimeInterval, duration: TimeInterval) -> LoopDescriptor {
        let current = loopDescriptorForCurrentDirection()

        guard case .looping(let currentKind) = playbackStage, currentKind == .up else {
            return current
        }
        guard current.kind == .up else { return current }
        guard turnLeadTime > 0, elapsed < duration else { return current }

        let lookaheadElapsed = min(duration, elapsed + turnLeadTime)
        guard lookaheadElapsed > elapsed else { return current }

        let currentProgress = progressForStep(step, elapsed: elapsed, duration: duration)
        let lookaheadProgress = progressForStep(step, elapsed: lookaheadElapsed, duration: duration)
        let source = position(along: path, at: currentProgress)
        let target = position(along: path, at: lookaheadProgress)
        let anticipated = loopDescriptor(from: source, to: target, roomIndex: path.roomIndex, fallback: current)

        if shouldPlayTurn(currentKind: currentKind, target: anticipated) && anticipated.kind == .down {
            return anticipated
        }
        return current
    }

    private func position(along path: PetPath, at progress: CGFloat) -> CGPoint {
        let nodes = path.nodes
        guard nodes.count > 1 else {
            return nodes.first.map { CGPoint(x: $0.x, y: $0.y) } ?? .zero
        }

        let clampedProgress = min(max(progress, 0), 1)
        let totalDistance = calculateTotalDistance(nodes: nodes)
        let targetDistance = totalDistance * clampedProgress
        var currentDist: CGFloat = 0

        for i in 0..<nodes.count-1 {
            let p1 = CGPoint(x: nodes[i].x, y: nodes[i].y)
            let p2 = CGPoint(x: nodes[i+1].x, y: nodes[i+1].y)
            let dist = hypot(p2.x - p1.x, p2.y - p1.y)

            if currentDist + dist >= targetDistance {
                let segmentProgress = dist > 0 ? (targetDistance - currentDist) / dist : 0
                return CGPoint(
                    x: p1.x + (p2.x - p1.x) * segmentProgress,
                    y: p1.y + (p2.y - p1.y) * segmentProgress
                )
            }

            currentDist += dist
        }

        if let last = nodes.last {
            return CGPoint(x: last.x, y: last.y)
        }
        return .zero
    }

    private func loopDescriptor(from source: CGPoint, to target: CGPoint, roomIndex: Int, fallback: LoopDescriptor) -> LoopDescriptor {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let distance = hypot(dx, dy)
        guard distance > 0.0001 else { return fallback }

        _ = roomIndex
        guard distance > 0.0001 else { return fallback }

        let fallbackDirection = fallback.kind == .up
            ? (fallback.mirrored ? IsoDirection.leftUp : IsoDirection.rightUp)
            : (fallback.mirrored ? IsoDirection.rightDown : IsoDirection.leftDown)
        let direction = isoDirection(from: source, to: target, fallback: fallbackDirection)
        return loopDescriptor(for: direction)
    }

    private enum IsoDirection {
        case rightUp
        case leftUp
        case rightDown
        case leftDown
    }

    private func applyIsoDirection(_ direction: IsoDirection) {
        switch direction {
        case .rightUp:
            isMovingRight = true
            isMovingUp = true
        case .leftUp:
            isMovingRight = false
            isMovingUp = true
        case .rightDown:
            isMovingRight = true
            isMovingUp = false
        case .leftDown:
            isMovingRight = false
            isMovingUp = false
        }
    }

    private func loopDescriptor(for direction: IsoDirection) -> LoopDescriptor {
        switch direction {
        case .rightUp:
            return LoopDescriptor(kind: .up, mirrored: false)
        case .leftUp:
            return LoopDescriptor(kind: .up, mirrored: true)
        case .rightDown:
            return LoopDescriptor(kind: .down, mirrored: true)
        case .leftDown:
            return LoopDescriptor(kind: .down, mirrored: false)
        }
    }

    private func isoDirection(from source: CGPoint, to target: CGPoint, fallback: IsoDirection) -> IsoDirection {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let distance = hypot(dx, dy)
        guard distance > 0.0001 else { return fallback }

        let vx = dx / distance
        let vy = -dy / distance
        let angle = isometricAxisAngleDegrees * .pi / 180.0
        let cosA = cos(angle)
        let sinA = sin(angle)

        let directions: [(IsoDirection, CGFloat, CGFloat)] = [
            (.rightUp, cosA, sinA),
            (.leftUp, -cosA, sinA),
            (.rightDown, cosA, -sinA),
            (.leftDown, -cosA, -sinA)
        ]

        var bestDirection = fallback
        var bestScore = -CGFloat.greatestFiniteMagnitude
        for (direction, axisX, axisY) in directions {
            let score = vx * axisX + vy * axisY
            if score > bestScore {
                bestScore = score
                bestDirection = direction
            }
        }
        return bestDirection
    }

    private func shouldPlayTurn(currentKind: LoopKind, target: LoopDescriptor) -> Bool {
        guard turnCommittedTarget == nil else { return false }
        guard currentKind == .up, target.kind == .down else { return false }
        return isMotionVideoMirrored != target.mirrored
    }

    private func startLoop(descriptor: LoopDescriptor) {
        resumeMovementAfterTurnIfNeeded()
        updateCurrentMotionVideoName(clipName(for: descriptor.kind))
        isMotionVideoMirrored = descriptor.mirrored
        isMotionVideoLooping = true
        motionPlaybackRate = loopPlaybackRate()
        playbackStage = .looping(kind: descriptor.kind)
    }

    private func startTurn(for target: LoopDescriptor) {
        if case .turning = playbackStage { return }
        pauseMovementForTurn()
        turnCommittedTarget = target
        updateCurrentMotionVideoName("\(petName)_left_turn")
        isMotionVideoMirrored = target.mirrored
        isMotionVideoLooping = false
        motionPlaybackRate = 2.0
        playbackStage = .turning
    }

    private func resetMotionPlaybackState() {
        isMovementPausedForTurn = false
        latestDesiredLoop = nil
        turnCommittedTarget = nil
        currentClipPlaybackTime = 0
        currentClipDuration = 0
        isTranslationFrozenByClip = false
        updateCurrentMotionVideoName("\(petName)_right_back")
        isMotionVideoLooping = true
        isMotionVideoMirrored = false
        motionPlaybackRate = 1.0
        playbackStage = .idle
    }

    private func loopPlaybackRate() -> Float {
        petName == "maomao" ? maomaoLoopPlaybackRate : 1.0
    }

    private func movementDurationScale() -> TimeInterval {
        petName == "maomao" ? maomaoMovementDurationScale : 1.0
    }

    private func pauseMovementForTurn() {
        guard !isMovementPausedForTurn else { return }
        isMovementPausedForTurn = true
        lastMovementTick = Date()
    }

    private func resumeMovementAfterTurnIfNeeded() {
        guard isMovementPausedForTurn else { return }
        isMovementPausedForTurn = false
        lastMovementTick = Date()
    }

    func handleMotionVideoFinished() {
        guard isVisible else { return }

        switch playbackStage {
        case .waitingLoopFinish(let currentKind):
            guard let target = latestDesiredLoop else {
                playbackStage = .looping(kind: currentKind)
                isMotionVideoLooping = true
                return
            }

            if target.kind == currentKind {
                startLoop(descriptor: target)
                return
            }

            // When switching from upward to downward movement, play turn clip once.
            if shouldPlayTurn(currentKind: currentKind, target: target) {
                startTurn(for: target)
            } else {
                startLoop(descriptor: target)
            }
        case .turning:
            resumeMovementAfterTurnIfNeeded()
            if let target = latestDesiredLoop {
                startLoop(descriptor: target)
            } else {
                playbackStage = .idle
            }
        default:
            break
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

    func updateMotionClipProgress(current: Double, duration: Double) {
        currentClipPlaybackTime = max(0, current)
        currentClipDuration = max(0, duration)
        synchronizeTranslationFreezeState()
    }

    private func updateCurrentMotionVideoName(_ newValue: String) {
        if currentMotionVideoName != newValue {
            currentClipPlaybackTime = 0
            currentClipDuration = 0
            isTranslationFrozenByClip = false
        }
        currentMotionVideoName = newValue
        synchronizeTranslationFreezeState()
    }

    private func synchronizeTranslationFreezeState() {
        let frozen = PetClipMotionFreezePolicy.shouldFreezeTranslation(
            videoName: currentMotionVideoName,
            clipTime: currentClipPlaybackTime
        )
        if frozen != isTranslationFrozenByClip {
            isTranslationFrozenByClip = frozen
            lastMovementTick = Date()
        }
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
