import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - 常用菜单功能项
enum FavoriteMenuItem: String, CaseIterable, Identifiable {
    case wardrobe = "衣橱"
    case finalPayment = "心愿尾款"
    case pet = "萌宠"
    case ootd = "魔法贴纸"
    case fashionJournal = "穿搭手帐"
    case smallWorld = "House"
    case wealth = "来财"
    case dressStock = "裙装股市"
    case perler = "拼豆工坊"
    case calendar = "梦裙日历"
    case bigWorld = "世界书"
    case recycleBin = "回收站"
    
    // MARK: - 默认常用菜单配置
    // 实验室-菜单设置中"清除常用菜单历史，恢复到默认"使用的配置
    // 当前默认：House、回收站
    static var defaultFavoriteItems: [FavoriteMenuItem] {
        [.recycleBin]
    }
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .wardrobe: return "cabinet.fill"
        case .finalPayment: return "tag.fill"
        case .pet: return "pawprint.fill"
        case .ootd: return "book.pages.fill"
        case .fashionJournal: return "book.closed.fill"
        case .smallWorld: return "house.fill"
        case .wealth: return "yensign.circle.fill"
        case .dressStock: return "chart.line.uptrend.xyaxis"
        case .perler: return "circle.grid.2x2.fill"
        case .calendar: return "calendar"
        case .bigWorld: return "globe.asia.australia"
        case .recycleBin: return "trash.fill"
        }
    }
    
    var color: String {
        switch self {
        case .wardrobe: return "#FF69B4"
        case .finalPayment: return "#FF1493"
        case .pet: return "#FF7F50"
        case .ootd: return "#FF69B4"
        case .fashionJournal: return "#FF85C1"
        case .smallWorld: return "#87CEEB"
        case .wealth: return "#FFD700"
        case .dressStock: return "#FF6B9D"
        case .perler: return "#FF8C94"
        case .calendar: return "#DDA0DD"
        case .bigWorld: return "#87CEEB"
        case .recycleBin: return "#808080"
        }
    }
    
    // 映射到 SmallWorldDestination
    var destination: SmallWorldDestination? {
        switch self {
        case .wardrobe: return .wardrobe
        case .finalPayment: return .depositPlan
        case .pet: return .pet
        case .ootd: return .ootdDefaultBook
        case .fashionJournal: return .ootd
        case .smallWorld: return .menu
        case .wealth: return .wealth(nil)
        case .dressStock: return .dressStock
        case .perler: return .perler
        case .calendar: return .calendar
        case .bigWorld: return .bigWorld
        case .recycleBin: return .recycleBin
        }
    }
    
    // 是否是House内的功能
    var isSmallWorldFeature: Bool {
        destination != nil
    }

    /// ponytail: ship-hide unfinished menu entries with AppFeatureID.isShipHidden
    var isAvailableInUI: Bool {
        switch self {
        case .smallWorld:
            return !AppFeatureID.house.isShipHidden
        case .dressStock:
            return !AppFeatureID.dressStock.isShipHidden
                && FeatureUnlockManager.shared.isVisible(.dressStock)
        case .perler:
            return !AppFeatureID.perler.isShipHidden
                && FeatureUnlockManager.shared.isVisible(.perler)
        case .bigWorld:
            return !AppFeatureID.bigWorld.isShipHidden
                && FeatureUnlockManager.shared.isVisible(.bigWorld)
        default:
            return true
        }
    }
    
    // 检查功能是否已解锁
    var isUnlocked: Bool {
        // 获取对应的功能项
        let featureItem: FeatureItem?
        switch self {
        case .wardrobe:
            featureItem = .wardrobe
        case .finalPayment:
            featureItem = .finalPayment
        case .pet:
            featureItem = .pet
        case .ootd:
            featureItem = .ootdDefaultBook
        case .fashionJournal:
            featureItem = .ootd
        case .smallWorld:
            // House 菜单始终可用
            return true
        case .wealth:
            featureItem = .wealth
        case .dressStock:
            featureItem = .dressStock
        case .perler:
            featureItem = .perler
        case .calendar:
            featureItem = .calendar
        case .bigWorld:
            featureItem = .bigWorld
        case .recycleBin:
            featureItem = .recycleBin
        }
        
        // 检查功能是否已解锁
        guard let feature = featureItem else { return true }
        return FeatureUnlockManager.shared.isUnlocked(feature)
    }
}

// MARK: - 常用菜单设置（SwiftData）
@Model
class FavoriteMenuSettings {
    // 存储用户选择的常用功能ID数组
    var selectedItemIDs: [String]
    var lastUpdated: Date
    
    // 使用 FavoriteMenuItem.defaultFavoriteItems 作为默认配置
    init(selectedItemIDs: [String]? = nil) {
        self.selectedItemIDs = selectedItemIDs ?? FavoriteMenuItem.defaultFavoriteItems.map { $0.rawValue }
        self.lastUpdated = Date()
    }
    
    // 获取可用的所有功能项
    static var allAvailableItems: [FavoriteMenuItem] {
        FavoriteMenuItem.allCases.filter(\.isAvailableInUI)
    }
    
    // 默认选中的功能（用于初始化时无保存数据的情况）
    // 注意：这里用于初始化无保存数据时的默认选项
    static var defaultItems: [FavoriteMenuItem] {
        [.recycleBin]
    }
}

// MARK: - 设置管理器（用于非SwiftData环境）
final class FavoriteMenuSettingsManager: ObservableObject {
    static let shared = FavoriteMenuSettingsManager()
    
    // 初始默认值，实际会从 UserDefaults 加载或使用 FavoriteMenuItem.defaultFavoriteItems
    @Published var selectedItems: [FavoriteMenuItem] = FavoriteMenuItem.defaultFavoriteItems
    
    private let userDefaultsKey = "favoriteMenuSelectedItems"
    
    private init() {
        loadSettings()
    }

    func loadSettings() {
        if let savedIDs = UserDefaults.standard.stringArray(forKey: userDefaultsKey) {
            selectedItems = savedIDs.compactMap { FavoriteMenuItem(rawValue: $0) }
                .filter { $0.isUnlocked && $0.isAvailableInUI }
            // 确保至少有一个选中项
            if selectedItems.isEmpty {
                selectedItems = FavoriteMenuSettings.defaultItems.filter { $0.isUnlocked && $0.isAvailableInUI }
            }
        } else {
            selectedItems = FavoriteMenuSettings.defaultItems.filter { $0.isUnlocked && $0.isAvailableInUI }
        }
    }
    
    func saveSettings() {
        let ids = selectedItems.map { $0.rawValue }
        UserDefaults.standard.set(ids, forKey: userDefaultsKey)
    }
    
    func addItem(_ item: FavoriteMenuItem) {
        // 未解锁的功能不能加入常用菜单
        guard item.isUnlocked, item.isAvailableInUI else { return }
        if !selectedItems.contains(item) && selectedItems.count < 5 {
            selectedItems.append(item)
            saveSettings()
        }
    }
    
    func removeItem(_ item: FavoriteMenuItem) {
        selectedItems.removeAll { $0 == item }
        // 确保至少保留一个
        if selectedItems.isEmpty {
            selectedItems = FavoriteMenuSettings.defaultItems.filter { $0.isAvailableInUI }
        }
        saveSettings()
    }
    
    func toggleItem(_ item: FavoriteMenuItem) {
        if selectedItems.contains(item) {
            removeItem(item)
        } else {
            addItem(item)
        }
    }
    
    func reorderItems(from source: IndexSet, to destination: Int) {
        selectedItems.move(fromOffsets: source, toOffset: destination)
        saveSettings()
    }
}
