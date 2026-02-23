//
//  PetConfigManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/8/26.
//

import Foundation
import Combine

class PetConfigManager: ObservableObject {
    static let shared = PetConfigManager()
    
    @Published var categories: [PetCategory] = []
    @Published var items: [PetItemDefinition] = []
    
    private var itemMap: [String: PetItemDefinition] = [:]
    
    private init() {
        loadConfig()
    }
    
    func loadConfig() {
        guard let url = Bundle.main.url(forResource: "PetItems", withExtension: "json") else {
            print("❌ PetConfigManager: PetItems.json not found in Bundle.")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(PetConfigRoot.self, from: data)
            
            self.categories = config.categories
            self.items = config.items.sorted { $0.sortIndex < $1.sortIndex }
            self.itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            
            print("✅ PetConfigManager: Loaded \(items.count) items and \(categories.count) categories.")
        } catch {
            print("❌ PetConfigManager: Failed to decode PetItems.json: \(error)")
        }
    }
    
    func getItem(byId id: String) -> PetItemDefinition? {
        return itemMap[id]
    }
    
    // 获取指定分类下的商品
    func items(for categoryId: String) -> [PetItemDefinition] {
        if categoryId == "all" {
            return items
        }
        return items.filter { $0.category == categoryId }
    }
    
    // 搜索商品
    func searchItems(query: String) -> [PetItemDefinition] {
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(query) ||
            item.description.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - JSON Structure

struct PetConfigRoot: Codable {
    let categories: [PetCategory]
    let items: [PetItemDefinition]
}
