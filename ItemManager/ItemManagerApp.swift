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
    @State private var themeManager = ThemeManager.shared
    
    init() {
        // Ensure NotificationManager is initialized to set the delegate
        _ = NotificationManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(themeManager)
        }
        .modelContainer(SharedPersistence.shared.sharedModelContainer)
    }
}
