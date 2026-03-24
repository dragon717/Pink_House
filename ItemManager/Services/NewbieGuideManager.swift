import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - App首次启动引导步骤

enum AppFirstLaunchStep: String, CaseIterable, Identifiable {
    case none = "none"           // 无引导
    case welcome = "welcome"     // 欢迎界面
    case running = "running"     // 跑步动画中
    case pointing = "pointing"   // 指向动画（等待用户点击）
    case complete = "complete"   // 引导完成

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none, .running, .pointing: return ""
        case .welcome: return "欢迎来到少女心愿衣橱"
        case .complete: return "引导完成"
        }
    }

    var description: String {
        switch self {
        case .none, .running: return ""
        case .welcome: return "我是你的向导奶茶，让我带你了解一下这个魔法衣橱吧！"
        case .pointing: return "点击右上角的 + 号，开始添加你的第一件裙子吧！"
        case .complete: return "你已经准备好开始使用啦！有问题随时找我哦~"
        }
    }

    var targetButtonText: String {
        switch self {
        case .none, .running, .pointing, .complete: return ""
        case .welcome: return "开始探索"
        }
    }
}

// MARK: - 气泡位置

enum BubblePosition {
    case top
    case center
    case bottom
}

// MARK: - 指向方向

enum PointDirection {
    case none
    case topRight    // 指向右上角
    case topLeft     // 指向左上角
    case bottom      // 指向底部
    case center      // 居中

    var needsFlip: Bool {
        switch self {
        case .topLeft: return true
        default: return false
        }
    }
}

// MARK: - 引导目标锚点 Key

enum GuideTargetKey: String, CaseIterable, Hashable {
    case aiAnalysisVIPCard = "aiAnalysis.vipCard"
    case aiAnalysisExchangeButton = "aiAnalysis.exchangeButton"
    case wealthEntry = "wealth.entry"
    case wealthMainTabSegment = "wealth.mainTab.segment"
    case accountSyncEntry = "accountSync.entry"
    case cloudAppleSignInButton = "cloud.appleSignInButton"
    case cloudFileBackupSection = "cloud.fileBackup.section"
    case iCloudRealtimeSyncSection = "cloud.realtimeSync.section"
    case systemSettingsEntry = "systemSettings.entry"
    case localFileBackupRestoreEntry = "localFileBackupRestore.entry"
    case exportCSVEntry = "exportCSV.entry"
    case widgetCustomizeEntry = "widgetCustomize.entry"
    case themeCustomizeEntry = "themeCustomize.entry"
    case wardrobeSettingsEntry = "wardrobeSettings.entry"
    case wardrobeInterfaceStyleSection = "wardrobe.interfaceStyle.section"
    case wardrobeFilterModeSection = "wardrobe.filterMode.section"
    case wardrobePrivacyShowPriceSection = "wardrobe.privacy.showPrice.section"
    case wardrobePrivacyShowOriginalPriceSection = "wardrobe.privacy.showOriginalPrice.section"
    case wardrobeTagManagementEntry = "wardrobe.tagManagement.entry"
    case wardrobeBrandManagementEntry = "wardrobe.brandManagement.entry"
    case wardrobeFieldManagementEntry = "wardrobe.fieldManagement.entry"
    case wardrobeAppAppearanceSection = "wardrobe.appAppearance.section"
    case wardrobeOotdEntry = "wardrobe.ootd.entry"
    case wardrobeAddButton = "wardrobe.addButton"
    case wardrobeManualCreateEntry = "wardrobe.manualCreateEntry"
    case wardrobeBatchImportEntry = "wardrobe.batchImportEntry"
    case wardrobeMoreMenuButton = "wardrobe.moreMenuButton"
    case wardrobeSelectionCard = "wardrobe.selectionCard"
    case wardrobeDoneSelectionButton = "wardrobe.doneSelectionButton"
    case ootdEntry = "ootd.entry"
    case calendarEntry = "calendar.entry"
    case favoriteMenuMagicStickerEntry = "favoriteMenu.magicStickerEntry"
    case themeColorModeTabs = "themeColorMode.tabs"
    case spaceBookModeTabs = "spaceBook.modeTabs"
    case spaceBookShelfMoreMenuButton = "spaceBook.shelfMoreMenuButton"
    case spaceBookDetailMoreMenuButton = "spaceBook.detailMoreMenuButton"
    case spaceBookFirstPageCard = "spaceBook.firstPageCard"
    case spatialCanvasToolbar = "spatialCanvas.toolbar"
    case spatialCanvasImportMenu = "spatialCanvas.importMenu"
}

// MARK: - 功能体验引导状态管理

extension FeatureUnlockManager {
    // 需要体验引导的功能列表
    static let experienceGuidedFeatures: [FeatureItem] = [
        .dataBackup,      // 数据备份
        .cloudSync,       // iCloud同步
        .batchImport,     // 批量导入
        .themeCustomize,  // 魔法配色
        .widgetCustomize, // 小组件定制
        .filterClassic,   // 筛选偏好
        .privacyDisplay,  // 隐私显示
        .tagBrandFieldDisplay, // 标签和品牌管理以及属性字段的显示
        .spaceBook,       // 空间手帐
        .batchEdit,       // 批量编辑
        .localFileBackupRestore, // 本地文件的备份与恢复
        .exportCSV,       // 导出表格
        .cloudFileBackupRestore, // 云端的文件备份与恢复
        .ootd,            // 穿搭手帐
        .ootdDefaultBook, // 魔法贴纸
        .calendar,        // 梦裙日历
        .wealth,          // 来财求签
        .aiAnalysis,      // 萌宠智能对话
    ]

    static let preUnlockGuidedFeatures: Set<FeatureItem> = [
        .ootd,
        .ootdDefaultBook,
        .calendar,
        .batchImport,
        .spaceBook
    ]

    func canStartPreUnlockGuide(for feature: FeatureItem) -> Bool {
        FeatureUnlockManager.preUnlockGuidedFeatures.contains(feature)
    }

    // 检查功能是否需要体验引导
    func needsFeatureExperienceGuide(for feature: FeatureItem) -> Bool {
        guard FeatureUnlockManager.experienceGuidedFeatures.contains(feature) else { return false }
        guard isUnlocked(feature) else { return false }
        let key = "featureExperienceGuide_\(feature.rawValue)"
        return !UserDefaults.standard.bool(forKey: key)
    }

    // 标记功能已完成体验引导
    func markFeatureExperienceGuideCompleted(for feature: FeatureItem) {
        let key = "featureExperienceGuide_\(feature.rawValue)"
        UserDefaults.standard.set(true, forKey: key)
    }

    // 重置功能体验引导状态
    func resetFeatureExperienceGuide(for feature: FeatureItem) {
        let key = "featureExperienceGuide_\(feature.rawValue)"
        UserDefaults.standard.set(false, forKey: key)
    }
}

// MARK: - App首次启动引导状态

struct AppFirstLaunchState: Codable {
    var isCompleted: Bool = false
    var currentStep: String = AppFirstLaunchStep.none.rawValue
    var skippedAt: Date? = nil
    var startedAt: Date = Date()
}

// MARK: - App首次启动引导管理器

final class AppFirstLaunchGuideManager: ObservableObject {
    static let shared = AppFirstLaunchGuideManager()
    
    // MARK: - Published Properties

    @Published var state: AppFirstLaunchState = AppFirstLaunchState()
    @Published var isShowingGuide: Bool = false
    @Published var currentStep: AppFirstLaunchStep = .none
    @Published var isRunningAnimation: Bool = false
    @Published var catPosition: CGPoint = .zero
    @Published var showPointingVideo: Bool = false
    @Published var showCreateButtonHighlight: Bool = false  // 是否显示创建按钮高亮

    // 功能体验引导相关
    @Published var isShowingFeatureExperienceGuide: Bool = false
    @Published var currentFeatureExperienceFeature: FeatureItem? = nil
    @Published private var guideTargetFrames: [GuideTargetKey: CGRect] = [:]
    @Published private(set) var lastKnownHomeTab: String = "wardrobe"
    
    // 向后兼容：保留已使用字段名，内部改为统一存储
    var aiAnalysisVIPCardGlobalFrame: CGRect? {
        guideTargetFrames[.aiAnalysisVIPCard]
    }
    
    var aiAnalysisExchangeButtonGlobalFrame: CGRect? {
        guideTargetFrames[.aiAnalysisExchangeButton]
    }

    var widgetCustomizeEntryGlobalFrame: CGRect? {
        guideTargetFrames[.widgetCustomizeEntry]
    }
    
    // MARK: - 配置
    
    private let stateKey = "newbieGuide.state"
    private let hasSeenWelcomeKey = "newbieGuide.hasSeenWelcome"
    
    let runningVideoName = "naicha_new_role"
    let pointingVideoName = "naicha_pointto"
    let runningDuration: TimeInterval = 5.0  // 跑步动画持续5秒
    
    // 小猫跑步终点位置（右上角）
    var createButtonPosition: CGPoint {
        let screenBounds = UIScreen.main.bounds
        return CGPoint(x: screenBounds.width * 0.8, y: screenBounds.height * 0.10)
    }
    
    // 高亮圈位置（+ 号按钮位置）- 可以独立调整
    var highlightCirclePosition: CGPoint {
        let screenBounds = UIScreen.main.bounds
        // 高亮圈往上挪一些
        return CGPoint(x: screenBounds.width * 0.88, y: screenBounds.height * 0.035)
    }
    
    // 悬浮小猫起始位置（底部中间）- 往上移动
    var floatingCatStartPosition: CGPoint {
        let screenBounds = UIScreen.main.bounds
        return CGPoint(x: screenBounds.width / 2, y: screenBounds.height - 155)
    }
    
    // MARK: - 计算属性
    
    var isFirstLaunch: Bool {
        return !UserDefaults.standard.bool(forKey: hasSeenWelcomeKey)
    }
    
    var shouldShowGuide: Bool {
        return !state.isCompleted && isFirstLaunch
    }
    
    // MARK: - Initialization
    
    private init() {
        loadState()
        NotificationCenter.default.addObserver(
            forName: .homeTabChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let tab = notification.userInfo?["tab"] as? String else { return }
            self?.lastKnownHomeTab = tab
        }
    }
    
    // MARK: - 状态管理
    
    private func loadState() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(AppFirstLaunchState.self, from: data) {
            state = decoded
            currentStep = AppFirstLaunchStep(rawValue: decoded.currentStep) ?? .none
        }
    }
    
    private func saveState() {
        state.currentStep = currentStep.rawValue
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: stateKey)
        }
    }
    
    // MARK: - 引导控制
    
    func startGuide() {
        guard shouldShowGuide else { return }
        
        currentStep = .welcome
        isShowingGuide = true
        saveState()
        
        UserDefaults.standard.set(true, forKey: hasSeenWelcomeKey)
    }
    
    /// 开始跑步动画（从欢迎界面点击后调用）
    func startRunningAnimation() {
        currentStep = .running
        isRunningAnimation = true
        showPointingVideo = false
        showCreateButtonHighlight = false
        
        // 设置起始位置（悬浮小猫位置）
        catPosition = floatingCatStartPosition
        
        // 延迟后开始动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            
            // 动画移动到目标位置（创建按钮位置）
            withAnimation(.linear(duration: self.runningDuration)) {
                self.catPosition = self.createButtonPosition
            }
            
            // 10秒后显示指向动画
            DispatchQueue.main.asyncAfter(deadline: .now() + self.runningDuration) { [weak self] in
                guard let self = self else { return }
                self.isRunningAnimation = false
                self.showPointingVideo = true
                self.showCreateButtonHighlight = true
                self.currentStep = .pointing
                self.saveState()
            }
        }
    }
    
    /// 用户点击了创建按钮，结束引导
    func userTappedCreateButton() {
        guard currentStep == .pointing else { return }
        completeGuide()
    }

    // MARK: - 功能体验引导

    /// 开始显示功能体验引导
    func startFeatureExperienceGuide(for feature: FeatureItem) {
        print("[FeatureExperienceGuide] 尝试启动引导: \(feature.rawValue)")
        
        guard FeatureUnlockManager.experienceGuidedFeatures.contains(feature) else {
            print("[FeatureExperienceGuide] 失败: 功能不在experienceGuidedFeatures列表中")
            return
        }
        
        let condition = FeatureUnlockManager.shared.getCondition(for: feature)
        let isManualExperienceTask = condition.type == UnlockConditionType.manual.rawValue
        let isUnlocked = FeatureUnlockManager.shared.isUnlocked(feature)
        let canStartPreUnlockGuide = FeatureUnlockManager.shared.canStartPreUnlockGuide(for: feature)
        print("[FeatureExperienceGuide] 功能解锁状态: \(isUnlocked), 是否体验任务: \(isManualExperienceTask), 是否支持解锁前引导: \(canStartPreUnlockGuide)")
        
        // 体验任务（manual）和指定功能允许在未解锁时先进入引导
        guard isUnlocked || isManualExperienceTask || canStartPreUnlockGuide else {
            print("[FeatureExperienceGuide] 失败: 功能未解锁")
            return
        }

        print("[FeatureExperienceGuide] 启动引导成功: \(feature.rawValue)")
        resetFeatureGuideTargetFrames()
        currentFeatureExperienceFeature = feature
        isShowingFeatureExperienceGuide = true
    }

    /// 完成当前功能体验引导
    func completeFeatureExperienceGuide() {
        if let feature = currentFeatureExperienceFeature {
            let condition = FeatureUnlockManager.shared.getCondition(for: feature)
            if condition.type == UnlockConditionType.manual.rawValue,
               !FeatureUnlockManager.shared.isUnlocked(feature) {
                let unlockResult = FeatureUnlockManager.shared.unlock(feature, force: true)
                if case .success = unlockResult,
                   let reward = feature.experienceFishCoinReward {
                    RewardManager.shared.triggerReward(
                        type: .custom(
                            amount: reward,
                            message: "体验任务完成，鱼币 +\(reward)"
                        )
                    )
                }
            }
            let shouldPersistCompletion =
                FeatureUnlockManager.shared.isUnlocked(feature) ||
                condition.type == UnlockConditionType.manual.rawValue
            if shouldPersistCompletion {
                FeatureUnlockManager.shared.markFeatureExperienceGuideCompleted(for: feature)
            }
        }
        isShowingFeatureExperienceGuide = false
        currentFeatureExperienceFeature = nil
        resetFeatureGuideTargetFrames()
    }

    /// 关闭功能体验引导（不标记为完成）
    func dismissFeatureExperienceGuide() {
        isShowingFeatureExperienceGuide = false
        currentFeatureExperienceFeature = nil
        resetFeatureGuideTargetFrames()
    }

    // MARK: - 萌宠智能对话引导目标位置信息

    func guideTargetFrame(for key: GuideTargetKey) -> CGRect? {
        guideTargetFrames[key]
    }

    func updateGuideTargetFrame(_ frame: CGRect, for key: GuideTargetKey) {
        guard frame.width > 0, frame.height > 0 else { return }
        guideTargetFrames[key] = frame
    }

    func resetGuideTargetFrames(_ keys: [GuideTargetKey]? = nil) {
        guard let keys else {
            guideTargetFrames.removeAll()
            return
        }
        
        for key in keys {
            guideTargetFrames[key] = nil
        }
    }

    func updateAIAnalysisVIPCardFrame(_ frame: CGRect) {
        updateGuideTargetFrame(frame, for: .aiAnalysisVIPCard)
    }

    func updateAIAnalysisExchangeButtonFrame(_ frame: CGRect) {
        updateGuideTargetFrame(frame, for: .aiAnalysisExchangeButton)
    }

    private func resetFeatureGuideTargetFrames() {
        resetGuideTargetFrames([
            .aiAnalysisVIPCard,
            .aiAnalysisExchangeButton,
            .wealthEntry,
            .wealthMainTabSegment,
            .accountSyncEntry,
            .cloudAppleSignInButton,
            .cloudFileBackupSection,
            .iCloudRealtimeSyncSection,
            .systemSettingsEntry,
            .localFileBackupRestoreEntry,
            .exportCSVEntry,
            .widgetCustomizeEntry,
            .themeCustomizeEntry,
            .wardrobeSettingsEntry,
            .wardrobeInterfaceStyleSection,
            .wardrobeFilterModeSection,
            .wardrobePrivacyShowPriceSection,
            .wardrobePrivacyShowOriginalPriceSection,
            .wardrobeTagManagementEntry,
            .wardrobeBrandManagementEntry,
            .wardrobeFieldManagementEntry,
            .wardrobeAppAppearanceSection,
            .wardrobeOotdEntry,
            .wardrobeAddButton,
            .wardrobeManualCreateEntry,
            .wardrobeBatchImportEntry,
            .wardrobeMoreMenuButton,
            .wardrobeSelectionCard,
            .wardrobeDoneSelectionButton,
            .ootdEntry,
            .calendarEntry,
            .favoriteMenuMagicStickerEntry,
            .themeColorModeTabs,
            .spaceBookModeTabs,
            .spaceBookShelfMoreMenuButton,
            .spaceBookDetailMoreMenuButton,
            .spaceBookFirstPageCard,
            .spatialCanvasToolbar,
            .spatialCanvasImportMenu
        ])
    }

    /// 完成引导
    func completeGuide() {
        state.isCompleted = true
        currentStep = .complete
        isShowingGuide = false
        isRunningAnimation = false
        showPointingVideo = false
        showCreateButtonHighlight = false
        saveState()
    }

    /// 重置引导状态
    func resetGuide() {
        state = AppFirstLaunchState()
        currentStep = .none
        isShowingGuide = false
        isRunningAnimation = false
        showPointingVideo = false
        showCreateButtonHighlight = false
        UserDefaults.standard.set(false, forKey: hasSeenWelcomeKey)
        saveState()
    }
}

// MARK: - 通用引导目标采集 Modifier

struct GuideTargetCaptureModifier: ViewModifier {
    let key: GuideTargetKey
    
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear {
                        AppFirstLaunchGuideManager.shared.updateGuideTargetFrame(frame, for: key)
                    }
                    .onChange(of: frame) { _, newValue in
                        AppFirstLaunchGuideManager.shared.updateGuideTargetFrame(newValue, for: key)
                    }
            }
        )
    }
}

extension View {
    func captureGuideTarget(_ key: GuideTargetKey) -> some View {
        modifier(GuideTargetCaptureModifier(key: key))
    }

    @ViewBuilder
    func captureGuideTarget(_ key: GuideTargetKey?) -> some View {
        if let key {
            modifier(GuideTargetCaptureModifier(key: key))
        } else {
            self
        }
    }
}

// MARK: - 引导视频播放器视图

struct GuideCatVideoPlayer: View {
    let videoName: String
    let isLooping: Bool
    let isFlipped: Bool
    let onFinished: (() -> Void)?
    
    var body: some View {
        PetVideoPlayer(
            videoName: videoName,
            isLooping: isLooping,
            isMuted: true,
            onFinished: onFinished
        )
        .frame(width: 100, height: 100)
        .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
    }
}

// MARK: - 欢迎气泡视图（第一步）

struct WelcomeBubbleView: View {
    let onStart: () -> Void
    let onSkip: () -> Void
    
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 跳过按钮
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            VStack(spacing: 12) {
                Text("欢迎来到少女心愿衣橱")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)
                
                Text("我是你的向导奶茶，让我带你了解一下这个魔法衣橱吧！")
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                Button {
                    onStart()
                } label: {
                    Text("开始探索")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(magicPalette.bubbleUserTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [magicPalette.accent, magicPalette.accent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(magicPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 320)
    }
}

// MARK: - 指向提示气泡视图

struct PointingBubbleView: View {
    let onSkip: () -> Void
    let onComplete: () -> Void
    
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 跳过按钮
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            VStack(spacing: 12) {
                Text("添加你的第一件裙子")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)
                
                Text("这里是衣橱的手动创建入口，你可以一件一件添加你的裙子。\n\n当然，我们也支持批量创建，一次导入多件衣物，省时省力！")
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                Text("点击右上角的 + 号试试")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(magicPalette.accent)
                    .padding(.top, 4)
                
                // 完成按钮
                Button {
                    onComplete()
                } label: {
                    Text("知道了")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(magicPalette.bubbleUserTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [magicPalette.accent, magicPalette.accent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(magicPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 320)
    }
}

// MARK: - 跳过确认弹窗

struct SkipGuideConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                
                Text("跳过新手引导？")
                    .font(.system(size: 18, weight: .bold))
                
                Text("跳过之后可以随时在设置中重新开启引导")
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Text("继续引导")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(magicPalette.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(magicPalette.quickOptionFill)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button {
                        onConfirm()
                    } label: {
                        Text("确认跳过")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(magicPalette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(magicPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - 脉冲高亮视图（不拦截点击，仅视觉）

struct HighlightPulseViewNoClick: View {
    let center: CGPoint
    let radius: CGFloat
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.8
    
    var body: some View {
        ZStack {
            // 外圈脉冲动画
            Circle()
                .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: radius * 2 * pulseScale, height: radius * 2 * pulseScale)
                .position(center)
            
            // 内圈白色边框
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
        }
        // 允许点击穿透
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                pulseScale = 1.5
                pulseOpacity = 0.0
            }
        }
    }
}

// MARK: - 圆角矩形高亮遮罩（可穿透点击）

struct RoundedRectHighlightView: View {
    let frame: CGRect
    let cornerRadius: CGFloat
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    
    var body: some View {
        ZStack {
            // 外圈脉冲动画
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: frame.width * pulseScale, height: frame.height * pulseScale)
                .position(x: frame.midX, y: frame.midY)
            
            // 内圈白色边框
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
        }
        // 允许点击穿透
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                pulseScale = 1.05
                pulseOpacity = 0.0
            }
        }
    }
}

// MARK: - 小猫爪点击动画组件

struct CatPawTapAnimation: View {
    let position: CGPoint
    let delay: Double
    
    @State private var isAnimating = false
    @State private var tapScale: CGFloat = 1.0
    @State private var tapOpacity: Double = 1.0
    
    var body: some View {
        ZStack {
            // 小猫爪图标
            Image(systemName: "pawprint.fill")
                .font(.system(size: 30))
                .foregroundColor(.white)
                .scaleEffect(tapScale)
                .opacity(tapOpacity)
                .position(position)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
            
            // 点击波纹效果
            Circle()
                .stroke(Color.white.opacity(tapOpacity * 0.5), lineWidth: 2)
                .frame(width: 50 * tapScale, height: 50 * tapScale)
                .position(position)
        }
        // 允许点击穿透
        .allowsHitTesting(false)
        .onAppear {
            // 延迟后开始动画
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                startAnimation()
            }
        }
    }
    
    private func startAnimation() {
        // 点击动画：缩小然后弹回，同时透明度变化
        withAnimation(.easeInOut(duration: 0.3)) {
            tapScale = 0.7
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.2)) {
                tapScale = 1.0
            }
        }
        
        // 波纹扩散动画
        withAnimation(.easeOut(duration: 0.6)) {
            tapScale = 1.5
            tapOpacity = 0.0
        }
        
        // 循环动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            tapScale = 1.0
            tapOpacity = 1.0
            startAnimation()
        }
    }
}

// MARK: - 带挖空的半透明遮罩（可穿透点击）

struct HollowMaskView: View {
    let highlightFrame: CGRect
    let highlightType: HighlightType
    let cornerRadius: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 半透明背景
                Color.black
                    .opacity(0.5)
                    .ignoresSafeArea()
                
                // 挖空区域
                switch highlightType {
                case .circle:
                    Circle()
                        .frame(width: highlightFrame.width, height: highlightFrame.height)
                        .position(x: highlightFrame.midX, y: highlightFrame.midY)
                        .blendMode(.destinationOut)
                case .roundedRect:
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .frame(width: highlightFrame.width, height: highlightFrame.height)
                        .position(x: highlightFrame.midX, y: highlightFrame.midY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            // 允许点击穿透到挖空区域
            .allowsHitTesting(false)
        }
    }
}

// MARK: - App首次启动引导遮罩视图

struct AppFirstLaunchGuideOverlay: View {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @State private var showingSkipConfirmation = false
    
    var body: some View {
        ZStack {
            // 根据当前步骤显示不同的遮罩
            switch guideManager.currentStep {
            case .welcome:
                welcomeMask
            case .running:
                runningMask
            case .pointing:
                pointingMask
            default:
                EmptyView()
            }
            
            // 跳过确认弹窗
            if showingSkipConfirmation {
                SkipGuideConfirmationView(
                    onConfirm: {
                        showingSkipConfirmation = false
                        guideManager.completeGuide()
                    },
                    onCancel: {
                        showingSkipConfirmation = false
                    }
                )
            }
        }
        .transition(.opacity)
        .zIndex(1000)
    }
    
    // MARK: - 欢迎界面遮罩
    
    private var welcomeMask: some View {
        ZStack {
            // 半透明背景 + 底部高亮
            GeometryReader { geometry in
                ZStack {
                    // 半透明背景
                    Color.black
                        .opacity(0.5)
                        .ignoresSafeArea()
                    
                    // 底部小猫位置挖空
                    Circle()
                        .frame(width: 100, height: 100)
                        .position(guideManager.floatingCatStartPosition)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            
            // 欢迎气泡
            VStack {
                Spacer()
                
                WelcomeBubbleView(
                    onStart: {
                        guideManager.startRunningAnimation()
                    },
                    onSkip: {
                        showingSkipConfirmation = true
                    }
                )
                .padding(.bottom, 160)
            }
        }
    }
    
    // MARK: - 跑步动画遮罩
    
    private var runningMask: some View {
        ZStack {
            // 半透明背景（无挖空，小猫在遮罩层之上跑动）
            Color.black
                .opacity(0.3)
                .ignoresSafeArea()
            
            // 跑步小猫
            if guideManager.isRunningAnimation {
                let needsFlip = guideManager.catPosition.x < UIScreen.main.bounds.width / 2
                
                GuideCatVideoPlayer(
                    videoName: guideManager.runningVideoName,
                    isLooping: true,
                    isFlipped: needsFlip,
                    onFinished: nil
                )
                .position(guideManager.catPosition)
            }
        }
    }
    
    // MARK: - 指向动画遮罩
    
    private var pointingMask: some View {
        ZStack {
            // 带挖空的半透明背景 - 右上角创建按钮位置挖空，允许点击穿透
            GeometryReader { geometry in
                ZStack {
                    // 半透明背景
                    Color.black
                        .opacity(0.4)
                        .ignoresSafeArea()
                    
                    // 创建按钮位置挖空 - 允许点击穿透到底层
                    Circle()
                        .frame(width: 80, height: 80)
                        .position(guideManager.highlightCirclePosition)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                // 允许点击穿透到挖空区域
                .allowsHitTesting(false)
            }
            
            // 指向小猫（不循环，停在最后一帧）- 使用小猫终点位置
            if guideManager.showPointingVideo {
                GuideCatVideoPlayer(
                    videoName: guideManager.pointingVideoName,
                    isLooping: false,  // 不循环
                    isFlipped: false,   // 指向右上角不需要翻转
                    onFinished: nil     // 停在最后一帧
                )
                .position(guideManager.createButtonPosition)
                // 小猫视频不阻挡点击
                .allowsHitTesting(false)
            }
            
            // 创建按钮高亮（仅视觉，不拦截点击）- 使用独立的高亮圈位置
            if guideManager.showCreateButtonHighlight {
                HighlightPulseViewNoClick(
                    center: guideManager.highlightCirclePosition,
                    radius: 35
                )
                // 高亮不阻挡点击
                .allowsHitTesting(false)
            }
            
            // 提示气泡（气泡本身需要拦截点击）
            VStack {
                Spacer()
                
                PointingBubbleView(
                    onSkip: {
                        showingSkipConfirmation = true
                    },
                    onComplete: {
                        guideManager.completeGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }
}

// MARK: - View Extension

extension View {
    func withAppFirstLaunchGuide() -> some View {
        modifier(AppFirstLaunchGuideModifier())
    }
}

// MARK: - App首次启动引导修饰器

struct AppFirstLaunchGuideModifier: ViewModifier {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            if guideManager.isShowingGuide {
                AppFirstLaunchGuideOverlay()
            }

            if guideManager.isShowingFeatureExperienceGuide {
                FeatureExperienceGuideOverlay()
            }
        }
    }
}

// MARK: - 萌宠智能对话引导步骤

enum AIAnalysisGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1  // 返回「我」界面
    case step2_clickVIP = 2    // 点击VIP卡片
    case step3_exchange = 3    // 兑换会员时长
    
    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_clickVIP: return "点击VIP卡片"
        case .step3_exchange: return "兑换会员时长"
        }
    }
    
    var message: String {
        switch self {
        case .step1_returnToMe: return "首先，请返回到「我」界面，我们将引导你开通VIP会员"
        case .step2_clickVIP: return "点击VIP会员卡片，进入会员中心"
        case .step3_exchange: return "点击「兑换会员时长」，使用喵币兑换VIP天数"
        }
    }
    
    var bubblePosition: BubblePosition {
        switch self {
        case .step1_returnToMe: return .bottom
        case .step2_clickVIP: return .bottom
        case .step3_exchange: return .top
        }
    }
    
    var highlightType: HighlightType {
        switch self {
        case .step1_returnToMe: return .circle
        case .step2_clickVIP: return .roundedRect
        case .step3_exchange: return .roundedRect
        }
    }
    
    var showCatPaw: Bool {
        switch self {
        case .step1_returnToMe: return true
        case .step2_clickVIP: return false
        case .step3_exchange: return true
        }
    }
}

// MARK: - 小组件定制引导步骤

enum WidgetCustomizeGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_scrollToWidget = 2
    case step3_clickWidgetEntry = 3
    case step4_widgetExplanation = 4

    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_scrollToWidget: return "下滑找到小组件"
        case .step3_clickWidgetEntry: return "点击小组件豆腐块"
        case .step4_widgetExplanation: return "认识小组件设置"
        }
    }

    var message: String {
        switch self {
        case .step1_returnToMe:
            return "先返回到「我」界面，我们带你找到小组件入口。"
        case .step2_scrollToWidget:
            return "请继续向下滑动，在下方的设置豆腐块区域里找到「小组件」入口。"
        case .step3_clickWidgetEntry:
            return "点击「小组件」豆腐块，进入小组件背景和教程页面。"
        case .step4_widgetExplanation:
            return "这里可以分别设置小、中、大组件背景，也能查看桌面添加教程。看完后就可以去主屏幕添加你的小组件啦。"
        }
    }

    var showCatPaw: Bool {
        switch self {
        case .step1_returnToMe, .step3_clickWidgetEntry:
            return true
        case .step2_scrollToWidget, .step4_widgetExplanation:
            return false
        }
    }
}

// MARK: - 右上角创建菜单引导步骤

enum WardrobeAddGuideStep: Int, CaseIterable {
    case step1_clickAddButton = 1
    case step2_chooseTargetOption = 2
}

// MARK: - 魔法配色引导步骤

enum ThemeCustomizeGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_scrollToThemeEntry = 2
    case step3_clickThemeEntry = 3
    case step4_switchToMagicTab = 4
    case step5_magicThemeExplanation = 5
}

// MARK: - 本地文件备份与恢复引导步骤

enum LocalFileBackupRestoreGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_scrollToSystemSettings = 2
    case step3_clickSystemSettings = 3
    case step4_clickBackupRestoreEntry = 4
}

// MARK: - 导出表格引导步骤

enum ExportCSVGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_scrollToSystemSettings = 2
    case step3_clickSystemSettings = 3
    case step4_clickExportCSV = 4
}

// MARK: - 云端文件备份与恢复引导步骤

enum CloudFileBackupRestoreGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_clickAccountSync = 2
    case step3_signInAppleID = 3
    case step4_cloudBackupExplanation = 4
    case step5_realtimeSyncDelayExplanation = 5
}

// MARK: - 个性化偏好引导步骤

enum PersonalPreferenceGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_clickWardrobeEntry = 2
    case step3_interfaceStyle = 3
    case step4_filterMode = 4
    case step5_appAppearance = 5
}

// MARK: - 隐私显示引导步骤

enum PrivacyDisplayGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_clickWardrobeEntry = 2
    case step3_showPurchasePrice = 3
    case step4_showOriginalPrice = 4
}

// MARK: - 标签/品牌/属性字段引导步骤

enum TagBrandFieldGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_clickWardrobeEntry = 2
    case step3_scrollToManagementEntries = 3
    case step4_tagManagement = 4
    case step5_brandManagement = 5
    case step6_fieldManagement = 6
}

// MARK: - 穿搭手帐引导步骤

enum OOTDGuideStep: Int, CaseIterable {
    case step1_clickOotdEntry = 1
    case step2_ootdExplanation = 2
}

// MARK: - 梦裙日历引导步骤

enum CalendarGuideStep: Int, CaseIterable {
    case step1_clickCalendarEntry = 1
    case step2_calendarExplanation = 2
}

// MARK: - 魔法贴纸引导步骤

enum MagicStickerGuideStep: Int, CaseIterable {
    case step1_longPressHouseTab = 1
    case step2_clickMagicStickerEntry = 2
    case step3_magicStickerExplanation = 3
}

// MARK: - 批量编辑引导步骤

enum BatchEditGuideStep: Int, CaseIterable {
    case step1_clickMoreMenu = 1
    case step2_selectOneCard = 2
    case step3_toolbarExplanation = 3
    case step4_finishSelection = 4
}

// MARK: - 空间手帐引导步骤

enum SpaceBookGuideStep: Int, CaseIterable {
    case step1_clickWardrobeOotdEntry = 1
    case step2_switchToSpaceTab = 2
    case step3_createSpaceBook = 3
    case step4_createFirstPage = 4
    case step5_open3DEditor = 5
    case step6_openScanner = 6
    case step7_scannerHowTo = 7
}

// MARK: - 来财引导步骤

enum WealthGuideStep: Int, CaseIterable {
    case step1_clickHouseTab = 1
    case step2_clickWealthEntry = 2
    case step3_divination = 3
    case step4_moneyCounting = 4
    case step5_wealthStorage = 5
    
    var title: String {
        switch self {
        case .step1_clickHouseTab: return "先进入 House"
        case .step2_clickWealthEntry: return "点击「马上来财」"
        case .step3_divination: return "请签功能"
        case .step4_moneyCounting: return "数钱功能"
        case .step5_wealthStorage: return "安财功能"
        }
    }
    
    var message: String {
        switch self {
        case .step1_clickHouseTab:
            return "先点击底部的 House 页签，我们从场景入口开始引导。"
        case .step2_clickWealthEntry:
            return "在 House 场景里点击「马上来财」入口，进入来财功能。"
        case .step3_divination:
            return "「请签」可查看今日运势与建议，适合每日打卡。"
        case .step4_moneyCounting:
            return "「数钱」是沉浸式数钞体验，能快速放松心情。"
        case .step5_wealthStorage:
            return "「安财」可管理财富展示与资产状态。"
        }
    }
    
    var showCatPaw: Bool {
        switch self {
        case .step1_clickHouseTab, .step2_clickWealthEntry:
            return true
        default:
            return false
        }
    }
}

enum HighlightType {
    case circle
    case roundedRect
}

// MARK: - 功能体验引导遮罩视图

struct FeatureExperienceGuideOverlay: View {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showingFullDescription = false
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    // 跨页面引导专用状态
    @State private var aiAnalysisStep: AIAnalysisGuideStep = .step1_returnToMe
    @State private var widgetCustomizeStep: WidgetCustomizeGuideStep = .step1_returnToMe
    @State private var wardrobeAddGuideStep: WardrobeAddGuideStep = .step1_clickAddButton
    @State private var themeCustomizeGuideStep: ThemeCustomizeGuideStep = .step1_returnToMe
    @State private var localFileBackupRestoreGuideStep: LocalFileBackupRestoreGuideStep = .step1_returnToMe
    @State private var exportCSVGuideStep: ExportCSVGuideStep = .step1_returnToMe
    @State private var cloudFileBackupRestoreGuideStep: CloudFileBackupRestoreGuideStep = .step1_returnToMe
    @State private var themeScrollStepStartedAt: Date? = nil
    @State private var personalPreferenceGuideStep: PersonalPreferenceGuideStep = .step1_returnToMe
    @State private var privacyDisplayGuideStep: PrivacyDisplayGuideStep = .step1_returnToMe
    @State private var tagBrandFieldGuideStep: TagBrandFieldGuideStep = .step1_returnToMe
    @State private var ootdGuideStep: OOTDGuideStep = .step1_clickOotdEntry
    @State private var calendarGuideStep: CalendarGuideStep = .step1_clickCalendarEntry
    @State private var magicStickerGuideStep: MagicStickerGuideStep = .step1_longPressHouseTab
    @State private var batchEditGuideStep: BatchEditGuideStep = .step1_clickMoreMenu
    @State private var spaceBookGuideStep: SpaceBookGuideStep = .step1_clickWardrobeOotdEntry
    @State private var wealthGuideStep: WealthGuideStep = .step1_clickHouseTab
    @State private var currentTab: String = "wardrobe"

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        bindGuideEvents(
            ZStack {
                // 半透明背景 - 允许点击穿透（具体内容的遮罩各自控制）
                Color.black
                    .opacity(0.5)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if let feature = guideManager.currentFeatureExperienceFeature {
                    // 根据功能显示不同的引导内容
                    guideContent(for: feature)
                }
            }
            .transition(.opacity)
            .zIndex(1000)
        )
    }

    private func bindGuideEvents<Content: View>(_ content: Content) -> some View {
        let lifecycleBound = bindLifecycleEvents(content)
        let tabBound = bindTabAndDismissEvents(lifecycleBound)
        let settingsBound = bindSettingsGuideEvents(tabBound)
        let wardrobeBound = bindWardrobeGuideEvents(settingsBound)
        let houseBound = bindHouseGuideEvents(wardrobeBound)
        let wealthBound = bindWealthGuideEvents(houseBound)
        let frameBound = bindFrameDrivenEvents(wealthBound)

        return frameBound
            .onChange(of: guideManager.currentFeatureExperienceFeature?.rawValue) { _, _ in
                resetGuideStepState()
            }
    }

    private func bindLifecycleEvents<Content: View>(_ content: Content) -> some View {
        content.onAppear {
            print("[FeatureExperienceGuide] onAppear, feature: \(guideManager.currentFeatureExperienceFeature?.rawValue ?? "nil")")
            currentTab = guideManager.lastKnownHomeTab
            resetGuideStepState()
        }
    }

    private func bindTabAndDismissEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .homeTabChanged)) { notification in
                guard let tab = notification.userInfo?["tab"] as? String else { return }
                currentTab = tab
                print("[FeatureExperienceGuide] Tab切换到: \(tab), aiStep: \(aiAnalysisStep), wealthStep: \(wealthGuideStep)")

                if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                   aiAnalysisStep == .step1_returnToMe,
                   tab == "me",
                   guideManager.guideTargetFrame(for: .aiAnalysisVIPCard) != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .step2_clickVIP
                    }
                }

                if guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                   widgetCustomizeStep == .step1_returnToMe,
                   tab == "me" {
                    advanceWidgetGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .themeCustomize,
                   themeCustomizeGuideStep == .step1_returnToMe,
                   tab == "me" {
                    advanceThemeGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                   localFileBackupRestoreGuideStep == .step1_returnToMe,
                   tab == "me" {
                    advanceLocalFileBackupRestoreGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .exportCSV,
                   exportCSVGuideStep == .step1_returnToMe,
                   tab == "me" {
                    advanceExportCSVGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore,
                   cloudFileBackupRestoreGuideStep == .step1_returnToMe,
                   tab == "me" {
                    advanceCloudFileBackupRestoreGuideFromReturnStep()
                }

                if guideManager.currentFeatureExperienceFeature == .wealth,
                   wealthGuideStep == .step1_clickHouseTab,
                   tab == "smallWorld" {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        wealthGuideStep = .step2_clickWealthEntry
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .magicTasksViewDismissed)) { _ in
                if guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                   widgetCustomizeStep == .step1_returnToMe {
                    advanceWidgetGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .themeCustomize,
                   themeCustomizeGuideStep == .step1_returnToMe {
                    advanceThemeGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                   localFileBackupRestoreGuideStep == .step1_returnToMe {
                    advanceLocalFileBackupRestoreGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .exportCSV,
                   exportCSVGuideStep == .step1_returnToMe {
                    advanceExportCSVGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore,
                   cloudFileBackupRestoreGuideStep == .step1_returnToMe {
                    advanceCloudFileBackupRestoreGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .filterClassic,
                   personalPreferenceGuideStep == .step1_returnToMe {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        personalPreferenceGuideStep = .step2_clickWardrobeEntry
                    }
                }
                if guideManager.currentFeatureExperienceFeature == .privacyDisplay,
                   privacyDisplayGuideStep == .step1_returnToMe {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        privacyDisplayGuideStep = .step2_clickWardrobeEntry
                    }
                }
                if guideManager.currentFeatureExperienceFeature == .tagBrandFieldDisplay,
                   tagBrandFieldGuideStep == .step1_returnToMe {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        tagBrandFieldGuideStep = .step2_clickWardrobeEntry
                    }
                }
            }
    }

    private func bindSettingsGuideEvents<Content: View>(_ content: Content) -> some View {
        let vipAndThemeBound = bindSettingsVIPAndThemeEvents(content)
        let wardrobeBound = bindSettingsWardrobeEvents(vipAndThemeBound)
        let systemBound = bindSettingsSystemEvents(wardrobeBound)
        let cloudBound = bindSettingsCloudEvents(systemBound)
        return cloudBound
    }

    private func bindSettingsVIPAndThemeEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .vipCenterOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                   aiAnalysisStep == .step2_clickVIP {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .step3_exchange
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .widgetSettingsOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                   widgetCustomizeStep.rawValue < WidgetCustomizeGuideStep.step4_widgetExplanation.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        widgetCustomizeStep = .step4_widgetExplanation
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .magicColorSettingsOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .themeCustomize,
                   themeCustomizeGuideStep.rawValue < ThemeCustomizeGuideStep.step4_switchToMagicTab.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        themeCustomizeGuideStep = .step4_switchToMagicTab
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .magicColorModeChanged)) { notification in
                guard let mode = notification.userInfo?["mode"] as? String else { return }
                if guideManager.currentFeatureExperienceFeature == .themeCustomize,
                   themeCustomizeGuideStep == .step4_switchToMagicTab,
                   mode == ColorSchemeMode.magic.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        themeCustomizeGuideStep = .step5_magicThemeExplanation
                    }
                }
            }
    }

    private func bindSettingsWardrobeEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeSettingsOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .filterClassic,
                   personalPreferenceGuideStep.rawValue < PersonalPreferenceGuideStep.step3_interfaceStyle.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        personalPreferenceGuideStep = .step3_interfaceStyle
                    }
                }
                if guideManager.currentFeatureExperienceFeature == .privacyDisplay,
                   privacyDisplayGuideStep.rawValue < PrivacyDisplayGuideStep.step3_showPurchasePrice.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        privacyDisplayGuideStep = .step3_showPurchasePrice
                    }
                }
                if guideManager.currentFeatureExperienceFeature == .tagBrandFieldDisplay,
                   tagBrandFieldGuideStep.rawValue < TagBrandFieldGuideStep.step3_scrollToManagementEntries.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        tagBrandFieldGuideStep = .step3_scrollToManagementEntries
                    }
                }
            }
    }

    private func bindSettingsSystemEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .systemSettingsOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                   localFileBackupRestoreGuideStep == .step3_clickSystemSettings {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        localFileBackupRestoreGuideStep = .step4_clickBackupRestoreEntry
                    }
                }
                if guideManager.currentFeatureExperienceFeature == .exportCSV,
                   exportCSVGuideStep == .step3_clickSystemSettings {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        exportCSVGuideStep = .step4_clickExportCSV
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataBackupManagementOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                   localFileBackupRestoreGuideStep.rawValue >= LocalFileBackupRestoreGuideStep.step3_clickSystemSettings.rawValue {
                    guideManager.completeFeatureExperienceGuide()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportCSVTriggered)) { _ in
                if guideManager.currentFeatureExperienceFeature == .exportCSV,
                   exportCSVGuideStep.rawValue >= ExportCSVGuideStep.step3_clickSystemSettings.rawValue {
                    guideManager.completeFeatureExperienceGuide()
                }
            }
    }

    private func bindSettingsCloudEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .cloudSyncSheetOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore,
                   cloudFileBackupRestoreGuideStep == .step2_clickAccountSync {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        cloudFileBackupRestoreGuideStep = authManager.isAuthenticated ? .step4_cloudBackupExplanation : .step3_signInAppleID
                    }
                }
            }
            .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                guard isAuthenticated else { return }
                if guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore,
                   cloudFileBackupRestoreGuideStep == .step3_signInAppleID {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        cloudFileBackupRestoreGuideStep = .step4_cloudBackupExplanation
                    }
                }
            }
    }

    private func bindWardrobeGuideEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeAddMenuOpened)) { _ in
                advanceWardrobeAddGuideToChooseOptionIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeManualCreateOpened)) { _ in
                guard let feature = guideManager.currentFeatureExperienceFeature else { return }
                if acceptsManualCreateGuideCompletion(for: feature) {
                    guideManager.completeFeatureExperienceGuide()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeBatchImportOpened)) { _ in
                guard let feature = guideManager.currentFeatureExperienceFeature else { return }
                if acceptsBatchImportGuideCompletion(for: feature) {
                    guideManager.completeFeatureExperienceGuide()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeSelectionModeChanged)) { notification in
                let isSelectionMode = notification.userInfo?["isSelectionMode"] as? Bool ?? false
                if guideManager.currentFeatureExperienceFeature == .batchEdit,
                   batchEditGuideStep == .step1_clickMoreMenu,
                   isSelectionMode {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        batchEditGuideStep = .step2_selectOneCard
                    }
                } else if guideManager.currentFeatureExperienceFeature == .batchEdit,
                          batchEditGuideStep == .step4_finishSelection,
                          !isSelectionMode {
                    guideManager.completeFeatureExperienceGuide()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeSelectionChanged)) { notification in
                let selectedCount = notification.userInfo?["selectedCount"] as? Int ?? 0
                if guideManager.currentFeatureExperienceFeature == .batchEdit,
                   batchEditGuideStep == .step2_selectOneCard,
                   selectedCount > 0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        batchEditGuideStep = .step3_toolbarExplanation
                    }
                }
            }
    }

    private func bindHouseGuideEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .ootdShelfOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .ootd,
                   ootdGuideStep == .step1_clickOotdEntry {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        ootdGuideStep = .step2_ootdExplanation
                    }
                }
                if guideManager.currentFeatureExperienceFeature == .spaceBook,
                   spaceBookGuideStep == .step1_clickWardrobeOotdEntry {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step2_switchToSpaceTab
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dreamDressCalendarOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .calendar,
                   calendarGuideStep == .step1_clickCalendarEntry {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        calendarGuideStep = .step2_calendarExplanation
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .smallWorldQuickMenuOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .ootdDefaultBook,
                   magicStickerGuideStep == .step1_longPressHouseTab {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        magicStickerGuideStep = .step2_clickMagicStickerEntry
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ootdDefaultBookOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .ootdDefaultBook,
                   magicStickerGuideStep.rawValue < MagicStickerGuideStep.step3_magicStickerExplanation.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        magicStickerGuideStep = .step3_magicStickerExplanation
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .spatialBookShelfOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .spaceBook,
                   spaceBookGuideStep == .step2_switchToSpaceTab {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step3_createSpaceBook
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookDetailOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .spaceBook,
                   spaceBookGuideStep == .step3_createSpaceBook {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step4_createFirstPage
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookPageCreated)) { _ in
                if guideManager.currentFeatureExperienceFeature == .spaceBook,
                   spaceBookGuideStep == .step4_createFirstPage {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step5_open3DEditor
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .spatialCanvasEditorOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .spaceBook,
                   spaceBookGuideStep == .step5_open3DEditor {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step6_openScanner
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .objectCaptureScannerOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .spaceBook,
                   spaceBookGuideStep == .step6_openScanner {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step7_scannerHowTo
                    }
                }
            }
    }

    private func bindWealthGuideEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .wealthDestinationOpened)) { _ in
                advanceWealthToMainTabGuideIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wealthViewOpened)) { _ in
                advanceWealthToMainTabGuideIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wealthMainTabChanged)) { notification in
                guard let tab = notification.userInfo?["tab"] as? String else { return }
                handleWealthMainTabChanged(tab)
            }
    }

    private func bindFrameDrivenEvents<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: guideManager.aiAnalysisVIPCardGlobalFrame) { _, vipCardFrame in
                if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                   aiAnalysisStep == .step1_returnToMe,
                   vipCardFrame != nil {
                    print("[FeatureExperienceGuide] 检测到VIP卡片位置，step1进入step2")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .step2_clickVIP
                    }
                }
            }
            .onChange(of: guideManager.widgetCustomizeEntryGlobalFrame) { _, widgetEntryFrame in
                if guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                   widgetCustomizeStep.rawValue <= WidgetCustomizeGuideStep.step2_scrollToWidget.rawValue,
                   widgetEntryFrame != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        widgetCustomizeStep = .step3_clickWidgetEntry
                    }
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .favoriteMenuMagicStickerEntry)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .ootdDefaultBook,
                   magicStickerGuideStep == .step1_longPressHouseTab,
                   frame != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        magicStickerGuideStep = .step2_clickMagicStickerEntry
                    }
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .wealthMainTabSegment)) { _, segmentFrame in
                if guideManager.currentFeatureExperienceFeature == .wealth,
                   wealthGuideStep == .step2_clickWealthEntry,
                   segmentFrame != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        wealthGuideStep = .step3_divination
                    }
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .wardrobeManualCreateEntry)) { _, frame in
                if frame != nil {
                    advanceWardrobeAddGuideToChooseOptionIfNeeded()
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .wardrobeBatchImportEntry)) { _, frame in
                if frame != nil {
                    advanceWardrobeAddGuideToChooseOptionIfNeeded()
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .systemSettingsEntry)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                   localFileBackupRestoreGuideStep == .step2_scrollToSystemSettings,
                   let frame,
                   isGuideTargetVisibleOnScreen(frame) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        localFileBackupRestoreGuideStep = .step3_clickSystemSettings
                    }
                }
                if guideManager.currentFeatureExperienceFeature == .exportCSV,
                   exportCSVGuideStep == .step2_scrollToSystemSettings,
                   let frame,
                   isGuideTargetVisibleOnScreen(frame) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        exportCSVGuideStep = .step3_clickSystemSettings
                    }
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .localFileBackupRestoreEntry)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                   localFileBackupRestoreGuideStep == .step3_clickSystemSettings,
                   frame != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        localFileBackupRestoreGuideStep = .step4_clickBackupRestoreEntry
                    }
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .exportCSVEntry)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .exportCSV,
                   exportCSVGuideStep == .step3_clickSystemSettings,
                   frame != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        exportCSVGuideStep = .step4_clickExportCSV
                    }
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .themeCustomizeEntry)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .themeCustomize,
                   themeCustomizeGuideStep == .step2_scrollToThemeEntry,
                   frame != nil {
                    advanceThemeGuideToClickStepWithMinimumDwell()
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .wardrobeTagManagementEntry)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .tagBrandFieldDisplay,
                   tagBrandFieldGuideStep == .step3_scrollToManagementEntries,
                   let frame,
                   isGuideTargetVisibleOnScreen(frame) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        tagBrandFieldGuideStep = .step4_tagManagement
                    }
                }
            }
    }

    @ViewBuilder
    private func guideContent(for feature: FeatureItem) -> some View {
        switch feature {
        case .dataBackup:
            backupGuideContent
        case .cloudSync:
            cloudSyncGuideContent
        case .batchImport:
            batchImportGuideContent
        case .themeCustomize:
            themeGuideContent
        case .localFileBackupRestore:
            localFileBackupRestoreGuideContent
        case .exportCSV:
            exportCSVGuideContent
        case .cloudFileBackupRestore:
            cloudFileBackupRestoreGuideContent
        case .widgetCustomize:
            widgetCustomizeGuideContent
        case .filterClassic:
            filterClassicGuideContent
        case .privacyDisplay:
            privacyDisplayGuideContent
        case .tagBrandFieldDisplay:
            tagBrandFieldGuideContent
        case .spaceBook:
            spaceBookGuideContent
        case .batchEdit:
            batchEditGuideContent
        case .ootd:
            ootdGuideContent
        case .ootdDefaultBook:
            magicStickerGuideContent
        case .calendar:
            calendarGuideContent
        case .wealth:
            wealthGuideContent
        case .aiAnalysis:
            aiAnalysisGuideContent
        default:
            genericGuideContent(for: feature)
        }
    }

    private func resetGuideStepState() {
        guard let feature = guideManager.currentFeatureExperienceFeature else { return }
        showingFullDescription = false
        themeScrollStepStartedAt = nil

        switch feature {
        case .aiAnalysis:
            aiAnalysisStep = .step1_returnToMe
            if guideManager.lastKnownHomeTab == "me",
               guideManager.guideTargetFrame(for: .aiAnalysisVIPCard) != nil {
                aiAnalysisStep = .step2_clickVIP
            }
        case .widgetCustomize:
            widgetCustomizeStep = .step1_returnToMe
        case .themeCustomize:
            themeCustomizeGuideStep = .step1_returnToMe
        case .localFileBackupRestore:
            localFileBackupRestoreGuideStep = .step1_returnToMe
        case .exportCSV:
            exportCSVGuideStep = .step1_returnToMe
        case .cloudFileBackupRestore:
            cloudFileBackupRestoreGuideStep = .step1_returnToMe
        case .filterClassic:
            personalPreferenceGuideStep = .step1_returnToMe
        case .privacyDisplay:
            privacyDisplayGuideStep = .step1_returnToMe
        case .tagBrandFieldDisplay:
            tagBrandFieldGuideStep = .step1_returnToMe
        case .batchImport:
            wardrobeAddGuideStep = .step1_clickAddButton
        case .ootdDefaultBook:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                magicStickerGuideStep = .step1_longPressHouseTab
            } else {
                wardrobeAddGuideStep = .step1_clickAddButton
            }
        case .ootd:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                ootdGuideStep = .step1_clickOotdEntry
            } else {
                wardrobeAddGuideStep = .step1_clickAddButton
            }
        case .calendar:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                calendarGuideStep = .step1_clickCalendarEntry
            } else {
                wardrobeAddGuideStep = .step1_clickAddButton
            }
        case .spaceBook:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                spaceBookGuideStep = .step1_clickWardrobeOotdEntry
            } else {
                wardrobeAddGuideStep = .step1_clickAddButton
            }
        case .batchEdit:
            batchEditGuideStep = .step1_clickMoreMenu
        case .wealth:
            wealthGuideStep = .step1_clickHouseTab
            // 兜底：如果当前已经在 House / 来财页面，则直接推进到对应步骤
            if guideManager.guideTargetFrame(for: .wealthEntry) != nil {
                wealthGuideStep = .step2_clickWealthEntry
            }
            if guideManager.guideTargetFrame(for: .wealthMainTabSegment) != nil {
                wealthGuideStep = .step3_divination
            }
        default:
            break
        }
    }

    private func advanceWealthToMainTabGuideIfNeeded() {
        guard guideManager.currentFeatureExperienceFeature == .wealth else { return }
        guard wealthGuideStep.rawValue < WealthGuideStep.step3_divination.rawValue else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            wealthGuideStep = .step3_divination
        }
    }

    private func advanceWidgetGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .widgetCustomize else { return }
        guard widgetCustomizeStep == .step1_returnToMe else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            widgetCustomizeStep = .step2_scrollToWidget
        }

        if guideManager.guideTargetFrame(for: .widgetCustomizeEntry) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                      widgetCustomizeStep == .step2_scrollToWidget else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    widgetCustomizeStep = .step3_clickWidgetEntry
                }
            }
        }
    }

    private func advanceThemeGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .themeCustomize else { return }
        guard themeCustomizeGuideStep == .step1_returnToMe else { return }

        themeScrollStepStartedAt = Date()
        withAnimation(.easeInOut(duration: 0.3)) {
            themeCustomizeGuideStep = .step2_scrollToThemeEntry
        }

        if guideManager.guideTargetFrame(for: .themeCustomizeEntry) != nil {
            advanceThemeGuideToClickStepWithMinimumDwell()
        }
    }

    private func advanceLocalFileBackupRestoreGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .localFileBackupRestore else { return }
        guard localFileBackupRestoreGuideStep == .step1_returnToMe else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            localFileBackupRestoreGuideStep = .step2_scrollToSystemSettings
        }

        if let frame = guideManager.guideTargetFrame(for: .systemSettingsEntry),
           isGuideTargetVisibleOnScreen(frame) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                      localFileBackupRestoreGuideStep == .step2_scrollToSystemSettings else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    localFileBackupRestoreGuideStep = .step3_clickSystemSettings
                }
            }
        }
    }

    private func advanceExportCSVGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .exportCSV else { return }
        guard exportCSVGuideStep == .step1_returnToMe else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            exportCSVGuideStep = .step2_scrollToSystemSettings
        }

        if let frame = guideManager.guideTargetFrame(for: .systemSettingsEntry),
           isGuideTargetVisibleOnScreen(frame) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard guideManager.currentFeatureExperienceFeature == .exportCSV,
                      exportCSVGuideStep == .step2_scrollToSystemSettings else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    exportCSVGuideStep = .step3_clickSystemSettings
                }
            }
        }
    }

    private func advanceCloudFileBackupRestoreGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore else { return }
        guard cloudFileBackupRestoreGuideStep == .step1_returnToMe else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            cloudFileBackupRestoreGuideStep = .step2_clickAccountSync
        }
    }

    private func advanceThemeGuideToClickStepWithMinimumDwell(minimumDwell: TimeInterval = 2.0) {
        guard guideManager.currentFeatureExperienceFeature == .themeCustomize else { return }
        guard themeCustomizeGuideStep == .step2_scrollToThemeEntry else { return }

        let start = themeScrollStepStartedAt ?? Date()
        if themeScrollStepStartedAt == nil {
            themeScrollStepStartedAt = start
        }

        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, minimumDwell - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            guard guideManager.currentFeatureExperienceFeature == .themeCustomize,
                  themeCustomizeGuideStep == .step2_scrollToThemeEntry else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                themeCustomizeGuideStep = .step3_clickThemeEntry
            }
            themeScrollStepStartedAt = nil
        }
    }

    private func isGuideTargetVisibleOnScreen(_ frame: CGRect) -> Bool {
        let visibleBounds = UIScreen.main.bounds.insetBy(dx: 0, dy: 120)
        return frame.width > 1 &&
        frame.height > 1 &&
        frame.maxY > visibleBounds.minY &&
        frame.minY < visibleBounds.maxY
    }

    private func advanceWardrobeAddGuideToChooseOptionIfNeeded() {
        guard wardrobeAddGuideStep == .step1_clickAddButton else { return }
        guard let feature = guideManager.currentFeatureExperienceFeature else { return }
        guard feature == .batchImport || usesPreUnlockWardrobeGuide(for: feature) else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            wardrobeAddGuideStep = .step2_chooseTargetOption
        }
    }

    private func handleWidgetGuideReturnAction() {
        guard guideManager.currentFeatureExperienceFeature == .widgetCustomize else { return }
        guard widgetCustomizeStep == .step1_returnToMe else { return }

        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                  widgetCustomizeStep == .step1_returnToMe,
                  guideManager.lastKnownHomeTab == "me" else { return }
            advanceWidgetGuideFromReturnStep()
        }
    }

    private func handleLocalFileBackupRestoreGuideReturnAction() {
        guard guideManager.currentFeatureExperienceFeature == .localFileBackupRestore else { return }
        guard localFileBackupRestoreGuideStep == .step1_returnToMe else { return }

        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                  localFileBackupRestoreGuideStep == .step1_returnToMe,
                  guideManager.lastKnownHomeTab == "me" else { return }
            advanceLocalFileBackupRestoreGuideFromReturnStep()
        }
    }

    private func handleExportCSVGuideReturnAction() {
        guard guideManager.currentFeatureExperienceFeature == .exportCSV else { return }
        guard exportCSVGuideStep == .step1_returnToMe else { return }

        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard guideManager.currentFeatureExperienceFeature == .exportCSV,
                  exportCSVGuideStep == .step1_returnToMe,
                  guideManager.lastKnownHomeTab == "me" else { return }
            advanceExportCSVGuideFromReturnStep()
        }
    }

    private func handleCloudFileBackupRestoreGuideReturnAction() {
        guard guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore else { return }
        guard cloudFileBackupRestoreGuideStep == .step1_returnToMe else { return }

        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore,
                  cloudFileBackupRestoreGuideStep == .step1_returnToMe,
                  guideManager.lastKnownHomeTab == "me" else { return }
            advanceCloudFileBackupRestoreGuideFromReturnStep()
        }
    }

    private func handleWealthMainTabChanged(_ tab: String) {
        guard guideManager.currentFeatureExperienceFeature == .wealth else { return }

        let targetStep: WealthGuideStep
        switch tab {
        case WealthMainTab.divination.rawValue:
            targetStep = .step3_divination
        case WealthMainTab.moneyCounting.rawValue:
            targetStep = .step4_moneyCounting
        case WealthMainTab.wealthStorage.rawValue:
            targetStep = .step5_wealthStorage
        default:
            return
        }

        guard targetStep.rawValue > wealthGuideStep.rawValue else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            wealthGuideStep = targetStep
        }
    }

    private func usesPreUnlockWardrobeGuide(for feature: FeatureItem) -> Bool {
        !FeatureUnlockManager.shared.isUnlocked(feature) &&
        [.ootd, .ootdDefaultBook, .calendar, .batchImport, .spaceBook].contains(feature)
    }

    private func acceptsManualCreateGuideCompletion(for feature: FeatureItem) -> Bool {
        switch feature {
        case .batchImport:
            return !FeatureUnlockManager.shared.isUnlocked(feature)
        case .ootd, .ootdDefaultBook, .calendar, .spaceBook:
            return usesPreUnlockWardrobeGuide(for: feature)
        default:
            return false
        }
    }

    private func acceptsBatchImportGuideCompletion(for feature: FeatureItem) -> Bool {
        switch feature {
        case .batchImport:
            return FeatureUnlockManager.shared.isUnlocked(feature)
        case .ootd, .ootdDefaultBook, .calendar, .spaceBook:
            return usesPreUnlockWardrobeGuide(for: feature)
        default:
            return false
        }
    }

    private var currentWardrobeGuideStep1Message: String {
        guard let feature = guideManager.currentFeatureExperienceFeature else { return "先点击衣橱右上角的 + 号，展开创建菜单。" }
        switch feature {
        case .ootd:
            return "先点击衣橱右上角的 + 号，展开创建菜单。"
        case .ootdDefaultBook:
            return "先点击衣橱右上角的 + 号，展开创建菜单。"
        case .calendar:
            return "先点击衣橱右上角的 + 号，展开创建菜单。"
        case .spaceBook:
            return "先点击衣橱右上角的 + 号，展开创建菜单。"
        case .batchImport:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                return "先点击右上角 + 号，展开菜单。"
            } else {
                return "解锁前先点击右上角 + 号，展开菜单。"
            }
        default:
            return "先点击衣橱右上角的 + 号，展开创建菜单。"
        }
    }

    private var currentWardrobeGuideStep2Title: String {
        guard let feature = guideManager.currentFeatureExperienceFeature else { return "选择创建方式" }
        if feature == .batchImport {
            return FeatureUnlockManager.shared.isUnlocked(feature) ? "点击「批量导入」" : "点击「手动创建」"
        }
        return "选择创建方式"
    }

    private var currentWardrobeGuideStep2Message: String {
        guard let feature = guideManager.currentFeatureExperienceFeature else { return "在展开菜单中选择创建方式，继续完成任务。" }
        switch feature {
        case .ootd:
            return "在菜单里选择「手动创建」或「批量导入」任一方式，先把裙子准备好，后面就能解锁穿搭手帐。"
        case .ootdDefaultBook:
            return "在菜单里选择「手动创建」或「批量导入」任一方式，先准备几件裙子，魔法贴纸体验会更完整。"
        case .calendar:
            return "在菜单里选择「手动创建」或「批量导入」任一方式，先录入裙子，梦裙日历才会有内容。"
        case .spaceBook:
            return "在菜单里选择「手动创建」或「批量导入」任一方式，先补齐衣橱内容，再完成空间手帐前置任务。"
        case .batchImport:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                return "现在点击「批量导入」，就能一次导入多件裙子。"
            } else {
                return "解锁前先点击「手动创建」，完成一次基础录入流程。"
            }
        default:
            return "在展开菜单中选择创建方式，继续完成任务。"
        }
    }

    private func handleReturnToMeGuideAction() {
        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)
    }

    // MARK: - 备份功能引导

    private var backupGuideContent: some View {
        VStack(spacing: 0) {
            // 跳过按钮
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFeatureExperienceGuide()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            // 引导内容
            VStack(spacing: 16) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(magicPalette.accent)

                Text("数据备份")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(magicPalette.primaryText)

                Text("保护你的数据安全")
                    .font(.subheadline)
                    .foregroundStyle(magicPalette.secondaryText)

                if showingFullDescription {
                    Text("支持本地备份和iCloud云端同步~\n\n本地备份：导出数据文件到本地存储\niCloud同步：在所有Apple设备间自动同步")
                        .font(.caption)
                        .foregroundStyle(magicPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(magicPalette.quickOptionText)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFeatureExperienceGuide()
                    } label: {
                        Text("知道了")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(magicPalette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(magicPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    // MARK: - iCloud同步引导

    private var cloudSyncGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFeatureExperienceGuide()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(magicPalette.accent)

                Text("iCloud云端同步")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(magicPalette.primaryText)

                Text("数据自动同步到云端")
                    .font(.subheadline)
                    .foregroundStyle(magicPalette.secondaryText)

                if showingFullDescription {
                    Text("开启后，你的所有数据将在所有Apple设备间自动同步~\n\n换手机也不用担心数据丢失！")
                        .font(.caption)
                        .foregroundStyle(magicPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(magicPalette.quickOptionText)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFeatureExperienceGuide()
                    } label: {
                        Text("知道了")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(magicPalette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(magicPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    // MARK: - 批量导入引导

    private var batchImportGuideContent: some View {
        wardrobeGuideContent(accent: .green)
    }

    // MARK: - 筛选偏好引导

    private var filterClassicGuideContent: some View {
        personalPreferenceGuideContent
    }

    // MARK: - 隐私显示引导

    private var privacyDisplayGuideContent: some View {
        privacyDisplayStepGuideContent
    }

    // MARK: - 标签/品牌/属性字段引导

    private var tagBrandFieldGuideContent: some View {
        tagBrandFieldStepGuideContent
    }

    // MARK: - 空间手帐引导

    private var spaceBookGuideContent: some View {
        AnyView(
            Group {
                if usesPreUnlockWardrobeGuide(for: .spaceBook) {
                    wardrobeGuideContent(accent: .blue)
                } else {
                    GeometryReader { geometry in
                        switch spaceBookGuideStep {
                        case .step1_clickWardrobeOotdEntry:
                            let targetFrame = wardrobeOotdEntryGuideFrame(in: geometry)
                            highlightedRectGuideContent(
                                frame: targetFrame,
                                cornerRadius: 18,
                                title: "点击统计卡片里的「穿搭手帐」",
                                message: "先点这个入口进入穿搭手帐，我们再去空间页签创建空间手帐。",
                                currentStep: 1,
                                totalSteps: 7,
                                accent: .blue,
                                actionTitle: nil,
                                onAction: nil
                            )
                        case .step2_switchToSpaceTab:
                            let fallbackFrame = CGRect(x: (geometry.size.width - 160) / 2, y: max(geometry.safeAreaInsets.top + 8, 12), width: 160, height: 32)
                            let targetFrame = aiGuideTargetFrame(
                                globalFrame: guideManager.guideTargetFrame(for: .spaceBookModeTabs),
                                in: geometry,
                                fallback: fallbackFrame
                            )
                            highlightedRectGuideContent(
                                frame: targetFrame,
                                cornerRadius: 12,
                                title: "切到「空间」页签",
                                message: "上方这里可以在「平面 / 空间」之间切换。请切到「空间」，下一步就去右上角「更多」新建空间手帐。",
                                currentStep: 2,
                                totalSteps: 7,
                                accent: .blue,
                                actionTitle: nil,
                                onAction: nil
                            )
                        case .step3_createSpaceBook:
                            let fallbackFrame = CGRect(x: geometry.size.width - 64, y: max(geometry.safeAreaInsets.top + 8, 12), width: 36, height: 36)
                            let targetFrame = aiGuideTargetFrame(
                                globalFrame: guideManager.guideTargetFrame(for: .spaceBookShelfMoreMenuButton),
                                in: geometry,
                                fallback: fallbackFrame
                            )
                            highlightedRectGuideContent(
                                frame: targetFrame,
                                cornerRadius: 18,
                                title: "点右上角「更多」新建空间手帐",
                                message: "在菜单里选择「新建空间手帐」。输入名称后点创建，会直接进入这本新手帐。",
                                currentStep: 3,
                                totalSteps: 7,
                                accent: .blue,
                                actionTitle: nil,
                                onAction: nil
                            )
                        case .step4_createFirstPage:
                            let fallbackFrame = CGRect(x: geometry.size.width - 64, y: max(geometry.safeAreaInsets.top + 8, 12), width: 36, height: 36)
                            let targetFrame = aiGuideTargetFrame(
                                globalFrame: guideManager.guideTargetFrame(for: .spaceBookDetailMoreMenuButton),
                                in: geometry,
                                fallback: fallbackFrame
                            )
                            highlightedRectGuideContent(
                                frame: targetFrame,
                                cornerRadius: 18,
                                title: "输入首张名字后点创建",
                                message: "进入新手帐后，继续点右上角「更多」，选「新建空间搭配」。输入首张名字并点创建。",
                                currentStep: 4,
                                totalSteps: 7,
                                accent: .blue,
                                actionTitle: nil,
                                onAction: nil
                            )
                        case .step5_open3DEditor:
                            let fallbackFrame = CGRect(x: 24, y: geometry.size.height * 0.22, width: (geometry.size.width - 64) / 2, height: 180)
                            let targetFrame = aiGuideTargetFrame(
                                globalFrame: guideManager.guideTargetFrame(for: .spaceBookFirstPageCard),
                                in: geometry,
                                fallback: fallbackFrame
                            )
                            highlightedRectGuideContent(
                                frame: targetFrame,
                                cornerRadius: 12,
                                title: "进入刚创建的空间书页",
                                message: "首张空间书页创建后，点击它进入 3D 编辑界面。",
                                currentStep: 5,
                                totalSteps: 7,
                                accent: .blue,
                                actionTitle: nil,
                                onAction: nil
                            )
                        case .step6_openScanner:
                            let fallbackFrame = CGRect(x: 8, y: geometry.size.height * 0.42, width: 60, height: 96)
                            let targetFrame = aiGuideTargetFrame(
                                globalFrame: guideManager.guideTargetFrame(for: .spatialCanvasImportMenu),
                                in: geometry,
                                fallback: fallbackFrame
                            )
                            highlightedRectGuideContent(
                                frame: targetFrame,
                                cornerRadius: 20,
                                title: "左侧工具栏点「导入」再点「相机」",
                                message: "这是进入空间扫描的入口。请先打开导入菜单，再点击「相机」进入扫描界面。",
                                currentStep: 6,
                                totalSteps: 7,
                                accent: .blue,
                                actionTitle: nil,
                                onAction: nil
                            )
                        case .step7_scannerHowTo:
                            bottomBubbleGuideContent(
                                title: "开始空间扫描（最后一步）",
                                message: "请在光线充足的地方开始检测；让镜头尽量包住需要扫描的物体，先完成稳定定位，再围绕物体做后续 360° 扫描。做到这一步就完成本次引导啦。",
                                currentStep: 7,
                                totalSteps: 7,
                                accent: .blue,
                                actionTitle: "知道了，完成引导",
                                onAction: {
                                    guideManager.completeFeatureExperienceGuide()
                                }
                            )
                        }
                    }
                }
            }
        )
    }

    // MARK: - 批量编辑引导

    private var batchEditGuideContent: some View {
        batchEditInteractiveGuideContent
    }

    // MARK: - 魔法配色引导

    private var themeGuideContent: some View {
        themeCustomizeGuideContent
    }

    // MARK: - OOTD手帐引导

    private var ootdGuideContent: some View {
        AnyView(
            Group {
                if usesPreUnlockWardrobeGuide(for: .ootd) {
                    wardrobeGuideContent(accent: .orange)
                } else {
                    ootdUnlockedGuideContent
                }
            }
        )
    }

    // MARK: - 来财求签引导

    private var wealthGuideContent: some View {
        GeometryReader { geometry in
            ZStack {
                switch wealthGuideStep {
                case .step1_clickHouseTab:
                    wealthStep1Content(in: geometry)
                case .step2_clickWealthEntry:
                    wealthStep2Content(in: geometry)
                case .step3_divination, .step4_moneyCounting, .step5_wealthStorage:
                    wealthMainTabContent(in: geometry, step: wealthGuideStep)
                }
            }
        }
    }

    // 来财步骤1：点击 House Tab
    private func wealthStep1Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let tabBarHeight: CGFloat = 56
        let houseGuideXOffset: CGFloat = 20
        let houseGuideYOffset: CGFloat = 40
        let houseTabFrame = CGRect(
            x: (screenBounds.width * 0.375) - 34 + houseGuideXOffset,
            y: screenBounds.height - geometry.safeAreaInsets.bottom - tabBarHeight + houseGuideYOffset,
            width: 68,
            height: tabBarHeight
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: houseTabFrame,
                highlightType: .circle,
                cornerRadius: 28
            )

            HighlightPulseViewNoClick(
                center: CGPoint(x: houseTabFrame.midX, y: houseTabFrame.midY),
                radius: 34
            )

            if wealthGuideStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: houseTabFrame.midX, y: houseTabFrame.midY),
                    delay: 0.5
                )
                .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                wealthGuideBubble(step: wealthGuideStep)
                    .padding(.bottom, 120)
            }
        }
    }

    // 来财步骤2：点击「马上来财」入口
    private func wealthStep2Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let fallbackEntryFrame = CGRect(
            x: (screenBounds.width * 0.52) - 36,
            y: (screenBounds.height * 0.47) - 28,
            width: 72,
            height: 56
        )
        let wealthEntryFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .wealthEntry),
            in: geometry,
            fallback: fallbackEntryFrame
        )
        let pawPosition = CGPoint(
            x: min(wealthEntryFrame.maxX + 22, screenBounds.width - 28),
            y: min(wealthEntryFrame.midY + 8, screenBounds.height - 28)
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: wealthEntryFrame,
                highlightType: .roundedRect,
                cornerRadius: 16
            )

            RoundedRectHighlightView(
                frame: wealthEntryFrame,
                cornerRadius: 16
            )
            .allowsHitTesting(false)

            if wealthGuideStep.showCatPaw {
                CatPawTapAnimation(
                    position: pawPosition,
                    delay: 0.5
                )
                .opacity(0.45)
                .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                wealthGuideBubble(step: wealthGuideStep)
                    .padding(.bottom, 120)
            }
        }
    }

    // 来财步骤3/4/5：讲解「请签/数钱/安财」主页签
    private func wealthMainTabContent(in geometry: GeometryProxy, step: WealthGuideStep) -> some View {
        let screenBounds = geometry.size
        let fallbackSegmentFrame = CGRect(
            x: (screenBounds.width - 190) / 2,
            y: max(geometry.safeAreaInsets.top + 8, 58),
            width: 190,
            height: 34
        )
        let segmentFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .wealthMainTabSegment),
            in: geometry,
            fallback: fallbackSegmentFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: segmentFrame,
                highlightType: .roundedRect,
                cornerRadius: 10
            )

            RoundedRectHighlightView(
                frame: segmentFrame,
                cornerRadius: 10
            )
            .allowsHitTesting(false)

            VStack {
                Spacer()
                wealthGuideBubble(
                    step: step,
                    onNext: {
                        switch step {
                        case .step3_divination:
                            switchWealthGuideTab(to: .moneyCounting, nextStep: .step4_moneyCounting)
                        case .step4_moneyCounting:
                            switchWealthGuideTab(to: .wealthStorage, nextStep: .step5_wealthStorage)
                        default:
                            break
                        }
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    private func switchWealthGuideTab(to tab: WealthMainTab, nextStep: WealthGuideStep) {
        NotificationCenter.default.post(
            name: .wealthGuideSwitchMainTab,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )

        withAnimation(.easeInOut(duration: 0.25)) {
            wealthGuideStep = nextStep
        }
    }

    private func wealthGuideBubble(
        step: WealthGuideStep,
        onNext: (() -> Void)? = nil
    ) -> some View {
        WealthGuideBubbleView(
            step: step,
            onSkip: {
                guideManager.dismissFeatureExperienceGuide()
            },
            onNext: onNext,
            onComplete: {
                guideManager.completeFeatureExperienceGuide()
            }
        )
    }

    // MARK: - 小组件定制引导（三步骤）

    private var widgetCustomizeGuideContent: some View {
        GeometryReader { geometry in
            ZStack {
                switch widgetCustomizeStep {
                case .step1_returnToMe:
                    widgetStep1Content(in: geometry)
                case .step2_scrollToWidget:
                    widgetStep2Content
                case .step3_clickWidgetEntry:
                    widgetStep3Content(in: geometry)
                case .step4_widgetExplanation:
                    widgetStep4Content
                }
            }
        }
    }

    private func widgetStep1Content(in geometry: GeometryProxy) -> some View {
        let backButtonFrame = CGRect(
            x: 16,
            y: 8,
            width: 44,
            height: 44
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: backButtonFrame,
                highlightType: .circle,
                cornerRadius: 22
            )

            HighlightPulseViewNoClick(
                center: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                radius: 28
            )

            if widgetCustomizeStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                    delay: 0.5
                )
            }

            if guideManager.lastKnownHomeTab == "me" {
                Button {
                    handleWidgetGuideReturnAction()
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 72, height: 72)
                }
                .position(x: backButtonFrame.midX, y: backButtonFrame.midY)
            }

            VStack {
                Spacer()

                widgetCustomizeBubble(
                    step: widgetCustomizeStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    private var widgetStep2Content: some View {
        ZStack {
            WidgetScrollHintView()
            .allowsHitTesting(false)

            VStack {
                Spacer()

                widgetCustomizeBubble(
                    step: widgetCustomizeStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    private func widgetStep3Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let fallbackWidgetFrame = CGRect(
            x: 16,
            y: screenBounds.height * 0.58,
            width: (screenBounds.width - 48) / 2,
            height: 92
        )
        let widgetEntryFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .widgetCustomizeEntry),
            in: geometry,
            fallback: fallbackWidgetFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: widgetEntryFrame,
                highlightType: .roundedRect,
                cornerRadius: 16
            )

            RoundedRectHighlightView(
                frame: widgetEntryFrame,
                cornerRadius: 16
            )
            .allowsHitTesting(false)

            if widgetCustomizeStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: widgetEntryFrame.midX, y: widgetEntryFrame.midY),
                    delay: 0.5
                )
                .allowsHitTesting(false)
            }

            VStack {
                widgetCustomizeBubble(
                    step: widgetCustomizeStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.top, 110)

                Spacer()
            }
        }
    }

    private var widgetStep4Content: some View {
        VStack {
            Spacer()

            widgetCustomizeBubble(
                step: widgetCustomizeStep,
                onSkip: {
                    guideManager.dismissFeatureExperienceGuide()
                },
                onComplete: {
                    guideManager.completeFeatureExperienceGuide()
                }
            )
            .padding(.bottom, 120)
        }
    }

    private func widgetCustomizeBubble(
        step: WidgetCustomizeGuideStep,
        onSkip: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) -> some View {
        WidgetCustomizeGuideBubbleView(
            step: step,
            onSkip: onSkip,
            onComplete: onComplete
        )
    }

    // MARK: - 新增批量引导内容

    private func localGuideTargetFrame(
        for key: GuideTargetKey,
        in geometry: GeometryProxy
    ) -> CGRect? {
        guard let globalFrame = guideManager.guideTargetFrame(for: key),
              globalFrame.width > 0, globalFrame.height > 0 else { return nil }

        let overlayGlobalOrigin = geometry.frame(in: .global).origin
        return CGRect(
            x: globalFrame.minX - overlayGlobalOrigin.x,
            y: globalFrame.minY - overlayGlobalOrigin.y,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }

    private func wardrobeMenuAreaFrameFromAddButton(
        in geometry: GeometryProxy,
        addFrame: CGRect
    ) -> CGRect {
        let screenBounds = geometry.size
        let menuWidth = min(max(screenBounds.width * 0.58, 208), 292)
        let menuHeight: CGFloat = 118
        let x = min(max(addFrame.maxX - menuWidth - 8, 12), screenBounds.width - menuWidth - 12)
        let y = max(geometry.safeAreaInsets.top + 10, addFrame.maxY + 16)
        return CGRect(x: x, y: y, width: menuWidth, height: menuHeight)
    }

    private func wardrobeMenuOptionFrameFromAddButton(
        in geometry: GeometryProxy,
        addFrame: CGRect,
        preferBatchImport: Bool
    ) -> CGRect {
        let menuFrame = wardrobeMenuAreaFrameFromAddButton(in: geometry, addFrame: addFrame)
        let rowHeight = (menuFrame.height - 20) / 2
        let rowIndex: CGFloat = preferBatchImport ? 1 : 0
        return CGRect(
            x: menuFrame.minX + 14,
            y: menuFrame.minY + 8 + rowHeight * rowIndex,
            width: menuFrame.width - 28,
            height: rowHeight - 6
        )
    }

    private func isReasonableWardrobeMenuCaptureFrame(
        _ frame: CGRect,
        in geometry: GeometryProxy,
        addFrame: CGRect
    ) -> Bool {
        guard frame.width >= 80, frame.height >= 24 else { return false }
        guard frame.minY < geometry.size.height * 0.45 else { return false }
        guard abs(frame.midX - addFrame.midX) < geometry.size.width * 0.46 else { return false }
        return true
    }

    private func wardrobeGuideStep2Frame(
        in geometry: GeometryProxy,
        addFrame: CGRect
    ) -> CGRect {
        let screenBounds = geometry.size
        let menuAreaFallback = wardrobeMenuAreaFrameFromAddButton(in: geometry, addFrame: addFrame)

        guard let feature = guideManager.currentFeatureExperienceFeature else {
            return menuAreaFallback
        }

        if feature == .batchImport {
            let preferBatchImport = FeatureUnlockManager.shared.isUnlocked(feature)
            let targetKey: GuideTargetKey = preferBatchImport ? .wardrobeBatchImportEntry : .wardrobeManualCreateEntry
            if let capturedFrame = localGuideTargetFrame(for: targetKey, in: geometry),
               isReasonableWardrobeMenuCaptureFrame(capturedFrame, in: geometry, addFrame: addFrame) {
                return capturedFrame.insetBy(dx: -4, dy: -3)
            }
            return wardrobeMenuOptionFrameFromAddButton(
                in: geometry,
                addFrame: addFrame,
                preferBatchImport: preferBatchImport
            )
        }

        let manualFrame = localGuideTargetFrame(for: .wardrobeManualCreateEntry, in: geometry)
        let batchFrame = localGuideTargetFrame(for: .wardrobeBatchImportEntry, in: geometry)

        if let manualFrame, let batchFrame,
           isReasonableWardrobeMenuCaptureFrame(manualFrame, in: geometry, addFrame: addFrame),
           isReasonableWardrobeMenuCaptureFrame(batchFrame, in: geometry, addFrame: addFrame) {
            return manualFrame.union(batchFrame).insetBy(dx: -4, dy: -4)
        }
        if let manualFrame,
           isReasonableWardrobeMenuCaptureFrame(manualFrame, in: geometry, addFrame: addFrame) {
            return manualFrame
        }
        if let batchFrame,
           isReasonableWardrobeMenuCaptureFrame(batchFrame, in: geometry, addFrame: addFrame) {
            return batchFrame
        }
        return menuAreaFallback
    }

    private func wardrobeOotdEntryGuideFrame(in geometry: GeometryProxy) -> CGRect {
        let fallbackFrame = CGRect(
            x: geometry.size.width * 0.36,
            y: max(geometry.safeAreaInsets.top + 120, geometry.size.height * 0.20),
            width: geometry.size.width * 0.28,
            height: 82
        )
        return aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .wardrobeOotdEntry),
            in: geometry,
            fallback: fallbackFrame
        )
    }

    private func ootdEntryGuideFrame(in geometry: GeometryProxy) -> CGRect {
        let screenBounds = geometry.size
        let compactFallback = CGRect(
            x: screenBounds.width * 0.30,
            y: screenBounds.height * 0.24,
            width: max(88, screenBounds.width * 0.14),
            height: max(132, screenBounds.height * 0.16)
        )

        let rawFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .ootdEntry),
            in: geometry,
            fallback: compactFallback
        )

        return normalizedOotdGuideFrame(rawFrame, in: geometry, fallback: compactFallback)
    }

    private func normalizedOotdGuideFrame(
        _ frame: CGRect,
        in geometry: GeometryProxy,
        fallback: CGRect
    ) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return fallback }

        let aspectRatio = frame.height / max(frame.width, 1)
        let isOverTall = aspectRatio > 2.1 || frame.height > geometry.size.height * 0.42
        guard isOverTall else { return frame }

        let clampedWidth = min(max(frame.width, 92), 136)
        let clampedHeight = min(max(frame.height * 0.35, 132), 188)

        let minX: CGFloat = 12
        let maxX = max(minX, geometry.size.width - clampedWidth - 12)
        let x = min(max(frame.midX - clampedWidth / 2, minX), maxX)

        let minY = max(geometry.safeAreaInsets.top + 36, 48)
        let maxY = max(minY, geometry.size.height - clampedHeight - 180)
        let y = min(max(frame.midY - clampedHeight / 2, minY), maxY)

        return CGRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
    }

    private func calendarEntryGuideFrame(in geometry: GeometryProxy) -> CGRect {
        let screenBounds = geometry.size
        let rococoFallback = CGRect(
            x: screenBounds.width * 0.40,
            y: screenBounds.height * 0.66,
            width: max(96, screenBounds.width * 0.16),
            height: max(108, screenBounds.height * 0.12)
        )

        guard let rawFrame = localGuideTargetFrame(for: .calendarEntry, in: geometry) else {
            return rococoFallback
        }

        if let ootdFrame = localGuideTargetFrame(for: .ootdEntry, in: geometry) {
            let isLikelyRococoLayout = ootdFrame.height < geometry.size.height * 0.35
            let isSuspiciousUpperFrame = rawFrame.minY < geometry.size.height * 0.52
            if isLikelyRococoLayout, isSuspiciousUpperFrame {
                return rococoFallback
            }
        }

        return rawFrame
    }

    private func wardrobeGuideContent(accent: Color) -> some View {
        GeometryReader { geometry in
            let screenBounds = geometry.size
            let addButtonFallbackFrame = CGRect(
                x: screenBounds.width - 54,
                y: max(geometry.safeAreaInsets.top + 8, 12),
                width: 36,
                height: 36
            )
            let addFrame = aiGuideTargetFrame(
                globalFrame: guideManager.guideTargetFrame(for: .wardrobeAddButton),
                in: geometry,
                fallback: addButtonFallbackFrame
            )

            let step1GuideFrame = addFrame.offsetBy(dx: 0, dy: -12)

            switch wardrobeAddGuideStep {
            case .step1_clickAddButton:
                ZStack {
                    HollowMaskView(
                        highlightFrame: step1GuideFrame,
                        highlightType: .roundedRect,
                        cornerRadius: 18
                    )

                    RoundedRectHighlightView(
                        frame: step1GuideFrame,
                        cornerRadius: 18
                    )

                    CatPawTapAnimation(
                        position: CGPoint(x: step1GuideFrame.midX, y: step1GuideFrame.midY - 12),
                        delay: 0.5
                    )

                    VStack {
                        Spacer()
                        featureStepBubble(
                            title: "先点击右上角 + 号",
                            message: currentWardrobeGuideStep1Message,
                            currentStep: 1,
                            totalSteps: 2,
                            accent: accent,
                            actionTitle: nil,
                            onSkip: {
                                guideManager.dismissFeatureExperienceGuide()
                            },
                            onAction: nil
                        )
                        .padding(.bottom, 120)
                    }
                }
            case .step2_chooseTargetOption:
                let optionFrame = wardrobeGuideStep2Frame(in: geometry, addFrame: addFrame)

                highlightedRectGuideContent(
                    frame: optionFrame,
                    cornerRadius: 14,
                    title: currentWardrobeGuideStep2Title,
                    message: currentWardrobeGuideStep2Message,
                    currentStep: 2,
                    totalSteps: 2,
                    accent: accent,
                    actionTitle: nil,
                    onAction: nil
                )
                .overlay {
                    CatPawTapAnimation(
                        position: CGPoint(x: optionFrame.maxX - 4, y: optionFrame.midY - 6),
                        delay: 0.5
                    )
                    .opacity(0.4)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var themeCustomizeGuideContent: some View {
        GeometryReader { geometry in
            switch themeCustomizeGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: "返回「我」界面",
                    message: "先从魔法任务页返回到「我」，再去找主题配色豆腐块。",
                    currentStep: 1,
                    totalSteps: 5,
                    accent: .purple,
                    onReturn: handleReturnToMeGuideAction
                ))
            case .step2_scrollToThemeEntry:
                return AnyView(
                    ZStack {
                        WidgetScrollHintView(
                            title: "请向下滑动",
                            subtitle: "主题配色入口在更下方的豆腐块区域"
                        )
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: "下滑找到主题配色",
                                message: "请继续向下滑动，在设置豆腐块区域找到「主题配色」入口。",
                                currentStep: 2,
                                totalSteps: 5,
                                accent: .purple,
                                actionTitle: nil,
                                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                onAction: nil
                            )
                            .padding(.bottom, 120)
                        }
                    }
                )
            case .step3_clickThemeEntry:
                let fallbackFrame = CGRect(x: 16, y: geometry.size.height * 0.42, width: (geometry.size.width - 48) / 2, height: 92)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .themeCustomizeEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "点击主题配色豆腐块",
                    message: "在「我」页找到「主题配色」豆腐块，点进去进入主题页。",
                    currentStep: 3,
                    totalSteps: 5,
                    accent: .purple,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step4_switchToMagicTab:
                let fallbackFrame = CGRect(x: (geometry.size.width - 240) / 2, y: max(geometry.safeAreaInsets.top + 64, 84), width: 240, height: 32)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .themeColorModeTabs),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 12,
                    title: "切换到魔法配色页签",
                    message: "这里有「原生魔法配色」和「客制化配色」两个页签。请切到「魔法配色」，看看自动调色是怎么工作的。",
                    currentStep: 4,
                    totalSteps: 5,
                    accent: .purple,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step5_magicThemeExplanation:
                return AnyView(bottomBubbleGuideContent(
                    title: "认识魔法配色",
                    message: "魔法配色会根据背景和卡片自动调整字体与模块颜色。你可以先看预览，再决定是否长期使用这套自动调色方案。",
                    currentStep: 5,
                    totalSteps: 5,
                    accent: .purple,
                    actionTitle: "知道了",
                    onAction: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                ))
            }
        }
    }

    private var localFileBackupRestoreGuideContent: some View {
        GeometryReader { geometry in
            switch localFileBackupRestoreGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: "返回「我」界面",
                    message: "先从魔法任务页返回到「我」，我们去找本地文件备份入口。",
                    currentStep: 1,
                    totalSteps: 4,
                    accent: .indigo,
                    onReturn: handleLocalFileBackupRestoreGuideReturnAction
                ))
            case .step2_scrollToSystemSettings:
                return AnyView(
                    ZStack {
                        WidgetScrollHintView(
                            title: "请向下滑动",
                            subtitle: "继续下滑，先找到「系统与更多」豆腐块"
                        )
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: "下滑找到系统与更多",
                                message: "继续向下滑动，在设置豆腐块区域找到「系统与更多」。",
                                currentStep: 2,
                                totalSteps: 4,
                                accent: .indigo,
                                actionTitle: nil,
                                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                onAction: nil
                            )
                            .padding(.bottom, 120)
                        }
                    }
                )
            case .step3_clickSystemSettings:
                let fallbackFrame = CGRect(x: 16, y: geometry.size.height * 0.58, width: (geometry.size.width - 48) / 2, height: 92)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .systemSettingsEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "点击系统与更多",
                    message: "点开「系统与更多」，进入系统设置页。",
                    currentStep: 3,
                    totalSteps: 4,
                    accent: .indigo,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step4_clickBackupRestoreEntry:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 250, 280),
                    width: geometry.size.width - 32,
                    height: 54
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .localFileBackupRestoreEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: "点击文件的备份与恢复",
                    message: "在「系统与更多」里点击「文件的备份与恢复」，就能进入本地文件备份与恢复页面。",
                    currentStep: 4,
                    totalSteps: 4,
                    accent: .indigo,
                    actionTitle: nil,
                    onAction: nil
                ))
            }
        }
    }

    private var exportCSVGuideContent: some View {
        GeometryReader { geometry in
            switch exportCSVGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: "返回「我」界面",
                    message: "先从魔法任务页返回到「我」，我们去找导出表格入口。",
                    currentStep: 1,
                    totalSteps: 4,
                    accent: .teal,
                    onReturn: handleExportCSVGuideReturnAction
                ))
            case .step2_scrollToSystemSettings:
                return AnyView(
                    ZStack {
                        WidgetScrollHintView(
                            title: "请向下滑动",
                            subtitle: "继续下滑，先找到「系统与更多」豆腐块"
                        )
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: "下滑找到系统与更多",
                                message: "继续向下滑动，在设置豆腐块区域找到「系统与更多」。",
                                currentStep: 2,
                                totalSteps: 4,
                                accent: .teal,
                                actionTitle: nil,
                                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                onAction: nil
                            )
                            .padding(.bottom, 120)
                        }
                    }
                )
            case .step3_clickSystemSettings:
                let fallbackFrame = CGRect(x: 16, y: geometry.size.height * 0.58, width: (geometry.size.width - 48) / 2, height: 92)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .systemSettingsEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "点击系统与更多",
                    message: "点开「系统与更多」，进入系统设置页。",
                    currentStep: 3,
                    totalSteps: 4,
                    accent: .teal,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step4_clickExportCSV:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 300, 328),
                    width: geometry.size.width - 32,
                    height: 54
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .exportCSVEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: "点击导出到 CSV",
                    message: "点击「导出 CSV (Export CSV)」，即可开始导出表格文件。",
                    currentStep: 4,
                    totalSteps: 4,
                    accent: .teal,
                    actionTitle: nil,
                    onAction: nil
                ))
            }
        }
    }

    private var cloudFileBackupRestoreGuideContent: some View {
        GeometryReader { geometry in
            switch cloudFileBackupRestoreGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: "返回「我」界面",
                    message: "先从魔法任务页返回到「我」，再去「账户与同步」。",
                    currentStep: 1,
                    totalSteps: 5,
                    accent: .blue,
                    onReturn: handleCloudFileBackupRestoreGuideReturnAction
                ))
            case .step2_clickAccountSync:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 150, 188),
                    width: (geometry.size.width - 48) / 2,
                    height: (geometry.size.width - 48) / 2
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .accountSyncEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 20,
                    title: "点击账户与同步",
                    message: "点开这个豆腐块，进入账号与 iCloud 同步管理页面。",
                    currentStep: 2,
                    totalSteps: 5,
                    accent: .blue,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step3_signInAppleID:
                let fallbackFrame = CGRect(
                    x: 24,
                    y: max(geometry.safeAreaInsets.top + 260, 300),
                    width: geometry.size.width - 48,
                    height: 52
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .cloudAppleSignInButton),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 12,
                    title: "先登录 Apple ID",
                    message: "点击这里完成 Apple 登录。登录后才能使用云端文件备份与恢复，以及 iCloud 自动同步。",
                    currentStep: 3,
                    totalSteps: 5,
                    accent: .blue,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step4_cloudBackupExplanation:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 380, 430),
                    width: geometry.size.width - 32,
                    height: 154
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .cloudFileBackupSection),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: "认识云端文件备份与恢复",
                    message: "这里可以「备份到云端」和「从云端恢复」。建议你先备份一份，这样换设备或误删后都能快速找回数据。",
                    currentStep: 4,
                    totalSteps: 5,
                    accent: .blue,
                    actionTitle: "下一步：及时同步延迟",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            cloudFileBackupRestoreGuideStep = .step5_realtimeSyncDelayExplanation
                        }
                    }
                ))
            case .step5_realtimeSyncDelayExplanation:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 170, 208),
                    width: geometry.size.width - 32,
                    height: 170
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .iCloudRealtimeSyncSection),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: "iCloud 及时同步与延迟说明",
                    message: "开启后会自动同步变更。大多数情况下是秒级到几十秒；网络较慢、系统省电或后台调度时，可能延迟到 1～5 分钟，属正常现象。",
                    currentStep: 5,
                    totalSteps: 5,
                    accent: .blue,
                    actionTitle: "知道了",
                    onAction: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                ))
            }
        }
    }

    private var personalPreferenceGuideContent: some View {
        GeometryReader { geometry in
            switch personalPreferenceGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: "返回「我」界面",
                    message: "先返回到「我」页，我们一起去找梦幻衣橱豆腐块。",
                    currentStep: 1,
                    totalSteps: 5,
                    accent: .pink,
                    onReturn: handleReturnToMeGuideAction
                ))
            case .step2_clickWardrobeEntry:
                let fallbackFrame = CGRect(x: 16, y: geometry.size.height * 0.28, width: (geometry.size.width - 48) / 2, height: 92)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeSettingsEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "点击梦幻衣橱豆腐块",
                    message: "进入梦幻衣橱设置页后，我们会一起看界面样式、筛选模式和应用外观这些个性化体验。",
                    currentStep: 2,
                    totalSteps: 5,
                    accent: .pink,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step3_interfaceStyle:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 78, 110),
                    width: geometry.size.width - 32,
                    height: 92
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeInterfaceStyleSection),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "界面样式：决定衣橱导航布局",
                    message: "这里用来切换衣橱的导航形态。不同样式会影响顶部导航与操作按钮的组织方式，按你的使用习惯选更顺手的就行。",
                    currentStep: 3,
                    totalSteps: 5,
                    accent: .pink,
                    actionTitle: "下一步：筛选模式",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            personalPreferenceGuideStep = .step4_filterMode
                        }
                    }
                ))
            case .step4_filterMode:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 186, 220),
                    width: geometry.size.width - 32,
                    height: 104
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeFilterModeSection),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "筛选模式：决定你怎么筛衣服",
                    message: "经典筛选是下拉菜单，适合快速单项筛；多维筛选是半屏多选，适合组合条件做更精细筛选。",
                    currentStep: 4,
                    totalSteps: 5,
                    accent: .pink,
                    actionTitle: "下一步：应用外观",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            personalPreferenceGuideStep = .step5_appAppearance
                        }
                    }
                ))
            case .step5_appAppearance:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 302, 346),
                    width: geometry.size.width - 32,
                    height: 190
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeAppAppearanceSection),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "应用外观：控制整体观感",
                    message: "这里是个性化最核心的一块：背景类型决定用纯色还是图片；背景颜色/图片与不透明度决定整体氛围；高斯模糊决定前景内容与背景的层次；「字体配色与卡片样式」则影响文字可读性和卡片风格。搭配好这几项，你会得到更舒适也更有个人风格的界面。",
                    currentStep: 5,
                    totalSteps: 5,
                    accent: .pink,
                    actionTitle: "知道了",
                    onAction: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                ))
            }
        }
    }

    private var privacyDisplayStepGuideContent: some View {
        GeometryReader { geometry in
            switch privacyDisplayGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: "返回「我」界面",
                    message: "先返回到「我」页，我们一起去找梦幻衣橱豆腐块。",
                    currentStep: 1,
                    totalSteps: 4,
                    accent: .pink,
                    onReturn: handleReturnToMeGuideAction
                ))
            case .step2_clickWardrobeEntry:
                let fallbackFrame = CGRect(x: 16, y: geometry.size.height * 0.28, width: (geometry.size.width - 48) / 2, height: 92)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeSettingsEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "点击梦幻衣橱豆腐块",
                    message: "进入梦幻衣橱设置页后，我们来认识「隐私显示」里的两个开关。",
                    currentStep: 2,
                    totalSteps: 4,
                    accent: .pink,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step3_showPurchasePrice:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 306, 340),
                    width: geometry.size.width - 32,
                    height: 52
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobePrivacyShowPriceSection),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: "入库价格开关",
                    message: "打开时，衣橱列表会显示每件衣服的入库价格；关闭后会隐藏入库价格，适合共享屏幕或给别人看衣橱时保护隐私。",
                    currentStep: 3,
                    totalSteps: 4,
                    accent: .pink,
                    actionTitle: "下一步：原价开关",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            privacyDisplayGuideStep = .step4_showOriginalPrice
                        }
                    }
                ))
            case .step4_showOriginalPrice:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 362, 396),
                    width: geometry.size.width - 32,
                    height: 52
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobePrivacyShowOriginalPriceSection),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: "原价开关",
                    message: "这个开关控制列表中是否显示原价信息。你可以和入库价格分开管理：例如只看当前入库价，或两者都隐藏，让衣橱浏览更清爽、更私密。",
                    currentStep: 4,
                    totalSteps: 4,
                    accent: .pink,
                    actionTitle: "知道了",
                    onAction: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                ))
            }
        }
    }

    private var tagBrandFieldStepGuideContent: some View {
        GeometryReader { geometry in
            switch tagBrandFieldGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: "返回「我」界面",
                    message: "先返回到「我」页，我们一起去找梦幻衣橱豆腐块。",
                    currentStep: 1,
                    totalSteps: 6,
                    accent: .pink,
                    onReturn: handleReturnToMeGuideAction
                ))
            case .step2_clickWardrobeEntry:
                let fallbackFrame = CGRect(x: 16, y: geometry.size.height * 0.28, width: (geometry.size.width - 48) / 2, height: 92)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeSettingsEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "点击梦幻衣橱豆腐块",
                    message: "进入梦幻衣橱设置页后，我们会依次认识标签管理、品牌管理和属性字段管理。",
                    currentStep: 2,
                    totalSteps: 6,
                    accent: .pink,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step3_scrollToManagementEntries:
                return AnyView(
                    ZStack {
                        WidgetScrollHintView(
                            title: "请向下滑动",
                            subtitle: "标签管理、品牌管理和属性字段管理在更下方"
                        )
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: "下滑找到管理项",
                                message: "请继续下滑到页面下方，找到「标签管理 / 品牌管理 / 属性字段排序与显示」这三项。",
                                currentStep: 3,
                                totalSteps: 6,
                                accent: .pink,
                                actionTitle: nil,
                                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                onAction: nil
                            )
                            .padding(.bottom, 120)
                        }
                    }
                )
            case .step4_tagManagement:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 464, 500),
                    width: geometry.size.width - 32,
                    height: 52
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeTagManagementEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: "标签管理",
                    message: "这里管理你所有标签（例如风格、场景、季节等）。把标签体系整理好后，衣橱筛选会更快、更准，也更方便复用。",
                    currentStep: 4,
                    totalSteps: 6,
                    accent: .pink,
                    actionTitle: "下一步：品牌管理",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            tagBrandFieldGuideStep = .step5_brandManagement
                        }
                    },
                    bubbleOnTop: true
                ))
            case .step5_brandManagement:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 520, 556),
                    width: geometry.size.width - 32,
                    height: 52
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeBrandManagementEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: "品牌管理",
                    message: "这里统一维护品牌名称，避免同品牌出现多个写法。品牌数据干净后，统计、筛选和搜索都会更稳定。",
                    currentStep: 5,
                    totalSteps: 6,
                    accent: .pink,
                    actionTitle: "下一步：属性字段管理",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            tagBrandFieldGuideStep = .step6_fieldManagement
                        }
                    },
                    bubbleOnTop: true
                ))
            case .step6_fieldManagement:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 576, 612),
                    width: geometry.size.width - 32,
                    height: 52
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeFieldManagementEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: "属性字段管理",
                    message: "这里可以控制属性字段的显示与排序。把常用字段放前面、低频字段放后面，日常录入和查看都会更顺手。",
                    currentStep: 6,
                    totalSteps: 6,
                    accent: .pink,
                    actionTitle: "知道了",
                    onAction: {
                        guideManager.completeFeatureExperienceGuide()
                    },
                    bubbleOnTop: true
                ))
            }
        }
    }

    private var ootdUnlockedGuideContent: some View {
        GeometryReader { geometry in
            switch ootdGuideStep {
            case .step1_clickOotdEntry:
                let targetFrame = ootdEntryGuideFrame(in: geometry)
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 18,
                    title: "点击 House 的穿搭手帐热区",
                    message: "先从 House 里的穿搭手帐热区进入，我们再认识手帐本和书页。",
                    currentStep: 1,
                    totalSteps: 2,
                    accent: .orange,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step2_ootdExplanation:
                return AnyView(bottomBubbleGuideContent(
                    title: "认识穿搭手帐和书页",
                    message: "这里先看到的是手帐本列表；点进任意一本后，就能看到它下面的书页。书页里可以继续记录搭配、图片和灵感。",
                    currentStep: 2,
                    totalSteps: 2,
                    accent: .orange,
                    actionTitle: "知道了",
                    onAction: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                ))
            }
        }
    }

    private var calendarGuideContent: some View {
        if usesPreUnlockWardrobeGuide(for: .calendar) {
            return AnyView(wardrobeGuideContent(accent: .purple))
        }

        return AnyView(
            GeometryReader { geometry in
                switch calendarGuideStep {
                case .step1_clickCalendarEntry:
                    let targetFrame = calendarEntryGuideFrame(in: geometry)
                    highlightedRectGuideContent(
                        frame: targetFrame,
                        cornerRadius: 16,
                        title: "点击 House 的梦裙日历热区",
                        message: "先从 House 里的梦裙日历热区进入，我们再认识最近、月度、年度三个视图。",
                        currentStep: 1,
                        totalSteps: 2,
                        accent: .purple,
                        actionTitle: nil,
                        onAction: nil,
                        bubbleOnTop: true
                    )
                case .step2_calendarExplanation:
                    bottomBubbleGuideContent(
                        title: "认识梦裙日历",
                        message: "最近会按时间线看近期记录，月度适合查具体月份，年度更适合总览全年的热度分布。右上角默认勾选了「只看心愿尾款」，所以你一进来就会先看到尾款相关内容。",
                        currentStep: 2,
                        totalSteps: 2,
                        accent: .purple,
                        actionTitle: "知道了",
                        onAction: {
                            guideManager.completeFeatureExperienceGuide()
                        }
                    )
                }
            }
        )
    }

    private var magicStickerGuideContent: some View {
        if usesPreUnlockWardrobeGuide(for: .ootdDefaultBook) {
            return AnyView(wardrobeGuideContent(accent: .pink))
        }

        return AnyView(
            GeometryReader { geometry in
                switch magicStickerGuideStep {
                case .step1_longPressHouseTab:
                    let tabBarHeight: CGFloat = 56
                    let houseTabFrame = CGRect(
                        x: (geometry.size.width * 0.375) - 34 + 20,
                        y: geometry.size.height - geometry.safeAreaInsets.bottom - tabBarHeight + 40,
                        width: 68,
                        height: tabBarHeight
                    )
                    ZStack {
                        HollowMaskView(
                            highlightFrame: houseTabFrame,
                            highlightType: .circle,
                            cornerRadius: 28
                        )

                        HighlightPulseViewNoClick(
                            center: CGPoint(x: houseTabFrame.midX, y: houseTabFrame.midY),
                            radius: 34
                        )

                        CatPawTapAnimation(
                            position: CGPoint(x: houseTabFrame.midX, y: houseTabFrame.midY),
                            delay: 0.5
                        )

                        VStack {
                            featureStepBubble(
                                title: "长按 House tab",
                                message: "请长按底部的 House tab，弹出常用菜单后，我们一起找到「魔法贴纸」。",
                                currentStep: 1,
                                totalSteps: 3,
                                accent: .pink,
                                actionTitle: nil,
                                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                onAction: nil
                            )
                            .padding(.top, max(geometry.safeAreaInsets.top + 24, 72))
                            Spacer()
                        }
                    }
                case .step2_clickMagicStickerEntry:
                    let fallbackFrame = CGRect(x: geometry.size.width * 0.18, y: geometry.size.height * 0.56, width: 96, height: 84)
                    let targetFrame = aiGuideTargetFrame(
                        globalFrame: guideManager.guideTargetFrame(for: .favoriteMenuMagicStickerEntry),
                        in: geometry,
                        fallback: fallbackFrame
                    )
                    highlightedRectGuideContent(
                        frame: targetFrame,
                        cornerRadius: 24,
                        title: "点击「魔法贴纸」",
                        message: "在长按弹出的常用菜单里点击「魔法贴纸」，进入默认贴纸编辑页。",
                        currentStep: 2,
                        totalSteps: 3,
                        accent: .pink,
                        actionTitle: nil,
                        onAction: nil,
                        bubbleOnTop: true
                    )
                case .step3_magicStickerExplanation:
                    bottomBubbleGuideContent(
                        title: "认识魔法贴纸",
                        message: "这里会直接进入默认贴纸页。主体区域是贴纸编辑内容，常用菜单能帮你继续跳到别的 House 功能；如果把贴纸加入手帐，还能继续回到对应手帐里编辑。",
                        currentStep: 3,
                        totalSteps: 3,
                        accent: .pink,
                        actionTitle: "知道了",
                        onAction: {
                            guideManager.completeFeatureExperienceGuide()
                        }
                    )
                }
            }
        )
    }

    private var batchEditInteractiveGuideContent: some View {
        GeometryReader { geometry in
            switch batchEditGuideStep {
            case .step1_clickMoreMenu:
                let fallbackFrame = CGRect(x: geometry.size.width - 64, y: max(geometry.safeAreaInsets.top + 8, 12), width: 36, height: 36)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeMoreMenuButton),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 18,
                    title: "点击右上角更多按钮",
                    message: "先点右上角「更多」，再在弹出菜单里选择「编辑」。进入编辑态后，我们继续下一步。",
                    currentStep: 1,
                    totalSteps: 4,
                    accent: .green,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step2_selectOneCard:
                let fallbackFrame = CGRect(x: 16, y: geometry.size.height * 0.28, width: (geometry.size.width - 48) / 2, height: 160)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeSelectionCard),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 16,
                    title: "选中一张卡片",
                    message: "随便点选一张衣橱卡片，让底部批量工具条进入可用状态。",
                    currentStep: 2,
                    totalSteps: 4,
                    accent: .green,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step3_toolbarExplanation:
                return AnyView(bottomBubbleGuideContent(
                    title: "认识批量编辑工具条",
                    message: "底部这排就是批量编辑常用操作：删除、复制、更多、全选。更多里还能继续做标签、品牌、颜色、尺码、状态等批量处理。",
                    currentStep: 3,
                    totalSteps: 4,
                    accent: .green,
                    actionTitle: "下一步：完成",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            batchEditGuideStep = .step4_finishSelection
                        }
                    }
                ))
            case .step4_finishSelection:
                let fallbackFrame = CGRect(x: geometry.size.width - 64, y: max(geometry.safeAreaInsets.top + 8, 12), width: 36, height: 36)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeDoneSelectionButton),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 18,
                    title: "点完成结束批量编辑",
                    message: "现在不用继续操作了，直接点右上角的完成勾选，退出这次批量编辑体验。",
                    currentStep: 4,
                    totalSteps: 4,
                    accent: .green,
                    actionTitle: nil,
                    onAction: nil
                ))
            }
        }
    }

    private func returnToMeGuideContent(
        in geometry: GeometryProxy,
        title: String,
        message: String,
        currentStep: Int,
        totalSteps: Int,
        accent: Color,
        onReturn: @escaping () -> Void
    ) -> some View {
        let backButtonFrame = CGRect(x: 16, y: 8, width: 44, height: 44)

        return ZStack {
            HollowMaskView(
                highlightFrame: backButtonFrame,
                highlightType: .circle,
                cornerRadius: 22
            )

            HighlightPulseViewNoClick(
                center: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                radius: 28
            )

            CatPawTapAnimation(
                position: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                delay: 0.5
            )

            if guideManager.lastKnownHomeTab == "me" {
                Button {
                    onReturn()
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 72, height: 72)
                }
                .position(x: backButtonFrame.midX, y: backButtonFrame.midY)
            }

            VStack {
                Spacer()
                featureStepBubble(
                    title: title,
                    message: message,
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    accent: accent,
                    actionTitle: nil,
                    onSkip: { guideManager.dismissFeatureExperienceGuide() },
                    onAction: nil
                )
                .padding(.bottom, 120)
            }
        }
    }

    private func highlightedRectGuideContent(
        frame: CGRect,
        cornerRadius: CGFloat,
        title: String,
        message: String,
        currentStep: Int,
        totalSteps: Int,
        accent: Color,
        actionTitle: String?,
        onAction: (() -> Void)?,
        bubbleOnTop: Bool = false
    ) -> some View {
        ZStack {
            HollowMaskView(
                highlightFrame: frame,
                highlightType: .roundedRect,
                cornerRadius: cornerRadius
            )

            RoundedRectHighlightView(
                frame: frame,
                cornerRadius: cornerRadius
            )

            VStack {
                if bubbleOnTop {
                    featureStepBubble(
                        title: title,
                        message: message,
                        currentStep: currentStep,
                        totalSteps: totalSteps,
                        accent: accent,
                        actionTitle: actionTitle,
                        onSkip: { guideManager.dismissFeatureExperienceGuide() },
                        onAction: onAction
                    )
                    .padding(.top, 72)
                    Spacer()
                } else {
                    Spacer()
                    featureStepBubble(
                        title: title,
                        message: message,
                        currentStep: currentStep,
                        totalSteps: totalSteps,
                        accent: accent,
                        actionTitle: actionTitle,
                        onSkip: { guideManager.dismissFeatureExperienceGuide() },
                        onAction: onAction
                    )
                    .padding(.bottom, 120)
                }
            }
        }
    }

    private func bottomBubbleGuideContent(
        title: String,
        message: String,
        currentStep: Int,
        totalSteps: Int,
        accent: Color,
        actionTitle: String,
        onAction: @escaping () -> Void
    ) -> some View {
        VStack {
            Spacer()
            featureStepBubble(
                title: title,
                message: message,
                currentStep: currentStep,
                totalSteps: totalSteps,
                accent: accent,
                actionTitle: actionTitle,
                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                onAction: onAction
            )
            .padding(.bottom, 120)
        }
    }

    private func simpleFeatureCardGuide(
        icon: String,
        accent: Color,
        title: String,
        subtitle: String
    ) -> some View {
        VStack {
            Spacer()
            featureStepBubble(
                title: title,
                message: subtitle,
                currentStep: 1,
                totalSteps: 1,
                accent: accent,
                actionTitle: "知道了",
                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                onAction: {
                    guideManager.completeFeatureExperienceGuide()
                }
            )
            .overlay(alignment: .top) {
                Image(systemName: icon)
                    .font(.system(size: 38))
                    .foregroundStyle(accent)
                    .offset(y: -26)
            }
            .padding(.bottom, 120)
        }
    }

    // MARK: - 萌宠智能对话引导（三步骤）

    private var aiAnalysisGuideContent: some View {
        GeometryReader { geometry in
            ZStack {
                // 根据当前步骤显示不同的遮罩和高亮
                switch aiAnalysisStep {
                case .step1_returnToMe:
                    // 第一步：高亮返回按钮
                    step1Content(in: geometry)
                case .step2_clickVIP:
                    // 第二步：高亮VIP卡片
                    step2Content(in: geometry)
                case .step3_exchange:
                    // 第三步：高亮兑换按钮
                    step3Content(in: geometry)
                }
            }
        }
    }

    // 步骤1：返回「我」界面
    private func step1Content(in geometry: GeometryProxy) -> some View {
        // 返回按钮位置（左上角导航栏区域）
        let backButtonFrame = CGRect(
            x: 16,
            y: 8,  // 调整到导航栏顶部区域
            width: 44,
            height: 44
        )
        
        return ZStack {
            // 带挖空的遮罩 - 允许点击穿透到挖空区域
            HollowMaskView(
                highlightFrame: backButtonFrame,
                highlightType: .circle,
                cornerRadius: 22
            )
            
            // 圆形高亮边框 - 仅视觉，不拦截点击
            HighlightPulseViewNoClick(
                center: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                radius: 28
            )
            
            // 小猫爪点击动画 - 仅视觉，不拦截点击
            if aiAnalysisStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                    delay: 0.5
                )
            }
            
            // 引导对话框（底部）
            VStack {
                Spacer()
                
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    // 步骤2：点击VIP卡片
    private func step2Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        // 优先使用真实VIP卡片位置，兜底再用估算值（兼容两种卡片高度）
        let fallbackVIPFrame = CGRect(
            x: 16,
            y: screenBounds.height * 0.16,
            width: screenBounds.width - 32,
            height: VIPManager.shared.isVIP ? 180 : 100
        )
        let vipCardFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .aiAnalysisVIPCard),
            in: geometry,
            fallback: fallbackVIPFrame
        )
        
        return ZStack {
            // 带挖空的遮罩（圆角矩形）
            HollowMaskView(
                highlightFrame: vipCardFrame,
                highlightType: .roundedRect,
                cornerRadius: 20
            )
            
            // 圆角矩形高亮边框
            RoundedRectHighlightView(
                frame: vipCardFrame,
                cornerRadius: 20
            )
            .allowsHitTesting(false)
            
            // 引导对话框（底部）
            VStack {
                Spacer()
                
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    // 步骤3：兑换会员时长
    private func step3Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        // 优先使用真实按钮位置；按反馈将高亮略微下移，避免偏上
        let fallbackExchangeFrame = CGRect(
            x: 20,
            y: screenBounds.height * 0.44,
            width: screenBounds.width - 40,
            height: 56
        )
        let exchangeButtonFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .aiAnalysisExchangeButton),
            in: geometry,
            fallback: fallbackExchangeFrame
        )
        .offsetBy(dx: 0, dy: 10)
        
        return ZStack {
            // 带挖空的遮罩（圆角矩形）
            HollowMaskView(
                highlightFrame: exchangeButtonFrame,
                highlightType: .roundedRect,
                cornerRadius: 12
            )
            
            // 圆角矩形高亮边框
            RoundedRectHighlightView(
                frame: exchangeButtonFrame,
                cornerRadius: 12
            )
            .allowsHitTesting(false)
            
            // 小猫爪点击动画
            if aiAnalysisStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: exchangeButtonFrame.midX, y: exchangeButtonFrame.midY),
                    delay: 0.5
                )
                .allowsHitTesting(false)
            }
            
            // 引导对话框（顶部）
            VStack {
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.top, 100)
                
                Spacer()
            }
        }
    }

    private func aiGuideTargetFrame(
        globalFrame: CGRect?,
        in geometry: GeometryProxy,
        fallback: CGRect
    ) -> CGRect {
        guard let globalFrame, globalFrame.width > 0, globalFrame.height > 0 else {
            return fallback
        }
        
        let overlayGlobalOrigin = geometry.frame(in: .global).origin
        return CGRect(
            x: globalFrame.minX - overlayGlobalOrigin.x,
            y: globalFrame.minY - overlayGlobalOrigin.y,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }

    // 萌宠智能对话引导对话框 - 复用开屏首次新手引导的PointingBubbleView设计
    private func aiAnalysisBubble(
        step: AIAnalysisGuideStep,
        onSkip: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) -> some View {
        AIAnalysisGuideBubbleView(
            step: step,
            onSkip: onSkip,
            onComplete: onComplete
        )
    }

    // MARK: - 通用引导内容

    private func genericGuideContent(for feature: FeatureItem) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: feature.icon)
                    .font(.system(size: 50))
                    .foregroundStyle(magicPalette.accent)

                Text(feature.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(magicPalette.primaryText)

                Text("探索这个神奇的功能")
                    .font(.subheadline)
                    .foregroundStyle(magicPalette.secondaryText)

                Button {
                    guideManager.completeFeatureExperienceGuide()
                } label: {
                    Text("知道了")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(magicPalette.bubbleUserTextColor)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(magicPalette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(magicPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - 萌宠智能对话引导气泡视图（复用PointingBubbleView设计风格）

private extension FeatureExperienceGuideOverlay {
    func featureStepBubble(
        title: String,
        message: String,
        currentStep: Int,
        totalSteps: Int,
        accent: Color,
        actionTitle: String?,
        onSkip: @escaping () -> Void,
        onAction: (() -> Void)?
    ) -> some View {
        GenericFeatureGuideBubbleView(
            title: title,
            message: message,
            currentStep: currentStep,
            totalSteps: totalSteps,
            accent: accent,
            actionTitle: actionTitle,
            onSkip: onSkip,
            onAction: onAction
        )
    }
}

struct GenericFeatureGuideBubbleView: View {
    let title: String
    let message: String
    let currentStep: Int
    let totalSteps: Int
    let accent: Color
    let actionTitle: String?
    let onSkip: () -> Void
    let onAction: (() -> Void)?

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var effectiveAccent: Color {
        accent.mixed(with: magicPalette.accent, amount: 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(1...max(totalSteps, 1), id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? effectiveAccent : magicPalette.tertiaryText.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                }

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)

                if let actionTitle {
                    Button {
                        onAction?()
                    } label: {
                        Text(actionTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [effectiveAccent, effectiveAccent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(magicPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 320)
        .padding(.horizontal, 20)
    }
}

struct AIAnalysisGuideBubbleView: View {
    let step: AIAnalysisGuideStep
    let onSkip: () -> Void
    let onComplete: () -> Void
    
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 跳过按钮
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            VStack(spacing: 12) {
                // 步骤指示器
                HStack(spacing: 4) {
                    ForEach(AIAnalysisGuideStep.allCases, id: \.rawValue) { s in
                        Circle()
                            .fill(s.rawValue <= step.rawValue ? magicPalette.accent : magicPalette.tertiaryText.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Text(step.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)
                
                Text(step.message)
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)
                
                // 完成按钮（仅在最后一步显示）
                if step == .step3_exchange {
                    Button {
                        onComplete()
                    } label: {
                        Text("知道了")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [magicPalette.accent, magicPalette.accent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(magicPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 320)
        .padding(.horizontal, 20)
    }
}

// MARK: - 小组件定制引导气泡视图

struct WidgetScrollHintView: View {
    let title: String
    let subtitle: String
    @State private var animateHint = false
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    init(
        title: String = "请向下滑动",
        subtitle: String = "小组件入口在更下方的豆腐块区域"
    ) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(magicPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
            )

            VStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(magicPalette.accent)
                    .offset(y: animateHint ? 18 : -4)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(magicPalette.accent.opacity(0.96))
                    .scaleEffect(animateHint ? 1.08 : 0.94)
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
                    .offset(y: animateHint ? 14 : 0)
            }
            .opacity(0.98)

            Spacer()
        }
        .padding(.bottom, 180)
        .onAppear {
            guard !animateHint else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                animateHint = true
            }
        }
    }
}

struct WidgetCustomizeGuideBubbleView: View {
    let step: WidgetCustomizeGuideStep
    let onSkip: () -> Void
    let onComplete: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(WidgetCustomizeGuideStep.allCases, id: \.rawValue) { current in
                        Circle()
                            .fill(current.rawValue <= step.rawValue ? magicPalette.accent : magicPalette.tertiaryText.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                }

                Text(step.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text(step.message)
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)

                if step == .step4_widgetExplanation {
                    Button {
                        onComplete()
                    } label: {
                        Text("知道了")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [magicPalette.accent, magicPalette.accent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(magicPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 320)
        .padding(.horizontal, 20)
    }
}

// MARK: - 来财引导气泡视图

struct WealthGuideBubbleView: View {
    let step: WealthGuideStep
    let onSkip: () -> Void
    let onNext: (() -> Void)?
    let onComplete: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var actionTitle: String? {
        switch step {
        case .step3_divination:
            return "下一步：数钱"
        case .step4_moneyCounting:
            return "下一步：安财"
        case .step5_wealthStorage:
            return "知道了"
        default:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(WealthGuideStep.allCases, id: \.rawValue) { s in
                        Circle()
                            .fill(s.rawValue <= step.rawValue ? magicPalette.accent : magicPalette.tertiaryText.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                }

                Text(step.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text(step.message)
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)

                if let actionTitle {
                    Button {
                        if step == .step5_wealthStorage {
                            onComplete()
                        } else {
                            onNext?()
                        }
                    } label: {
                        Text(actionTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [magicPalette.accent, magicPalette.accent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(magicPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 320)
        .padding(.horizontal, 20)
    }
}
