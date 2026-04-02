import SwiftUI

struct PetDirectionalMotionEngine {
    enum IsoDirection {
        case rightUp
        case leftUp
        case rightDown
        case leftDown
    }

    enum LoopKind {
        case up
        case down
    }

    struct LoopDescriptor: Equatable {
        let kind: LoopKind
        let mirrored: Bool
    }

    static func isoDirection(
        from source: CGPoint,
        to target: CGPoint,
        angleDegrees: CGFloat = 35.0,
        fallback: IsoDirection
    ) -> IsoDirection {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let distance = hypot(dx, dy)
        guard distance > 0.0001 else { return fallback }

        let vx = dx / distance
        let vy = -dy / distance
        let angle = angleDegrees * .pi / 180.0
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

    static func loopDescriptor(for direction: IsoDirection) -> LoopDescriptor {
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

    static func clipName(for kind: LoopKind, petName: String) -> String {
        switch kind {
        case .up:
            return "\(petName)_right_back"
        case .down:
            return "\(petName)_left_front"
        }
    }

    static func fallbackDirection(for descriptor: LoopDescriptor) -> IsoDirection {
        switch (descriptor.kind, descriptor.mirrored) {
        case (.up, false):
            return .rightUp
        case (.up, true):
            return .leftUp
        case (.down, false):
            return .leftDown
        case (.down, true):
            return .rightDown
        }
    }

    static func shouldPlayTurn(
        currentKind: LoopKind,
        target: LoopDescriptor,
        currentMirrored: Bool,
        hasCommittedTarget: Bool
    ) -> Bool {
        guard !hasCommittedTarget else { return false }
        guard currentKind == .up, target.kind == .down else { return false }
        return currentMirrored != target.mirrored
    }
}
