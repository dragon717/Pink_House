import Foundation
import Combine

enum AppFeatureID: String, CaseIterable, Identifiable, Codable, Hashable {
    case wardrobe
    case depositPlan
    case house
    case me
    case petHome
    case petChat
    case timeHall
    case magicSticker
    case outfitJournal
    case wealth
    case calendar
    case bigWorld
    case perler
    case dressStock
    case recycleBin

    var id: String { rawValue }

    /// ponytail: unfinished pages hidden from UI; remove cases when ready to ship
    var isShipHidden: Bool {
        switch self {
        case .house, .perler, .dressStock, .bigWorld:
            return true
        default:
            return false
        }
    }
}

enum AppFeatureSurface: String, Codable, Hashable {
    case bottomDock
    case houseRoom
    case petPhone
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

    var isAvailableInUI: Bool {
        if id.isShipHidden { return false }
        guard let unlockFeature else { return true }
        return FeatureUnlockManager.shared.isVisible(unlockFeature)
    }

    var localizedTitle: String {
        title.appLocalized
    }

    var localizedSubtitle: String {
        subtitle.appLocalized
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
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .depositPlan,
            title: "心愿尾款",
            subtitle: "查看待补尾款与提醒",
            systemImage: "tag.fill",
            tintHex: "#FF1493",
            route: .wardrobe(.depositPlan),
            unlockFeature: .finalPayment,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .house,
            title: "House",
            subtitle: "进入手帐房间",
            systemImage: "house.fill",
            tintHex: "#87CEEB",
            route: .smallWorld(.menu),
            unlockFeature: nil,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .me,
            title: "我",
            subtitle: "设置、VIP 与备份",
            systemImage: "face.smiling",
            tintHex: "#F4C542",
            route: .tab(2),
            unlockFeature: nil,
            surfaces: [.bottomDock]
        ),
        AppFeatureDescriptor(
            id: .petHome,
            title: "萌宠",
            subtitle: "喂食、打工与照顾",
            systemImage: "pawprint.fill",
            tintHex: "#FF7F50",
            route: .smallWorld(.pet),
            unlockFeature: .pet,
            surfaces: [.houseRoom, .petPhone]
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
            id: .timeHall,
            title: "时光馆",
            subtitle: "梦裙编年史与风格浪花",
            systemImage: "books.vertical.fill",
            tintHex: "#E8B4B8",
            route: .tab(4),
            unlockFeature: nil,
            surfaces: [.bottomDock]
        ),
        AppFeatureDescriptor(
            id: .magicSticker,
            title: "魔法贴纸",
            subtitle: "默认贴纸页与手帐创作",
            systemImage: "book.pages.fill",
            tintHex: "#FF69B4",
            route: .smallWorld(.ootdDefaultBook),
            unlockFeature: .ootdDefaultBook,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .outfitJournal,
            title: "穿搭手帐",
            subtitle: "书架、翻页与搭配记录",
            systemImage: "book.closed.fill",
            tintHex: "#FF85C1",
            route: .smallWorld(.ootd),
            unlockFeature: .ootd,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .wealth,
            title: "来财",
            subtitle: "资产、请签与数钱",
            systemImage: "yensign.circle.fill",
            tintHex: "#FFD700",
            route: .smallWorld(.wealth(nil)),
            unlockFeature: .wealth,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .calendar,
            title: "梦裙日历",
            subtitle: "按日期回看收藏",
            systemImage: "calendar",
            tintHex: "#DDA0DD",
            route: .smallWorld(.calendar),
            unlockFeature: .calendar,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .bigWorld,
            title: "世界书",
            subtitle: "旅行式收藏世界",
            systemImage: "globe.asia.australia",
            tintHex: "#87CEEB",
            route: .smallWorld(.bigWorld),
            unlockFeature: .bigWorld,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .perler,
            title: "拼豆工坊",
            subtitle: "像素图与拼豆创作",
            systemImage: "circle.grid.2x2.fill",
            tintHex: "#FF8C94",
            route: .smallWorld(.perler),
            unlockFeature: .perler,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .dressStock,
            title: "裙装股市",
            subtitle: "行情、观察与情报",
            systemImage: "chart.line.uptrend.xyaxis",
            tintHex: "#FF6B9D",
            route: .smallWorld(.dressStock),
            unlockFeature: .dressStock,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        ),
        AppFeatureDescriptor(
            id: .recycleBin,
            title: "回收站",
            subtitle: "恢复误删衣物",
            systemImage: "trash.fill",
            tintHex: "#808080",
            route: .smallWorld(.recycleBin),
            unlockFeature: .recycleBin,
            surfaces: [.bottomDock, .houseRoom, .petPhone]
        )
    ]

    static func descriptor(for id: AppFeatureID) -> AppFeatureDescriptor {
        all.first { $0.id == id } ?? petChat
    }

    static var petChat: AppFeatureDescriptor {
        all.first { $0.id == .petChat }!
    }

    static var bottomDockFeatures: [AppFeatureDescriptor] {
        all.filter { $0.surfaces.contains(.bottomDock) && $0.isAvailableInUI }
    }

    static var unlockedBottomDockFeatures: [AppFeatureDescriptor] {
        bottomDockFeatures.filter(\.isUnlocked)
    }
}

final class BottomDockSettingsManager: ObservableObject {
    static let shared = BottomDockSettingsManager()

    static let slotCount = 4

    @Published private(set) var selectedFeatureIDs: [AppFeatureID]

    private let layoutUserDefaultsKey = "bottomDockLayout.v3"
    private let legacyLayoutUserDefaultsKey = "bottomDockLayout.v2"
    private let legacyUserDefaultsKey = "bottomDockSelectedFeature.v1"
    private let defaultFeatureIDs: [AppFeatureID] = [.wardrobe, .depositPlan, .timeHall, .me]
    private let requiredFeatureIDs: [AppFeatureID] = [.me]

    /// 参考 ThemeManager.app_theme_version：改此常量即强制重写底部导航默认布局
    private static let forcedLayoutVersionKey = "bottom_dock_layout_version"
    private static let targetVersion = "3.2"

    private init() {
        if Self.shouldForceDefaultLayout() {
            selectedFeatureIDs = Self.sanitizedLayout(defaultFeatureIDs, defaultFeatureIDs: defaultFeatureIDs, requiredFeatureIDs: requiredFeatureIDs)
            saveLayout()
            UserDefaults.standard.set(Self.targetVersion, forKey: Self.forcedLayoutVersionKey)
            print("🧭 [BottomDock] 版本变化 → 强制默认：衣橱 / 心愿尾款 / 时光馆 / 我")
            return
        }

        if let savedIDs = Self.loadLayout(from: layoutUserDefaultsKey) {
            selectedFeatureIDs = Self.sanitizedLayout(savedIDs, defaultFeatureIDs: defaultFeatureIDs, requiredFeatureIDs: requiredFeatureIDs)
        } else if let legacyIDs = Self.loadLayout(from: legacyLayoutUserDefaultsKey) {
            // ponytail: one-shot migrate old default petChat slot → timeHall
            let migrated = legacyIDs.map { $0 == .petChat ? AppFeatureID.timeHall : $0 }
            selectedFeatureIDs = Self.sanitizedLayout(migrated, defaultFeatureIDs: defaultFeatureIDs, requiredFeatureIDs: requiredFeatureIDs)
        } else if let legacyID = Self.loadLegacyFeature(from: legacyUserDefaultsKey) {
            var migrated = defaultFeatureIDs
            migrated[Self.slotCount - 1] = legacyID
            selectedFeatureIDs = Self.sanitizedLayout(migrated, defaultFeatureIDs: defaultFeatureIDs, requiredFeatureIDs: requiredFeatureIDs)
        } else {
            selectedFeatureIDs = Self.sanitizedLayout(defaultFeatureIDs, defaultFeatureIDs: defaultFeatureIDs, requiredFeatureIDs: requiredFeatureIDs)
        }
        saveLayout()
    }

    private static func shouldForceDefaultLayout() -> Bool {
        UserDefaults.standard.string(forKey: forcedLayoutVersionKey) != targetVersion
    }

    var selectedFeatureID: AppFeatureID {
        featureID(at: Self.slotCount - 1)
    }

    var selectedFeature: AppFeatureDescriptor {
        feature(at: Self.slotCount - 1)
    }

    var slots: [Int] {
        Array(0..<Self.slotCount)
    }

    var availableFeatures: [AppFeatureDescriptor] {
        let unlocked = AppFeatureRegistry.unlockedBottomDockFeatures
        return unlocked.isEmpty ? defaultFeatureIDs.map(AppFeatureRegistry.descriptor(for:)) : unlocked
    }

    var houseSlotIndex: Int? {
        selectedFeatureIDs.firstIndex(of: .house)
    }

    func featureID(at slotIndex: Int) -> AppFeatureID {
        guard selectedFeatureIDs.indices.contains(slotIndex) else {
            return defaultFeatureIDs[min(slotIndex, defaultFeatureIDs.count - 1)]
        }
        return selectedFeatureIDs[slotIndex]
    }

    func feature(at slotIndex: Int) -> AppFeatureDescriptor {
        let featureID = featureID(at: slotIndex)
        let descriptor = AppFeatureRegistry.descriptor(for: featureID)
        guard descriptor.surfaces.contains(.bottomDock), descriptor.isAvailableInUI, descriptor.isUnlocked else {
            return AppFeatureRegistry.descriptor(for: defaultFeatureIDs[min(slotIndex, defaultFeatureIDs.count - 1)])
        }
        return descriptor
    }

    func slotTitle(for slotIndex: Int) -> String {
        "位置 %d".appLocalized(slotIndex + 1)
    }

    func setSelectedFeature(_ featureID: AppFeatureID) {
        setFeature(featureID, at: Self.slotCount - 1)
    }

    func setFeature(_ featureID: AppFeatureID, at slotIndex: Int) {
        let descriptor = AppFeatureRegistry.descriptor(for: featureID)
        guard descriptor.surfaces.contains(.bottomDock), descriptor.isAvailableInUI, descriptor.isUnlocked else { return }
        guard selectedFeatureIDs.indices.contains(slotIndex) else { return }

        var nextIDs = selectedFeatureIDs
        if let existingIndex = nextIDs.firstIndex(of: featureID), existingIndex != slotIndex {
            nextIDs[existingIndex] = nextIDs[slotIndex]
        }
        nextIDs[slotIndex] = featureID
        selectedFeatureIDs = Self.sanitizedLayout(nextIDs, defaultFeatureIDs: defaultFeatureIDs, requiredFeatureIDs: requiredFeatureIDs)
        saveLayout()
    }

    func resetToDefault() {
        selectedFeatureIDs = Self.sanitizedLayout(defaultFeatureIDs, defaultFeatureIDs: defaultFeatureIDs, requiredFeatureIDs: requiredFeatureIDs)
        saveLayout()
    }

    private func saveLayout() {
        UserDefaults.standard.set(selectedFeatureIDs.map(\.rawValue), forKey: layoutUserDefaultsKey)
    }

    private static func loadLayout(from key: String) -> [AppFeatureID]? {
        guard let rawValues = UserDefaults.standard.stringArray(forKey: key), !rawValues.isEmpty else {
            return nil
        }
        return rawValues.compactMap(AppFeatureID.init(rawValue:))
    }

    private static func loadLegacyFeature(from key: String) -> AppFeatureID? {
        guard let rawValue = UserDefaults.standard.string(forKey: key),
              let featureID = AppFeatureID(rawValue: rawValue),
              isBottomDockFeature(featureID) else {
            return nil
        }
        return featureID
    }

    private static func sanitizedLayout(
        _ featureIDs: [AppFeatureID],
        defaultFeatureIDs: [AppFeatureID],
        requiredFeatureIDs: [AppFeatureID]
    ) -> [AppFeatureID] {
        var result: [AppFeatureID] = []

        for featureID in featureIDs {
            guard result.count < slotCount,
                  isBottomDockFeature(featureID),
                  !result.contains(featureID) else {
                continue
            }
            result.append(featureID)
        }

        for featureID in defaultFeatureIDs + AppFeatureRegistry.unlockedBottomDockFeatures.map(\.id) {
            guard result.count < slotCount,
                  isBottomDockFeature(featureID),
                  !result.contains(featureID) else {
                continue
            }
            result.append(featureID)
        }

        while result.count < slotCount {
            result.append(.timeHall)
        }

        for requiredFeatureID in requiredFeatureIDs where !result.contains(requiredFeatureID) {
            if let replacementIndex = result.indices.reversed().first(where: { !requiredFeatureIDs.contains(result[$0]) }) {
                result[replacementIndex] = requiredFeatureID
            }
        }

        return Array(result.prefix(slotCount))
    }

    private static func isBottomDockFeature(_ featureID: AppFeatureID) -> Bool {
        let descriptor = AppFeatureRegistry.descriptor(for: featureID)
        return descriptor.surfaces.contains(.bottomDock)
            && descriptor.isAvailableInUI
            && descriptor.isUnlocked
    }
}
