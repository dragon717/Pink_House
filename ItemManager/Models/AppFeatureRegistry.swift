import Foundation
import Combine

enum AppFeatureID: String, CaseIterable, Identifiable, Codable, Hashable {
    case wardrobe
    case depositPlan
    case house
    case petHome
    case petChat
    case magicSticker
    case outfitJournal
    case wealth
    case calendar
    case bigWorld
    case perler
    case dressStock
    case recycleBin

    var id: String { rawValue }
}

enum AppFeatureSurface: String, Codable, Hashable {
    case bottomDock
    case houseRoom
    case petPhone
    case favoriteMenu
}

enum AppFeatureRoute {
    case tab(Int)
    case wardrobe(HomeTab)
    case smallWorld(SmallWorldDestination)
}

struct AppFeatureDescriptor: Identifiable {
    let id: AppFeatureID
    let title: String
    let subtitle: String
    let systemImage: String
    let tintHex: String
    let route: AppFeatureRoute
    let unlockFeature: FeatureItem?
    let surfaces: Set<AppFeatureSurface>

    var isUnlocked: Bool {
        guard let unlockFeature else { return true }
        return FeatureUnlockManager.shared.isUnlocked(unlockFeature)
    }
}

enum AppFeatureRegistry {
    static let all: [AppFeatureDescriptor] = [
        AppFeatureDescriptor(
            id: .wardrobe,
            title: "衣橱",
            subtitle: "管理裙装与搭配资料",
            systemImage: "cabinet.fill",
            tintHex: "#FF69B4",
            route: .wardrobe(.wardrobe),
            unlockFeature: .wardrobe,
            surfaces: [.houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .depositPlan,
            title: "心愿尾款",
            subtitle: "查看待补尾款与提醒",
            systemImage: "tag.fill",
            tintHex: "#FF1493",
            route: .wardrobe(.depositPlan),
            unlockFeature: .finalPayment,
            surfaces: [.bottomDock, .houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .house,
            title: "House",
            subtitle: "进入手帐房间",
            systemImage: "house.fill",
            tintHex: "#87CEEB",
            route: .smallWorld(.menu),
            unlockFeature: nil,
            surfaces: [.houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .petHome,
            title: "萌宠",
            subtitle: "喂食、打工与照顾",
            systemImage: "pawprint.fill",
            tintHex: "#FF7F50",
            route: .smallWorld(.pet),
            unlockFeature: .pet,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .petChat,
            title: "萌宠对话",
            subtitle: "聊天、搜索与搭配建议",
            systemImage: "bubble.left.and.bubble.right.fill",
            tintHex: "#FF7F50",
            route: .tab(3),
            unlockFeature: nil,
            surfaces: [.bottomDock, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .magicSticker,
            title: "魔法贴纸",
            subtitle: "默认贴纸页与手帐创作",
            systemImage: "book.pages.fill",
            tintHex: "#FF69B4",
            route: .smallWorld(.ootdDefaultBook),
            unlockFeature: .ootdDefaultBook,
            surfaces: [.bottomDock, .houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .outfitJournal,
            title: "穿搭手帐",
            subtitle: "书架、翻页与搭配记录",
            systemImage: "book.closed.fill",
            tintHex: "#FF85C1",
            route: .smallWorld(.ootd),
            unlockFeature: .ootd,
            surfaces: [.bottomDock, .houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .wealth,
            title: "来财",
            subtitle: "资产、请签与数钱",
            systemImage: "yensign.circle.fill",
            tintHex: "#FFD700",
            route: .smallWorld(.wealth(nil)),
            unlockFeature: .wealth,
            surfaces: [.bottomDock, .houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .calendar,
            title: "梦裙日历",
            subtitle: "按日期回看收藏",
            systemImage: "calendar",
            tintHex: "#DDA0DD",
            route: .smallWorld(.calendar),
            unlockFeature: .calendar,
            surfaces: [.bottomDock, .houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .bigWorld,
            title: "世界书",
            subtitle: "旅行式收藏世界",
            systemImage: "globe.asia.australia",
            tintHex: "#87CEEB",
            route: .smallWorld(.bigWorld),
            unlockFeature: .bigWorld,
            surfaces: [.bottomDock, .houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .perler,
            title: "拼豆工坊",
            subtitle: "像素图与拼豆创作",
            systemImage: "circle.grid.2x2.fill",
            tintHex: "#FF8C94",
            route: .smallWorld(.perler),
            unlockFeature: .perler,
            surfaces: [.bottomDock, .houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .dressStock,
            title: "裙装股市",
            subtitle: "行情、观察与情报",
            systemImage: "chart.line.uptrend.xyaxis",
            tintHex: "#FF6B9D",
            route: .smallWorld(.dressStock),
            unlockFeature: .dressStock,
            surfaces: [.bottomDock, .houseRoom, .petPhone, .favoriteMenu]
        ),
        AppFeatureDescriptor(
            id: .recycleBin,
            title: "回收站",
            subtitle: "恢复误删衣物",
            systemImage: "trash.fill",
            tintHex: "#808080",
            route: .smallWorld(.recycleBin),
            unlockFeature: .recycleBin,
            surfaces: [.bottomDock, .houseRoom, .petPhone, .favoriteMenu]
        )
    ]

    static func descriptor(for id: AppFeatureID) -> AppFeatureDescriptor {
        all.first { $0.id == id } ?? petChat
    }

    static var petChat: AppFeatureDescriptor {
        all.first { $0.id == .petChat }!
    }

    static var bottomDockFeatures: [AppFeatureDescriptor] {
        all.filter { $0.surfaces.contains(.bottomDock) }
    }

    static var unlockedBottomDockFeatures: [AppFeatureDescriptor] {
        bottomDockFeatures.filter(\.isUnlocked)
    }
}

final class BottomDockSettingsManager: ObservableObject {
    static let shared = BottomDockSettingsManager()

    @Published private(set) var selectedFeatureID: AppFeatureID

    private let userDefaultsKey = "bottomDockSelectedFeature.v1"
    private let defaultFeatureID: AppFeatureID = .petChat

    private init() {
        if let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
           let saved = AppFeatureID(rawValue: rawValue),
           AppFeatureRegistry.descriptor(for: saved).surfaces.contains(.bottomDock),
           AppFeatureRegistry.descriptor(for: saved).isUnlocked {
            selectedFeatureID = saved
        } else {
            selectedFeatureID = defaultFeatureID
        }
    }

    var selectedFeature: AppFeatureDescriptor {
        let descriptor = AppFeatureRegistry.descriptor(for: selectedFeatureID)
        guard descriptor.surfaces.contains(.bottomDock), descriptor.isUnlocked else {
            return AppFeatureRegistry.descriptor(for: defaultFeatureID)
        }
        return descriptor
    }

    var availableFeatures: [AppFeatureDescriptor] {
        let unlocked = AppFeatureRegistry.unlockedBottomDockFeatures
        return unlocked.isEmpty ? [AppFeatureRegistry.descriptor(for: defaultFeatureID)] : unlocked
    }

    func setSelectedFeature(_ featureID: AppFeatureID) {
        let descriptor = AppFeatureRegistry.descriptor(for: featureID)
        guard descriptor.surfaces.contains(.bottomDock), descriptor.isUnlocked else { return }
        selectedFeatureID = featureID
        UserDefaults.standard.set(featureID.rawValue, forKey: userDefaultsKey)
    }

    func resetToDefault() {
        setSelectedFeature(defaultFeatureID)
    }
}
