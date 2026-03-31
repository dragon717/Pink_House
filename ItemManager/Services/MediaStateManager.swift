import Foundation
import Combine
import SwiftUI

/// 页面类型
enum AppPage: String, CaseIterable {
    case pet = "pet"           // 萌宠页面
    case wealth = "wealth"     // 财富页面（黄金/白银）
    case wardrobe = "wardrobe" // 衣橱页面
    case other = "other"       // 其他页面
}

/// 媒体类型
struct MediaTypes: OptionSet {
    let rawValue: Int
    static let video = MediaTypes(rawValue: 1 << 0)
    static let audio = MediaTypes(rawValue: 1 << 1)
    static let haptics = MediaTypes(rawValue: 1 << 2)
    static let physics = MediaTypes(rawValue: 1 << 3)
    static let all: MediaTypes = [.video, .audio, .haptics, .physics]
}

/// 媒体状态管理器
/// 统一管理所有页面的视频、音频、震动、物理计算状态
/// 当切换页面时自动暂停上一个页面的媒体
@MainActor
final class MediaStateManager: ObservableObject {
    static let shared = MediaStateManager()
    
    // MARK: - Published Properties
    
    /// 当前活跃的页面
    @Published var currentPage: AppPage = .wardrobe
    
    /// 上一个页面（用于恢复）
    @Published private(set) var previousPage: AppPage?
    
    /// 是否暂停视频播放
    @Published var isVideoPaused: Bool = false
    
    /// 是否暂停物理计算
    @Published var isPhysicsPaused: Bool = false
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // 各页面的媒体配置
    private let pageMediaConfig: [AppPage: MediaTypes] = [
        .pet: [.video, .audio, .haptics],
        .wealth: [.audio, .haptics, .physics],
        .wardrobe: [],
        .other: []
    ]
    
    // MARK: - Initialization
    
    private init() {
        setupNotifications()
    }
    
    // MARK: - Public Methods
    
    /// 切换到指定页面
    func switchToPage(_ page: AppPage) {
        print("📱 MediaStateManager: 切换到页面 \(page.rawValue), 当前页面: \(currentPage.rawValue)")
        
        // 先停止所有媒体，确保干净状态
        stopAllMedia()
        
        previousPage = currentPage
        currentPage = page
        
        // 然后启动新页面的媒体
        startMediaForPage(page)
        
        print("📱 MediaStateManager: 切换完成，当前页面: \(currentPage.rawValue), 视频暂停: \(isVideoPaused), 物理暂停: \(isPhysicsPaused)")
    }
    
    /// 停止所有媒体
    private func stopAllMedia() {
        print("🛑 MediaStateManager: 停止所有媒体")

        // 停止萌宠媒体（使用不保存的方法，避免覆盖用户的持久化设置）
        AudioManager.shared.stopBackgroundMusicWithoutSaving()
        AudioManager.shared.isInteractionEnabled = false
        print("🎵 萌宠背景音乐已停止（不覆盖持久化设置）")

        // 停止财富媒体
        SoundManager.shared.stopAllSounds()
        print("🔔 财富音效已停止")

        // 停止震动
        HapticEngineManager.shared.stopHaptics()
        print("📳 震动已停止")

        // 暂停视频和物理
        isVideoPaused = true
        isPhysicsPaused = true
        print("⏸️ 视频和物理计算已暂停")
    }
    
    /// 启动指定页面的媒体
    private func startMediaForPage(_ page: AppPage) {
        switch page {
        case .pet:
            startPetMedia()
        case .wealth:
            startWealthMedia()
        default:
            // 其他页面不需要媒体
            break
        }
    }
    
    /// 获取指定页面支持的媒体类型
    func supportedMedia(for page: AppPage) -> MediaTypes {
        return pageMediaConfig[page] ?? []
    }
    
    /// 检查指定页面是否支持某类媒体
    func isMediaSupported(_ media: MediaTypes, for page: AppPage) -> Bool {
        return supportedMedia(for: page).contains(media)
    }
    
    /// 暂停所有媒体（用于应用进入后台）
    func pauseAllMedia() {
        stopAllMedia()
    }
    
    /// 恢复当前页面的媒体（用于应用回到前台）
    func resumeCurrentPageMedia() {
        startMediaForPage(currentPage)
    }
    
    // MARK: - Pet Page Media Control
    
    /// 启动萌宠页面的所有媒体
    func startPetMedia() {
        print("🐱 MediaStateManager: 启动萌宠媒体")
        guard isMediaSupported(.video, for: .pet) else {
            print("⚠️ 萌宠页面不支持视频媒体")
            return
        }

        // 恢复视频播放
        isVideoPaused = false
        print("▶️ 视频播放已恢复")

        // 根据用户历史习惯决定是否启动背景音乐
        // 如果用户曾经手动设置过，则恢复之前的设置；否则默认关闭
        let audioManager = AudioManager.shared
        if audioManager.hasUserManuallySetBackgroundMusic {
            // 用户有历史设置，恢复之前的习惯（使用内部方法避免重复持久化）
            audioManager.restoreBackgroundMusicFromSavedState()
            print("🎵 萌宠背景音乐已恢复历史状态")
        } else {
            // 首次使用，默认关闭背景音乐
            audioManager.isBackgroundMusicEnabled = false
            print("🎵 萌宠背景音乐默认关闭（首次使用）")
        }

        NotificationCenter.default.post(name: .petMediaShouldStart, object: nil)
        print("📢 发送萌宠媒体启动通知")
    }
    
    /// 停止萌宠页面的所有媒体
    func stopPetMedia() {
        // 暂停视频播放
        isVideoPaused = true

        // 停止背景音乐（使用不保存的方法，避免覆盖用户的持久化设置）
        AudioManager.shared.stopBackgroundMusicWithoutSaving()
        AudioManager.shared.isInteractionEnabled = false

        // 停止震动
        HapticEngineManager.shared.stopHaptics()

        NotificationCenter.default.post(name: .petMediaShouldStop, object: nil)
    }
    
    // MARK: - Wealth Page Media Control
    
    /// 启动财富页面的所有媒体
    func startWealthMedia() {
        print("💰 MediaStateManager: 启动财富媒体")
        guard isMediaSupported(.audio, for: .wealth) else {
            print("⚠️ 财富页面不支持音频媒体")
            return
        }
        
        // 恢复物理计算
        isPhysicsPaused = false
        print("▶️ 物理计算已恢复")
        
        // 启动音效
        SoundManager.shared.isSoundEnabled = true
        print("🔔 财富音效已启用: \(SoundManager.shared.isSoundEnabled)")
        
        NotificationCenter.default.post(name: .wealthMediaShouldStart, object: nil)
        print("📢 发送财富媒体启动通知")
    }
    
    /// 停止财富页面的所有媒体
    func stopWealthMedia() {
        // 暂停物理计算
        isPhysicsPaused = true
        
        // 停止音效
        SoundManager.shared.stopAllSounds()
        
        // 停止震动
        HapticEngineManager.shared.stopHaptics()
        
        NotificationCenter.default.post(name: .wealthMediaShouldStop, object: nil)
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        // 监听应用生命周期
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.pauseAllMedia()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.resumeCurrentPageMedia()
            }
            .store(in: &cancellables)
    }
    
}

// MARK: - Notification Names

extension Notification.Name {
    static let petMediaShouldStart = Notification.Name("petMediaShouldStart")
    static let petMediaShouldStop = Notification.Name("petMediaShouldStop")
    static let wealthMediaShouldStart = Notification.Name("wealthMediaShouldStart")
    static let wealthMediaShouldStop = Notification.Name("wealthMediaShouldStop")
    // 萌宠对话搜索栏状态变化通知（用于控制常用菜单长按交互）
    static let petChatSearchStateChanged = Notification.Name("petChatSearchStateChanged")
    // 自动展开萌宠对话搜索栏通知
    static let autoExpandPetChatSearch = Notification.Name("autoExpandPetChatSearch")
    // 萌宠对话内嵌引导选项点击通知（用于 AI 引导）
    static let petChatGuideOptionTapped = Notification.Name("petChatGuideOptionTapped")
    // 首页 Tab 切换通知（用于新手引导）
    static let homeTabChanged = Notification.Name("homeTabChanged")
    // VIP 中心打开通知（用于新手引导）
    static let vipCenterOpened = Notification.Name("vipCenterOpened")
    // VIP 兑换按钮点击通知（用于新手引导，点击即算完成尝试）
    static let vipExchangeAttempted = Notification.Name("vipExchangeAttempted")
    // House 内进入马上来财通知（用于新手引导）
    static let wealthDestinationOpened = Notification.Name("wealthDestinationOpened")
    // 来财主页面已出现通知（用于新手引导）
    static let wealthViewOpened = Notification.Name("wealthViewOpened")
    // 来财主页面页签切换通知（用于新手引导）
    static let wealthMainTabChanged = Notification.Name("wealthMainTabChanged")
    // 新手引导驱动来财页签切换
    static let wealthGuideSwitchMainTab = Notification.Name("wealthGuideSwitchMainTab")
    // 请求关闭魔法任务页面
    static let dismissMagicTasksView = Notification.Name("dismissMagicTasksView")
    // 小组件设置页打开通知（用于新手引导）
    static let widgetSettingsOpened = Notification.Name("widgetSettingsOpened")
    // 魔法任务页面 dismiss 通知（用于萌宠智能对话引导）
    static let magicTasksViewDismissed = Notification.Name("magicTasksViewDismissed")
    static let wardrobeAddMenuOpened = Notification.Name("wardrobeAddMenuOpened")
    static let wardrobeMoreMenuOpened = Notification.Name("wardrobeMoreMenuOpened")
    static let wardrobeManualCreateOpened = Notification.Name("wardrobeManualCreateOpened")
    static let wardrobeBatchImportOpened = Notification.Name("wardrobeBatchImportOpened")
    static let guideRequestWardrobeManualCreate = Notification.Name("guideRequestWardrobeManualCreate")
    static let guideRequestWardrobeBatchImport = Notification.Name("guideRequestWardrobeBatchImport")
    static let wardrobeSelectionModeChanged = Notification.Name("wardrobeSelectionModeChanged")
    static let wardrobeSelectionChanged = Notification.Name("wardrobeSelectionChanged")
    static let wardrobeSettingsOpened = Notification.Name("wardrobeSettingsOpened")
    static let systemSettingsOpened = Notification.Name("systemSettingsOpened")
    static let dataBackupManagementOpened = Notification.Name("dataBackupManagementOpened")
    static let exportCSVTriggered = Notification.Name("exportCSVTriggered")
    static let localBackupTriggered = Notification.Name("localBackupTriggered")
    static let localRestoreTriggered = Notification.Name("localRestoreTriggered")
    static let cloudSyncSheetOpened = Notification.Name("cloudSyncSheetOpened")
    static let magicColorSettingsOpened = Notification.Name("magicColorSettingsOpened")
    static let magicColorModeChanged = Notification.Name("magicColorModeChanged")
    static let batchImportViewOpened = Notification.Name("batchImportViewOpened")
    static let dreamDressCalendarOpened = Notification.Name("dreamDressCalendarOpened")
    static let ootdShelfOpened = Notification.Name("ootdShelfOpened")
    // 穿搭手帐书架打开通知（用于空间手帐前置任务引导）
    static let ootdBookShelfOpened = Notification.Name("ootdBookShelfOpened")
    static let ootdDefaultBookOpened = Notification.Name("ootdDefaultBookOpened")
    // 穿搭手帐详情页打开通知（用于空间手帐前置任务引导）
    static let ootdBookDetailOpened = Notification.Name("ootdBookDetailOpened")
    static let smallWorldQuickMenuOpened = Notification.Name("smallWorldQuickMenuOpened")
    static let favoriteMenuSettingsOpened = Notification.Name("favoriteMenuSettingsOpened")
    static let dismissFavoriteMenuSettingsView = Notification.Name("dismissFavoriteMenuSettingsView")
    static let favoriteMenuSettingsViewDismissed = Notification.Name("favoriteMenuSettingsViewDismissed")
    static let ootdShelfMoreMenuOpened = Notification.Name("ootdShelfMoreMenuOpened")
    static let ootdDetailMoreMenuOpened = Notification.Name("ootdDetailMoreMenuOpened")
    static let ootdBookCreated = Notification.Name("ootdBookCreated")
    static let ootdPageCreated = Notification.Name("ootdPageCreated")
    static let spatialBookShelfOpened = Notification.Name("spatialBookShelfOpened")
    static let spaceBookDetailOpened = Notification.Name("spaceBookDetailOpened")
    static let spaceBookPageCreated = Notification.Name("spaceBookPageCreated")
    static let spaceBookCreationPromptVisibilityChanged = Notification.Name("spaceBookCreationPromptVisibilityChanged")
    static let spaceBookShelfDataStateChanged = Notification.Name("spaceBookShelfDataStateChanged")
    static let spaceBookDetailDataStateChanged = Notification.Name("spaceBookDetailDataStateChanged")
    static let spatialCanvasEditorOpened = Notification.Name("spatialCanvasEditorOpened")
    static let objectCaptureScannerOpened = Notification.Name("objectCaptureScannerOpened")
    static let spatialCanvasImportMenuOpened = Notification.Name("spatialCanvasImportMenuOpened")
}

// MARK: - View Modifier

struct MediaStateViewModifier: ViewModifier {
    let page: AppPage
    @StateObject private var mediaManager = MediaStateManager.shared
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                mediaManager.switchToPage(page)
            }
            .onDisappear {
                // 如果当前页面是这个页面，切换到其他页面
                if mediaManager.currentPage == page {
                    mediaManager.switchToPage(.other)
                }
            }
    }
}

extension View {
    /// 为视图绑定媒体状态管理
    /// - Parameter page: 页面类型
    func manageMediaState(for page: AppPage) -> some View {
        modifier(MediaStateViewModifier(page: page))
    }
}
