import Foundation

enum AIAnalysisGuideStep: Int, CaseIterable {
    case preUnlockStep1ReturnToMe = 1
    case preUnlockStep2ClickVIP = 2
    case preUnlockStep3Exchange = 3
    case postUnlockStep1ClickPetChatTab = 4
    case postUnlockStep2ClickSearchBar = 5
    case postUnlockStep3FeatureIntro = 6

    enum Flow {
        case preUnlock
        case postUnlock
    }

    static var preUnlockCases: [AIAnalysisGuideStep] {
        [.preUnlockStep1ReturnToMe, .preUnlockStep2ClickVIP, .preUnlockStep3Exchange]
    }

    static var postUnlockCases: [AIAnalysisGuideStep] {
        [.postUnlockStep1ClickPetChatTab, .postUnlockStep2ClickSearchBar, .postUnlockStep3FeatureIntro]
    }

    var flow: Flow {
        switch self {
        case .preUnlockStep1ReturnToMe, .preUnlockStep2ClickVIP, .preUnlockStep3Exchange:
            return .preUnlock
        case .postUnlockStep1ClickPetChatTab, .postUnlockStep2ClickSearchBar, .postUnlockStep3FeatureIntro:
            return .postUnlock
        }
    }

    var stepsInFlow: [AIAnalysisGuideStep] {
        switch flow {
        case .preUnlock:
            return Self.preUnlockCases
        case .postUnlock:
            return Self.postUnlockCases
        }
    }

    var currentStepInFlow: Int {
        (stepsInFlow.firstIndex(of: self) ?? 0) + 1
    }

    var totalStepsInFlow: Int {
        stepsInFlow.count
    }

    var title: String {
        switch self {
        case .preUnlockStep1ReturnToMe: return "返回「我」界面"
        case .preUnlockStep2ClickVIP: return "点击VIP卡片"
        case .preUnlockStep3Exchange: return "兑换会员时长"
        case .postUnlockStep1ClickPetChatTab: return "点击「萌宠对话」Tab"
        case .postUnlockStep2ClickSearchBar: return "点击对话内引导选项"
        case .postUnlockStep3FeatureIntro: return "萌宠智能对话怎么玩"
        }
    }

    var message: String {
        switch self {
        case .preUnlockStep1ReturnToMe:
            return "首先，请返回到「我」界面，我们将引导你开通 VIP 会员。"
        case .preUnlockStep2ClickVIP:
            return "点击 VIP 会员卡片，进入会员中心。"
        case .preUnlockStep3Exchange:
            return "点击「兑换会员时长」，使用喵币兑换 VIP 天数，解锁萌宠智能对话。"
        case .postUnlockStep1ClickPetChatTab:
            return "先点击底部「萌宠对话」Tab，进入智能对话页。"
        case .postUnlockStep2ClickSearchBar:
            return "点击对话窗口里的「看天气穿搭」引导按钮，它是嵌入在聊天气泡里的选项。"
        case .postUnlockStep3FeatureIntro:
            return "这里可以直接点对话内选项，也可以在输入区提问：情感陪伴、穿搭建议、衣橱统计都能聊。"
        }
    }

    var bubblePosition: BubblePosition {
        switch self {
        case .preUnlockStep1ReturnToMe, .preUnlockStep2ClickVIP, .postUnlockStep2ClickSearchBar, .postUnlockStep3FeatureIntro:
            return .bottom
        case .preUnlockStep3Exchange, .postUnlockStep1ClickPetChatTab:
            return .top
        }
    }

    var highlightType: HighlightType {
        switch self {
        case .preUnlockStep1ReturnToMe, .postUnlockStep1ClickPetChatTab:
            return .circle
        case .preUnlockStep2ClickVIP, .preUnlockStep3Exchange, .postUnlockStep2ClickSearchBar, .postUnlockStep3FeatureIntro:
            return .roundedRect
        }
    }

    var showCatPaw: Bool {
        switch self {
        case .preUnlockStep2ClickVIP, .postUnlockStep3FeatureIntro:
            return false
        case .preUnlockStep1ReturnToMe, .preUnlockStep3Exchange, .postUnlockStep1ClickPetChatTab, .postUnlockStep2ClickSearchBar:
            return true
        }
    }

    var showsCompletionButton: Bool {
        switch self {
        case .preUnlockStep3Exchange, .postUnlockStep3FeatureIntro:
            return true
        default:
            return false
        }
    }

    var completionButtonTitle: String {
        switch self {
        case .postUnlockStep3FeatureIntro:
            return "开始体验"
        default:
            return "知道了"
        }
    }
}

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

enum WardrobeAddGuideStep: Int, CaseIterable {
    case step1_clickAddButton = 1
    case step2_chooseTargetOption = 2
}

enum ThemeCustomizeGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_scrollToThemeEntry = 2
    case step3_clickThemeEntry = 3
    case step4_switchToMagicTab = 4
    case step5_magicThemeExplanation = 5
}

enum CustomColorPersonalizationGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_scrollToThemeEntry = 2
    case step3_clickThemeEntry = 3
    case step4_switchToCustomTab = 4
    case step5_personalizationExplanation = 5
}

enum LocalFileBackupRestoreGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_scrollToSystemSettings = 2
    case step3_clickSystemSettings = 3
    case step4_introBackupData = 4
    case step5_introRestoreData = 5
    case step6_firstBackup = 6
}

enum ExportCSVGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_scrollToSystemSettings = 2
    case step3_clickSystemSettings = 3
    case step4_clickExportCSV = 4
}

enum CloudFileBackupRestoreGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_clickAccountSync = 2
    case step3_signInAppleID = 3
    case step4_cloudBackupExplanation = 4
    case step5_realtimeSyncDelayExplanation = 5
}

enum PersonalPreferenceGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_clickWardrobeEntry = 2
    case step3_interfaceStyle = 3
    case step4_filterMode = 4
    case step5_appAppearance = 5
}

enum PrivacyDisplayGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_clickWardrobeEntry = 2
    case step3_showPurchasePrice = 3
    case step4_showOriginalPrice = 4
}

enum TagBrandFieldGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1
    case step2_clickWardrobeEntry = 2
    case step3_scrollToManagementEntries = 3
    case step4_tagManagement = 4
    case step5_brandManagement = 5
    case step6_fieldManagement = 6
}

enum OOTDGuideStep: Int, CaseIterable {
    case step1_clickOotdEntry = 1
    case step2_ootdExplanation = 2
}

enum CalendarGuideStep: Int, CaseIterable {
    case step1_clickCalendarEntry = 1
    case step2_calendarExplanation = 2
}

enum MagicStickerGuideStep: Int, CaseIterable {
    case step1_returnToMeForMenuSetup = 1
    case step2_clickFavoriteMenuSettings = 2
    case step3_addMagicStickerButton = 3
    case step4_returnToMeAfterMenuSetup = 4
    case step5_longPressHouseTab = 5
    case step6_clickMagicStickerEntry = 6
    case step7_magicStickerExplanation = 7
}

enum BatchEditGuideStep: Int, CaseIterable {
    case step1_clickMoreMenu = 1
    case step2_selectOneCard = 2
    case step3_toolbarExplanation = 3
    case step4_finishSelection = 4
}

enum SpaceBookGuideStep: Int, CaseIterable {
    case step1_clickWardrobeOotdEntry = 1
    case step1a_createOotdBook = 2
    case step1b_createOotdPage = 3
    case step2_switchToSpaceTab = 4
    case step3_createSpaceBook = 5
    case step4_createFirstPage = 6
    case step5_open3DEditor = 7
    case step6_openScanner = 8
    case step7_scannerHowTo = 9
}

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
