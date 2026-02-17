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
        
        // 预热 RealityKit 渲染引擎，避免 Object Capture 时的材质加载错误
        // 这会在 App 启动时预加载 engine:throttleGhosted.rematerial 等内部资源
        RealityKitHelper.warmUp()
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
                    // 0. Preload Spatial Assets (iOS 26+ only)
                    // 仅在支持的系统上预加载，避免旧设备浪费资源
                    if #available(iOS 26.0, *) {
                        await MainActor.run {
                            SpatialAssetManager.shared.preload(imageName: "small_world_bg_normal", extension: "png")
                            SpatialAssetManager.shared.preload(imageName: "small_world_bg_sun", extension: "png")
                        }
                    }
                    
                    // 0.5 Migrate 3D models from Clothing to Model3D
                    await Model3DMigrationService.shared.migrateIfNeeded(modelContainer: SharedPersistence.shared.sharedModelContainer)
                    
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
