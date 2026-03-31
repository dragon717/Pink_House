import Foundation
import SwiftUI
import Combine
import UIKit

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
    @Published private var guideInteractiveRegions: [String: CGRect] = [:]
    @Published private(set) var guideTargetCaptureVersion: UInt = 0
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
    private let firstCompletionRewardClaimedKey = "newbieGuide.firstCompletionRewardClaimed"
    private let firstCompletionRewardAmount = 888
    
    let runningVideoName = "naicha_new_role"
    let pointingVideoName = "naicha_pointto"
    let runningDuration: TimeInterval = 5.0  // 跑步动画持续5秒
    
    // 小猫跑步终点位置（右上角）
    var createButtonPosition: CGPoint {
        let screenBounds = UIScreen.main.bounds
        let addButtonFrame = firstLaunchAddButtonGuideFrame
        let horizontalOffset = min(max(screenBounds.width * 0.075, addButtonFrame.width * 0.75), 44)
        let verticalOffset = min(max(screenBounds.height * 0.035, addButtonFrame.height * 0.78), 42)
        return CGPoint(
            x: max(32, addButtonFrame.midX - horizontalOffset),
            y: min(screenBounds.height - 140, addButtonFrame.midY + verticalOffset)
        )
    }
    
    // 高亮圈位置（+ 号按钮位置）- 可以独立调整
    var highlightCirclePosition: CGPoint {
        let addButtonFrame = firstLaunchAddButtonGuideFrame
        return CGPoint(x: addButtonFrame.midX, y: addButtonFrame.midY)
    }
    
    // 悬浮小猫起始位置（底部中间）- 往上移动
    var floatingCatStartPosition: CGPoint {
        let screenBounds = UIScreen.main.bounds
        let proportionalDownOffset = screenBounds.height * 0.024
        let maxAllowedY = screenBounds.height - max(currentWindowSafeAreaBottom + 92, 108)
        let targetY = min(screenBounds.height - 155 + proportionalDownOffset, maxAllowedY)
        return CGPoint(x: screenBounds.width / 2, y: targetY)
    }
    
    // MARK: - 计算属性
    
    var isFirstLaunch: Bool {
        return !UserDefaults.standard.bool(forKey: hasSeenWelcomeKey)
    }
    
    var shouldShowGuide: Bool {
        return !state.isCompleted && isFirstLaunch
    }

    var isPadGuideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var shouldUseGuideFallbackFrames: Bool {
        !isPadGuideLayout
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
        resetGuideInteractiveRegions()
        requestGuideTargetRecapture()
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
        resetGuideInteractiveRegions()
    }

    /// 关闭功能体验引导（不标记为完成）
    func dismissFeatureExperienceGuide() {
        isShowingFeatureExperienceGuide = false
        currentFeatureExperienceFeature = nil
        resetFeatureGuideTargetFrames()
        resetGuideInteractiveRegions()
    }

    // MARK: - 萌宠智能对话引导目标位置信息

    func guideTargetFrame(for key: GuideTargetKey) -> CGRect? {
        guideTargetFrames[key]
    }

    func normalizedTopTrailingToolbarButtonFrame(
        _ frame: CGRect,
        containerSize: CGSize,
        safeAreaTop: CGFloat
    ) -> CGRect {
        let minimumSide: CGFloat = 40
        let maximumSide: CGFloat = 48
        var normalized = frame

        let looksLikeGroupedCapsule = frame.width > frame.height * 1.45 && frame.width > 52
        if looksLikeGroupedCapsule {
            let targetSide = min(max(frame.height - 6, minimumSide), maximumSide)
            normalized = CGRect(
                x: frame.maxX - targetSide - 4,
                y: frame.midY - targetSide / 2,
                width: targetSide,
                height: targetSide
            )
        }

        let looksLikeIconOnlyCapture = normalized.width < 30 || normalized.height < 30
        if looksLikeIconOnlyCapture || normalized.width < minimumSide || normalized.height < minimumSide {
            let targetSide = min(
                max(max(normalized.width, normalized.height) + (looksLikeIconOnlyCapture ? 22 : 8), minimumSide),
                maximumSide
            )
            let verticalBias = looksLikeIconOnlyCapture
                ? min(max(containerSize.height * 0.012, targetSide * 0.24), targetSide * 0.40)
                : 0
            normalized = CGRect(
                x: normalized.midX - targetSide / 2,
                y: normalized.midY - targetSide / 2 + verticalBias,
                width: targetSide,
                height: targetSide
            )
        }

        let minX: CGFloat = 8
        let maxX = max(minX, containerSize.width - normalized.width - 8)
        let minY = max(safeAreaTop + 6, 12)
        let maxY = max(minY, containerSize.height * 0.34)

        return CGRect(
            x: min(max(normalized.minX, minX), maxX),
            y: min(max(normalized.minY, minY), maxY),
            width: normalized.width,
            height: normalized.height
        )
    }

    private var currentWindowSafeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }

    private var currentWindowSafeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
    }

    private var firstLaunchAddButtonGuideFrame: CGRect {
        let screenBounds = UIScreen.main.bounds
        let safeAreaTop = currentWindowSafeAreaTop
        let fallbackFrame = CGRect(
            x: screenBounds.width - 56,
            y: max(safeAreaTop + 6, 12),
            width: 40,
            height: 40
        )

        if let moreMenuGlobalFrame = guideTargetFrame(for: .wardrobeMoreMenuButton),
           moreMenuGlobalFrame.width > 0,
           moreMenuGlobalFrame.height > 0 {
            let moreButtonFrame = normalizedTopTrailingToolbarButtonFrame(
                moreMenuGlobalFrame,
                containerSize: screenBounds.size,
                safeAreaTop: safeAreaTop
            )
            let inferredAddFrame = CGRect(
                x: min(screenBounds.width - moreButtonFrame.width - 8, moreButtonFrame.maxX + 8),
                y: moreButtonFrame.minY,
                width: moreButtonFrame.width,
                height: moreButtonFrame.height
            )
            return normalizedTopTrailingToolbarButtonFrame(
                inferredAddFrame,
                containerSize: screenBounds.size,
                safeAreaTop: safeAreaTop
            )
        }

        let capturedFrame = guideTargetFrame(for: .wardrobeAddButton) ?? fallbackFrame
        return normalizedTopTrailingToolbarButtonFrame(
            capturedFrame,
            containerSize: screenBounds.size,
            safeAreaTop: safeAreaTop
        )
    }

    func updateGuideTargetFrame(_ frame: CGRect, for key: GuideTargetKey) {
        guard frame.width > 0, frame.height > 0 else { return }
        guideTargetFrames[key] = frame
    }

    func requestGuideTargetRecapture() {
        guideTargetCaptureVersion &+= 1
    }

    func updateGuideInteractiveRegion(_ frame: CGRect, for id: String) {
        guard frame.width > 0, frame.height > 0 else { return }
        guideInteractiveRegions[id] = frame
    }

    func clearGuideInteractiveRegion(for id: String) {
        guideInteractiveRegions[id] = nil
    }

    func resetGuideInteractiveRegions() {
        guideInteractiveRegions.removeAll()
    }

    func hasGuideInteractiveRegions() -> Bool {
        !guideInteractiveRegions.isEmpty
    }

    func isPointInGuideInteractiveRegions(_ point: CGPoint, hitSlop: CGFloat = 12) -> Bool {
        guideInteractiveRegions.values.contains { region in
            region.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point)
        }
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
            .aiAnalysisVIPTrialConfirmButton,
            .homeHouseTab,
            .homePetChatTab,
            .petChatSearchBar,
            .petChatGuideOptionButton,
            .wealthEntry,
            .wealthMainTabSegment,
            .accountSyncEntry,
            .cloudAppleSignInButton,
            .cloudFileBackupSection,
            .iCloudRealtimeSyncSection,
            .systemSettingsEntry,
            .localBackupDataAction,
            .localRestoreDataAction,
            .exportCSVEntry,
            .widgetCustomizeEntry,
            .themeCustomizeEntry,
            .themeCustomPersonalizationEntry,
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
            .wardrobeShortcutManualCreateAction,
            .wardrobeShortcutBatchImportAction,
            .wardrobeMoreMenuButton,
            .wardrobeEditMenuEntry,
            .wardrobeBatchEditToolbar,
            .wardrobeSelectionCard,
            .wardrobeDoneSelectionButton,
            .ootdEntry,
            .calendarEntry,
            .favoriteMenuSettingsEntry,
            .favoriteMenuMagicStickerAddButton,
            .favoriteMenuMagicStickerEntry,
            .themeColorModeTabs,
            .spaceBookModeTabs,
            .spaceBookShelfMoreMenuButton,
            .spaceBookFirstBookCard,
            .spaceBookDetailMoreMenuButton,
            .spaceBookFirstPageCard,
            .spatialCanvasToolbar,
            .spatialCanvasImportMenu
        ])
    }

    /// 完成引导
    func completeGuide(shouldGrantFirstCompletionReward: Bool = true) {
        let wasCompletedBefore = state.isCompleted

        state.isCompleted = true
        currentStep = .complete
        isShowingGuide = false
        isRunningAnimation = false
        showPointingVideo = false
        showCreateButtonHighlight = false
        resetGuideInteractiveRegions()

        if shouldGrantFirstCompletionReward, !wasCompletedBefore {
            grantFirstCompletionRewardIfNeeded()
        }
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
        resetGuideInteractiveRegions()
        UserDefaults.standard.set(false, forKey: hasSeenWelcomeKey)
        saveState()
    }

    private func grantFirstCompletionRewardIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: firstCompletionRewardClaimedKey) else { return }

        UserDefaults.standard.set(true, forKey: firstCompletionRewardClaimedKey)
        RewardManager.shared.triggerReward(
            type: .custom(
                amount: firstCompletionRewardAmount,
                message: "首次完成新手引导，鱼币 +\(firstCompletionRewardAmount)"
            )
        )
    }
}

// MARK: - 功能体验引导遮罩视图

struct FeatureExperienceGuideOverlay: View {
    @StateObject var guideManager = AppFirstLaunchGuideManager.shared
    @StateObject var authManager = AuthenticationManager.shared
    @StateObject var favoriteMenuSettingsManager = FavoriteMenuSettingsManager.shared
    @State var showingFullDescription = false
    @Environment(ThemeManager.self) var themeManager
    @Environment(\.colorScheme) var colorScheme
    
    // 跨页面引导专用状态
    @State var aiAnalysisStep: AIAnalysisGuideStep = .preUnlockStep1ReturnToMe
    @State var widgetCustomizeStep: WidgetCustomizeGuideStep = .step1_returnToMe
    @State var wardrobeAddGuideStep: WardrobeAddGuideStep = .step1_clickAddButton
    @State var themeCustomizeGuideStep: ThemeCustomizeGuideStep = .step1_returnToMe
    @State var localFileBackupRestoreGuideStep: LocalFileBackupRestoreGuideStep = .step1_returnToMe
    @State var exportCSVGuideStep: ExportCSVGuideStep = .step1_returnToMe
    @State var cloudFileBackupRestoreGuideStep: CloudFileBackupRestoreGuideStep = .step1_returnToMe
    @State var themeScrollStepStartedAt: Date? = nil
    @State var customColorScrollStepStartedAt: Date? = nil
    @State var customColorPersonalizationGuideStep: CustomColorPersonalizationGuideStep = .step1_returnToMe
    @State var personalPreferenceGuideStep: PersonalPreferenceGuideStep = .step1_returnToMe
    @State var privacyDisplayGuideStep: PrivacyDisplayGuideStep = .step1_returnToMe
    @State var tagBrandFieldGuideStep: TagBrandFieldGuideStep = .step1_returnToMe
    @State var ootdGuideStep: OOTDGuideStep = .step1_clickOotdEntry
    @State var calendarGuideStep: CalendarGuideStep = .step1_clickCalendarEntry
    @State var magicStickerGuideStep: MagicStickerGuideStep = .step6_longPressHouseTab
    @State var magicStickerGuideRequiresMenuSetup: Bool = false
    @State var batchEditGuideStep: BatchEditGuideStep = .step1_clickMoreMenu
    @State var didOpenBatchEditMoreMenu: Bool = false
    @State var spaceBookGuideStep: SpaceBookGuideStep = .preUnlockStep1_clickWardrobeOotdEntry
    @State var wealthGuideStep: WealthGuideStep = .step1_clickHouseTab
    @State var currentTab: String = "wardrobe"
    @State var isSpaceBookCreationPromptVisible: Bool = false
    @State var hasSpaceBooksForGuide: Bool = false
    @State var hasNonDefaultSpaceBooksForGuide: Bool = false  // 是否有非默认手帐（用于进入时判断逻辑）
    @State var hasSpaceBookPagesForGuide: Bool = false

    var magicPalette: MagicThemePalette {
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
                   aiAnalysisStep == .preUnlockStep1ReturnToMe,
                   tab == "me",
                   guideManager.guideTargetFrame(for: .aiAnalysisVIPCard) != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .preUnlockStep2ClickVIP
                    }
                }

                if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                   aiAnalysisStep == .postUnlockStep1ClickPetChatTab,
                   tab == "petChat" {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .postUnlockStep2ClickSearchBar
                    }
                }

                if guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                   widgetCustomizeStep == .step1_returnToMe,
                   tab == "me" {
                    advanceWidgetGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .ootdDefaultBook,
                   magicStickerGuideStep == .step1_returnToMeForMenuSetup,
                   tab == "me" {
                    advanceMagicStickerGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .themeCustomize,
                   themeCustomizeGuideStep == .step1_returnToMe,
                   tab == "me" {
                    advanceThemeGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .customColorPersonalization,
                   customColorPersonalizationGuideStep == .step1_returnToMe,
                   tab == "me" {
                    advanceCustomColorPersonalizationGuideFromReturnStep()
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
                if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                   aiAnalysisStep == .preUnlockStep1ReturnToMe {
                    if guideManager.lastKnownHomeTab == "me",
                       guideManager.guideTargetFrame(for: .aiAnalysisVIPCard) != nil {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            aiAnalysisStep = .preUnlockStep2ClickVIP
                        }
                    }
                }
                if guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                   widgetCustomizeStep == .step1_returnToMe {
                    advanceWidgetGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .ootdDefaultBook,
                   magicStickerGuideStep == .step1_returnToMeForMenuSetup {
                    advanceMagicStickerGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .themeCustomize,
                   themeCustomizeGuideStep == .step1_returnToMe {
                    advanceThemeGuideFromReturnStep()
                }
                if guideManager.currentFeatureExperienceFeature == .customColorPersonalization,
                   customColorPersonalizationGuideStep == .step1_returnToMe {
                    advanceCustomColorPersonalizationGuideFromReturnStep()
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
            .onReceive(NotificationCenter.default.publisher(for: .petChatGuideOptionTapped)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }

                if aiAnalysisStep == .postUnlockStep2ClickSearchBar ||
                    (aiAnalysisStep == .postUnlockStep1ClickPetChatTab && currentTab == "petChat") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .postUnlockStep3FeatureIntro
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: FeatureUnlockManager.featureUnlockedNotification)) { notification in
                guard let feature = notification.userInfo?["feature"] as? FeatureItem else { return }

                // AI 分析功能解锁后，自动切换到解锁后引导流程
                if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                   feature == .aiAnalysis,
                   aiAnalysisStep.flow == .preUnlock {
                    print("[FeatureExperienceGuide] AI分析已解锁，切换到解锁后引导流程")

                    // 关闭魔法任务页面
                    NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)

                    // 延迟切换到解锁后引导
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }

                        withAnimation(.easeInOut(duration: 0.3)) {
                            aiAnalysisStep = .postUnlockStep1ClickPetChatTab
                        }
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
                   aiAnalysisStep == .preUnlockStep2ClickVIP {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .preUnlockStep3Exchange
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .vipExchangeAttempted)) { _ in
                if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                   aiAnalysisStep == .preUnlockStep3Exchange {
                    guideManager.completeFeatureExperienceGuide()
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
                if guideManager.currentFeatureExperienceFeature == .customColorPersonalization,
                   customColorPersonalizationGuideStep.rawValue < CustomColorPersonalizationGuideStep.step4_switchToCustomTab.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        customColorPersonalizationGuideStep = .step4_switchToCustomTab
                    }
                    if themeManager.colorSchemeMode == .custom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            guard guideManager.currentFeatureExperienceFeature == .customColorPersonalization,
                                  customColorPersonalizationGuideStep == .step4_switchToCustomTab else { return }
                            withAnimation(.easeInOut(duration: 0.3)) {
                                customColorPersonalizationGuideStep = .step5_scrollToPersonalization
                            }
                            // 如果个性化入口已经可见，直接跳到说明步骤
                            if let frame = guideManager.guideTargetFrame(for: .themeCustomPersonalizationEntry),
                               isGuideTargetVisibleOnScreen(frame) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    guard customColorPersonalizationGuideStep == .step5_scrollToPersonalization else { return }
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        customColorPersonalizationGuideStep = .step6_personalizationExplanation
                                    }
                                }
                            }
                        }
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
                if guideManager.currentFeatureExperienceFeature == .customColorPersonalization,
                   customColorPersonalizationGuideStep == .step4_switchToCustomTab,
                   mode == ColorSchemeMode.custom.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        customColorPersonalizationGuideStep = .step5_scrollToPersonalization
                    }
                    // 如果个性化入口已经可见，直接跳到说明步骤
                    if let frame = guideManager.guideTargetFrame(for: .themeCustomPersonalizationEntry),
                       isGuideTargetVisibleOnScreen(frame) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            guard customColorPersonalizationGuideStep == .step5_scrollToPersonalization else { return }
                            withAnimation(.easeInOut(duration: 0.3)) {
                                customColorPersonalizationGuideStep = .step6_personalizationExplanation
                            }
                        }
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
                        localFileBackupRestoreGuideStep = .step4_introBackupData
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
                   localFileBackupRestoreGuideStep == .step3_clickSystemSettings {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        localFileBackupRestoreGuideStep = .step4_introBackupData
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .localBackupTriggered)) { _ in
                if guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                   localFileBackupRestoreGuideStep.rawValue >= LocalFileBackupRestoreGuideStep.step6_firstBackup.rawValue {
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
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeMoreMenuOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .batchEdit,
                   batchEditGuideStep == .step1_clickMoreMenu {
                    didOpenBatchEditMoreMenu = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeAddMenuOpened)) { _ in
                advanceWardrobeAddGuideToChooseOptionIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeManualCreateOpened)) { _ in
                advanceWardrobeAddGuideToChooseOptionIfNeeded()
                guard let feature = guideManager.currentFeatureExperienceFeature else { return }
                if acceptsManualCreateGuideCompletion(for: feature) {
                    guideManager.completeFeatureExperienceGuide()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .wardrobeBatchImportOpened)) { _ in
                advanceWardrobeAddGuideToChooseOptionIfNeeded()
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
                    didOpenBatchEditMoreMenu = false
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
        let houseEntryBound = bindHouseEntryGuideEvents(content)
        let magicStickerSetupBound = bindMagicStickerSetupGuideEvents(houseEntryBound)
        let spaceBookStateBound = bindSpaceBookStateGuideEvents(magicStickerSetupBound)
        return bindSpaceBookEditorGuideEvents(spaceBookStateBound)
    }

    private func bindHouseEntryGuideEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .ootdShelfOpened)) { notification in
                if guideManager.currentFeatureExperienceFeature == .ootd,
                   ootdGuideStep == .step1_clickOotdEntry {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        ootdGuideStep = .step2_ootdExplanation
                    }
                }
                // 空间手帐引导：Step 1 -> 后续步骤（根据进入时判断逻辑）
                if guideManager.currentFeatureExperienceFeature == .spaceBook,
                   spaceBookGuideStep == .preUnlockStep1_clickWardrobeOotdEntry {
                    let hasNonDefaultBooks = notification.userInfo?["hasNonDefaultBooks"] as? Bool ?? false
                    let hasPages = notification.userInfo?["hasPages"] as? Bool ?? false
                    print("[Guide] Received ootdBookShelfOpened - hasNonDefaultBooks: \(hasNonDefaultBooks), hasPages: \(hasPages)")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if !hasNonDefaultBooks {
                            // 没有非默认手帐，引导创建手帐（Step 1 -> Step 2）
                            print("[Guide] Advancing to preUnlockStep2_createOotdBook")
                            spaceBookGuideStep = .preUnlockStep2_createOotdBook
                        } else if !hasPages {
                            // 有非默认手帐但没有书页，跳过Step 2直接进入Step 3（点击进入手帐）
                            print("[Guide] Skipping step2, advancing to preUnlockStep3_clickOotdBook")
                            spaceBookGuideStep = .preUnlockStep3_clickOotdBook
                        } else {
                            // 都有，直接到 Step 5（前置任务完成）
                            print("[Guide] Skipping step2-4, advancing to preUnlockStep5_complete")
                            spaceBookGuideStep = .preUnlockStep5_complete
                        }
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
                   magicStickerGuideStep == .step6_longPressHouseTab {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        magicStickerGuideStep = .step7_clickMagicStickerEntry
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ootdDefaultBookOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .ootdDefaultBook,
                   magicStickerGuideStep.rawValue < MagicStickerGuideStep.step8_magicStickerExplanation.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        magicStickerGuideStep = .step8_magicStickerExplanation
                    }
                }
            }
    }

    private func bindMagicStickerSetupGuideEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .favoriteMenuSettingsOpened)) { _ in
                advanceMagicStickerGuideToAddButtonStep()
            }
            .onReceive(NotificationCenter.default.publisher(for: .favoriteMenuSettingsViewDismissed)) { _ in
                advanceMagicStickerGuideToLongPressStep()
            }
    }

    private func bindSpaceBookStateGuideEvents<Content: View>(_ content: Content) -> some View {
        content
            // MARK: 前置任务引导事件（解锁前）
            // Step 1 -> Step 2: 进入穿搭手帐书架
            .onReceive(NotificationCenter.default.publisher(for: .ootdBookShelfOpened)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                // 前置任务引导：Step 1 -> Step 2
                if spaceBookGuideStep == .preUnlockStep1_clickWardrobeOotdEntry {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // 根据进入时的判断逻辑决定是否跳过Step 2
                        // 有非默认手帐则跳过Step 2
                        spaceBookGuideStep = shouldSkipPreUnlockStep2() ? .preUnlockStep3_clickOotdBook : .preUnlockStep2_createOotdBook
                    }
                }
            }
            // Step 2 -> Step 3: 创建了穿搭手帐
            .onReceive(NotificationCenter.default.publisher(for: .ootdBookCreated)) { notification in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                let isDefault = notification.userInfo?["isDefault"] as? Bool ?? false
                // 前置任务引导：Step 2 -> Step 3
                if spaceBookGuideStep == .preUnlockStep2_createOotdBook, !isDefault {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .preUnlockStep3_clickOotdBook
                    }
                }
            }
            // Step 3 -> Step 4: 进入手帐详情页
            .onReceive(NotificationCenter.default.publisher(for: .ootdBookDetailOpened)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                // 前置任务引导：Step 3 -> Step 4
                if spaceBookGuideStep == .preUnlockStep3_clickOotdBook {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // 根据进入时的判断逻辑决定是否跳过Step 4
                        // 有手帐且有书页则直接到Step 5
                        spaceBookGuideStep = shouldSkipPreUnlockStep4() ? .preUnlockStep5_complete : .preUnlockStep4_createOotdPage
                    }
                }
            }
            // Step 4 -> Step 5: 创建了书页
            .onReceive(NotificationCenter.default.publisher(for: .ootdPageCreated)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                // 前置任务引导：Step 4 -> Step 5（完成）
                if spaceBookGuideStep == .preUnlockStep4_createOotdPage {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .preUnlockStep5_complete
                    }
                }
            }

            // MARK: 完整功能引导事件（解锁后）
            // Step 6 -> Step 7: 进入穿搭手帐书架 -> 切换到空间页签
            .onReceive(NotificationCenter.default.publisher(for: .ootdBookShelfOpened)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                // 完整引导：Step 6 -> Step 7
                if spaceBookGuideStep == .step1_clickWardrobeOotdEntry {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step2_switchToSpaceTab
                    }
                }
            }
            // Step 7 -> Step 8: 切换到空间页签 -> 创建空间手帐
            .onReceive(NotificationCenter.default.publisher(for: .spatialBookShelfOpened)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                // 完整引导：Step 7 -> Step 8
                if spaceBookGuideStep == .step2_switchToSpaceTab {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step3_createSpaceBook
                    }
                }
            }
            // Step 8 -> Step 9: 创建/进入空间手帐详情
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookDetailOpened)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                // 完整引导：Step 8 -> Step 9
                if spaceBookGuideStep == .step3_createSpaceBook {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // 已有书页则跳过Step 9直接进入Step 10
                        spaceBookGuideStep = hasSpaceBookPagesForGuide ? .step5_enter3DEditor : .step4_createSpacePage
                    }
                }
            }
            // Step 9 -> Step 10: 创建空间书页
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookPageCreated)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                // 完整引导：Step 9 -> Step 10
                if spaceBookGuideStep == .step4_createSpacePage {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step5_enter3DEditor
                    }
                }
            }
            // 弹窗状态变化
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookCreationPromptVisibilityChanged)) { notification in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                let isVisible = notification.userInfo?["isVisible"] as? Bool ?? false
                isSpaceBookCreationPromptVisible = isVisible
            }
            // 书架数据状态
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookShelfDataStateChanged)) { notification in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                let hasBooks = notification.userInfo?["hasBooks"] as? Bool ?? false
                let hasNonDefaultBooks = notification.userInfo?["hasNonDefaultBooks"] as? Bool ?? false
                hasSpaceBooksForGuide = hasBooks
                hasNonDefaultSpaceBooksForGuide = hasNonDefaultBooks
            }
            // 详情页数据状态
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookDetailDataStateChanged)) { notification in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                let hasPages = notification.userInfo?["hasPages"] as? Bool ?? false
                hasSpaceBookPagesForGuide = hasPages
            }
    }

    private func bindSpaceBookEditorGuideEvents<Content: View>(_ content: Content) -> some View {
        content
            // Step 10 -> Step 11: 进入3D编辑器
            .onReceive(NotificationCenter.default.publisher(for: .spatialCanvasEditorOpened)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                // 完整引导：Step 10 -> Step 11
                if spaceBookGuideStep == .step5_enter3DEditor {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step6_openScanner
                    }
                }
            }
            // Step 11 -> Step 12: 打开空间扫描器
            .onReceive(NotificationCenter.default.publisher(for: .objectCaptureScannerOpened)) { _ in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                // 完整引导：Step 11 -> Step 12（最后一步）
                if spaceBookGuideStep == .step6_openScanner {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step7_scannerHowTo
                    }
                }
            }
    }

    // MARK: - 空间手帐进入时的判断逻辑
    /// 流程图关键逻辑：
    /// - 有非默认手帐？→ 跳过Step 2
    /// - 有手帐且有书页？→ 直接到Step 5
    /// - 只有默认手帐？→ 从Step 2开始
    /// - 注：默认手帐(title="默认手帐")不算！

    /// 是否应该跳过前置任务 Step 2（新建手帐）
    /// 条件：用户已有非默认手帐
    private func shouldSkipPreUnlockStep2() -> Bool {
        // 根据流程图：有非默认手帐 → 跳过 Step 2
        return hasNonDefaultSpaceBooksForGuide
    }

    /// 是否应该跳过前置任务 Step 4（新建书页）
    /// 条件：用户已有手帐且有书页
    private func shouldSkipPreUnlockStep4() -> Bool {
        // 根据流程图：有手帐且有书页 → 直接到 Step 5
        return hasSpaceBookPagesForGuide
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
            .onChange(of: guideManager.guideTargetFrame(for: .aiAnalysisVIPCard)) { _, vipCardFrame in
                if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                   aiAnalysisStep == .preUnlockStep1ReturnToMe,
                   currentTab == "me",
                   vipCardFrame != nil {
                    print("[FeatureExperienceGuide] 检测到在me界面且VIP卡片frame已采集，step1进入step2")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .preUnlockStep2ClickVIP
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
                   magicStickerGuideStep == .step6_longPressHouseTab,
                   frame != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        magicStickerGuideStep = .step7_clickMagicStickerEntry
                    }
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .favoriteMenuMagicStickerAddButton)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .ootdDefaultBook,
                   magicStickerGuideRequiresMenuSetup,
                   magicStickerGuideStep == .step3_clickFavoriteMenuSettings,
                   frame != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        magicStickerGuideStep = .step4_addMagicStickerButton
                    }
                }
            }
            .onChange(of: favoriteMenuSettingsManager.selectedItems) { _, _ in
                advanceMagicStickerGuideToReturnAfterSetupStep()
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
            .onChange(of: guideManager.guideTargetFrame(for: .localBackupDataAction)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                   localFileBackupRestoreGuideStep == .step3_clickSystemSettings,
                   frame != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        localFileBackupRestoreGuideStep = .step4_introBackupData
                    }
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .localRestoreDataAction)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                   localFileBackupRestoreGuideStep == .step3_clickSystemSettings,
                   frame != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        localFileBackupRestoreGuideStep = .step4_introBackupData
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
                if guideManager.currentFeatureExperienceFeature == .customColorPersonalization,
                   customColorPersonalizationGuideStep == .step2_scrollToThemeEntry,
                   frame != nil {
                    advanceCustomColorGuideToClickStepWithMinimumDwell()
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .themeCustomPersonalizationEntry)) { _, frame in
                if guideManager.currentFeatureExperienceFeature == .customColorPersonalization,
                   customColorPersonalizationGuideStep == .step5_scrollToPersonalization,
                   let frame,
                   isGuideTargetVisibleOnScreen(frame) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        customColorPersonalizationGuideStep = .step6_personalizationExplanation
                    }
                }
            }
            .onChange(of: guideManager.guideTargetFrame(for: .favoriteMenuSettingsEntry)) { _, frame in
                // 魔法贴纸引导：滚动到常用菜单入口可见时，推进到点击步骤
                if guideManager.currentFeatureExperienceFeature == .ootdDefaultBook,
                   magicStickerGuideStep == .step2_scrollToFavoriteMenu,
                   let frame,
                   isGuideTargetVisibleOnScreen(frame) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        magicStickerGuideStep = .step3_clickFavoriteMenuSettings
                    }
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

    // MARK: - 空间手帐引导
    // 根据流程图：https://github.com/Pink_House/docs/space_book_guide_flow.png
    // 阶段1: 未解锁时（前置任务引导 - 共5步）
    // 阶段2: 已解锁后（完整引导 - 共11步）

    var spaceBookGuideContent: some View {
        // 1. 先检查 ootd 是否解锁，如果未解锁，引导用户先完成 ootd 新手引导（解锁穿搭手帐功能）
        if !FeatureUnlockManager.shared.isUnlocked(.ootd) {
            return AnyView(ootdGuideContent)
        }

        // 2. ootd 已解锁，根据 spaceBook 解锁状态决定引导流程
        return AnyView(
            GeometryReader { geometry in
                switch spaceBookGuideStep {
                // MARK: 阶段1: 前置任务引导（解锁前）
                case .preUnlockStep1_clickWardrobeOotdEntry:
                    spaceBookPreUnlockStep1Content(in: geometry)
                case .preUnlockStep2_createOotdBook:
                    spaceBookPreUnlockStep2Content(in: geometry)
                case .preUnlockStep3_clickOotdBook:
                    spaceBookPreUnlockStep3Content(in: geometry)
                case .preUnlockStep4_createOotdPage:
                    spaceBookPreUnlockStep4Content(in: geometry)
                case .preUnlockStep5_complete:
                    spaceBookPreUnlockStep5Content()

                // MARK: 阶段2: 完整功能引导（解锁后）
                case .step1_clickWardrobeOotdEntry:
                    spaceBookPostUnlockStep0Content(in: geometry)
                case .step2_switchToSpaceTab:
                    spaceBookPostUnlockStep1Content(in: geometry)
                case .step3_createSpaceBook:
                    spaceBookPostUnlockStep2Content(in: geometry)
                case .step4_createSpacePage:
                    spaceBookPostUnlockStep3Content(in: geometry)
                case .step5_enter3DEditor:
                    spaceBookPostUnlockStep4Content(in: geometry)
                case .step6_openScanner:
                    spaceBookPostUnlockStep5Content(in: geometry)
                case .step7_scannerHowTo:
                    spaceBookPostUnlockStep6Content()
                }
            }
        )
    }

    // MARK: 阶段1: 前置任务引导（解锁前）- 共5步

    /// Step 1: 点击衣橱「穿搭手帐」
    func spaceBookPreUnlockStep1Content(in geometry: GeometryProxy) -> some View {
        let targetFrame = wardrobeOotdEntryGuideFrame(in: geometry)
        return highlightedRectGuideContent(
            frame: targetFrame,
            cornerRadius: 18,
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: nil,
            onAction: nil
        )
    }

    /// Step 2: 右上角「更多」→ 新建手帐
    func spaceBookPreUnlockStep2Content(in geometry: GeometryProxy) -> some View {
        let fallbackFrame = CGRect(
            x: geometry.size.width - 70,
            y: max(geometry.safeAreaInsets.top + 12, 16),
            width: 50,
            height: 50
        )
        let targetFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .ootdShelfMoreMenuButton),
            in: geometry,
            fallback: fallbackFrame
        )
        return highlightedRectGuideContent(
            frame: targetFrame,
            cornerRadius: 12,
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: nil,
            onAction: nil
        )
    }

    /// Step 3: 点击刚创建的手帐进入
    func spaceBookPreUnlockStep3Content(in geometry: GeometryProxy) -> some View {
        // 高亮第一个非默认手帐（用户刚创建的）
        let fallbackFrame = CGRect(
            x: 24,
            y: max(geometry.safeAreaInsets.top + 100, geometry.size.height * 0.22),
            width: min(180, geometry.size.width - 48),
            height: 220
        )
        let targetFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .ootdFirstNonDefaultBookCard),
            in: geometry,
            fallback: fallbackFrame
        )
        return highlightedRectGuideContent(
            frame: targetFrame,
            cornerRadius: 20,
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: nil,
            onAction: nil
        )
    }

    /// Step 4: 手帐详情页「更多」→ 新建书页
    func spaceBookPreUnlockStep4Content(in geometry: GeometryProxy) -> some View {
        let fallbackFrame = CGRect(
            x: geometry.size.width - 70,
            y: max(geometry.safeAreaInsets.top + 12, 16),
            width: 50,
            height: 50
        )
        let targetFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .ootdDetailMoreMenuButton),
            in: geometry,
            fallback: fallbackFrame
        )
        return highlightedRectGuideContent(
            frame: targetFrame,
            cornerRadius: 12,
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: nil,
            onAction: nil
        )
    }

    /// Step 5: 前置任务完成！自动解锁空间手帐
    func spaceBookPreUnlockStep5Content() -> some View {
        bottomBubbleGuideContent(
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: spaceBookGuideStep.completionButtonTitle,
            onAction: {
                // 解锁空间手帐
                _ = FeatureUnlockManager.shared.unlock(.spaceBook, force: true)
                // 标记引导完成
                guideManager.completeFeatureExperienceGuide()
            }
        )
    }

    // MARK: 阶段2: 完整功能引导（解锁后）- 共7步

    /// Step 6: 点击衣橱「穿搭手帐」（解锁后入口）
    func spaceBookPostUnlockStep0Content(in geometry: GeometryProxy) -> some View {
        let targetFrame = wardrobeOotdEntryGuideFrame(in: geometry)
        return highlightedRectGuideContent(
            frame: targetFrame,
            cornerRadius: 18,
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: nil,
            onAction: nil
        )
    }

    /// Step 7: 切换到空间页签
    func spaceBookPostUnlockStep1Content(in geometry: GeometryProxy) -> some View {
        let fallbackFrame = CGRect(
            x: (geometry.size.width - 160) / 2,
            y: max(geometry.safeAreaInsets.top + 8, 12),
            width: 160,
            height: 32
        )
        let targetFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .spaceBookModeTabs),
            in: geometry,
            fallback: fallbackFrame
        )
        return highlightedRectGuideContent(
            frame: targetFrame,
            cornerRadius: 12,
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: nil,
            onAction: nil
        )
    }

    /// Step 8: 创建空间手帐
    func spaceBookPostUnlockStep2Content(in geometry: GeometryProxy) -> AnyView {
        if hasSpaceBooksForGuide {
            // 用户已有空间手帐，引导点击第一本
            let fallbackFrame = CGRect(
                x: 24,
                y: max(geometry.safeAreaInsets.top + 100, geometry.size.height * 0.22),
                width: min(180, geometry.size.width - 48),
                height: 220
            )
            let targetFrame = aiGuideTargetFrame(
                globalFrame: guideManager.guideTargetFrame(for: .spaceBookFirstBookCard),
                in: geometry,
                fallback: fallbackFrame
            )
            return AnyView(highlightedRectGuideContent(
                frame: targetFrame,
                cornerRadius: 20,
                title: "直接点第一本空间手帐",
                message: "你已经有空间手帐了，不用新建。先点进第一本，我们继续下一步。",
                currentStep: spaceBookGuideStep.stepNumberInFlow,
                totalSteps: spaceBookGuideStep.totalStepsInFlow,
                accent: .blue,
                actionTitle: nil,
                onAction: nil
            ))
        } else if isSpaceBookCreationPromptVisible {
            // 新建弹窗已打开
            return AnyView(VStack {
                featureStepBubble(
                    title: "输入名称后点创建",
                    message: "已打开新建空间手帐弹窗，输入名称并点击创建，即可进入下一步。",
                    currentStep: spaceBookGuideStep.stepNumberInFlow,
                    totalSteps: spaceBookGuideStep.totalStepsInFlow,
                    accent: .blue,
                    actionTitle: nil,
                    onSkip: { guideManager.dismissFeatureExperienceGuide() },
                    onAction: nil
                )
                .padding(.top, max(geometry.safeAreaInsets.top + 24, 72))
                Spacer()
            })
        } else {
            // 引导点击右上角「更多」
            let fallbackFrame = CGRect(
                x: geometry.size.width - 70,
                y: max(geometry.safeAreaInsets.top + 12, 16),
                width: 50,
                height: 50
            )
            let targetFrame = aiGuideTargetFrame(
                globalFrame: guideManager.guideTargetFrame(for: .spaceBookShelfMoreMenuButton),
                in: geometry,
                fallback: fallbackFrame
            )
            return AnyView(highlightedRectGuideContent(
                frame: targetFrame,
                cornerRadius: 12,
                title: spaceBookGuideStep.title,
                message: spaceBookGuideStep.message,
                currentStep: spaceBookGuideStep.stepNumberInFlow,
                totalSteps: spaceBookGuideStep.totalStepsInFlow,
                accent: .blue,
                actionTitle: nil,
                onAction: nil
            ))
        }
    }

    /// Step 9: 创建空间书页
    func spaceBookPostUnlockStep3Content(in geometry: GeometryProxy) -> AnyView {
        if hasSpaceBookPagesForGuide {
            // 用户已有空间书页，引导点击第一张
            let fallbackFrame = CGRect(
                x: 24,
                y: geometry.size.height * 0.22,
                width: (geometry.size.width - 64) / 2,
                height: 180
            )
            let targetFrame = aiGuideTargetFrame(
                globalFrame: guideManager.guideTargetFrame(for: .spaceBookFirstPageCard),
                in: geometry,
                fallback: fallbackFrame
            )
            return AnyView(highlightedRectGuideContent(
                frame: targetFrame,
                cornerRadius: 12,
                title: "直接点第一张空间书页",
                message: "当前手帐里已经有书页了，不用新建，直接点第一张进入 3D 编辑。",
                currentStep: spaceBookGuideStep.stepNumberInFlow,
                totalSteps: spaceBookGuideStep.totalStepsInFlow,
                accent: .blue,
                actionTitle: nil,
                onAction: nil
            ))
        } else if isSpaceBookCreationPromptVisible {
            // 新建书页弹窗已打开
            return AnyView(VStack {
                featureStepBubble(
                    title: "输入书页名称后点创建",
                    message: "已打开新建书页弹窗，输入名称并点击创建，即可进入下一步。",
                    currentStep: spaceBookGuideStep.stepNumberInFlow,
                    totalSteps: spaceBookGuideStep.totalStepsInFlow,
                    accent: .blue,
                    actionTitle: nil,
                    onSkip: { guideManager.dismissFeatureExperienceGuide() },
                    onAction: nil
                )
                .padding(.top, max(geometry.safeAreaInsets.top + 24, 72))
                Spacer()
            })
        } else {
            // 引导点击右上角「更多」
            let fallbackFrame = CGRect(
                x: geometry.size.width - 70,
                y: max(geometry.safeAreaInsets.top + 12, 16),
                width: 50,
                height: 50
            )
            let targetFrame = aiGuideTargetFrame(
                globalFrame: guideManager.guideTargetFrame(for: .spaceBookDetailMoreMenuButton),
                in: geometry,
                fallback: fallbackFrame
            )
            return AnyView(highlightedRectGuideContent(
                frame: targetFrame,
                cornerRadius: 12,
                title: spaceBookGuideStep.title,
                message: spaceBookGuideStep.message,
                currentStep: spaceBookGuideStep.stepNumberInFlow,
                totalSteps: spaceBookGuideStep.totalStepsInFlow,
                accent: .blue,
                actionTitle: nil,
                onAction: nil
            ))
        }
    }

    /// Step 10: 进入3D编辑器
    func spaceBookPostUnlockStep4Content(in geometry: GeometryProxy) -> some View {
        let fallbackFrame = CGRect(
            x: 24,
            y: geometry.size.height * 0.22,
            width: (geometry.size.width - 64) / 2,
            height: 180
        )
        let targetFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .spaceBookFirstPageCard),
            in: geometry,
            fallback: fallbackFrame
        )
        return highlightedRectGuideContent(
            frame: targetFrame,
            cornerRadius: 12,
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: nil,
            onAction: nil
        )
    }

    /// Step 11: 打开空间扫描器
    func spaceBookPostUnlockStep5Content(in geometry: GeometryProxy) -> some View {
        let fallbackFrame = CGRect(
            x: 8,
            y: geometry.size.height * 0.42,
            width: 60,
            height: 96
        )
        let targetFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .spatialCanvasImportMenu),
            in: geometry,
            fallback: fallbackFrame
        )
        return highlightedRectGuideContent(
            frame: targetFrame,
            cornerRadius: 20,
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: nil,
            onAction: nil
        )
    }

    /// Step 12: 扫描操作指引
    func spaceBookPostUnlockStep6Content() -> some View {
        bottomBubbleGuideContent(
            title: spaceBookGuideStep.title,
            message: spaceBookGuideStep.message,
            currentStep: spaceBookGuideStep.stepNumberInFlow,
            totalSteps: spaceBookGuideStep.totalStepsInFlow,
            accent: .blue,
            actionTitle: spaceBookGuideStep.completionButtonTitle,
            onAction: {
                guideManager.completeFeatureExperienceGuide()
            }
        )
    }

    // MARK: - 批量编辑引导

    var batchEditGuideContent: some View {
        batchEditInteractiveGuideContent
    }

    // MARK: - OOTD手帐引导

    var ootdGuideContent: some View {
        if let preUnlockGuide = preUnlockWardrobeGuideContentIfNeeded(for: .ootd) {
            return preUnlockGuide
        }
        return AnyView(ootdUnlockedGuideContent)
    }

    // MARK: - 新增批量引导内容

    func localGuideTargetFrame(
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

    func wardrobeAddButtonGuideFrame(in geometry: GeometryProxy) -> CGRect {
        let fallbackFrame = CGRect(
            x: geometry.size.width - 54,
            y: max(geometry.safeAreaInsets.top + 8, 12),
            width: 36,
            height: 36
        )

        if let moreMenuGlobalFrame = guideManager.guideTargetFrame(for: .wardrobeMoreMenuButton),
           moreMenuGlobalFrame.width > 0, moreMenuGlobalFrame.height > 0 {
            let moreMenuLocalFrame = aiGuideTargetFrame(
                globalFrame: moreMenuGlobalFrame,
                in: geometry,
                fallback: fallbackFrame
            )
            let inferredFromMoreMenu = CGRect(
                x: min(geometry.size.width - moreMenuLocalFrame.width - 8, moreMenuLocalFrame.maxX + 8),
                y: moreMenuLocalFrame.minY,
                width: moreMenuLocalFrame.width,
                height: moreMenuLocalFrame.height
            )
            return normalizedWardrobeAddButtonFrame(inferredFromMoreMenu, in: geometry)
        }

        let capturedFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .wardrobeAddButton),
            in: geometry,
            fallback: fallbackFrame
        )

        return normalizedWardrobeAddButtonFrame(capturedFrame, in: geometry)
    }

    func normalizedWardrobeAddButtonFrame(
        _ frame: CGRect,
        in geometry: GeometryProxy
    ) -> CGRect {
        guideManager.normalizedTopTrailingToolbarButtonFrame(
            frame,
            containerSize: geometry.size,
            safeAreaTop: geometry.safeAreaInsets.top
        )
    }

    func wardrobeMenuAreaFrameFromAddButton(
        in geometry: GeometryProxy,
        addFrame: CGRect
    ) -> CGRect {
        let hasDraftContinueEntry = hasValidWardrobeDraftForGuide()
        // 增大宽度，覆盖整个菜单区域
        let menuWidth: CGFloat = 240
        // 标准 SwiftUI Menu 行高 44pt，稍微增加高度
        let menuHeight: CGFloat = hasDraftContinueEntry ? 156 : 112
        // 向左上偏移：x 减小（更靠左），y 减小（更靠上）
        let x = geometry.size.width - menuWidth - 8
        let y = addFrame.maxY - 8
        return CGRect(x: x, y: y, width: menuWidth, height: menuHeight)
    }

    func wardrobeMenuOptionFrameFromAddButton(
        in geometry: GeometryProxy,
        addFrame: CGRect,
        preferBatchImport: Bool
    ) -> CGRect {
        let hasDraftContinueEntry = hasValidWardrobeDraftForGuide()
        let menuFrame = wardrobeMenuAreaFrameFromAddButton(in: geometry, addFrame: addFrame)
        // 标准 SwiftUI Menu 行高 44pt
        let rowHeight: CGFloat = 44
        let baseRowIndex: CGFloat = preferBatchImport ? 1 : 0
        let rowIndex: CGFloat = baseRowIndex + (hasDraftContinueEntry ? 1 : 0)
        return CGRect(
            x: menuFrame.minX + 4,
            y: menuFrame.minY + 8 + rowHeight * rowIndex,
            width: menuFrame.width - 8,
            height: rowHeight
        )
    }

    func hasValidWardrobeDraftForGuide() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: "ClothingEditDraft") else { return false }
        return (try? JSONDecoder().decode(ClothingEditDraft.self, from: data)) != nil
    }

    func isCloseToExpectedWardrobeMenuOptionFrame(
        _ frame: CGRect,
        expected: CGRect
    ) -> Bool {
        // 放宽容差，让捕获的 frame 更容易被接受
        let verticalTolerance = max(60, expected.height * 1.5)
        let horizontalTolerance = max(90, expected.width * 0.6)
        let widthRatio = frame.width / max(expected.width, 1)
        let heightRatio = frame.height / max(expected.height, 1)

        return abs(frame.midY - expected.midY) <= verticalTolerance &&
            abs(frame.midX - expected.midX) <= horizontalTolerance &&
            widthRatio >= 0.35 && widthRatio <= 2.2 &&
            heightRatio >= 0.35 && heightRatio <= 2.2
    }

    func isReasonableWardrobeMenuCaptureFrame(
        _ frame: CGRect,
        in geometry: GeometryProxy,
        addFrame: CGRect
    ) -> Bool {
        // 放宽尺寸检查，Menu 项可能比预期小
        guard frame.width >= 60, frame.height >= 20 else { return false }
        // 放宽垂直位置限制：Menu 可以在屏幕上半部分（截图中就在上方）
        guard frame.minY < geometry.size.height * 0.65 else { return false }
        // 放宽水平位置检查，Menu 可能在按钮左侧或右侧
        guard abs(frame.midX - addFrame.midX) < geometry.size.width * 0.55 else { return false }
        // 确保 frame 不在太靠左的位置
        guard frame.maxX > geometry.size.width * 0.35 else { return false }
        // 放宽宽度限制
        guard frame.width <= geometry.size.width * 0.85 else { return false }
        return true
    }

    func wardrobeGuideStep2Frame(
        in geometry: GeometryProxy,
        addFrame: CGRect
    ) -> CGRect {
        // 直接高亮整个菜单区域，不精确捕获单个选项
        let menuFrame = wardrobeMenuAreaFrameFromAddButton(in: geometry, addFrame: addFrame)
        // 扩大范围确保覆盖完整菜单
        return menuFrame.insetBy(dx: -12, dy: -12)
    }

    func wardrobeShortcutActionFallbackFrame(in geometry: GeometryProxy) -> CGRect {
        let buttonWidth = min(288, geometry.size.width - 48)
        let buttonHeight: CGFloat = 52
        return CGRect(
            x: (geometry.size.width - buttonWidth) / 2,
            y: geometry.size.height - 182,
            width: buttonWidth,
            height: buttonHeight
        )
    }

    func batchEditMenuAreaFrameFromMoreButton(
        in geometry: GeometryProxy,
        moreButtonFrame: CGRect
    ) -> CGRect {
        let screenBounds = geometry.size
        let menuWidth = min(max(screenBounds.width * 0.52, 216), 300)
        let menuHeight: CGFloat = 112
        let padding: CGFloat = 24
        let x = min(max(moreButtonFrame.maxX - menuWidth + 4, 12), screenBounds.width - menuWidth - 12)
        let menuY = max(geometry.safeAreaInsets.top + 2, moreButtonFrame.maxY)
        return CGRect(x: x - padding, y: menuY - padding, width: menuWidth + padding * 2, height: menuHeight + padding * 2)
    }

    func batchEditMenuEditEntryFallbackFrame(
        in geometry: GeometryProxy,
        moreButtonFrame: CGRect
    ) -> CGRect {
        let menuFrame = batchEditMenuAreaFrameFromMoreButton(in: geometry, moreButtonFrame: moreButtonFrame)
        let rowHeight = (menuFrame.height - 16) / 2
        return CGRect(
            x: menuFrame.minX + 14,
            y: menuFrame.minY + 8 + rowHeight,
            width: menuFrame.width - 28,
            height: rowHeight - 6
        )
    }

    func batchEditMenuEditEntryGuideFrame(
        in geometry: GeometryProxy,
        moreButtonFrame: CGRect
    ) -> CGRect {
        let fallbackFrame = batchEditMenuEditEntryFallbackFrame(in: geometry, moreButtonFrame: moreButtonFrame)
        guard let capturedFrame = localGuideTargetFrame(for: .wardrobeEditMenuEntry, in: geometry),
              capturedFrame.width >= 90,
              capturedFrame.height >= 28,
              capturedFrame.minY < geometry.size.height * 0.46,
              abs(capturedFrame.midX - fallbackFrame.midX) <= geometry.size.width * 0.42,
              abs(capturedFrame.midY - fallbackFrame.midY) <= max(64, fallbackFrame.height * 1.5) else {
            return fallbackFrame
        }
        return capturedFrame.insetBy(dx: -6, dy: -4)
    }

    func wardrobeOotdEntryGuideFrame(in geometry: GeometryProxy) -> CGRect {
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

    func ootdEntryGuideFrame(in geometry: GeometryProxy) -> CGRect {
        if let rawFrame = localGuideTargetFrame(for: .ootdEntry, in: geometry) {
            return normalizedOotdGuideFrame(rawFrame, in: geometry)
        }
        // 没拿到实时采集时，先用镜子热区 fallback，避免用户等待数秒才出现高亮
        return ootdEntryMirrorFallbackFrame(in: geometry)
    }

    func ootdEntryMirrorFallbackFrame(in geometry: GeometryProxy) -> CGRect {
        let containerSize = geometry.size
        // fallback 直接贴近当前 House 画面里的镜子区域：
        // 再往下挪一点，避免高亮偏到镜子上沿之外
        let hotspot = CGRect(x: 0.355, y: 0.24, width: 0.072, height: 0.1)
        return CGRect(
            x: containerSize.width * hotspot.minX,
            y: containerSize.height * hotspot.minY,
            width: max(1, containerSize.width * hotspot.width),
            height: max(1, containerSize.height * hotspot.height)
        )
    }

    func normalizedOotdGuideFrame(
        _ frame: CGRect,
        in geometry: GeometryProxy
    ) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return frame }

        let expandedFrame = frame.insetBy(dx: -6, dy: -10)

        // 仅在捕获框异常偏大时才收敛；细长镜子型热区保持原始尺寸，避免“自动放大”
        let isOversized =
            frame.width > geometry.size.width * 0.22 ||
            frame.height > geometry.size.height * 0.45
        guard isOversized else { return expandedFrame }

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

    func calendarEntryGuideFrame(in geometry: GeometryProxy) -> CGRect {
        let screenBounds = geometry.size
        let rococoFallback = CGRect(
            x: screenBounds.width * 0.40,
            y: screenBounds.height * 0.75,
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

    func wardrobeGuideContent(accent: Color) -> some View {
        GeometryReader { geometry in
            let addFrame = wardrobeAddButtonGuideFrame(in: geometry)
            let step1GuideFrame = addFrame

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
                    .zIndex(1000)

                    CatPawTapAnimation(
                        position: CGPoint(
                            x: step1GuideFrame.midX,
                            y: step1GuideFrame.midY
                        ),
                        delay: 0.5
                    )
                    .zIndex(1000)

                    // 添加透明点击区域，允许点击穿透到下层实际的 + 号按钮
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.001))
                        .frame(width: step1GuideFrame.width, height: step1GuideFrame.height)
                        .allowsHitTesting(false)
                        .position(x: step1GuideFrame.midX, y: step1GuideFrame.midY)

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
                        position: CGPoint(
                            x: optionFrame.midX,
                            y: optionFrame.midY
                        ),
                        delay: 0.5
                    )
                    .opacity(0.4)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    var themeCustomizeGuideContent: some View {
        GeometryReader { geometry in
            switch themeCustomizeGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: themeCustomizeGuideStep.title,
                    message: themeCustomizeGuideStep.message,
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
                                title: themeCustomizeGuideStep.title,
                                message: themeCustomizeGuideStep.message,
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
                    title: themeCustomizeGuideStep.title,
                    message: themeCustomizeGuideStep.message,
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
                    title: themeCustomizeGuideStep.title,
                    message: themeCustomizeGuideStep.message,
                    currentStep: 4,
                    totalSteps: 5,
                    accent: .purple,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step5_magicThemeExplanation:
                return AnyView(bottomBubbleGuideContent(
                    title: themeCustomizeGuideStep.title,
                    message: themeCustomizeGuideStep.message,
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

    var customColorPersonalizationGuideContent: some View {
        GeometryReader { geometry in
            switch customColorPersonalizationGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: customColorPersonalizationGuideStep.title,
                    message: customColorPersonalizationGuideStep.message,
                    currentStep: 1,
                    totalSteps: 6,
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
                                title: customColorPersonalizationGuideStep.title,
                                message: customColorPersonalizationGuideStep.message,
                                currentStep: 2,
                                totalSteps: 6,
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
                    title: customColorPersonalizationGuideStep.title,
                    message: customColorPersonalizationGuideStep.message,
                    currentStep: 3,
                    totalSteps: 6,
                    accent: .purple,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step4_switchToCustomTab:
                let fallbackFrame = CGRect(x: (geometry.size.width - 240) / 2, y: max(geometry.safeAreaInsets.top + 64, 84), width: 240, height: 32)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .themeColorModeTabs),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 12,
                    title: customColorPersonalizationGuideStep.title,
                    message: customColorPersonalizationGuideStep.message,
                    currentStep: 4,
                    totalSteps: 6,
                    accent: .purple,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step5_scrollToPersonalization:
                return AnyView(
                    ZStack {
                        WidgetScrollHintView(
                            title: "请向下滑动",
                            subtitle: "「个性化」入口在更下方"
                        )
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: customColorPersonalizationGuideStep.title,
                                message: customColorPersonalizationGuideStep.message,
                                currentStep: 5,
                                totalSteps: 6,
                                accent: .purple,
                                actionTitle: nil,
                                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                onAction: nil
                            )
                            .padding(.bottom, 120)
                        }
                    }
                )
            case .step6_personalizationExplanation:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 330, geometry.size.height * 0.56),
                    width: (geometry.size.width - 48) / 2,
                    height: 112
                )
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .themeCustomPersonalizationEntry),
                    in: geometry,
                    fallback: fallbackFrame
                )
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: customColorPersonalizationGuideStep.title,
                    message: customColorPersonalizationGuideStep.message,
                    currentStep: 6,
                    totalSteps: 6,
                    accent: .purple,
                    actionTitle: "知道了",
                    onAction: {
                        guideManager.completeFeatureExperienceGuide()
                    },
                    bubbleOnTop: true
                ))
            }
        }
    }

    var localFileBackupRestoreGuideContent: some View {
        GeometryReader { geometry in
            switch localFileBackupRestoreGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: localFileBackupRestoreGuideStep.title,
                    message: localFileBackupRestoreGuideStep.message,
                    currentStep: 1,
                    totalSteps: 6,
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
                                title: localFileBackupRestoreGuideStep.title,
                                message: localFileBackupRestoreGuideStep.message,
                                currentStep: 2,
                                totalSteps: 6,
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
                    title: localFileBackupRestoreGuideStep.title,
                    message: localFileBackupRestoreGuideStep.message,
                    currentStep: 3,
                    totalSteps: 6,
                    accent: .indigo,
                    actionTitle: nil,
                    onAction: nil,
                    bubbleOnTop: true
                ))
            case .step4_introBackupData:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 330, geometry.size.height * 0.43),
                    width: geometry.size.width - 32,
                    height: 52
                )
                let backupFrame = localGuideTargetFrame(for: .localBackupDataAction, in: geometry)
                let targetFrame = backupFrame?.insetBy(dx: -4, dy: -4) ?? fallbackFrame
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: localFileBackupRestoreGuideStep.title,
                    message: localFileBackupRestoreGuideStep.message,
                    currentStep: 4,
                    totalSteps: 6,
                    accent: .indigo,
                    actionTitle: "下一步：看恢复",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            localFileBackupRestoreGuideStep = .step5_introRestoreData
                        }
                    },
                    bubbleOnTop: true
                ))
            case .step5_introRestoreData:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 390, geometry.size.height * 0.5),
                    width: geometry.size.width - 32,
                    height: 52
                )
                let restoreFrame = localGuideTargetFrame(for: .localRestoreDataAction, in: geometry)
                let targetFrame = restoreFrame?.insetBy(dx: -4, dy: -4) ?? fallbackFrame
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: localFileBackupRestoreGuideStep.title,
                    message: localFileBackupRestoreGuideStep.message,
                    currentStep: 5,
                    totalSteps: 6,
                    accent: .indigo,
                    actionTitle: "下一步：首次备份",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            localFileBackupRestoreGuideStep = .step6_firstBackup
                        }
                    },
                    bubbleOnTop: true
                ))
            case .step6_firstBackup:
                let fallbackFrame = CGRect(
                    x: 16,
                    y: max(geometry.safeAreaInsets.top + 330, geometry.size.height * 0.43),
                    width: geometry.size.width - 32,
                    height: 52
                )
                let backupFrame = localGuideTargetFrame(for: .localBackupDataAction, in: geometry)
                let targetFrame = backupFrame?.insetBy(dx: -4, dy: -4) ?? fallbackFrame
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 14,
                    title: localFileBackupRestoreGuideStep.title,
                    message: localFileBackupRestoreGuideStep.message,
                    currentStep: 6,
                    totalSteps: 6,
                    accent: .indigo,
                    actionTitle: nil,
                    onAction: nil,
                    bubbleOnTop: true
                ))
            }
        }
    }

    var exportCSVGuideContent: some View {
        GeometryReader { geometry in
            switch exportCSVGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: exportCSVGuideStep.title,
                    message: exportCSVGuideStep.message,
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
                                title: exportCSVGuideStep.title,
                                message: exportCSVGuideStep.message,
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
                    title: exportCSVGuideStep.title,
                    message: exportCSVGuideStep.message,
                    currentStep: 3,
                    totalSteps: 4,
                    accent: .teal,
                    actionTitle: nil,
                    onAction: nil,
                    bubbleOnTop: true
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
                    title: exportCSVGuideStep.title,
                    message: exportCSVGuideStep.message,
                    currentStep: 4,
                    totalSteps: 4,
                    accent: .teal,
                    actionTitle: nil,
                    onAction: nil
                ))
            }
        }
    }

    var cloudFileBackupRestoreGuideContent: some View {
        GeometryReader { geometry in
            switch cloudFileBackupRestoreGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: cloudFileBackupRestoreGuideStep.title,
                    message: cloudFileBackupRestoreGuideStep.message,
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
                    title: cloudFileBackupRestoreGuideStep.title,
                    message: cloudFileBackupRestoreGuideStep.message,
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
                    title: cloudFileBackupRestoreGuideStep.title,
                    message: cloudFileBackupRestoreGuideStep.message,
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
                    title: cloudFileBackupRestoreGuideStep.title,
                    message: cloudFileBackupRestoreGuideStep.message,
                    currentStep: 4,
                    totalSteps: 5,
                    accent: .blue,
                    actionTitle: "下一步：及时同步延迟",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            cloudFileBackupRestoreGuideStep = .step5_realtimeSyncDelayExplanation
                        }
                    },
                    bubbleOnTop: true
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
                    title: cloudFileBackupRestoreGuideStep.title,
                    message: cloudFileBackupRestoreGuideStep.message,
                    currentStep: 5,
                    totalSteps: 5,
                    accent: .blue,
                    actionTitle: "知道了",
                    onAction: {
                        guideManager.completeFeatureExperienceGuide()
                    },
                    bubbleOnTop: true
                ))
            }
        }
    }

    var personalPreferenceGuideContent: some View {
        GeometryReader { geometry in
            switch personalPreferenceGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: personalPreferenceGuideStep.title,
                    message: personalPreferenceGuideStep.message,
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
                    title: personalPreferenceGuideStep.title,
                    message: personalPreferenceGuideStep.message,
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
                    title: personalPreferenceGuideStep.title,
                    message: personalPreferenceGuideStep.message,
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
                    title: personalPreferenceGuideStep.title,
                    message: personalPreferenceGuideStep.message,
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
                    title: personalPreferenceGuideStep.title,
                    message: personalPreferenceGuideStep.message,
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

    var privacyDisplayStepGuideContent: some View {
        GeometryReader { geometry in
            switch privacyDisplayGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: privacyDisplayGuideStep.title,
                    message: privacyDisplayGuideStep.message,
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
                    title: privacyDisplayGuideStep.title,
                    message: privacyDisplayGuideStep.message,
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
                    title: privacyDisplayGuideStep.title,
                    message: privacyDisplayGuideStep.message,
                    currentStep: 3,
                    totalSteps: 4,
                    accent: .pink,
                    actionTitle: "下一步：原价开关",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            privacyDisplayGuideStep = .step4_showOriginalPrice
                        }
                    },
                    bubbleOnTop: true
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
                    title: privacyDisplayGuideStep.title,
                    message: privacyDisplayGuideStep.message,
                    currentStep: 4,
                    totalSteps: 4,
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

    var tagBrandFieldStepGuideContent: some View {
        GeometryReader { geometry in
            switch tagBrandFieldGuideStep {
            case .step1_returnToMe:
                return AnyView(returnToMeGuideContent(
                    in: geometry,
                    title: tagBrandFieldGuideStep.title,
                    message: tagBrandFieldGuideStep.message,
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
                    title: tagBrandFieldGuideStep.title,
                    message: tagBrandFieldGuideStep.message,
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
                                title: tagBrandFieldGuideStep.title,
                                message: tagBrandFieldGuideStep.message,
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
                if let globalFrame = guideManager.guideTargetFrame(for: .wardrobeTagManagementEntry),
                   isGuideTargetVisibleOnScreen(globalFrame) {
                    let targetFrame = aiGuideTargetFrame(
                        globalFrame: globalFrame,
                        in: geometry,
                        fallback: CGRect(
                            x: 16,
                            y: max(geometry.safeAreaInsets.top + 464, 500),
                            width: geometry.size.width - 32,
                            height: 52
                        )
                    )
                    return AnyView(highlightedRectGuideContent(
                        frame: targetFrame,
                        cornerRadius: 14,
                        title: tagBrandFieldGuideStep.title,
                        message: tagBrandFieldGuideStep.message,
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
                }
                return AnyView(
                    ZStack {
                        WidgetScrollHintView(
                            title: "请继续向下滑动",
                            subtitle: "先找到「标签管理」后再继续"
                        )
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: "继续下滑找到标签管理",
                                message: "当前还没进入「标签管理」区域，请继续往下滑动。",
                                currentStep: 4,
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
            case .step5_brandManagement:
                if let globalFrame = guideManager.guideTargetFrame(for: .wardrobeBrandManagementEntry),
                   isGuideTargetVisibleOnScreen(globalFrame) {
                    let targetFrame = aiGuideTargetFrame(
                        globalFrame: globalFrame,
                        in: geometry,
                        fallback: CGRect(
                            x: 16,
                            y: max(geometry.safeAreaInsets.top + 520, 556),
                            width: geometry.size.width - 32,
                            height: 52
                        )
                    )
                    return AnyView(highlightedRectGuideContent(
                        frame: targetFrame,
                        cornerRadius: 14,
                        title: tagBrandFieldGuideStep.title,
                        message: tagBrandFieldGuideStep.message,
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
                }
                return AnyView(
                    ZStack {
                        WidgetScrollHintView(
                            title: "请继续向下滑动",
                            subtitle: "先找到「品牌管理」后再继续"
                        )
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: "继续下滑找到品牌管理",
                                message: "请继续往下滑动，看到「品牌管理」后再继续下一步。",
                                currentStep: 5,
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
            case .step6_fieldManagement:
                if let globalFrame = guideManager.guideTargetFrame(for: .wardrobeFieldManagementEntry),
                   isGuideTargetVisibleOnScreen(globalFrame) {
                    let targetFrame = aiGuideTargetFrame(
                        globalFrame: globalFrame,
                        in: geometry,
                        fallback: CGRect(
                            x: 16,
                            y: max(geometry.safeAreaInsets.top + 576, 612),
                            width: geometry.size.width - 32,
                            height: 52
                        )
                    )
                    return AnyView(highlightedRectGuideContent(
                        frame: targetFrame,
                        cornerRadius: 14,
                        title: tagBrandFieldGuideStep.title,
                        message: tagBrandFieldGuideStep.message,
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
                return AnyView(
                    ZStack {
                        WidgetScrollHintView(
                            title: "请继续向下滑动",
                            subtitle: "先找到「属性字段管理」后再完成"
                        )
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: "继续下滑找到属性字段管理",
                                message: "请继续往下滑动，看到「属性字段排序与显示」后完成本次引导。",
                                currentStep: 6,
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
            }
        }
    }

    var ootdUnlockedGuideContent: some View {
        GeometryReader { geometry in
            switch ootdGuideStep {
            case .step1_clickOotdEntry:
                let targetFrame = ootdEntryGuideFrame(in: geometry)
                return AnyView(highlightedRectGuideContent(
                    frame: targetFrame,
                    cornerRadius: 18,
                    title: ootdGuideStep.title,
                    message: ootdGuideStep.message,
                    currentStep: 1,
                    totalSteps: 2,
                    accent: .orange,
                    actionTitle: nil,
                    onAction: nil,
                    showPulse: false
                ))
            case .step2_ootdExplanation:
                return AnyView(bottomBubbleGuideContent(
                    title: ootdGuideStep.title,
                    message: ootdGuideStep.message,
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

    var calendarGuideContent: some View {
        if let preUnlockGuide = preUnlockWardrobeGuideContentIfNeeded(for: .calendar) {
            return preUnlockGuide
        }

        return AnyView(
            GeometryReader { geometry in
                switch calendarGuideStep {
                case .step1_clickCalendarEntry:
                    let targetFrame = calendarEntryGuideFrame(in: geometry)
                    highlightedRectGuideContent(
                        frame: targetFrame,
                        cornerRadius: 16,
                        title: calendarGuideStep.title,
                        message: calendarGuideStep.message,
                        currentStep: 1,
                        totalSteps: 2,
                        accent: .purple,
                        actionTitle: nil,
                        onAction: nil,
                        bubbleOnTop: true
                    )
                case .step2_calendarExplanation:
                    bottomBubbleGuideContent(
                        title: calendarGuideStep.title,
                        message: calendarGuideStep.message,
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

    var magicStickerGuideContent: some View {
        if let preUnlockGuide = preUnlockWardrobeGuideContentIfNeeded(for: .ootdDefaultBook) {
            return preUnlockGuide
        }

        return AnyView(
            GeometryReader { geometry in
                switch magicStickerGuideStep {
                case .step1_returnToMeForMenuSetup:
                    returnToMeGuideContent(
                        in: geometry,
                        title: magicStickerGuideStep.title,
                        message: magicStickerGuideStep.message,
                        currentStep: magicStickerGuideDisplayStep(for: .step1_returnToMeForMenuSetup),
                        totalSteps: magicStickerGuideTotalSteps,
                        accent: .pink,
                        onReturn: handleMagicStickerGuideReturnAction
                    )
                case .step2_scrollToFavoriteMenu:
                    // 滚动引导：提示用户往下滑找到常用菜单
                    ZStack {
                        WidgetScrollHintView(
                            title: "请向下滑动",
                            subtitle: "「常用菜单」入口在更下方"
                        )
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: magicStickerGuideStep.title,
                                message: magicStickerGuideStep.message,
                                currentStep: magicStickerGuideDisplayStep(for: .step2_scrollToFavoriteMenu),
                                totalSteps: magicStickerGuideTotalSteps,
                                accent: .pink,
                                actionTitle: nil,
                                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                onAction: nil
                            )
                            .padding(.bottom, max(geometry.safeAreaInsets.bottom + 80, 100))
                        }
                    }
                case .step3_clickFavoriteMenuSettings:
                    let fallbackFrame = CGRect(
                        x: geometry.size.width * 0.5 + 8,
                        y: geometry.size.height * 0.48,
                        width: (geometry.size.width - 48) / 2,
                        height: 92
                    )
                    let targetFrame = aiGuideTargetFrame(
                        globalFrame: guideManager.guideTargetFrame(for: .favoriteMenuSettingsEntry),
                        in: geometry,
                        fallback: fallbackFrame
                    )
                    highlightedRectGuideContent(
                        frame: targetFrame,
                        cornerRadius: 16,
                        title: magicStickerGuideStep.title,
                        message: magicStickerGuideStep.message,
                        currentStep: magicStickerGuideDisplayStep(for: .step3_clickFavoriteMenuSettings),
                        totalSteps: magicStickerGuideTotalSteps,
                        accent: .pink,
                        actionTitle: nil,
                        onAction: nil,
                        bubbleOnTop: true
                    )
                case .step4_addMagicStickerButton:
                    let fallbackFrame = CGRect(
                        x: geometry.size.width - 74,
                        y: max(geometry.safeAreaInsets.top + 210, geometry.size.height * 0.36),
                        width: 44,
                        height: 44
                    )
                    let targetFrame = aiGuideTargetFrame(
                        globalFrame: guideManager.guideTargetFrame(for: .favoriteMenuMagicStickerAddButton),
                        in: geometry,
                        fallback: fallbackFrame
                    )
                    highlightedRectGuideContent(
                        frame: targetFrame,
                        cornerRadius: 22,
                        title: magicStickerGuideStep.title,
                        message: magicStickerGuideStep.message,
                        currentStep: magicStickerGuideDisplayStep(for: .step4_addMagicStickerButton),
                        totalSteps: magicStickerGuideTotalSteps,
                        accent: .pink,
                        actionTitle: nil,
                        onAction: nil,
                        bubbleOnTop: true
                    )
                case .step5_returnToMeAfterMenuSetup:
                    returnToMeGuideContent(
                        in: geometry,
                        title: magicStickerGuideStep.title,
                        message: magicStickerGuideStep.message,
                        currentStep: magicStickerGuideDisplayStep(for: .step5_returnToMeAfterMenuSetup),
                        totalSteps: magicStickerGuideTotalSteps,
                        accent: .pink,
                        onReturn: handleMagicStickerGuideReturnFromMenuSettingsAction
                    )
                case .step6_longPressHouseTab:
                    let safeAreaBottom = geometry.safeAreaInsets.bottom
                    let tabBarHeight = 65.0 + safeAreaBottom
                    let fallbackHouseTabFrame = CGRect(
                        x: geometry.size.width / 2 - 34,
                        y: geometry.size.height - tabBarHeight,
                        width: 68,
                        height: tabBarHeight
                    )
                    let houseTabFrame = TabBarItemAnchorResolver.resolvedFrame(
                        for: .homeHouseTab,
                        preferredTabIndex: 1,
                        in: geometry,
                        expansion: 0,
                        fallback: fallbackHouseTabFrame
                    )
                    let houseTabRadius = max(34, max(houseTabFrame.width, houseTabFrame.height) / 2)
                    ZStack {
                        HollowMaskView(
                            highlightFrame: houseTabFrame,
                            highlightType: .circle,
                            cornerRadius: houseTabRadius
                        )

                        HighlightPulseViewNoClick(
                            center: CGPoint(x: houseTabFrame.midX, y: houseTabFrame.midY),
                            radius: houseTabRadius
                        )

                        if !guideManager.isPadGuideLayout {
                            CatPawTapAnimation(
                                position: CGPoint(x: houseTabFrame.midX, y: houseTabFrame.midY),
                                delay: 0.5
                            )
                        }

                        VStack {
                            featureStepBubble(
                                title: magicStickerGuideStep.title,
                                message: magicStickerGuideStep.message,
                                currentStep: magicStickerGuideDisplayStep(for: .step6_longPressHouseTab),
                                totalSteps: magicStickerGuideTotalSteps,
                                accent: .pink,
                                actionTitle: nil,
                                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                onAction: nil
                            )
                            .padding(.top, max(geometry.safeAreaInsets.top + 24, 72))
                            Spacer()
                        }
                    }
                case .step7_clickMagicStickerEntry:
                    let fallbackFrame = CGRect(x: geometry.size.width * 0.18, y: geometry.size.height * 0.56, width: 96, height: 84)
                    let targetFrame = aiGuideTargetFrame(
                        globalFrame: guideManager.guideTargetFrame(for: .favoriteMenuMagicStickerEntry),
                        in: geometry,
                        fallback: fallbackFrame
                    )
                    highlightedRectGuideContent(
                        frame: targetFrame,
                        cornerRadius: 24,
                        title: magicStickerGuideStep.title,
                        message: magicStickerGuideStep.message,
                        currentStep: magicStickerGuideDisplayStep(for: .step7_clickMagicStickerEntry),
                        totalSteps: magicStickerGuideTotalSteps,
                        accent: .pink,
                        actionTitle: nil,
                        onAction: nil,
                        bubbleOnTop: true
                    )
                case .step8_magicStickerExplanation:
                    bottomBubbleGuideContent(
                        title: magicStickerGuideStep.title,
                        message: magicStickerGuideStep.message,
                        currentStep: magicStickerGuideDisplayStep(for: .step8_magicStickerExplanation),
                        totalSteps: magicStickerGuideTotalSteps,
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

    var batchEditInteractiveGuideContent: some View {
        GeometryReader { geometry in
            switch batchEditGuideStep {
            case .step1_clickMoreMenu:
                let fallbackFrame = CGRect(x: geometry.size.width - 64, y: max(geometry.safeAreaInsets.top + 8, 12), width: 36, height: 36)
                let rawTargetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeMoreMenuButton),
                    in: geometry,
                    fallback: fallbackFrame
                )
                let targetFrame = guideManager.normalizedTopTrailingToolbarButtonFrame(
                    rawTargetFrame,
                    containerSize: geometry.size,
                    safeAreaTop: geometry.safeAreaInsets.top
                )
                // 菜单定位必须基于原始「更多」按钮坐标；
                // 不要复用 step1 的下移高亮坐标，否则会把「编辑」行 fallback 算到下方。
                let menuAreaFrame = batchEditMenuAreaFrameFromMoreButton(in: geometry, moreButtonFrame: rawTargetFrame)
                let shouldHighlightEditEntry = didOpenBatchEditMoreMenu ||
                    guideManager.guideTargetFrame(for: .wardrobeEditMenuEntry) != nil
                let step1Frame = shouldHighlightEditEntry ? menuAreaFrame : targetFrame
                let step1CornerRadius: CGFloat = shouldHighlightEditEntry ? 14 : 18
                let step1Title = shouldHighlightEditEntry ? "点击「编辑」" : batchEditGuideStep.title
                let step1Message = shouldHighlightEditEntry
                    ? "菜单已经弹出啦，点击「编辑」进入批量编辑模式。"
                    : batchEditGuideStep.message
                return AnyView(highlightedRectGuideContent(
                    frame: step1Frame,
                    cornerRadius: step1CornerRadius,
                    title: step1Title,
                    message: step1Message,
                    currentStep: 1,
                    totalSteps: 4,
                    accent: .green,
                    actionTitle: nil,
                    onAction: nil
                )
                .overlay {
                    CatPawTapAnimation(
                        position: CGPoint(x: step1Frame.midX, y: step1Frame.midY),
                        delay: 0.5
                    )
                    .allowsHitTesting(false)
                })
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
                    title: batchEditGuideStep.title,
                    message: batchEditGuideStep.message,
                    currentStep: 2,
                    totalSteps: 4,
                    accent: .green,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step3_toolbarExplanation:
                let fallbackFrame = CGRect(
                    x: 12,
                    y: geometry.size.height - geometry.safeAreaInsets.bottom - 180,
                    width: geometry.size.width - 24,
                    height: 100
                )
                let toolbarFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeBatchEditToolbar),
                    in: geometry,
                    fallback: fallbackFrame
                ).insetBy(dx: -4, dy: -6)

                return AnyView(highlightedRectGuideContent(
                    frame: toolbarFrame,
                    cornerRadius: 16,
                    title: batchEditGuideStep.title,
                    message: batchEditGuideStep.message,
                    currentStep: 3,
                    totalSteps: 4,
                    accent: .green,
                    actionTitle: "下一步：完成",
                    onAction: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            batchEditGuideStep = .step4_finishSelection
                        }
                    },
                    bubbleOnTop: true
                )
                .overlay {
                    CatPawTapAnimation(
                        position: CGPoint(x: toolbarFrame.midX, y: toolbarFrame.midY),
                        delay: 0.5
                    )
                    .opacity(0.4)
                    .allowsHitTesting(false)
                })
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
                    title: batchEditGuideStep.title,
                    message: batchEditGuideStep.message,
                    currentStep: 4,
                    totalSteps: 4,
                    accent: .green,
                    actionTitle: nil,
                    onAction: nil
                ))
            }
        }
    }

}
