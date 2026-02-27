import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - 常用菜单功能项
enum FavoriteMenuItem: String, CaseIterable, Identifiable {
    case wardrobe = "衣橱"
    case finalPayment = "尾款天使"
    case pet = "萌宠"
    case ootd = "魔法贴纸"
    case fashionJournal = "穿搭手帐"
    case smallWorld = "House"
    case wealth = "来财"
    case dressStock = "裙子股市"
    case perler = "拼豆工坊"
    case calendar = "梦裙日历"
    case bigWorld = "世界书"
    case recycleBin = "回收站"
    
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
        case .wealth: return .wealth
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
}

// MARK: - 常用菜单设置（SwiftData）
@Model
class FavoriteMenuSettings {
    // 存储用户选择的常用功能ID数组
    var selectedItemIDs: [String]
    var lastUpdated: Date
    
    init(selectedItemIDs: [String] = ["萌宠", "拼豆工坊", "世界书", "House","来财"]) {
        self.selectedItemIDs = selectedItemIDs
        self.lastUpdated = Date()
    }
    
    // 获取可用的所有功能项
    static var allAvailableItems: [FavoriteMenuItem] {
        FavoriteMenuItem.allCases
    }
    
    // 默认选中的功能
    static var defaultItems: [FavoriteMenuItem] {
        [.pet, .ootd, .smallWorld]
    }
}

// MARK: - 设置管理器（用于非SwiftData环境）
final class FavoriteMenuSettingsManager: ObservableObject {
    static let shared = FavoriteMenuSettingsManager()
    
    @Published var selectedItems: [FavoriteMenuItem] = [.pet, .ootd, .smallWorld]
    
    private let userDefaultsKey = "favoriteMenuSelectedItems"
    
    private init() {
        loadSettings()
    }
    
    func loadSettings() {
        if let savedIDs = UserDefaults.standard.stringArray(forKey: userDefaultsKey) {
            selectedItems = savedIDs.compactMap { FavoriteMenuItem(rawValue: $0) }
            // 确保至少有一个选中项
            if selectedItems.isEmpty {
                selectedItems = FavoriteMenuSettings.defaultItems
            }
        } else {
            selectedItems = FavoriteMenuSettings.defaultItems
        }
    }
    
    func saveSettings() {
        let ids = selectedItems.map { $0.rawValue }
        UserDefaults.standard.set(ids, forKey: userDefaultsKey)
    }
    
    func addItem(_ item: FavoriteMenuItem) {
        if !selectedItems.contains(item) && selectedItems.count < 5 {
            selectedItems.append(item)
            saveSettings()
        }
    }
    
    func removeItem(_ item: FavoriteMenuItem) {
        selectedItems.removeAll { $0 == item }
        // 确保至少保留一个
        if selectedItems.isEmpty {
            selectedItems = [.smallWorld]
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
