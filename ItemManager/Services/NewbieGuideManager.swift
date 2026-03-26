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
        resetGuideInteractiveRegions()
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

    func updateGuideTargetFrame(_ frame: CGRect, for key: GuideTargetKey) {
        guard frame.width > 0, frame.height > 0 else { return }
        guideTargetFrames[key] = frame
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
            .homeHouseTab,
            .homePetChatTab,
            .petChatSearchBar,
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
    func completeGuide() {
        state.isCompleted = true
        currentStep = .complete
        isShowingGuide = false
        isRunningAnimation = false
        showPointingVideo = false
        showCreateButtonHighlight = false
        resetGuideInteractiveRegions()
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
}

// MARK: - 功能体验引导遮罩视图

struct FeatureExperienceGuideOverlay: View {
    @StateObject var guideManager = AppFirstLaunchGuideManager.shared
    @StateObject var authManager = AuthenticationManager.shared
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
    @State var magicStickerGuideStep: MagicStickerGuideStep = .step1_longPressHouseTab
    @State var batchEditGuideStep: BatchEditGuideStep = .step1_clickMoreMenu
    @State var didOpenBatchEditMoreMenu: Bool = false
    @State var spaceBookGuideStep: SpaceBookGuideStep = .step1_clickWardrobeOotdEntry
    @State var wealthGuideStep: WealthGuideStep = .step1_clickHouseTab
    @State var currentTab: String = "wardrobe"
    @State var isSpaceBookCreationPromptVisible: Bool = false
    @State var hasSpaceBooksForGuide: Bool = false
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
                if guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                   widgetCustomizeStep == .step1_returnToMe {
                    advanceWidgetGuideFromReturnStep()
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
            .onReceive(NotificationCenter.default.publisher(for: .petChatSearchStateChanged)) { notification in
                guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }
                let isSearching = notification.userInfo?["isSearching"] as? Bool ?? false
                guard isSearching else { return }

                if aiAnalysisStep == .postUnlockStep2ClickSearchBar ||
                    (aiAnalysisStep == .postUnlockStep1ClickPetChatTab && currentTab == "petChat") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .postUnlockStep3FeatureIntro
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
                                customColorPersonalizationGuideStep = .step5_personalizationExplanation
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
                        customColorPersonalizationGuideStep = .step5_personalizationExplanation
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
        let spaceBookStateBound = bindSpaceBookStateGuideEvents(houseEntryBound)
        return bindSpaceBookEditorGuideEvents(spaceBookStateBound)
    }

    private func bindHouseEntryGuideEvents<Content: View>(_ content: Content) -> some View {
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
    }

    private func bindSpaceBookStateGuideEvents<Content: View>(_ content: Content) -> some View {
        content
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
                        spaceBookGuideStep = hasSpaceBookPagesForGuide ? .step5_open3DEditor : .step4_createFirstPage
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
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookCreationPromptVisibilityChanged)) { notification in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                let isVisible = notification.userInfo?["isVisible"] as? Bool ?? false
                isSpaceBookCreationPromptVisible = isVisible
            }
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookShelfDataStateChanged)) { notification in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                let hasBooks = notification.userInfo?["hasBooks"] as? Bool ?? false
                hasSpaceBooksForGuide = hasBooks
            }
            .onReceive(NotificationCenter.default.publisher(for: .spaceBookDetailDataStateChanged)) { notification in
                guard guideManager.currentFeatureExperienceFeature == .spaceBook else { return }
                let hasPages = notification.userInfo?["hasPages"] as? Bool ?? false
                hasSpaceBookPagesForGuide = hasPages
            }
    }

    private func bindSpaceBookEditorGuideEvents<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .spatialCanvasEditorOpened)) { _ in
                if guideManager.currentFeatureExperienceFeature == .spaceBook,
                   spaceBookGuideStep == .step5_open3DEditor {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        spaceBookGuideStep = .step6_openScanner
                    }
                } else if guideManager.currentFeatureExperienceFeature == .spaceBook,
                          spaceBookGuideStep == .step4_createFirstPage,
                          hasSpaceBookPagesForGuide {
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
                   aiAnalysisStep == .preUnlockStep1ReturnToMe,
                   vipCardFrame != nil {
                    print("[FeatureExperienceGuide] 检测到VIP卡片位置，step1进入step2")
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

    var spaceBookGuideContent: some View {
        if let preUnlockGuide = preUnlockWardrobeGuideContentIfNeeded(for: .spaceBook) {
            return preUnlockGuide
        }

        return AnyView(
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
                            if hasSpaceBooksForGuide {
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
                                highlightedRectGuideContent(
                                    frame: targetFrame,
                                    cornerRadius: 20,
                                    title: "直接点第一本空间手帐",
                                    message: "你已经有空间手帐了，不用新建。先点进第一本，我们继续下一步。",
                                    currentStep: 3,
                                    totalSteps: 7,
                                    accent: .blue,
                                    actionTitle: nil,
                                    onAction: nil
                                )
                            } else {
                                VStack {
                                    featureStepBubble(
                                        title: isSpaceBookCreationPromptVisible ? "输入名称后点创建" : "点右上角「更多」新建空间手帐",
                                        message: isSpaceBookCreationPromptVisible
                                            ? "已打开新建弹窗，输入空间手帐名称并点击创建，即可进入下一步。"
                                            : "请点右上角「更多」，选择「新建空间手帐」。输入名称并点击创建。",
                                        currentStep: 3,
                                        totalSteps: 7,
                                        accent: .blue,
                                        actionTitle: nil,
                                        onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                        onAction: nil
                                    )
                                    .padding(.top, max(geometry.safeAreaInsets.top + 24, 72))
                                    Spacer()
                                }
                            }
                        case .step4_createFirstPage:
                            if hasSpaceBookPagesForGuide {
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
                                highlightedRectGuideContent(
                                    frame: targetFrame,
                                    cornerRadius: 12,
                                    title: "直接点第一张空间书页",
                                    message: "当前手帐里已经有书页了，不用新建，直接点第一张进入 3D 编辑。",
                                    currentStep: 4,
                                    totalSteps: 7,
                                    accent: .blue,
                                    actionTitle: nil,
                                    onAction: nil
                                )
                            } else {
                                VStack {
                                    featureStepBubble(
                                        title: "输入首张名字后点创建",
                                        message: isSpaceBookCreationPromptVisible
                                            ? "已打开新建书页弹窗，输入名称并点击创建，即可进入下一步。"
                                            : "进入新手帐后，点右上角「更多」并选择「新建空间搭配」，输入首张名字后点击创建。",
                                        currentStep: 4,
                                        totalSteps: 7,
                                        accent: .blue,
                                        actionTitle: nil,
                                        onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                        onAction: nil
                                    )
                                    .padding(.top, max(geometry.safeAreaInsets.top + 24, 72))
                                    Spacer()
                                }
                            }
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
                                title: "进入空间书页",
                                message: "点击书页进入 3D 编辑界面。若是刚创建的首张书页，也是在这里进入。",
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
        let minimumSide: CGFloat = 34
        let maximumSide: CGFloat = 46

        var normalized = frame

        // iOS 新导航样式下，右上角按钮可能被系统组合进同一胶囊。
        // 引导要稳定对准最右侧的「+」按钮，而不是整个胶囊组。
        let looksLikeGroupedCapsule = frame.width > frame.height * 1.45 && frame.width > 52
        if looksLikeGroupedCapsule {
            let targetSide = min(max(frame.height - 8, minimumSide), maximumSide)
            normalized = CGRect(
                x: frame.maxX - targetSide - 6,
                y: frame.midY - targetSide / 2,
                width: targetSide,
                height: targetSide
            )
        }

        if normalized.width < minimumSide || normalized.height < minimumSide {
            let side = min(max(max(normalized.width, normalized.height) + 14, minimumSide), maximumSide)
            normalized = CGRect(
                x: normalized.midX - side / 2,
                y: normalized.midY - side / 2,
                width: side,
                height: side
            )
        }

        let minX: CGFloat = 8
        let maxX = max(minX, geometry.size.width - normalized.width - 8)
        let minY = max(geometry.safeAreaInsets.top + 4, 10)
        let maxY = max(minY, geometry.size.height * 0.34)

        return CGRect(
            x: min(max(normalized.minX, minX), maxX),
            y: min(max(normalized.minY, minY), maxY),
            width: normalized.width,
            height: normalized.height
        )
    }

    func wardrobeMenuAreaFrameFromAddButton(
        in geometry: GeometryProxy,
        addFrame: CGRect
    ) -> CGRect {
        let screenBounds = geometry.size
        let hasDraftContinueEntry = hasValidWardrobeDraftForGuide()
        let menuWidth = min(max(screenBounds.width * 0.58, 208), 292)
        let menuHeight: CGFloat = hasDraftContinueEntry ? 167 : 118
        let x = min(max(addFrame.maxX - menuWidth - 8, 12), screenBounds.width - menuWidth - 12)
        let y = max(geometry.safeAreaInsets.top + 10, addFrame.maxY + 16)
        return CGRect(x: x, y: y, width: menuWidth, height: menuHeight)
    }

    func wardrobeMenuOptionFrameFromAddButton(
        in geometry: GeometryProxy,
        addFrame: CGRect,
        preferBatchImport: Bool
    ) -> CGRect {
        let hasDraftContinueEntry = hasValidWardrobeDraftForGuide()
        let menuFrame = wardrobeMenuAreaFrameFromAddButton(in: geometry, addFrame: addFrame)
        let totalRows: CGFloat = hasDraftContinueEntry ? 3 : 2
        let rowHeight = (menuFrame.height - 20) / totalRows
        let baseRowIndex: CGFloat = preferBatchImport ? 1 : 0
        let rowIndex: CGFloat = baseRowIndex + (hasDraftContinueEntry ? 1 : 0)
        return CGRect(
            x: menuFrame.minX + 14,
            y: menuFrame.minY + 8 + rowHeight * rowIndex,
            width: menuFrame.width - 28,
            height: rowHeight - 6
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
        let verticalTolerance = max(40, expected.height * 1.05)
        let horizontalTolerance = max(70, expected.width * 0.45)
        let widthRatio = frame.width / max(expected.width, 1)
        let heightRatio = frame.height / max(expected.height, 1)

        return abs(frame.midY - expected.midY) <= verticalTolerance &&
            abs(frame.midX - expected.midX) <= horizontalTolerance &&
            widthRatio >= 0.45 && widthRatio <= 1.8 &&
            heightRatio >= 0.45 && heightRatio <= 1.8
    }

    func isReasonableWardrobeMenuCaptureFrame(
        _ frame: CGRect,
        in geometry: GeometryProxy,
        addFrame: CGRect
    ) -> Bool {
        guard frame.width >= 80, frame.height >= 24 else { return false }
        guard frame.minY < geometry.size.height * 0.45 else { return false }
        guard abs(frame.midX - addFrame.midX) < geometry.size.width * 0.46 else { return false }
        guard frame.maxX > geometry.size.width * 0.45 else { return false }
        guard frame.width <= geometry.size.width * 0.78 else { return false }
        return true
    }

    func wardrobeGuideStep2Frame(
        in geometry: GeometryProxy,
        addFrame: CGRect
    ) -> CGRect {
        let menuAreaFallback = wardrobeMenuAreaFrameFromAddButton(in: geometry, addFrame: addFrame)

        guard let feature = guideManager.currentFeatureExperienceFeature,
              let target = wardrobeGuideStep2Target(for: feature) else {
            return menuAreaFallback
        }

        let manualExpected = wardrobeMenuOptionFrameFromAddButton(
            in: geometry,
            addFrame: addFrame,
            preferBatchImport: false
        )
        let batchExpected = wardrobeMenuOptionFrameFromAddButton(
            in: geometry,
            addFrame: addFrame,
            preferBatchImport: true
        )

        let manualCaptured = localGuideTargetFrame(for: .wardrobeManualCreateEntry, in: geometry)
        let batchCaptured = localGuideTargetFrame(for: .wardrobeBatchImportEntry, in: geometry)

        let manualFrame = manualCaptured.flatMap {
            isReasonableWardrobeMenuCaptureFrame($0, in: geometry, addFrame: addFrame) &&
            isCloseToExpectedWardrobeMenuOptionFrame($0, expected: manualExpected) ? $0 : nil
        }
        let batchFrame = batchCaptured.flatMap {
            isReasonableWardrobeMenuCaptureFrame($0, in: geometry, addFrame: addFrame) &&
            isCloseToExpectedWardrobeMenuOptionFrame($0, expected: batchExpected) ? $0 : nil
        }

        switch target {
        case .batchImport:
            if let batchFrame, let manualFrame {
                let chosen = batchFrame.midY >= manualFrame.midY ? batchFrame : manualFrame
                return chosen.insetBy(dx: -6, dy: -4)
            }
            if let batchFrame {
                return batchFrame.insetBy(dx: -6, dy: -4)
            }
            if let manualFrame,
               isCloseToExpectedWardrobeMenuOptionFrame(manualFrame, expected: batchExpected) {
                return manualFrame.insetBy(dx: -6, dy: -4)
            }
            return wardrobeMenuOptionFrameFromAddButton(
                in: geometry,
                addFrame: addFrame,
                preferBatchImport: true
            )

        case .manualCreate:
            if let manualFrame, let batchFrame {
                let chosen = manualFrame.midY <= batchFrame.midY ? manualFrame : batchFrame
                return chosen.insetBy(dx: -6, dy: -4)
            }
            if let manualFrame {
                return manualFrame.insetBy(dx: -6, dy: -4)
            }
            if let batchFrame,
               isCloseToExpectedWardrobeMenuOptionFrame(batchFrame, expected: manualExpected) {
                return batchFrame.insetBy(dx: -6, dy: -4)
            }
            return wardrobeMenuOptionFrameFromAddButton(
                in: geometry,
                addFrame: addFrame,
                preferBatchImport: false
            )

        case .either:
            if let manualFrame, let batchFrame {
                return manualFrame.union(batchFrame).insetBy(dx: -4, dy: -4)
            }
            if let manualFrame {
                return manualFrame
            }
            if let batchFrame {
                return batchFrame
            }
            return menuAreaFallback
        }
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
        let menuHeight: CGFloat = 172
        let x = min(max(moreButtonFrame.maxX - menuWidth + 4, 12), screenBounds.width - menuWidth - 12)
        let y = max(geometry.safeAreaInsets.top + 2, moreButtonFrame.maxY)
        return CGRect(x: x, y: y, width: menuWidth, height: menuHeight)
    }

    func batchEditMenuEditEntryFallbackFrame(
        in geometry: GeometryProxy,
        moreButtonFrame: CGRect
    ) -> CGRect {
        let menuFrame = batchEditMenuAreaFrameFromMoreButton(in: geometry, moreButtonFrame: moreButtonFrame)
        let rowHeight = (menuFrame.height - 22) / 3
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

            let step1GuideFrame = addFrame.offsetBy(dx: 0, dy: 32)

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
                        position: CGPoint(
                            x: step1GuideFrame.midX,
                            y: step1GuideFrame.midY
                        ),
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
                if let feature = guideManager.currentFeatureExperienceFeature,
                   feature == .batchImport,
                   let target = wardrobeGuideStep2Target(for: feature),
                   target != .either {
                    let shortcutTitle = target == .batchImport ? "点击「批量导入」" : "点击「手动创建」"
                    let actionTitle = target == .batchImport ? "打开「批量导入」" : "打开「手动创建」"
                    let actionMessage = target == .batchImport
                        ? "点击下方按钮，直接进入「批量导入」流程。"
                        : "点击下方按钮，直接进入「手动创建」流程。"
                    let shortcutKey: GuideTargetKey = target == .batchImport
                        ? .wardrobeShortcutBatchImportAction
                        : .wardrobeShortcutManualCreateAction

                    let shortcutFrame = aiGuideTargetFrame(
                        globalFrame: guideManager.guideTargetFrame(for: shortcutKey),
                        in: geometry,
                        fallback: wardrobeShortcutActionFallbackFrame(in: geometry)
                    )

                    ZStack {
                        HollowMaskView(
                            highlightFrame: shortcutFrame,
                            highlightType: .roundedRect,
                            cornerRadius: 12
                        )

                        RoundedRectHighlightView(
                            frame: shortcutFrame,
                            cornerRadius: 12
                        )

                        CatPawTapAnimation(
                            position: CGPoint(
                                x: shortcutFrame.midX,
                                y: shortcutFrame.midY
                            ),
                            delay: 0.5
                        )
                        .opacity(0.4)
                        .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            featureStepBubble(
                                title: shortcutTitle,
                                message: actionMessage,
                                currentStep: 2,
                                totalSteps: 2,
                                accent: accent,
                                actionTitle: actionTitle,
                                actionGuideTarget: shortcutKey,
                                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                                onAction: {
                                    NotificationCenter.default.post(
                                        name: target == .batchImport ? .guideRequestWardrobeBatchImport : .guideRequestWardrobeManualCreate,
                                        object: nil
                                    )
                                }
                            )
                            .padding(.bottom, 120)
                        }
                    }
                } else {
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
    }

    var themeCustomizeGuideContent: some View {
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

    var customColorPersonalizationGuideContent: some View {
        GeometryReader { geometry in
            switch customColorPersonalizationGuideStep {
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
                    title: "切换到客制化配色页签",
                    message: "请切到「客制化配色」，我们下一步会看「个性化」入口和我的主题方案。",
                    currentStep: 4,
                    totalSteps: 5,
                    accent: .purple,
                    actionTitle: nil,
                    onAction: nil
                ))
            case .step5_personalizationExplanation:
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
                    title: "认识个性化入口",
                    message: "这里是「个性化」豆腐块。点击后会展开「我的主题方案」，你可以继续自定义字体配色和卡片样式，打造自己的专属主题。",
                    currentStep: 5,
                    totalSteps: 5,
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
                    title: "返回「我」界面",
                    message: "先从魔法任务页返回到「我」，我们去找本地文件备份入口。",
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
                                title: "下滑找到系统与更多",
                                message: "继续向下滑动，在设置豆腐块区域找到「系统与更多」。",
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
                    title: "点击系统与更多",
                    message: "点开「系统与更多」，进入系统设置页。",
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
                    title: "先认识「备份数据」",
                    message: "备份是最重要的一步：它会把当前数据打包保存，防止误删、换机或重装时丢失记录。建议养成定期备份习惯。",
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
                    title: "再认识「恢复数据」",
                    message: "恢复可以把已备份的数据找回来，支持跨设备/跨平台迁移后继续使用。先有备份，恢复才有意义。",
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
                    title: "现在做一次首次备份",
                    message: "请点击「备份数据」完成首次备份。备份可能需要一点时间；若你现在不方便，也可以点左上角「跳过」，下次再备份。",
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

    var cloudFileBackupRestoreGuideContent: some View {
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
                    title: "iCloud 及时同步与延迟说明",
                    message: "开启后会自动同步变更。大多数情况下是秒级到几十秒；网络较慢、系统省电或后台调度时，可能延迟到 1～5 分钟，属正常现象。",
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

    var privacyDisplayStepGuideContent: some View {
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
                    title: "原价开关",
                    message: "这个开关控制列表中是否显示原价信息。你可以和入库价格分开管理：例如只看当前入库价，或两者都隐藏，让衣橱浏览更清爽、更私密。",
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
                    title: "点击 House 的穿搭手帐热区",
                    message: "先从 House 里的穿搭手帐热区进入，我们再认识手帐本和书页。",
                    currentStep: 1,
                    totalSteps: 2,
                    accent: .orange,
                    actionTitle: nil,
                    onAction: nil,
                    showPulse: false
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

    var magicStickerGuideContent: some View {
        if let preUnlockGuide = preUnlockWardrobeGuideContentIfNeeded(for: .ootdDefaultBook) {
            return preUnlockGuide
        }

        return AnyView(
            GeometryReader { geometry in
                switch magicStickerGuideStep {
                case .step1_longPressHouseTab:
                    let tabBarHeight: CGFloat = 56
                    let houseTabFrame = CGRect(
                        x: (geometry.size.width * 0.375) - 34,
                        y: geometry.size.height - geometry.safeAreaInsets.bottom - tabBarHeight,
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

    var batchEditInteractiveGuideContent: some View {
        GeometryReader { geometry in
            switch batchEditGuideStep {
            case .step1_clickMoreMenu:
                let fallbackFrame = CGRect(x: geometry.size.width - 64, y: max(geometry.safeAreaInsets.top + 8, 12), width: 36, height: 36)
                let targetFrame = aiGuideTargetFrame(
                    globalFrame: guideManager.guideTargetFrame(for: .wardrobeMoreMenuButton),
                    in: geometry,
                    fallback: fallbackFrame
                )
                // 右上角“更多”按钮在新导航样式下会偏上；
                // 统一下移高亮与猫爪，确保两者持续对齐真实菜单入口
                let step1GuideYOffset: CGFloat = 26
                let adjustedFrame = CGRect(
                    x: max(8, targetFrame.minX - 10),
                    y: max(geometry.safeAreaInsets.top + 12, targetFrame.minY + step1GuideYOffset),
                    width: targetFrame.width,
                    height: targetFrame.height
                )
                // 菜单定位必须基于原始「更多」按钮坐标；
                // 不要复用 step1 的下移高亮坐标，否则会把「编辑」行 fallback 算到下方。
                let menuEditFrame = batchEditMenuEditEntryGuideFrame(in: geometry, moreButtonFrame: targetFrame)
                let shouldHighlightEditEntry = didOpenBatchEditMoreMenu ||
                    guideManager.guideTargetFrame(for: .wardrobeEditMenuEntry) != nil
                let step1Frame = shouldHighlightEditEntry ? menuEditFrame : adjustedFrame
                let step1CornerRadius: CGFloat = shouldHighlightEditEntry ? 14 : 18
                let step1Title = shouldHighlightEditEntry ? "点击「编辑」" : "点击右上角更多按钮"
                let step1Message = shouldHighlightEditEntry
                    ? "菜单已经弹出啦，点击「编辑」进入批量编辑模式。"
                    : "先点右上角「更多」，再在弹出菜单里选择「编辑」。进入编辑态后，我们继续下一步。"
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
                    title: "选中一张卡片",
                    message: "随便点选一张衣橱卡片，让底部批量工具条进入可用状态。",
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

}
