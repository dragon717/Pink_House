//
//  ItemManagerApp.swift
//  ItemManager
//
//  Created by 木鸟 on 1/15/26.
//

import SwiftUI
import SwiftData

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@main
struct ItemManagerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var themeManager = ThemeManager.shared
    @State private var calendarThemeManager = CalendarThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    // Splash Screen State
    @State private var showSplash = true
    
    init() {
        // Ensure NotificationManager is initialized to set the delegate
        _ = NotificationManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .environment(themeManager)
                    .environment(calendarThemeManager)
                    .zIndex(0)
                
                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier) {
                    print("App Group Container URL: \(url.path)")
                } else {
                    print("CRITICAL ERROR: App Group Container NOT FOUND. Check Entitlements.")
                }
                
                // Initialization Buffer & Peak Shaving
                Task {
                    // 1. Minimum splash duration (aesthetic + buffer)
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    
                    // 2. Perform heavy initialization tasks
                    // Optimized syncWidgetData (now async to offload image processing)
                    await SharedPersistence.shared.syncWidgetData()
                    
                    // 3. Cloud Sync Check (async)
                    await CloudSyncManager.shared.checkAndSilentRestore(container: SharedPersistence.shared.sharedModelContainer)
                    
                    // 4. Dismiss Splash
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    Task {
                        await SharedPersistence.shared.syncWidgetData()
                    }
                }
            }
        }
        .modelContainer(SharedPersistence.shared.sharedModelContainer)
    }
}
