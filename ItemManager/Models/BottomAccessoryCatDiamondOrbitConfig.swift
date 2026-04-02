import SwiftUI

enum BottomAccessoryCatOrbitDirection: String, Codable {
    case clockwise
    case counterclockwise
}

enum BottomAccessoryCatOrbitStartAnchor {
    case top
    case bottom
}

struct BottomAccessoryCatDiamondOrbitConfig {
    var direction: BottomAccessoryCatOrbitDirection = .clockwise
    var startAnchor: BottomAccessoryCatOrbitStartAnchor = .bottom
    var diamondWidthRatio: CGFloat = 0.48
    var diamondHeightRatio: CGFloat = 0.66
    var centerYOffset: CGFloat = 0
    var normalizedCenterPoint: CGPoint?
    var lapPattern: [Int] = [2, 1]
    var pauseDurations: [TimeInterval] = [1.2, 0.9]
    var lapDuration: TimeInterval = 4.8
    var speedScale: CGFloat = 1.0
    var turnLeadTime: TimeInterval = 0.12
    var isometricAxisAngleDegrees: CGFloat = 35.0
    var hitSlop: CGSize = CGSize(width: 24, height: 24)
    var petSize: CGSize = CGSize(width: 58, height: 58)
    var contentHeight: CGFloat = 112

    func normalizedCenter() -> CGPoint {
        normalizedCenterPoint ?? CGPoint(x: 0.5, y: 0.54 + centerYOffset)
    }
}
