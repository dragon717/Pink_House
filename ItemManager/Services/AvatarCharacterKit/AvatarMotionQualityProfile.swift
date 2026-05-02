import Foundation
import SwiftUI

struct AvatarMotionQualityProfile: Equatable {
    let targetFramesPerSecond: Double
    let amplitudeScale: Double
    let containerScaleAmplitude: Double
    let containerLiftAmplitude: Double
    let staticPhaseSeconds: TimeInterval
    let pausesInLowPowerMode: Bool

    var frameInterval: TimeInterval {
        1.0 / max(targetFramesPerSecond, 1.0)
    }

    static let magicStickerCanvasScale: CGFloat = 0.72
    static let live2DSpikeFramesPerSecond = 24

    static let staticSnapshot = AvatarMotionQualityProfile(
        targetFramesPerSecond: 1,
        amplitudeScale: 0,
        containerScaleAmplitude: 0,
        containerLiftAmplitude: 0,
        staticPhaseSeconds: 0,
        pausesInLowPowerMode: true
    )

    private static let calmIdle = AvatarMotionQualityProfile(
        targetFramesPerSecond: 24,
        amplitudeScale: 0.62,
        containerScaleAmplitude: 0.0024,
        containerLiftAmplitude: -2.1,
        staticPhaseSeconds: 0,
        pausesInLowPowerMode: true
    )

    private static let expressiveGesture = AvatarMotionQualityProfile(
        targetFramesPerSecond: 30,
        amplitudeScale: 0.78,
        containerScaleAmplitude: 0.0028,
        containerLiftAmplitude: -2.4,
        staticPhaseSeconds: 0,
        pausesInLowPowerMode: true
    )

    private static let talkLoop = AvatarMotionQualityProfile(
        targetFramesPerSecond: 24,
        amplitudeScale: 0.56,
        containerScaleAmplitude: 0.0022,
        containerLiftAmplitude: -1.9,
        staticPhaseSeconds: 0,
        pausesInLowPowerMode: true
    )

    static func profile(for action: AvatarAction, isLowPowerModeEnabled: Bool) -> AvatarMotionQualityProfile {
        if isLowPowerModeEnabled {
            return staticSnapshot
        }

        switch action {
        case .wave, .greet, .happy, .shy, .touchHead, .touchBody:
            return expressiveGesture
        case .talkLoop, .thinking:
            return talkLoop
        case .idle, .sleep, .stickerPresent:
            return calmIdle
        }
    }
}
