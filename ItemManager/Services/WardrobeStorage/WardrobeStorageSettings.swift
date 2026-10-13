import Foundation
import Observation

nonisolated enum WardrobeStorageIconKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case wardrobe, shoes, bags, accessories, beauty, lifestyle, hat, star
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wardrobe: return "衣柜"
        case .shoes: return "鞋履"
        case .bags: return "包包"
        case .accessories: return "蝴蝶结"
        case .beauty: return "香水"
        case .lifestyle: return "小屋"
        case .hat: return "礼帽"
        case .star: return "星星"
        }
    }
    var style: WardrobeStorageCategory {
        switch self {
        case .shoes: return .shoes
        case .bags: return .bags
        case .beauty: return .beauty
        case .lifestyle: return .lifestyle
        default: return .accessories
        }
    }
}

nonisolated struct WardrobeStorageDestination: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let category: WardrobeStorageCategory
    let icon: WardrobeStorageIconKind
    let iconImageFile: String?
    let customID: UUID?

    init(_ category: WardrobeStorageCategory) {
        id = category.rawValue; title = category.title; self.category = category
        icon = WardrobeStorageIconKind(rawValue: category.rawValue) ?? .accessories
        customID = nil
        iconImageFile = nil
    }

    init(custom: WardrobeStorageCustomCabinet) {
        id = "custom/" + custom.id.uuidString; title = custom.name
        category = custom.icon.style; icon = custom.icon; customID = custom.id
        iconImageFile = custom.iconImageFile
    }

    static var defaults: [Self] { WardrobeStorageCategory.defaultCategories.map(Self.init) }
}

nonisolated struct WardrobeStorageCustomCabinet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var icon: WardrobeStorageIconKind
    var clothingIDs: Set<UUID> = []
    var iconImageFile: String? = nil
}

nonisolated enum WardrobeStorageIconUpdate: Sendable {
    case keep, useBuiltIn, replace(Data)
}

/// Local display organization only. Clothing, photos and CloudKit models are unchanged.
@Observable @MainActor
final class WardrobeStorageSettings {
    static let shared: WardrobeStorageSettings = {
        #if DEBUG
        // UI acceptance can use isolated preferences without populating user cabinets.
        if let suite = ProcessInfo.processInfo.environment["PINK_HOUSE_STORAGE_TEST_SUITE"],
           suite.hasPrefix("pink-house-storage-ui-tests-"), let defaults = UserDefaults(suiteName: suite) {
            return WardrobeStorageSettings(defaults: defaults)
        }
        #endif
        return WardrobeStorageSettings()
    }()
    private(set) var cabinets: [WardrobeStorageCustomCabinet]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let iconStore: WardrobeStorageIconStore
    @ObservationIgnored private let key = "wardrobe.storage.custom-cabinets.v1"

    init(defaults: UserDefaults = .standard, iconStore: WardrobeStorageIconStore? = nil) {
        self.defaults = defaults
        self.iconStore = iconStore ?? .shared
        cabinets = defaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode([WardrobeStorageCustomCabinet].self, from: $0)
        } ?? []
    }

    var destinations: [WardrobeStorageDestination] {
        WardrobeStorageDestination.defaults + cabinets.map(WardrobeStorageDestination.init(custom:))
    }

    func saveCabinet(id: UUID? = nil, name: String, icon: WardrobeStorageIconKind,
                     iconUpdate: WardrobeStorageIconUpdate = .keep) throws -> WardrobeStorageDestination {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 12 else { throw ValidationError.invalidName }
        let names = WardrobeStorageCategory.defaultCategories.map(\.title) + cabinets.filter { $0.id != id }.map(\.name)
        guard !names.contains(where: { $0.compare(name, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }) else {
            throw ValidationError.duplicateName
        }
        var updated = cabinets
        let index: Int
        if let id, let existing = updated.firstIndex(where: { $0.id == id }) {
            index = existing
            updated[index].name = name; updated[index].icon = icon
        } else {
            index = updated.count
            updated.append(WardrobeStorageCustomCabinet(name: name, icon: icon))
        }
        let previousImage = updated[index].iconImageFile
        var createdImage: String?
        do {
            switch iconUpdate {
            case .keep: break
            case .useBuiltIn: updated[index].iconImageFile = nil
            case .replace(let data):
                let file = try iconStore.save(data)
                createdImage = file
                updated[index].iconImageFile = file
            }
            try persist(updated)
        } catch {
            if let createdImage { iconStore.remove(named: createdImage) }
            throw error
        }
        if let previousImage, previousImage != updated[index].iconImageFile,
           !updated.contains(where: { $0.iconImageFile == previousImage }) {
            iconStore.remove(named: previousImage)
        }
        return WardrobeStorageDestination(custom: updated[index])
    }

    func setContents(_ clothingIDs: Set<UUID>, for id: UUID) throws {
        guard cabinets.contains(where: { $0.id == id }) else { return }
        var updated = cabinets
        for index in updated.indices {
            if updated[index].id == id { updated[index].clothingIDs = clothingIDs }
            else { updated[index].clothingIDs.subtract(clothingIDs) }
        }
        try persist(updated)
    }

    func include(_ clothingID: UUID, in id: UUID) throws {
        guard let cabinet = cabinets.first(where: { $0.id == id }) else { return }
        try setContents(cabinet.clothingIDs.union([clothingID]), for: id)
    }

    private func persist(_ updated: [WardrobeStorageCustomCabinet]) throws {
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: key)
        cabinets = updated
    }

    nonisolated enum ValidationError: LocalizedError {
        case invalidName, duplicateName
        var errorDescription: String? {
            switch self {
            case .invalidName: return "柜子名称请输入 1–12 个字。"
            case .duplicateName: return "已经有同名的柜子了，换个名字吧。"
            }
        }
    }
}
