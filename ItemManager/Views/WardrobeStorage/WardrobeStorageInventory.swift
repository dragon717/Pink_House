import Foundation

/// A read-only projection of the existing wardrobe. No new persisted category or inventory.
nonisolated enum WardrobeStorageCategory: String, CaseIterable, Identifiable, Hashable {
    case wardrobe, shoes, bags, accessories, beauty, lifestyle

    static let defaultCategories: [Self] = [.wardrobe, .shoes, .bags, .accessories]

    var id: String { rawValue }
    var title: String {
        switch self {
        case .wardrobe: return "衣柜"
        case .shoes: return "鞋柜"
        case .bags: return "包包柜"
        case .accessories: return "配饰柜"
        case .beauty: return "美妆柜"
        case .lifestyle: return "生活柜"
        }
    }
    var symbol: String {
        switch self {
        case .wardrobe: return "tshirt"
        case .shoes: return "shoe"
        case .bags: return "handbag"
        case .accessories: return "gift"
        case .beauty: return "sparkles"
        case .lifestyle: return "house"
        }
    }
    var unit: String { self == .shoes ? "双" : self == .bags ? "个" : "件" }
    var shelfHeightRatio: Double {
        switch self {
        case .shoes: return 253.0 / 780
        case .bags, .lifestyle: return 350.0 / 780
        case .beauty: return 330.0 / 780
        case .accessories, .wardrobe: return 300.0 / 780
        }
    }
    var initialTypes: Set<String> {
        switch self {
        case .wardrobe: return []
        case .shoes: return ["鞋"]
        case .bags: return ["包"]
        case .accessories: return ["小物"]
        case .beauty: return ["美妆"]
        case .lifestyle: return ["生活"]
        }
    }

    static func classify(name: String, types: String = "", accessories: String = "", fallback: Self = .wardrobe) -> Self {
        let tokens = typeTokens(types)
        // A set belongs to its main garment, even when it also carries 小物 / 包 / KC tags.
        if hasMainGarmentType(types) { return .wardrobe }
        // Legacy imports use the broad 小物 type for shoes and bags as well.
        if let explicit = match(types), explicit != .accessories { return visibleCategory(explicit) }
        // The editor's 小物标签 field stores 包 in Clothing.accessories, not Clothing.types.
        let accessoryTokens = accessories.lowercased().components(separatedBy: CharacterSet(charactersIn: ",，、;/；| \n\t"))
        if !Set(["包", "包包", "手提包", "手袋", "肩包", "背包", "挎包", "痛包", "bag", "handbag"]).isDisjoint(with: accessoryTokens) {
            return .bags
        }
        if let tagged = match(accessories), tagged != .accessories { return visibleCategory(tagged) }
        if !Set(["kc", "bnt"]).isDisjoint(with: tokens + accessoryTokens) { return .accessories }
        return visibleCategory(match(name) ?? match(types) ?? match(accessories) ?? fallback)
    }

    static func hasMainGarmentType(_ types: String) -> Bool {
        let garmentTypes: Set<String> = ["jsk", "op", "sk", "blouse", "裙装", "连衣裙", "上衣", "外套", "衬衫", "裙子",
                                         "内搭", "短袖", "长袖", "开衫", "半裙", "背带裙", "大衣", "斗篷", "南瓜裤", "撑"]
        return !garmentTypes.isDisjoint(with: typeTokens(types))
    }

    private static func typeTokens(_ types: String) -> [String] {
        types.folding(options: .widthInsensitive, locale: nil).lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ",，、;/；|+＋ \n\t"))
    }

    private static func visibleCategory(_ category: Self) -> Self {
        defaultCategories.contains(category) ? category : .wardrobe
    }

    static func destination(clothingID: UUID, name: String, types: String, accessories: String,
                            customCabinets: [WardrobeStorageCustomCabinet] = []) -> WardrobeStorageDestination {
        if !hasMainGarmentType(types), let custom = customCabinets.first(where: { $0.clothingIDs.contains(clothingID) }) {
            return WardrobeStorageDestination(custom: custom)
        }
        return WardrobeStorageDestination(classify(name: name, types: types, accessories: accessories))
    }

    private static func match(_ text: String) -> Self? {
        let value = text.lowercased()
        let groups: [(Self, [String])] = [
            (.shoes, ["鞋", "靴", "玛丽珍", "乐福", "shoe", "boot", "sneaker", "loafer", "mary jane", "maryjane"]),
            (.bags, ["包包", "手提包", "手袋", "挎包", "背包", "肩包", "钱包", "handbag", "bag", "backpack", "tote", "purse", "包"]),
            (.beauty, ["美妆", "口红", "香水", "粉底", "眼影", "腮红", "护肤", "lipstick", "perfume", "makeup"]),
            (.lifestyle, ["生活", "玩偶", "娃娃", "毛绒", "公仔", "杯", "摆件", "文具", "doll", "plush"]),
            (.accessories, ["小物", "配饰", "头饰", "发饰", "发夹", "发带", "发卡", "边夹", "蝴蝶结", "项链", "耳环", "耳饰", "戒指", "胸针", "帽", "袜", "手袖", "腕饰", "手套", "遮阳伞", "扇子", "accessory", "sock", "bonnet"])
        ]
        return groups.first { _, hints in hints.contains(where: value.contains) }?.0
    }
}

nonisolated enum WardrobeShoeFilter: String, CaseIterable, Identifiable {
    case all = "全部", sneakers = "运动鞋", whiteSneakers = "小白鞋", boots = "靴子", maryJanes = "玛丽珍", heels = "高跟鞋"
    var id: String { rawValue }

    func matches(_ text: String) -> Bool {
        let text = text.lowercased()
        func contains(_ words: [String]) -> Bool { words.contains(where: text.contains) }
        switch self {
        case .all: return true
        case .sneakers: return contains(["运动", "球鞋", "帆布", "小白鞋", "sneaker", "trainer"])
        case .whiteSneakers:
            return text.contains("小白鞋") || (Self.sneakers.matches(text) && contains(["白", "white", "ivory"]))
        case .boots: return contains(["靴", "boot"])
        case .maryJanes: return contains(["玛丽珍", "mary jane", "maryjane"])
        case .heels: return contains(["高跟", "中跟", "粗跟", "heel"])
        }
    }
}

struct WardrobeStorageEntry: Identifiable {
    let id: String
    let title: String
    let category: WardrobeStorageCategory
    let searchTerms: String
    let originalImagePath: String?
    let cutoutImagePath: String?
    let price: Decimal?
    let quantity: Int
    let clothing: Clothing?
    var originalImagePaths: [String] = []
    var imageRevision: TimeInterval = 0
    var cabinetID: String? = nil
    var storageID: String { cabinetID ?? category.rawValue }

    var imageSource: WardrobeStorageImageSource {
        WardrobeStorageImageSource(preferredCutout: cutoutImagePath,
            originals: originalImagePaths.isEmpty ? [originalImagePath].compactMap { $0 } : originalImagePaths,
            revision: imageRevision)
    }

    var statusLabel: String? {
        guard let clothing else { return nil }
        switch clothing.reservationKind {
        case .owned: return nil
        case .depositPlan: return "待付尾款"
        case .fullPaymentReservation: return "待到货"
        case .sold: return "已售出"
        }
    }


}

@MainActor
enum WardrobeStorageInventory {
    static func entries(clothings: [Clothing], cutouts: [CutoutItem] = [], customCabinets: [WardrobeStorageCustomCabinet] = []) -> [WardrobeStorageEntry] {
        let byID = Dictionary(cutouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byClothing = Dictionary(grouping: cutouts.filter { $0.linkedClothingID != nil }) { $0.linkedClothingID! }
        var result: [WardrobeStorageEntry] = []

        for clothing in clothings where !clothing.isDeleted && clothing.deletedAt == nil {
            let category = WardrobeStorageCategory.classify(name: clothing.name, types: clothing.types, accessories: clothing.accessories)
            let destination = WardrobeStorageCategory.destination(clothingID: clothing.id, name: clothing.name,
                types: clothing.types, accessories: clothing.accessories, customCabinets: customCabinets)
            let linked = (byClothing[clothing.id] ?? []).sorted { $0.timestamp > $1.timestamp }
            let cutout = clothing.replacedCutoutID.flatMap { byID[$0] }
                ?? linked.first { $0.clothingName == clothing.name }
                ?? linked.first { $0.clothingName == nil }
                ?? linked.first { WardrobeStorageCategory.classify(name: $0.clothingName ?? "", types: $0.category, fallback: category) == category }
            result.append(WardrobeStorageEntry(
                id: "clothing/\(clothing.id)", title: clothing.name, category: destination.category,
                searchTerms: [clothing.name, clothing.types, clothing.accessories, clothing.colors, clothing.brand?.name ?? ""].joined(separator: " "),
                originalImagePath: clothing.imagePaths.first, cutoutImagePath: cutout?.imagePath,
                price: clothing.price,
                quantity: clothing.reservationKind == .owned ? max(clothing.stock, 1) : 0, clothing: clothing,
                originalImagePaths: clothing.imagePaths,
                imageRevision: max(clothing.lastModified, cutout?.timestamp ?? .distantPast).timeIntervalSince1970,
                cabinetID: destination.id
            ))
            // AccessoryItem is a set's price/detail breakdown, not another inventory record.
            // Only independently saved Clothing records enter separate cabinets.
        }
        return result
    }
}
