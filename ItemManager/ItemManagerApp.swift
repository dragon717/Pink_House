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
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Ensure NotificationManager is initialized to set the delegate
        _ = NotificationManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(themeManager)
                .onAppear {
                    // Check App Group
                    if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier) {
                        print("App Group Container URL: \(url.path)")
                    } else {
                        print("CRITICAL ERROR: App Group Container NOT FOUND. Check Entitlements.")
                    }
                    
                    // Sync widget data on launch
                    SharedPersistence.shared.syncWidgetData()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // Sync when app becomes active to ensure widget has latest data
                        SharedPersistence.shared.syncWidgetData()
                    } else if newPhase == .background || newPhase == .inactive {
                        // Sync when app goes to background so widget is up to date
                        SharedPersistence.shared.syncWidgetData()
                    }
                }
        }
        .modelContainer(SharedPersistence.shared.sharedModelContainer)
    }
}
