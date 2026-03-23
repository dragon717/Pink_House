//
//  ItemManagerApp.swift
//  ItemManager
//
//  Created by 木鸟 on 1/15/26.
//

import SwiftUI
import SwiftData
import BackgroundTasks
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // iOS 26+ 设置 TabBar 全局样式
        if #available(iOS 26.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()

            // 设置未选中项的颜色（黑色，适配暗黑模式）
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.label
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.label]

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }

        // 注册裙装股市后台任务
        registerSkirtMarketBackgroundTask()
        
        // 注册内存警告通知
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            DailyCheckInManager.shared.handleMemoryWarning()
            print("📱 [AppDelegate] 收到内存警告通知")
        }

        return true
    }
    
    // MARK: - 后台任务注册
    
    private func registerSkirtMarketBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.yourapp.skirtmarket.fetch",
            using: nil
        ) { task in
            self.handleSkirtMarketBackgroundTask(task as! BGAppRefreshTask)
        }
        print("✅ 后台任务已注册: com.yourapp.skirtmarket.fetch")
    }
    
    private func handleSkirtMarketBackgroundTask(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            print("⏰ 后台任务即将过期")
        }
        
        Task {
            // 执行裙装股市的后台任务
            await TaskDispatcher.shared.checkAndClaimTasks()
            task.setTaskCompleted(success: true)
            
            // 调度下一次任务
            TaskDispatcher.shared.scheduleBackgroundTask()
        }
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
                .tint(themeManager.accentTextColor)
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
    @State private var showDailyCheckIn = false
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    
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
            
            // 全局解锁通知覆盖层
            GlobalUnlockNotificationOverlay()
                .zIndex(3)
            
            // 全局拷贝提示覆盖层
            GlobalCopyToast()
                .zIndex(4)
            
            // 全局 Toast 提示覆盖层
            GlobalToast()
                .zIndex(5)
        }
        .sheet(isPresented: $showDailyCheckIn) {
            DailyCheckInView()
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
                
                // 0.7 裙装股市功能 - 使用 GRDB 版本（完全独立于 SwiftData）
                do {
                    try await GRDBManager.shared.initialize()
                    await SyncEngine.shared.configure()
                    print("✅ 裙装股市功能已启用（GRDB 版本）")
                } catch {
                    print("❌ 裙装股市初始化失败: \(error)")
                }
                
                // 0.8 刷新魔法任务进度（在开屏期间完成）
                await MainActor.run {
                    FeatureUnlockManager.shared.refreshMagicTaskProgress(modelContext: modelContext)
                }

                // 0.9 OOTD 坐标版本迁移（将老数据的绝对坐标转换为相对坐标）
                await OOTDCoordinateMigrationService.shared.migrateIfNeeded(modelContext: modelContext)

                // 0.10 并行预加载每日打卡数据（问候语 + 穿搭色）
                // 使用 TaskGroup 实现并行加载，减少开屏等待时间
                await withTaskGroup(of: Void.self) { group in
                    // 预加载今日问候语
                    group.addTask {
                        _ = await DailyGreetingManager.shared.getCurrentGreeting()
                    }
                    
                    // 预加载今日穿搭色
                    group.addTask {
                        await DailyCheckInManager.shared.preloadTodayOutfitColor()
                    }
                }
                
                // 0.11 预加载本周穿搭色（可选优化，低内存设备建议注释掉）
                // await DailyCheckInManager.shared.preloadWeekOutfitColors()

                // 1. Minimum splash duration (aesthetic + buffer)
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                
                // 2. Perform heavy initialization tasks
                // Optimized syncWidgetData (now async to offload image processing)
                await SharedPersistence.shared.syncWidgetData()
                
                // 3. Dismiss Splash
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
                
                // 4. 启动新手引导（开屏结束后）
                try? await Task.sleep(nanoseconds: 300_000_000) // 等待 0.3 秒确保动画完成
                await MainActor.run {
                    guideManager.startGuide()
                    // 检查是否需要显示每日打卡（仅在未显示新手引导时）
                    if !guideManager.isShowingGuide {
                        checkAndShowDailyCheckIn()
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                Task {
                    await SharedPersistence.shared.syncWidgetData()
                    // 调度裙装股市后台任务
                    TaskDispatcher.shared.scheduleBackgroundTask()
                }
            } else if newPhase == .active {
                // 从后台回到前台时检查是否需要打卡
                checkAndShowDailyCheckIn()
            }
        }
    }
    
    // MARK: - 检查并显示每日打卡
    private func checkAndShowDailyCheckIn() {
        // 检查今天是否已经打卡
        if !DailyCheckInManager.shared.hasCheckedInToday {
            // 延迟一点显示，让主界面先加载完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showDailyCheckIn = true
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
