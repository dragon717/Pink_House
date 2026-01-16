//
//  ItemManagerApp.swift
//  ItemManager
//
//  Created by 木鸟 on 1/15/26.
//

import SwiftUI
import SwiftData

@main
struct ItemManagerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
                    Item.self,
                    Clothing.self,
                    Brand.self,
                    Tag.self,
                    StoredImage.self,
                ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // 如果迁移失败，尝试删除旧的 store
            print("Could not create ModelContainer: \(error)")
            print("Attempting to delete old store and recreate...")
            
            // 获取默认的 store URL (通常在 Application Support 目录下)
            // 兼容性写法
            if let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let dbUrl = supportDir.appendingPathComponent("default.store")
                let shmUrl = supportDir.appendingPathComponent("default.store-shm")
                let walUrl = supportDir.appendingPathComponent("default.store-wal")
                
                try? FileManager.default.removeItem(at: dbUrl)
                try? FileManager.default.removeItem(at: shmUrl)
                try? FileManager.default.removeItem(at: walUrl)
            }
            
            // 再次尝试创建
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after cleanup: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ClothingListView()
        }
        .modelContainer(sharedModelContainer)
    }
}
