import Foundation

enum AvatarPetDialogueAdapter {
    static func avatarAction(fromLegacyPetAction action: String) -> AvatarAction {
        switch action {
        case "idle":
            return .idle
        case "sleeping":
            return .sleep
        case "grooming":
            return .happy
        case "enjoy_click":
            return .touchHead
        case "angry_click":
            return .touchBody
        case "rolling":
            return .happy
        default:
            if action.hasPrefix("bathing_") {
                return .happy
            }
            if action.hasPrefix("eating_") || action.hasPrefix("drinking_") {
                return .happy
            }
            return .idle
        }
    }

    static func shouldLoop(action: AvatarAction) -> Bool {
        action.loopsByDefault
    }

    static func petVideoCandidates(petID: String, legacyAction: String) -> [String] {
        var candidates: [String] = ["\(petID)_\(legacyAction)"]
        if legacyAction == "sleeping" {
            candidates.append("\(petID)_sleep")
        }
        if legacyAction.hasPrefix("bathing_") {
            candidates.append("\(petID)_bathing_happy")
        }
        candidates.append("\(petID)_idle")
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }
}
