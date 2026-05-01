import Foundation
import SwiftUI

enum AvatarCharacterID: String, CaseIterable, Codable, Identifiable, Hashable {
    case girlV1 = "girl_v1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .girlV1:
            return "少女小人"
        }
    }

    var staticImageName: String {
        switch self {
        case .girlV1:
            return "avatar_girl_v1_static"
        }
    }

    var videoResourcePrefix: String {
        rawValue
    }

    var assetDirectoryName: String {
        rawValue
    }
}

enum AvatarAction: String, CaseIterable, Codable, Identifiable, Hashable {
    case idle
    case greet
    case wave
    case thinking
    case happy
    case shy
    case stickerPresent
    case touchHead
    case touchBody
    case sleep
    case talkLoop

    var id: String { rawValue }

    var loopsByDefault: Bool {
        switch self {
        case .idle, .sleep, .talkLoop:
            return true
        case .greet, .wave, .thinking, .happy, .shy, .stickerPresent, .touchHead, .touchBody:
            return false
        }
    }

    var videoSuffix: String {
        switch self {
        case .idle:
            return "idle"
        case .greet:
            return "greet"
        case .wave:
            return "wave"
        case .thinking:
            return "thinking"
        case .happy:
            return "happy"
        case .shy:
            return "shy"
        case .stickerPresent:
            return "sticker_present"
        case .touchHead:
            return "touch_head"
        case .touchBody:
            return "touch_body"
        case .sleep:
            return "sleep"
        case .talkLoop:
            return "talk_loop"
        }
    }
}

enum AvatarExpression: String, CaseIterable, Codable, Identifiable, Hashable {
    case neutral
    case smile
    case surprised
    case sad
    case angry
    case sleepy

    var id: String { rawValue }
}

enum AvatarHairStyleID: String, CaseIterable, Codable, Identifiable, Hashable {
    case defaultLongPink = "default_long_pink"
    case shortBob = "short_bob"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultLongPink:
            return "粉色长发"
        case .shortBob:
            return "短波波头"
        }
    }
}

enum AvatarRenderBackend: String, CaseIterable, Codable, Identifiable, Hashable {
    case staticImage
    case transparentVideo
    case live2d

    var id: String { rawValue }
}

struct AvatarRenderRequest: Equatable, Hashable {
    var characterID: AvatarCharacterID
    var action: AvatarAction
    var expression: AvatarExpression
    var hairStyleID: AvatarHairStyleID
    var preferredBackend: AvatarRenderBackend
    var isPaused: Bool

    init(
        characterID: AvatarCharacterID = .girlV1,
        action: AvatarAction = .idle,
        expression: AvatarExpression = .neutral,
        hairStyleID: AvatarHairStyleID = .defaultLongPink,
        preferredBackend: AvatarRenderBackend = .staticImage,
        isPaused: Bool = false
    ) {
        self.characterID = characterID
        self.action = action
        self.expression = expression
        self.hairStyleID = hairStyleID
        self.preferredBackend = preferredBackend
        self.isPaused = isPaused
    }
}

enum AvatarVideoAssetResolver {
    static func videoName(characterID: AvatarCharacterID, action: AvatarAction) -> String {
        "\(characterID.videoResourcePrefix)_\(action.videoSuffix)"
    }

    static func relativeVideoName(characterID: AvatarCharacterID, action: AvatarAction) -> String {
        "avatar/\(characterID.assetDirectoryName)/video/\(videoName(characterID: characterID, action: action))"
    }

    static func firstAvailableVideoName(characterID: AvatarCharacterID, action: AvatarAction) -> String? {
        let candidates = [
            relativeVideoName(characterID: characterID, action: action),
            relativeVideoName(characterID: characterID, action: .idle),
            videoName(characterID: characterID, action: action),
            videoName(characterID: characterID, action: .idle)
        ]
        return candidates.first { VideoResourceManager.shared.isVideoAvailable(name: $0) }
    }
}
