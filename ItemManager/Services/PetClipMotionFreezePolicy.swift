import Foundation

struct PetClipMotionFreezePolicy {
    struct Rule {
        var isEnabled: Bool
        var freezeRanges: [ClosedRange<Double>]
    }

    static var isNaichaLeftFrontFreezeEnabled = true

    static func shouldFreezeTranslation(videoName: String, clipTime: Double) -> Bool {
        guard let rule = rule(for: videoName), rule.isEnabled else { return false }
        return rule.freezeRanges.contains { range in
            clipTime >= range.lowerBound && clipTime <= range.upperBound
        }
    }

    static func rule(for videoName: String) -> Rule? {
        switch videoName {
        case "naicha_left_front":
            return Rule(
                isEnabled: isNaichaLeftFrontFreezeEnabled,
                freezeRanges: [3.0 ... 5.0]
            )
        default:
            return nil
        }
    }
}
