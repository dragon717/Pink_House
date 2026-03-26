import Foundation

enum AppFirstLaunchStep: String, CaseIterable, Identifiable {
    case none = "none"
    case welcome = "welcome"
    case running = "running"
    case pointing = "pointing"
    case complete = "complete"

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

enum BubblePosition {
    case top
    case center
    case bottom
}

enum PointDirection {
    case none
    case topRight
    case topLeft
    case bottom
    case center

    var needsFlip: Bool {
        switch self {
        case .topLeft: return true
        default: return false
        }
    }
}

enum GuideTargetKey: String, CaseIterable, Hashable {
    case aiAnalysisVIPCard = "aiAnalysis.vipCard"
    case aiAnalysisExchangeButton = "aiAnalysis.exchangeButton"
    case homePetChatTab = "home.petChatTab"
    case petChatSearchBar = "petChat.searchBar"
    case petChatGuideOptionButton = "petChat.guideOptionButton"
    case homeHouseTab = "home.houseTab"
    case wealthEntry = "wealth.entry"
    case wealthMainTabSegment = "wealth.mainTab.segment"
    case accountSyncEntry = "accountSync.entry"
    case cloudAppleSignInButton = "cloud.appleSignInButton"
    case cloudFileBackupSection = "cloud.fileBackup.section"
    case iCloudRealtimeSyncSection = "cloud.realtimeSync.section"
    case systemSettingsEntry = "systemSettings.entry"
    case localBackupDataAction = "localBackupData.action"
    case localRestoreDataAction = "localRestoreData.action"
    case exportCSVEntry = "exportCSV.entry"
    case widgetCustomizeEntry = "widgetCustomize.entry"
    case themeCustomizeEntry = "themeCustomize.entry"
    case themeCustomPersonalizationEntry = "themeCustom.personalizationEntry"
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
    case wardrobeShortcutManualCreateAction = "wardrobe.shortcut.manualCreateAction"
    case wardrobeShortcutBatchImportAction = "wardrobe.shortcut.batchImportAction"
    case wardrobeMoreMenuButton = "wardrobe.moreMenuButton"
    case wardrobeEditMenuEntry = "wardrobe.editMenuEntry"
    case wardrobeBatchEditToolbar = "wardrobe.batchEditToolbar"
    case wardrobeSelectionCard = "wardrobe.selectionCard"
    case wardrobeDoneSelectionButton = "wardrobe.doneSelectionButton"
    case ootdEntry = "ootd.entry"
    case calendarEntry = "calendar.entry"
    case favoriteMenuMagicStickerEntry = "favoriteMenu.magicStickerEntry"
    case themeColorModeTabs = "themeColorMode.tabs"
    case spaceBookModeTabs = "spaceBook.modeTabs"
    case spaceBookShelfMoreMenuButton = "spaceBook.shelfMoreMenuButton"
    case spaceBookFirstBookCard = "spaceBook.firstBookCard"
    case spaceBookDetailMoreMenuButton = "spaceBook.detailMoreMenuButton"
    case spaceBookFirstPageCard = "spaceBook.firstPageCard"
    case spatialCanvasToolbar = "spatialCanvas.toolbar"
    case spatialCanvasImportMenu = "spatialCanvas.importMenu"
}

extension FeatureUnlockManager {
    static let experienceGuidedFeatures: [FeatureItem] = [
        .dataBackup,
        .cloudSync,
        .batchImport,
        .themeCustomize,
        .widgetCustomize,
        .filterClassic,
        .privacyDisplay,
        .tagBrandFieldDisplay,
        .spaceBook,
        .batchEdit,
        .localFileBackupRestore,
        .exportCSV,
        .cloudFileBackupRestore,
        .customColorPersonalization,
        .ootd,
        .ootdDefaultBook,
        .calendar,
        .wealth,
        .aiAnalysis,
    ]

    static let preUnlockGuidedFeatures: Set<FeatureItem> = [
        .aiAnalysis,
        .ootd,
        .ootdDefaultBook,
        .calendar,
        .batchImport,
        .spaceBook
    ]

    func canStartPreUnlockGuide(for feature: FeatureItem) -> Bool {
        FeatureUnlockManager.preUnlockGuidedFeatures.contains(feature)
    }

    func needsFeatureExperienceGuide(for feature: FeatureItem) -> Bool {
        guard FeatureUnlockManager.experienceGuidedFeatures.contains(feature) else { return false }
        guard isUnlocked(feature) else { return false }
        let key = "featureExperienceGuide_\(feature.rawValue)"
        return !UserDefaults.standard.bool(forKey: key)
    }

    func markFeatureExperienceGuideCompleted(for feature: FeatureItem) {
        let key = "featureExperienceGuide_\(feature.rawValue)"
        UserDefaults.standard.set(true, forKey: key)
    }

    func resetFeatureExperienceGuide(for feature: FeatureItem) {
        let key = "featureExperienceGuide_\(feature.rawValue)"
        UserDefaults.standard.set(false, forKey: key)
    }
}

struct AppFirstLaunchState: Codable {
    var isCompleted: Bool = false
    var currentStep: String = AppFirstLaunchStep.none.rawValue
    var skippedAt: Date? = nil
    var startedAt: Date = Date()
}

enum HighlightType {
    case circle
    case roundedRect
}
