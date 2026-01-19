//
//  SharedPersistence.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import Foundation
import SwiftData

class SharedPersistence {
    static let shared = SharedPersistence()
    
    // REPLACE THIS WITH YOUR ACTUAL APP GROUP ID
    // 这里的 App Group ID 需要在 Xcode -> Signing & Capabilities -> App Groups 中配置
    // 并且在 App 和 Widget Extension 中都要勾选同一个 Group ID
    static let appGroupIdentifier = "group.com.pinkhouse.itemmanager"
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Clothing.self,
            Item.self,
            Tag.self,
            Brand.self
        ])
        
        let modelConfiguration: ModelConfiguration
        
        // 尝试使用 App Group 共享容器
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let storeURL = containerURL.appendingPathComponent("ItemManager.sqlite")
            modelConfiguration = ModelConfiguration(url: storeURL, allowsSave: true)
            print("SharedPersistence: Using App Group container at \(storeURL.path)")
        } else {
            // 如果找不到 App Group (例如在模拟器未配置时)，回退到默认位置
            // 注意：这会导致 Widget 无法看到数据
            print("SharedPersistence: WARNING - App Group container not found. Using default storage.")
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
