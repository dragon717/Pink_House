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
    let customID: UUID?

    init(_ category: WardrobeStorageCategory) {
        id = category.rawValue; title = category.title; self.category = category
        icon = WardrobeStorageIconKind(rawValue: category.rawValue) ?? .accessories
        customID = nil
    }

    init(custom: WardrobeStorageCustomCabinet) {
        id = "custom/" + custom.id.uuidString; title = custom.name
        category = custom.icon.style; icon = custom.icon; customID = custom.id
    }

    static var defaults: [Self] { WardrobeStorageCategory.defaultCategories.map(Self.init) }
}

nonisolated struct WardrobeStorageCustomCabinet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var icon: WardrobeStorageIconKind
    var clothingIDs: Set<UUID> = []
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
    @ObservationIgnored private let key = "wardrobe.storage.custom-cabinets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cabinets = defaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode([WardrobeStorageCustomCabinet].self, from: $0)
        } ?? []
    }

    var destinations: [WardrobeStorageDestination] {
        WardrobeStorageDestination.defaults + cabinets.map(WardrobeStorageDestination.init(custom:))
    }

    func saveCabinet(id: UUID? = nil, name: String, icon: WardrobeStorageIconKind) throws -> WardrobeStorageDestination {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 12 else { throw ValidationError.invalidName }
        let names = WardrobeStorageCategory.defaultCategories.map(\.title) + cabinets.filter { $0.id != id }.map(\.name)
        guard !names.contains(where: { $0.compare(name, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }) else {
            throw ValidationError.duplicateName
        }
        var updated = cabinets
        let cabinet: WardrobeStorageCustomCabinet
        if let id, let index = updated.firstIndex(where: { $0.id == id }) {
            updated[index].name = name; updated[index].icon = icon; cabinet = updated[index]
        } else {
            cabinet = WardrobeStorageCustomCabinet(name: name, icon: icon)
            updated.append(cabinet)
        }
        try persist(updated)
        return WardrobeStorageDestination(custom: cabinet)
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
