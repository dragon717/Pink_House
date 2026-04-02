import SwiftUI
import Combine

@available(iOS 26.0, *)
final class BottomAccessoryCatDiamondOrbitViewModel: ObservableObject {
    @Published var currentPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var currentMotionVideoName: String
    @Published var isMotionVideoLooping: Bool = true
    @Published var isMotionVideoMirrored: Bool = false
    @Published var motionPlaybackRate: Float = 1.0
    @Published var isPlaybackPaused: Bool = false

    let config: BottomAccessoryCatDiamondOrbitConfig

    private var petName: String
    private var timer: Timer?
    private var lapElapsed: TimeInterval = 0
    private var lastMovementTick: Date?
    private var pauseEndTime: Date?
    private var completedLapsInBurst = 0
    private var patternIndex = 0
    private var isMovementPausedForTurn = false
    private var latestDesiredLoop: PetDirectionalMotionEngine.LoopDescriptor?
    private var turnCommittedTarget: PetDirectionalMotionEngine.LoopDescriptor?
    private var playbackStage: MotionPlaybackStage = .idle
    private var currentClipPlaybackTime: Double = 0
    private var currentClipDuration: Double = 0
    private var isTranslationFrozenByClip = false

    private enum MotionPlaybackStage {
        case idle
        case looping(kind: PetDirectionalMotionEngine.LoopKind)
        case turning
    }

    init(
        config: BottomAccessoryCatDiamondOrbitConfig = BottomAccessoryCatDiamondOrbitConfig(),
        petName: String = "naicha"
    ) {
        self.config = config
        self.petName = petName
        self.currentMotionVideoName = PetDirectionalMotionEngine.clipName(for: .up, petName: petName)
        self.currentPosition = CGPoint(x: 0.5, y: 0.5)
    }

    deinit {
        timer?.invalidate()
    }

    func startIfNeeded() {
        guard timer == nil else { return }
        resetState()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateLoop()
        }
    }

    func updatePetName(_ newValue: String) {
        guard !newValue.isEmpty, petName != newValue else { return }
        petName = newValue
        updateCurrentMotionVideoName(
            PetDirectionalMotionEngine.clipName(for: currentLoopKind(), petName: petName)
        )
    }

    func handleMotionVideoFinished() {
        guard !isPlaybackPaused else { return }

        switch playbackStage {
        case .turning:
            resumeMovementAfterTurnIfNeeded()
            if let target = latestDesiredLoop {
                startLoop(descriptor: target)
            } else {
                playbackStage = .idle
            }
        case .idle, .looping:
            break
        }
    }

    private func resetState() {
        completedLapsInBurst = 0
        patternIndex = 0
        pauseEndTime = nil
        lapElapsed = 0
        lastMovementTick = Date()
        isMovementPausedForTurn = false
        latestDesiredLoop = nil
        turnCommittedTarget = nil
        currentClipPlaybackTime = 0
        currentClipDuration = 0
        isTranslationFrozenByClip = false
        isPlaybackPaused = false
        currentPosition = orderedPoints().first ?? CGPoint(x: 0.5, y: 0.5)
        startLoop(descriptor: currentLoopDescriptor(progress: 0))
    }

    private func updateLoop() {
        let now = Date()

        if let pauseEndTime {
            if now < pauseEndTime {
                lastMovementTick = now
                return
            }
            self.pauseEndTime = nil
            isPlaybackPaused = false
            completedLapsInBurst = 0
            lapElapsed = 0
            lastMovementTick = now
        }

        if lastMovementTick == nil {
            lastMovementTick = now
        }
        let delta = now.timeIntervalSince(lastMovementTick ?? now)
        lastMovementTick = now

        if isMovementPausedForTurn {
            return
        }

        let lapDuration = effectiveLapDuration()
        guard lapDuration > 0 else { return }

        if !isTranslationFrozenByClip {
            lapElapsed += max(delta, 0)
        }

        while lapElapsed >= lapDuration {
            lapElapsed -= lapDuration
            completedLapsInBurst += 1

            if completedLapsInBurst >= currentLapGoal() {
                beginPause(after: now)
                return
            }
        }

        let progress = CGFloat(min(max(lapElapsed / lapDuration, 0), 1))
        currentPosition = position(for: progress)
        let desired = desiredLoopDescriptor(currentProgress: progress, lapDuration: lapDuration)
        updateMotionPlayback(desired: desired)
    }

    private func beginPause(after now: Date) {
        currentPosition = orderedPoints().first ?? currentPosition
        lapElapsed = 0
        isPlaybackPaused = true
        pauseEndTime = now.addingTimeInterval(currentPauseDuration())
        patternIndex = (patternIndex + 1) % max(config.lapPattern.count, 1)
    }

    private func currentLapGoal() -> Int {
        guard !config.lapPattern.isEmpty else { return 1 }
        return max(config.lapPattern[patternIndex % config.lapPattern.count], 1)
    }

    private func currentPauseDuration() -> TimeInterval {
        guard !config.pauseDurations.isEmpty else { return 1.0 }
        return config.pauseDurations[patternIndex % config.pauseDurations.count]
    }

    private func effectiveLapDuration() -> TimeInterval {
        let scale = max(config.speedScale, 0.1)
        return config.lapDuration / scale
    }

    private func orderedPoints() -> [CGPoint] {
        let center = config.normalizedCenter()
        let halfWidth = config.diamondWidthRatio / 2
        let halfHeight = config.diamondHeightRatio / 2

        let top = CGPoint(x: center.x, y: center.y - halfHeight)
        let right = CGPoint(x: center.x + halfWidth, y: center.y)
        let bottom = CGPoint(x: center.x, y: center.y + halfHeight)
        let left = CGPoint(x: center.x - halfWidth, y: center.y)

        switch (config.startAnchor, config.direction) {
        case (.top, .clockwise):
            return [top, right, bottom, left, top]
        case (.top, .counterclockwise):
            return [top, left, bottom, right, top]
        case (.bottom, .clockwise):
            return [bottom, left, top, right, bottom]
        case (.bottom, .counterclockwise):
            return [bottom, right, top, left, bottom]
        }
    }

    private func position(for progress: CGFloat) -> CGPoint {
        let clampedProgress = min(max(progress, 0), 1)
        let points = orderedPoints()
        let scaled = min(clampedProgress * 4, 3.999_999)
        let segmentIndex = Int(scaled)
        let segmentProgress = scaled - CGFloat(segmentIndex)
        let start = points[segmentIndex]
        let end = points[segmentIndex + 1]

        return CGPoint(
            x: start.x + (end.x - start.x) * segmentProgress,
            y: start.y + (end.y - start.y) * segmentProgress
        )
    }

    private func currentLoopDescriptor(progress: CGFloat) -> PetDirectionalMotionEngine.LoopDescriptor {
        let points = orderedPoints()
        let scaled = min(max(progress, 0), 0.999_999) * 4
        let segmentIndex = Int(scaled)
        let start = points[segmentIndex]
        let end = points[segmentIndex + 1]

        let fallback = latestDesiredLoop.map(PetDirectionalMotionEngine.fallbackDirection(for:)) ?? .rightUp
        let direction = PetDirectionalMotionEngine.isoDirection(
            from: start,
            to: end,
            angleDegrees: config.isometricAxisAngleDegrees,
            fallback: fallback
        )
        return PetDirectionalMotionEngine.loopDescriptor(for: direction)
    }

    private func desiredLoopDescriptor(
        currentProgress: CGFloat,
        lapDuration: TimeInterval
    ) -> PetDirectionalMotionEngine.LoopDescriptor {
        let current = currentLoopDescriptor(progress: currentProgress)

        guard case .looping(let currentKind) = playbackStage, currentKind == .up else {
            return current
        }
        guard current.kind == .up else { return current }

        let lookaheadProgress = (currentProgress + CGFloat(config.turnLeadTime / max(lapDuration, 0.001)))
            .truncatingRemainder(dividingBy: 1)
        let anticipated = currentLoopDescriptor(progress: lookaheadProgress)

        if PetDirectionalMotionEngine.shouldPlayTurn(
            currentKind: currentKind,
            target: anticipated,
            currentMirrored: isMotionVideoMirrored,
            hasCommittedTarget: turnCommittedTarget != nil
        ) {
            return anticipated
        }
        return current
    }

    private func updateMotionPlayback(desired: PetDirectionalMotionEngine.LoopDescriptor) {
        let target: PetDirectionalMotionEngine.LoopDescriptor
        if let committed = turnCommittedTarget {
            if desired.kind == .down {
                turnCommittedTarget = nil
                target = desired
            } else {
                target = committed
            }
        } else {
            target = desired
        }

        latestDesiredLoop = target

        switch playbackStage {
        case .idle:
            startLoop(descriptor: target)
        case .looping(let currentKind):
            if currentKind == target.kind {
                isMotionVideoMirrored = target.mirrored
            } else if PetDirectionalMotionEngine.shouldPlayTurn(
                currentKind: currentKind,
                target: target,
                currentMirrored: isMotionVideoMirrored,
                hasCommittedTarget: turnCommittedTarget != nil
            ) {
                startTurn(for: target)
            } else {
                startLoop(descriptor: target)
            }
        case .turning:
            break
        }
    }

    private func startLoop(descriptor: PetDirectionalMotionEngine.LoopDescriptor) {
        resumeMovementAfterTurnIfNeeded()
        updateCurrentMotionVideoName(
            PetDirectionalMotionEngine.clipName(for: descriptor.kind, petName: petName)
        )
        isMotionVideoMirrored = descriptor.mirrored
        isMotionVideoLooping = true
        motionPlaybackRate = loopPlaybackRate()
        playbackStage = .looping(kind: descriptor.kind)
    }

    private func startTurn(for target: PetDirectionalMotionEngine.LoopDescriptor) {
        if case .turning = playbackStage { return }
        pauseMovementForTurn()
        turnCommittedTarget = target
        updateCurrentMotionVideoName("\(petName)_left_turn")
        isMotionVideoMirrored = target.mirrored
        isMotionVideoLooping = false
        motionPlaybackRate = 2.0
        playbackStage = .turning
    }

    private func currentLoopKind() -> PetDirectionalMotionEngine.LoopKind {
        switch playbackStage {
        case .looping(let kind):
            return kind
        case .idle, .turning:
            return .up
        }
    }

    private func loopPlaybackRate() -> Float {
        1.0
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
}
