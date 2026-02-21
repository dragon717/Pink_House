//
//  SearchService.swift
//  ItemManager
//
//  全局搜索服务 - 提供可复用的搜索能力
//

import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - 搜索协议
/// 定义可搜索实体的基本接口
@MainActor
protocol Searchable {
    associatedtype ResultItem: Identifiable
    
    /// 搜索方法
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - context: 可选的搜索上下文
    /// - Returns: 搜索结果
    func search(query: String, context: SearchContext?) -> [ResultItem]
    
    /// 获取搜索建议
    func searchSuggestions() -> [String]
}

// MARK: - 搜索上下文
/// 传递搜索上下文信息
struct SearchContext {
    var userInfo: [String: Any] = [:]
    
    static let `default` = SearchContext()
}

// MARK: - 搜索结果类型
/// 定义不同类型的搜索结果
enum SearchResultType: String, CaseIterable {
    case clothing = "裙子"
    case brand = "品牌"
    case tag = "标签"
    case ootd = "穿搭"
    case cutout = "抠图"
    
    var icon: String {
        switch self {
        case .clothing: return "tshirt"
        case .brand: return "bag"
        case .tag: return "tag"
        case .ootd: return "book.pages"
        case .cutout: return "scissors"
        }
    }
}

// MARK: - 搜索结果项
/// 统一的搜索结果包装
struct SearchResultItem: Identifiable {
    let id = UUID()
    let type: SearchResultType
    let title: String
    let subtitle: String?
    let icon: String?
    let imagePath: String?
    let originalItem: Any
    let action: () -> Void
}

// MARK: - 衣橱搜索服务
/// 衣橱模块的搜索实现
@MainActor
class ClothingSearchService: ObservableObject, Searchable {
    typealias ResultItem = Clothing
    
    private let clothings: [Clothing]
    
    init(clothings: [Clothing]) {
        self.clothings = clothings
    }
    
    /// 执行搜索
    func search(query: String, context: SearchContext? = nil) -> [Clothing] {
        guard !query.isEmpty else { return [] }
        
        return clothings.filter { clothing in
            // 检查是否包含价格范围搜索
            let priceRange = parsePriceRange(from: query)
            
            if let (minPrice, maxPrice) = priceRange {
                let clothingPrice = NSDecimalNumber(decimal: clothing.price).doubleValue
                return clothingPrice >= minPrice && clothingPrice <= maxPrice
            } else {
                // 普通文本搜索
                let nameMatch = clothing.name.localizedCaseInsensitiveContains(query)
                let brandMatch = clothing.brand?.name.localizedCaseInsensitiveContains(query) ?? false
                let tagMatch = clothing.tags?.contains { tag in
                    tag.name.localizedCaseInsensitiveContains(query)
                } ?? false
                let typeMatch = clothing.types.localizedCaseInsensitiveContains(query)
                let colorMatch = clothing.colors.localizedCaseInsensitiveContains(query)
                let sizeMatch = clothing.sizes.localizedCaseInsensitiveContains(query)
                let lengthMatch = clothing.length.localizedCaseInsensitiveContains(query)
                let conditionMatch = clothing.condition.localizedCaseInsensitiveContains(query)
                let accessoryMatch = clothing.accessories.localizedCaseInsensitiveContains(query)
                let noteMatch = clothing.note.localizedCaseInsensitiveContains(query)
                
                // 库存数量搜索
                let stockMatch: Bool
                if let searchStock = Int(query.trimmingCharacters(in: .whitespaces)), searchStock > 0 {
                    stockMatch = clothing.stock == searchStock
                } else {
                    stockMatch = false
                }
                
                return nameMatch || brandMatch || tagMatch || typeMatch ||
                       colorMatch || sizeMatch || lengthMatch || conditionMatch ||
                       accessoryMatch || noteMatch || stockMatch
            }
        }
    }
    
    /// 获取搜索建议
    func searchSuggestions() -> [String] {
        return [
            "输入名称搜索裙子",
            "输入品牌名搜索",
            "输入标签名搜索",
            "输入类型如 JSK、OP",
            "输入颜色搜索",
            "输入尺码搜索",
            "输入价格范围如 2000-3000"
        ]
    }
    
    // MARK: - 价格范围解析
    /// 支持格式: "2000 3000", "2000-3000", "2000~3000", "2000到3000"
    private func parsePriceRange(from searchText: String) -> (min: Double, max: Double)? {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let separators = [" ", "-", "~", "到", "—", "–"]
        
        for separator in separators {
            let components = trimmed.components(separatedBy: separator)
            if components.count == 2 {
                let first = components[0].trimmingCharacters(in: .whitespaces)
                let second = components[1].trimmingCharacters(in: .whitespaces)
                
                let cleanFirst = first.replacingOccurrences(of: "¥", with: "")
                                      .replacingOccurrences(of: "￥", with: "")
                                      .replacingOccurrences(of: ",", with: "")
                let cleanSecond = second.replacingOccurrences(of: "¥", with: "")
                                        .replacingOccurrences(of: "￥", with: "")
                                        .replacingOccurrences(of: ",", with: "")
                
                if let minPrice = Double(cleanFirst), let maxPrice = Double(cleanSecond),
                   minPrice >= 0, maxPrice >= 0 {
                    return (min: min(minPrice, maxPrice), max: max(minPrice, maxPrice))
                }
            }
        }
        
        return nil
    }
}

// MARK: - 全局搜索管理器
/// 管理所有搜索服务，提供统一的全局搜索入口
@MainActor
class GlobalSearchManager: ObservableObject {
    static let shared = GlobalSearchManager()
    
    @Published var searchResults: [SearchResultSection] = []
    @Published var isSearching = false
    @Published var recentSearches: [String] = []
    
    private var clothingService: ClothingSearchService?
    
    private init() {}
    
    /// 配置衣橱搜索服务
    func configureClothingService(_ service: ClothingSearchService) {
        self.clothingService = service
    }
    
    /// 执行全局搜索
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - onItemTap: 点击结果的回调，用于导航
    func performSearch(query: String, onItemTap: ((Any) -> Void)? = nil) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        var sections: [SearchResultSection] = []
        
        // 搜索衣橱
        if let clothingService = clothingService {
            let clothings = clothingService.search(query: query)
            if !clothings.isEmpty {
                let items = clothings.map { clothing -> SearchResultItem in
                    SearchResultItem(
                        type: .clothing,
                        title: clothing.name,
                        subtitle: clothing.brand?.name,
                        icon: nil,
                        imagePath: clothing.imagePaths.first,
                        originalItem: clothing,
                        action: {
                            onItemTap?(clothing)
                        }
                    )
                }
                sections.append(SearchResultSection(type: .clothing, items: items))
            }
        }
        
        // TODO: 添加其他模块的搜索
        // - OOTD 搜索
        // - 抠图搜索
        // - 品牌搜索
        // - 标签搜索
        
        searchResults = sections
        isSearching = false
        
        // 保存到最近搜索
        if !recentSearches.contains(query) {
            recentSearches.insert(query, at: 0)
            if recentSearches.count > 10 {
                recentSearches.removeLast()
            }
        }
    }
    
    /// 清除最近搜索
    func clearRecentSearches() {
        recentSearches.removeAll()
    }
}

// MARK: - 搜索结果分区
struct SearchResultSection: Identifiable {
    let id = UUID()
    let type: SearchResultType
    let items: [SearchResultItem]
}
