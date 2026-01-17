
import Foundation
import SwiftData
import SwiftUI

enum SuggestionField: String, CaseIterable {
    case name
    case brand
    case type
    case color
    case size
    case accessory
}

class SuggestionManager {
    static let shared = SuggestionManager()
    
    private var tries: [SuggestionField: Trie] = [:]
    private let cache = LRUCache<String, [String]>(capacity: 100)
    private let queue = DispatchQueue(label: "com.pinkhouse.suggestion", qos: .userInitiated)
    
    private init() {
        for field in SuggestionField.allCases {
            tries[field] = Trie()
        }
        // 预置一些基础数据，防止冷启动无数据
        seedDefaultData()
    }
    
    private func seedDefaultData() {
        // 常见 Lolita 品牌
        let brands = ["Angelic Pretty", "Baby, the Stars Shine Bright", "Innocent World", "Mary Magdalene", "Victorian Maiden", "Alice and the Pirates", "Metamorphose temps de fille", "Moi-même-Moitié", "Juliette et Justine", "Triple Fortune", "表面咒语", "Elpress L", "Honey Honey", "仲夏物语", "古典玩偶", "Lullaby", "NyaNya", "Precious Clove", "Soufflesong", "Tiny Garden"]
        
        // 常见类型
        let types = ["JSK", "OP", "SK", "Blouse", "衬衫", "半裙", "背带裙", "连衣裙", "外套", "大衣", "斗篷", "南瓜裤", "撑"]
        
        // 常见颜色
        let colors = ["粉色", "生成色", "白色", "黑色", "酒红", "绀色", "萨克斯蓝", "若草色", "薄荷绿", "薰衣草紫", "巧克力色", "咖啡色", "灰色", "米色", "多色"]
        
        // 常见尺码
        let sizes = ["XS", "S", "M", "L", "XL", "XXL", "均码", "定制"]
        
        // 常见小物
        let accessories = ["KC", "发带", "BNT", "扁帽", "发卡", "边夹", "手袖", "腕饰", "项链", "戒指", "胸针", "包", "袜子", "过膝袜", "连裤袜", "手套", "遮阳伞", "扇子"]
        
        queue.async { [weak self] in
            guard let self = self else { return }
            for brand in brands { self.tries[.brand]?.insert(brand) }
            for type in types { self.tries[.type]?.insert(type) }
            for color in colors { self.tries[.color]?.insert(color) }
            for size in sizes { self.tries[.size]?.insert(size) }
            for accessory in accessories { self.tries[.accessory]?.insert(accessory) }
        }
    }
    
    @MainActor
    func loadDataAndBuildIndex(modelContext: ModelContext) {
        do {
            // 1. 获取所有 Clothing 数据
            let clothingDescriptor = FetchDescriptor<Clothing>()
            let clothings = try modelContext.fetch(clothingDescriptor)
            
            // 2. 获取所有 Brand 数据
            let brandDescriptor = FetchDescriptor<Brand>()
            let brands = try modelContext.fetch(brandDescriptor)
            
            // 3. 提取数据 (运行在 MainActor)
            var names = Set<String>()
            var types = Set<String>()
            var colors = Set<String>()
            var sizes = Set<String>()
            var accessories = Set<String>()
            var brandNames = Set<String>()
            
            for brand in brands {
                if !brand.name.isEmpty {
                    brandNames.insert(brand.name)
                }
            }
            
            for clothing in clothings {
                if !clothing.name.isEmpty { names.insert(clothing.name) }
                
                // 处理逗号分隔的字段
                parseTags(clothing.types, into: &types)
                parseTags(clothing.colors, into: &colors)
                parseTags(clothing.sizes, into: &sizes)
                parseTags(clothing.accessories, into: &accessories)
            }
            
            // 4. 后台构建 Trie
            queue.async { [weak self] in
                guard let self = self else { return }
                
                self.updateTrie(for: .name, with: names)
                self.updateTrie(for: .brand, with: brandNames)
                self.updateTrie(for: .type, with: types)
                self.updateTrie(for: .color, with: colors)
                self.updateTrie(for: .size, with: sizes)
                self.updateTrie(for: .accessory, with: accessories)
                
                print("Suggestion index build completed")
            }
            
        } catch {
            print("Failed to load data for suggestion index: \(error)")
        }
    }
    
    private func parseTags(_ text: String, into set: inout Set<String>) {
        let tags = text.replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        set.formUnion(tags)
    }
    
    private func updateTrie(for field: SuggestionField, with items: Set<String>) {
        let trie = tries[field] ?? Trie()
        trie.clear() // 重建索引
        for item in items {
            trie.insert(item)
        }
        tries[field] = trie
    }
    
    // 搜索建议
    func getSuggestions(for field: SuggestionField, query: String) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        
        return queue.sync {
            // 检查缓存
            let cacheKey = "\(field.rawValue):\(trimmedQuery)"
            if let cached = cache.getValue(for: cacheKey) {
                return cached
            }
            
            // 搜索
            var results: [String] = []
            if let trie = tries[field] {
                // Trie 只能做前缀搜索
                results = trie.search(prefix: trimmedQuery)
            }
            
            // 存入缓存
            cache.setValue(results, for: cacheKey)
            
            return results
        }
    }
    
    // 更新单个条目 (当用户保存新数据时调用)
    func addData(field: SuggestionField, value: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            // 处理逗号分隔
            if field != .name && field != .brand {
                let tags = value.replacingOccurrences(of: "，", with: ",")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                
                for tag in tags {
                    self.tries[field]?.insert(tag)
                }
            } else {
                self.tries[field]?.insert(value)
            }
            // 清除相关缓存
            // 简单起见，可以不清空或者只清空特定前缀，这里暂不处理缓存失效，依靠 LRU 淘汰
        }
    }
}
