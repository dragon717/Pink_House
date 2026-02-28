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
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 设置TabBar全局样式为B22222深红色
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.698, green: 0.133, blue: 0.133, alpha: 1.0)
        
        // 设置未选中项的颜色（白色70%透明度）
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.7)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.7)]
        
        // 设置选中项的颜色（纯白色）
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        
        return true
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
            MainContentView()
                .environment(themeManager)
                .environment(calendarThemeManager)
        }
        .modelContainer(SharedPersistence.shared.sharedModelContainer)
    }
}

// 主内容视图，处理启动逻辑
struct MainContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var showMigrationOverlay = false
    
    var body: some View {
        ZStack {
            MainTabView()
                .zIndex(0)
            
            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            // 迁移进度遮罩
            if SwiftDataMigrationManager.shared.isMigrating {
                MigrationProgressView()
                    .zIndex(2)
            }
        }
        .onAppear {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier) {
                print("App Group Container URL: \(url.path)")
            } else {
                print("CRITICAL ERROR: App Group Container NOT FOUND. Check Entitlements.")
            }
            
            // 打印当前同步状态
            let migrationManager = SwiftDataMigrationManager.shared
            print("iCloud 同步状态: \(migrationManager.isCloudSyncEnabled ? "已启用" : "未启用")")
            print("迁移完成状态: \(migrationManager.isMigrationCompleted ? "已完成" : "未完成")")
            
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
                
                // 0.6 Validate Model3D references integrity
                await Model3DValidationService.shared.validateIfNeeded(modelContainer: SharedPersistence.shared.sharedModelContainer)
                
                // 0.7 裙子股市功能已暂时禁用，避免影响原有衣橱数据
                // await SkirtMarketPersistence.shared.configure()
                // await TaskDispatcher.shared.start()
                print("⚠️ 裙子股市功能已禁用，保护原有衣橱数据")
                
                // 1. Minimum splash duration (aesthetic + buffer)
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                
                // 2. Perform heavy initialization tasks
                // Optimized syncWidgetData (now async to offload image processing)
                await SharedPersistence.shared.syncWidgetData()
                
                // 3. Dismiss Splash
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                Task {
                    await SharedPersistence.shared.syncWidgetData()
                    // 调度裙子股市后台任务
                    TaskDispatcher.shared.scheduleBackgroundTask()
                }
            }
        }
    }
}

// MARK: - Migration Progress View
struct MigrationProgressView: View {
    @ObservedObject private var manager = SwiftDataMigrationManager.shared
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce)
                
                Text("正在同步到 iCloud")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                
                Text("首次启用 iCloud 同步需要一些时间...")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                
                ProgressView(value: manager.migrationProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(width: 250)
                
                Text("\(Int(manager.migrationProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.gray)
                
                if let error = manager.migrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}
