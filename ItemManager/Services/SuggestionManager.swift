
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
    case condition
}

class SuggestionManager {
    static let shared = SuggestionManager()
    
    private var tries: [SuggestionField: Trie] = [:]
    private let cache = LRUCache(capacity: 100)
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
        let types = ["JSK", "OP", "SK", "Blouse", "衬衫", "内搭", "短袖", "长袖", "上衣", "开衫", "半裙", "背带裙", "连衣裙", "外套", "大衣", "斗篷", "南瓜裤", "撑"]
        
        // 常见颜色
        let colors = ["粉色", "生成色", "白色", "黑色", "酒红", "绀色", "萨克斯蓝", "若草色", "薄荷绿", "薰衣草紫", "巧克力色", "咖啡色", "灰色", "米色", "多色"]
        
        // 常见尺码
        let sizes = ["XS", "S", "M", "L", "XL", "XXL", "均码", "定制"]
        
        // 常见小物
        let accessories = ["KC", "发带", "BNT", "扁帽", "发卡", "边夹", "手袖", "腕饰", "项链", "戒指", "胸针", "包", "袜子", "过膝袜", "连裤袜", "手套", "遮阳伞", "扇子"]
        
        // 常见状态
        let conditions = ["全新", "仅试穿", "99新", "95新", "9成新", "有瑕疵", "战斗成色", "未到货", "待付尾款"]
        
        queue.async { [weak self] in
            guard let self = self else { return }
            for brand in brands { self.tries[.brand]?.insert(brand) }
            for type in types { self.tries[.type]?.insert(type) }
            for color in colors { self.tries[.color]?.insert(color) }
            for size in sizes { self.tries[.size]?.insert(size) }
            for accessory in accessories { self.tries[.accessory]?.insert(accessory) }
            for condition in conditions { self.tries[.condition]?.insert(condition) }
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
            var conditions = Set<String>()
            var brandNames = Set<String>()
            
            for brand in brands {
                if !brand.name.isEmpty {
                    brandNames.insert(brand.name)
                }
            }
            
            for clothing in clothings {
                if !clothing.name.isEmpty { 
                    names.insert(clothing.name)
                    
                    // 特殊逻辑：如果类型包含"小物"，则该物品名称也加入小物索引
                    if clothing.types.contains("小物") {
                        print("SuggestionManager: Found accessory item '\(clothing.name)' (type: \(clothing.types))")
                        accessories.insert(clothing.name)
                    }
                }
                
                // 处理逗号分隔的字段
                parseTags(clothing.types, into: &types)
                parseTags(clothing.colors, into: &colors)
                parseTags(clothing.sizes, into: &sizes)
                parseTags(clothing.accessories, into: &accessories)
                
                if !clothing.condition.isEmpty {
                    conditions.insert(clothing.condition)
                }
            }
            
            print("SuggestionManager: Total accessories loaded: \(accessories.count)")
            
            // 4. 后台构建 Trie
            queue.async { [weak self] in
                guard let self = self else { return }
                
                self.updateTrie(for: .name, with: names)
                self.updateTrie(for: .brand, with: brandNames)
                self.updateTrie(for: .type, with: types)
                self.updateTrie(for: .color, with: colors)
                self.updateTrie(for: .size, with: sizes)
                self.updateTrie(for: .accessory, with: accessories)
                self.updateTrie(for: .condition, with: conditions)
                
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
            if let cached = cache.getValue(for: cacheKey) as? [String] {
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
    
    // 专门用于搜索类型含"小物"的商品
    @MainActor
    func searchAccessories(query: String, modelContext: ModelContext) -> [String] {
        // 1. 先从 Trie 中搜索 (这里包含了 tag 和 类型含小物的商品名)
        let trieResults = getSuggestions(for: .accessory, query: query)
        print("SuggestionManager: Trie results for '\(query)': \(trieResults)")
        
        // 2. 再从数据库搜索 (作为兜底)
        let descriptor = FetchDescriptor<Clothing>(
            predicate: #Predicate { $0.types.contains("小物") }
        )
        
        var dbResults: [String] = []
        do {
            let candidates = try modelContext.fetch(descriptor)
            dbResults = candidates.filter { clothing in
                return clothing.name.localizedStandardContains(query)
            }.map { $0.name }
            print("SuggestionManager: DB results for '\(query)': \(dbResults)")
        } catch {
            print("SuggestionManager: searchAccessories failed: \(error)")
        }
        
        // 3. 合并去重
        var finalResults = trieResults
        for item in dbResults {
            if !finalResults.contains(item) {
                finalResults.append(item)
            }
        }
        
        return Array(finalResults.prefix(20))
    }
    
    // 更新单个条目 (当用户保存新数据时调用)
    func addData(field: SuggestionField, value: String) {
        // 如果是类型字段，检查是否包含"小物"，如果是，需要联动更新
        // 但这里 addData 接口目前只接收单个字段。
        // 为了支持联动，我们需要更丰富的上下文，或者调用方显式处理。
        // 考虑到接口兼容性，我们暂时只处理基础更新。
        // 如果需要联动更新（比如保存时），建议扩展这个方法或者调用方多调一次。
        // 
        // 修正：实际上 ClothingEditView 保存时会分别调用 addData。
        // 但是 ClothingEditView 调用 addData(field: .type, value: types) 时，我们无法得知此时的 name 是什么。
        // 所以单纯修改 addData 比较困难。
        // 更好的方式是：ClothingEditView 在保存时，如果检测到 types 包含 "小物"，
        // 则显式调用 SuggestionManager.shared.addData(field: .accessory, value: name)
        
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
        }
    }
    
    // 提供一个特殊方法用于处理"类型含小物"的情况
    func addAccessoryNameIfTypeContainsAccessory(name: String, types: String) {
        if types.contains("小物") {
            queue.async { [weak self] in
                self?.tries[.accessory]?.insert(name)
            }
        }
    }
    
    // MARK: - 获取所有预设值（用于批量编辑）
    
    func getAllColors() -> [String] {
        return queue.sync {
            return tries[.color]?.getAllWords() ?? []
        }
    }
    
    func getAllSizes() -> [String] {
        return queue.sync {
            return tries[.size]?.getAllWords() ?? []
        }
    }
    
    func getAllAccessories() -> [String] {
        return queue.sync {
            return tries[.accessory]?.getAllWords() ?? []
        }
    }
    
    func getAllLengths() -> [String] {
        // 衣长从数据库中收集，没有固定预设
        return ["80cm", "90cm", "100cm", "110cm", "120cm", "短款", "中长款", "长款", "超长款"]
    }
}
