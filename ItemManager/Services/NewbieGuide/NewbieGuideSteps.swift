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

// MARK: - 空间手帐引导步骤
// 根据流程图，分为两个阶段：
// 阶段1：未解锁时（前置任务引导 - 共5步）
// 阶段2：已解锁后（完整引导 - 共7步）
enum SpaceBookGuideStep: Int, CaseIterable {
    // MARK: 阶段1: 前置任务引导（解锁前）- 共5步
    case preUnlockStep1_clickWardrobeOotdEntry = 1  // 点击衣橱「穿搭手帐」
    case preUnlockStep2_createOotdBook = 2          // 右上角「更多」→ 新建手帐
    case preUnlockStep3_clickOotdBook = 3           // 点击刚创建的手帐进入
    case preUnlockStep4_createOotdPage = 4          // 手帐详情页「更多」→ 新建书页
    case preUnlockStep5_complete = 5                // 前置任务完成！自动解锁空间手帐

    // MARK: 阶段2: 完整功能引导（解锁后）- 共7步
    case step1_clickWardrobeOotdEntry = 6          // 点击衣橱「穿搭手帐」（解锁后入口）
    case step2_switchToSpaceTab = 7                // 切换到空间页签
    case step3_createSpaceBook = 8                 // 创建空间手帐
    case step4_createSpacePage = 9                 // 创建空间书页
    case step5_enter3DEditor = 10                  // 进入3D编辑器
    case step6_openScanner = 11                    // 打开空间扫描器
    case step7_scannerHowTo = 12                   // 扫描操作指引

    // MARK: - Flow 定义
    enum Flow {
        case preUnlock  // 前置任务引导（5步）
        case postUnlock // 完整功能引导（7步，从第6步开始编号）
    }

    var flow: Flow {
        switch self {
        case .preUnlockStep1_clickWardrobeOotdEntry,
             .preUnlockStep2_createOotdBook,
             .preUnlockStep3_clickOotdBook,
             .preUnlockStep4_createOotdPage,
             .preUnlockStep5_complete:
            return .preUnlock
        case .step1_clickWardrobeOotdEntry,
             .step2_switchToSpaceTab,
             .step3_createSpaceBook,
             .step4_createSpacePage,
             .step5_enter3DEditor,
             .step6_openScanner,
             .step7_scannerHowTo:
            return .postUnlock
        }
    }

    // MARK: - 步骤信息

    /// 当前流程中的步骤序号（用于UI显示）
    var stepNumberInFlow: Int {
        switch flow {
        case .preUnlock:
            return rawValue
        case .postUnlock:
            return rawValue - 5  // 解锁后步骤从1开始计数
        }
    }

    /// 当前流程的总步数
    var totalStepsInFlow: Int {
        switch flow {
        case .preUnlock:
            return 5
        case .postUnlock:
            return 7
        }
    }

    /// 标题
    var title: String {
        switch self {
        // 前置任务引导
        case .preUnlockStep1_clickWardrobeOotdEntry:
            return "点击衣橱「穿搭手帐」"
        case .preUnlockStep2_createOotdBook:
            return "新建穿搭手帐"
        case .preUnlockStep3_clickOotdBook:
            return "进入手帐"
        case .preUnlockStep4_createOotdPage:
            return "新建书页"
        case .preUnlockStep5_complete:
            return "前置任务完成"

        // 完整功能引导
        case .step1_clickWardrobeOotdEntry:
            return "点击衣橱「穿搭手帐」"
        case .step2_switchToSpaceTab:
            return "切换到空间页签"
        case .step3_createSpaceBook:
            return "创建空间手帐"
        case .step4_createSpacePage:
            return "创建空间书页"
        case .step5_enter3DEditor:
            return "进入3D编辑器"
        case .step6_openScanner:
            return "打开空间扫描器"
        case .step7_scannerHowTo:
            return "扫描操作指引"
        }
    }

    /// 提示消息
    var message: String {
        switch self {
        // 前置任务引导
        case .preUnlockStep1_clickWardrobeOotdEntry:
            return "点击衣橱统计卡片里的「穿搭手帐」入口，进入穿搭手帐。"
        case .preUnlockStep2_createOotdBook:
            return "点击右上角「更多」，选择「新建手帐」，创建一个非默认手帐。"
        case .preUnlockStep3_clickOotdBook:
            return "点击刚创建的「非默认手帐」进入详情页。"
        case .preUnlockStep4_createOotdPage:
            return "在手帐详情页点击右上角「更多」，选择「新建书页」。"
        case .preUnlockStep5_complete:
            return "恭喜完成前置任务！空间手帐功能已自动解锁。"

        // 完整功能引导
        case .step1_clickWardrobeOotdEntry:
            return "先从衣橱统计卡片进入「穿搭手帐」，空间手帐入口就在里面。"
        case .step2_switchToSpaceTab:
            return "点击上方「空间」页签，切换到空间手帐模式。"
        case .step3_createSpaceBook:
            return "点击右上角「更多」，选择「新建空间手帐」。"
        case .step4_createSpacePage:
            return "点击右上角「更多」，选择「新建空间书页」。"
        case .step5_enter3DEditor:
            return "点击书页卡片，进入3D编辑器开始创作。"
        case .step6_openScanner:
            return "点击左侧工具栏「导入」按钮，再选择「相机」进入空间扫描。"
        case .step7_scannerHowTo:
            return "请在光线充足的地方扫描；让镜头包住物体，先完成稳定定位，再做360°扫描。"
        }
    }

    /// 是否显示猫爪动画
    var showCatPaw: Bool {
        switch self {
        case .preUnlockStep1_clickWardrobeOotdEntry,
             .preUnlockStep2_createOotdBook,
             .preUnlockStep3_clickOotdBook,
             .preUnlockStep4_createOotdPage:
            return true
        default:
            return false
        }
    }

    /// 是否显示完成按钮
    var showsCompletionButton: Bool {
        switch self {
        case .preUnlockStep5_complete, .step7_scannerHowTo:
            return true
        default:
            return false
        }
    }

    /// 完成按钮标题
    var completionButtonTitle: String {
        switch self {
        case .preUnlockStep5_complete:
            return "开始空间手帐之旅"
        case .step7_scannerHowTo:
            return "知道了，完成引导"
        default:
            return "知道了"
        }
    }
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
