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
                    if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier) {
                        print("App Group Container URL: \(url.path)")
                    } else {
                        print("CRITICAL ERROR: App Group Container NOT FOUND. Check Entitlements.")
                    }

                    SharedPersistence.shared.syncWidgetData()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        SharedPersistence.shared.syncWidgetData()
                    }
                }
        }
        .modelContainer(SharedPersistence.shared.sharedModelContainer)
    }
}
