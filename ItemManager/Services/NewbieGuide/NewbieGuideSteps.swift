import Foundation

// MARK: - 统一引导步骤协议

protocol GuideStepDescribable {
    var title: String { get }
    var message: String { get }
    var showCatPaw: Bool { get }
}

enum AIAnalysisGuideStep: Int, CaseIterable, GuideStepDescribable {
    case preUnlockStep1ReturnToMe = 1
    case preUnlockStep2ClickVIP = 2
    case preUnlockStep3Exchange = 3
    case postUnlockStep1ClickPetChatTab = 4
    case postUnlockStep2BrowsePets = 5
    case postUnlockStep3AdoptNaicha = 6
    case postUnlockStep4NamePet = 7
    case postUnlockStep5ClickSearchBar = 8
    case postUnlockStep6FeatureIntro = 9

    enum Flow {
        case preUnlock
        case postUnlock
    }

    static var preUnlockCases: [AIAnalysisGuideStep] {
        [.preUnlockStep1ReturnToMe, .preUnlockStep2ClickVIP, .preUnlockStep3Exchange]
    }

    static var postUnlockCases: [AIAnalysisGuideStep] {
        [
            .postUnlockStep1ClickPetChatTab,
            .postUnlockStep2BrowsePets,
            .postUnlockStep3AdoptNaicha,
            .postUnlockStep4NamePet,
            .postUnlockStep5ClickSearchBar,
            .postUnlockStep6FeatureIntro
        ]
    }

    var flow: Flow {
        switch self {
        case .preUnlockStep1ReturnToMe, .preUnlockStep2ClickVIP, .preUnlockStep3Exchange:
            return .preUnlock
        case .postUnlockStep1ClickPetChatTab,
             .postUnlockStep2BrowsePets,
             .postUnlockStep3AdoptNaicha,
             .postUnlockStep4NamePet,
             .postUnlockStep5ClickSearchBar,
             .postUnlockStep6FeatureIntro:
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
        case .postUnlockStep2BrowsePets: return "左右滑动看看伙伴"
        case .postUnlockStep3AdoptNaicha: return "领养「奶茶」"
        case .postUnlockStep4NamePet: return "给萌宠起名字"
        case .postUnlockStep5ClickSearchBar: return "点击对话内引导选项"
        case .postUnlockStep6FeatureIntro: return "萌宠智能对话怎么玩"
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
        case .postUnlockStep2BrowsePets:
            return "先左右滑动看看不同的小伙伴，最后回到「奶茶」，再继续下一步。"
        case .postUnlockStep3AdoptNaicha:
            return "选中「奶茶」后，点击下方「领养」。"
        case .postUnlockStep4NamePet:
            return "给你的萌宠起个名字，输入后点「确定」，我们再继续后面的智能对话引导。"
        case .postUnlockStep5ClickSearchBar:
            return "点击对话窗口里的「看天气穿搭」引导按钮，它是嵌入在聊天气泡里的选项。"
        case .postUnlockStep6FeatureIntro:
            return "这里可以直接点对话内选项，也可以在输入区提问：情感陪伴、穿搭建议、衣橱统计都能聊。"
        }
    }

    var bubblePosition: BubblePosition {
        switch self {
        case .preUnlockStep1ReturnToMe, .preUnlockStep2ClickVIP, .postUnlockStep5ClickSearchBar, .postUnlockStep6FeatureIntro:
            return .bottom
        case .preUnlockStep3Exchange,
             .postUnlockStep1ClickPetChatTab,
             .postUnlockStep2BrowsePets,
             .postUnlockStep3AdoptNaicha,
             .postUnlockStep4NamePet:
            return .top
        }
    }

    var highlightType: HighlightType {
        switch self {
        case .preUnlockStep1ReturnToMe, .postUnlockStep1ClickPetChatTab:
            return .circle
        case .preUnlockStep2ClickVIP,
             .preUnlockStep3Exchange,
             .postUnlockStep2BrowsePets,
             .postUnlockStep3AdoptNaicha,
             .postUnlockStep4NamePet,
             .postUnlockStep5ClickSearchBar,
             .postUnlockStep6FeatureIntro:
            return .roundedRect
        }
    }

    var showCatPaw: Bool {
        switch self {
        case .preUnlockStep2ClickVIP,
             .postUnlockStep2BrowsePets,
             .postUnlockStep4NamePet,
             .postUnlockStep6FeatureIntro:
            return false
        case .preUnlockStep1ReturnToMe,
             .preUnlockStep3Exchange,
             .postUnlockStep1ClickPetChatTab,
             .postUnlockStep3AdoptNaicha,
             .postUnlockStep5ClickSearchBar:
            return true
        }
    }

    var showsCompletionButton: Bool {
        switch self {
        case .preUnlockStep3Exchange, .postUnlockStep6FeatureIntro:
            return true
        default:
            return false
        }
    }

    var completionButtonTitle: String {
        switch self {
        case .postUnlockStep6FeatureIntro:
            return "开始体验"
        default:
            return "知道了"
        }
    }
}

enum WidgetCustomizeGuideStep: Int, CaseIterable, GuideStepDescribable {
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

enum WardrobeAddGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_clickAddButton = 1
    case step2_chooseTargetOption = 2

    var title: String {
        switch self {
        case .step1_clickAddButton: return "点击右上角 + 号"
        case .step2_chooseTargetOption: return "选择创建方式"
        }
    }

    var message: String {
        switch self {
        case .step1_clickAddButton: return "先点击衣橱右上角的 + 号，展开创建菜单。"
        case .step2_chooseTargetOption: return "在展开菜单中选择创建方式，继续完成任务。"
        }
    }

    var showCatPaw: Bool {
        switch self {
        case .step1_clickAddButton: return true
        case .step2_chooseTargetOption: return false
        }
    }
}

enum ThemeCustomizeGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_returnToMe = 1
    case step2_scrollToThemeEntry = 2
    case step3_clickThemeEntry = 3
    case step4_switchToMagicTab = 4
    case step5_magicThemeExplanation = 5

    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_scrollToThemeEntry: return "下滑找到主题配色"
        case .step3_clickThemeEntry: return "点击主题配色豆腐块"
        case .step4_switchToMagicTab: return "切换到魔法配色页签"
        case .step5_magicThemeExplanation: return "认识魔法配色"
        }
    }

    var message: String {
        switch self {
        case .step1_returnToMe: return "先从魔法任务页返回到「我」，再去找主题配色豆腐块。"
        case .step2_scrollToThemeEntry: return "请继续向下滑动，在设置豆腐块区域找到「主题配色」入口。"
        case .step3_clickThemeEntry: return "在「我」页找到「主题配色」豆腐块，点进去进入主题页。"
        case .step4_switchToMagicTab: return "这里有「原生魔法配色」和「客制化配色」两个页签。请切到「魔法配色」，看看自动调色是怎么工作的。"
        case .step5_magicThemeExplanation: return "魔法配色会根据背景和卡片自动调整字体与模块颜色。你可以先看预览，再决定是否长期使用这套自动调色方案。"
        }
    }

    var showCatPaw: Bool {
        switch self {
        case .step4_switchToMagicTab:
            return true
        default:
            return false
        }
    }
}

enum CustomColorPersonalizationGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_returnToMe = 1
    case step2_scrollToThemeEntry = 2
    case step3_clickThemeEntry = 3
    case step4_switchToCustomTab = 4
    case step5_scrollToPersonalization = 5
    case step6_personalizationExplanation = 6

    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_scrollToThemeEntry: return "下滑找到主题配色"
        case .step3_clickThemeEntry: return "点击主题配色豆腐块"
        case .step4_switchToCustomTab: return "切换到客制化配色页签"
        case .step5_scrollToPersonalization: return "下滑找到个性化入口"
        case .step6_personalizationExplanation: return "认识个性化入口"
        }
    }

    var message: String {
        switch self {
        case .step1_returnToMe: return "先从魔法任务页返回到「我」，再去找主题配色豆腐块。"
        case .step2_scrollToThemeEntry: return "请继续向下滑动，在设置豆腐块区域找到「主题配色」入口。"
        case .step3_clickThemeEntry: return "在「我」页找到「主题配色」豆腐块，点进去进入主题页。"
        case .step4_switchToCustomTab: return "请切到「客制化配色」，我们下一步会看「个性化」入口和我的主题方案。"
        case .step5_scrollToPersonalization: return "请继续向下滑动，找到「个性化」豆腐块。"
        case .step6_personalizationExplanation: return "这里是「个性化」豆腐块。点击后会展开「我的主题方案」，你可以继续自定义字体配色和卡片样式，打造自己的专属主题。"
        }
    }

    var showCatPaw: Bool { false }
}

enum LocalFileBackupRestoreGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_returnToMe = 1
    case step2_scrollToSystemSettings = 2
    case step3_clickSystemSettings = 3
    case step4_introBackupData = 4
    case step5_introRestoreData = 5
    case step6_firstBackup = 6

    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_scrollToSystemSettings: return "下滑找到系统与更多"
        case .step3_clickSystemSettings: return "点击系统与更多"
        case .step4_introBackupData: return "先认识「备份数据」"
        case .step5_introRestoreData: return "再认识「恢复数据」"
        case .step6_firstBackup: return "现在做一次首次备份"
        }
    }

    var message: String {
        switch self {
        case .step1_returnToMe: return "先从魔法任务页返回到「我」，我们去找本地文件备份入口。"
        case .step2_scrollToSystemSettings: return "继续向下滑动，在设置豆腐块区域找到「系统与更多」。"
        case .step3_clickSystemSettings: return "点开「系统与更多」，进入系统设置页。"
        case .step4_introBackupData: return "备份是最重要的一步：它会把当前数据打包保存，防止误删、换机或重装时丢失记录。建议养成定期备份习惯。"
        case .step5_introRestoreData: return "恢复可以把已备份的数据找回来，支持跨设备/跨平台迁移后继续使用。先有备份，恢复才有意义。"
        case .step6_firstBackup: return "请点击「备份数据」完成首次备份。备份可能需要一点时间；若你现在不方便，也可以点左上角「跳过」，下次再备份。"
        }
    }

    var showCatPaw: Bool { false }
}

enum ExportCSVGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_returnToMe = 1
    case step2_scrollToSystemSettings = 2
    case step3_clickSystemSettings = 3
    case step4_clickExportCSV = 4

    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_scrollToSystemSettings: return "下滑找到系统与更多"
        case .step3_clickSystemSettings: return "点击系统与更多"
        case .step4_clickExportCSV: return "点击导出到 CSV"
        }
    }

    var message: String {
        switch self {
        case .step1_returnToMe: return "先从魔法任务页返回到「我」，我们去找导出表格入口。"
        case .step2_scrollToSystemSettings: return "继续向下滑动，在设置豆腐块区域找到「系统与更多」。"
        case .step3_clickSystemSettings: return "点开「系统与更多」，进入系统设置页。"
        case .step4_clickExportCSV: return "点击「导出 CSV (Export CSV)」，即可开始导出表格文件。"
        }
    }

    var showCatPaw: Bool { false }
}

enum CloudFileBackupRestoreGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_returnToMe = 1
    case step2_clickAccountSync = 2
    case step3_signInAppleID = 3
    case step4_cloudBackupExplanation = 4
    case step5_realtimeSyncDelayExplanation = 5

    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_clickAccountSync: return "点击账户与同步"
        case .step3_signInAppleID: return "先登录 Apple ID"
        case .step4_cloudBackupExplanation: return "认识云端文件备份与恢复"
        case .step5_realtimeSyncDelayExplanation: return "iCloud 及时同步与延迟说明"
        }
    }

    var message: String {
        switch self {
        case .step1_returnToMe: return "先从魔法任务页返回到「我」，再去「账户与同步」。"
        case .step2_clickAccountSync: return "点开这个豆腐块，进入账号与 iCloud 同步管理页面。"
        case .step3_signInAppleID: return "点击这里完成 Apple 登录。登录后才能使用云端文件备份与恢复，以及 iCloud 自动同步。"
        case .step4_cloudBackupExplanation: return "这里可以「备份到云端」和「从云端恢复」。建议你先备份一份，这样换设备或误删后都能快速找回数据。"
        case .step5_realtimeSyncDelayExplanation: return "开启后会自动同步变更。大多数情况下是秒级到几十秒；网络较慢、系统省电或后台调度时，可能延迟到 1～5 分钟，属正常现象。"
        }
    }

    var showCatPaw: Bool { false }
}

enum PersonalPreferenceGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_returnToMe = 1
    case step2_clickWardrobeEntry = 2
    case step3_interfaceStyle = 3
    case step4_filterMode = 4
    case step5_appAppearance = 5

    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_clickWardrobeEntry: return "点击梦幻衣橱豆腐块"
        case .step3_interfaceStyle: return "界面样式：决定衣橱导航布局"
        case .step4_filterMode: return "筛选模式：决定你怎么筛衣服"
        case .step5_appAppearance: return "应用外观：控制整体观感"
        }
    }

    var message: String {
        switch self {
        case .step1_returnToMe: return "先返回到「我」页，我们一起去找梦幻衣橱豆腐块。"
        case .step2_clickWardrobeEntry: return "进入梦幻衣橱设置页后，我们会一起看界面样式、筛选模式和应用外观这些个性化体验。"
        case .step3_interfaceStyle: return "这里用来切换衣橱的导航形态。不同样式会影响顶部导航与操作按钮的组织方式，按你的使用习惯选更顺手的就行。"
        case .step4_filterMode: return "经典筛选是下拉菜单，适合快速单项筛；多维筛选是半屏多选，适合组合条件做更精细筛选。"
        case .step5_appAppearance: return "这里是个性化最核心的一块：背景类型决定用纯色还是图片；背景颜色/图片与不透明度决定整体氛围；高斯模糊决定前景内容与背景的层次；「字体配色与卡片样式」则影响文字可读性和卡片风格。搭配好这几项，你会得到更舒适也更有个人风格的界面。"
        }
    }

    var showCatPaw: Bool { false }
}

enum PrivacyDisplayGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_returnToMe = 1
    case step2_clickWardrobeEntry = 2
    case step3_showPurchasePrice = 3
    case step4_showOriginalPrice = 4

    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_clickWardrobeEntry: return "点击梦幻衣橱豆腐块"
        case .step3_showPurchasePrice: return "入库价格开关"
        case .step4_showOriginalPrice: return "原价开关"
        }
    }

    var message: String {
        switch self {
        case .step1_returnToMe: return "先返回到「我」页，我们一起去找梦幻衣橱豆腐块。"
        case .step2_clickWardrobeEntry: return "进入梦幻衣橱设置页后，我们来认识「隐私显示」里的两个开关。"
        case .step3_showPurchasePrice: return "打开时，衣橱列表会显示每件衣服的入库价格；关闭后会隐藏入库价格，适合共享屏幕或给别人看衣橱时保护隐私。"
        case .step4_showOriginalPrice: return "这个开关控制列表中是否显示原价信息。你可以和入库价格分开管理：例如只看当前入库价，或两者都隐藏，让衣橱浏览更清爽、更私密。"
        }
    }

    var showCatPaw: Bool { false }
}

enum TagBrandFieldGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_returnToMe = 1
    case step2_clickWardrobeEntry = 2
    case step3_scrollToManagementEntries = 3
    case step4_tagManagement = 4
    case step5_brandManagement = 5
    case step6_fieldManagement = 6

    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_clickWardrobeEntry: return "点击梦幻衣橱豆腐块"
        case .step3_scrollToManagementEntries: return "下滑找到管理项"
        case .step4_tagManagement: return "标签管理"
        case .step5_brandManagement: return "品牌管理"
        case .step6_fieldManagement: return "属性字段管理"
        }
    }

    var message: String {
        switch self {
        case .step1_returnToMe: return "先返回到「我」页，我们一起去找梦幻衣橱豆腐块。"
        case .step2_clickWardrobeEntry: return "进入梦幻衣橱设置页后，我们会依次认识标签管理、品牌管理和属性字段管理。"
        case .step3_scrollToManagementEntries: return "请继续下滑到页面下方，找到「标签管理 / 品牌管理 / 属性字段排序与显示」这三项。"
        case .step4_tagManagement: return "这里管理你所有标签（例如风格、场景、季节等）。把标签体系整理好后，衣橱筛选会更快、更准，也更方便复用。"
        case .step5_brandManagement: return "这里统一维护品牌名称，避免同品牌出现多个写法。品牌数据干净后，统计、筛选和搜索都会更稳定。"
        case .step6_fieldManagement: return "这里可以控制属性字段的显示与排序。把常用字段放前面、低频字段放后面，日常录入和查看都会更顺手。"
        }
    }

    var showCatPaw: Bool { false }
}

enum OOTDGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_clickOotdEntry = 1
    case step2_ootdExplanation = 2

    var title: String {
        switch self {
        case .step1_clickOotdEntry: return "点击 House 的穿搭手帐热区"
        case .step2_ootdExplanation: return "认识穿搭手帐和书页"
        }
    }

    var message: String {
        switch self {
        case .step1_clickOotdEntry: return "先从 House 里的穿搭手帐热区进入，我们再认识手帐本和书页。"
        case .step2_ootdExplanation: return "这里先看到的是手帐本列表；点进任意一本后，就能看到它下面的书页。书页里可以继续记录搭配、图片和灵感。"
        }
    }

    var showCatPaw: Bool { false }
}

enum CalendarGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_clickCalendarEntry = 1
    case step2_calendarExplanation = 2

    var title: String {
        switch self {
        case .step1_clickCalendarEntry: return "点击 House 的梦裙日历热区"
        case .step2_calendarExplanation: return "认识梦裙日历"
        }
    }

    var message: String {
        switch self {
        case .step1_clickCalendarEntry: return "先从 House 里的梦裙日历热区进入，我们再认识最近、月度、年度三个视图。"
        case .step2_calendarExplanation: return "最近会按时间线看近期记录，月度适合查具体月份，年度更适合总览全年的热度分布。右上角默认勾选了「只看心愿尾款」，所以你一进来就会先看到尾款相关内容。"
        }
    }

    var showCatPaw: Bool { false }
}

enum MagicStickerGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_clickMagicStickerEntry = 1
    case step2_magicStickerExplanation = 2

    var title: String {
        switch self {
        case .step1_clickMagicStickerEntry: return "点击「魔法贴纸」"
        case .step2_magicStickerExplanation: return "认识魔法贴纸"
        }
    }

    var message: String {
        switch self {
        case .step1_clickMagicStickerEntry: return "从底部导航或 House 房间里的「魔法贴纸」入口进入默认贴纸页。"
        case .step2_magicStickerExplanation: return "这里会直接进入默认贴纸页。主体区域是贴纸编辑内容；如果把贴纸加入手帐，还能继续回到对应手帐里编辑。"
        }
    }

    var showCatPaw: Bool { false }
}

enum BatchEditGuideStep: Int, CaseIterable, GuideStepDescribable {
    case step1_clickMoreMenu = 1
    case step2_selectOneCard = 2
    case step3_toolbarExplanation = 3
    case step4_finishSelection = 4

    var title: String {
        switch self {
        case .step1_clickMoreMenu: return "点击右上角更多按钮"
        case .step2_selectOneCard: return "选中一张卡片"
        case .step3_toolbarExplanation: return "认识批量编辑工具条"
        case .step4_finishSelection: return "点完成结束批量编辑"
        }
    }

    var message: String {
        switch self {
        case .step1_clickMoreMenu: return "先点右上角「更多」，再在弹出菜单里选择「编辑」。进入编辑态后，我们继续下一步。"
        case .step2_selectOneCard: return "随便点选一张衣橱卡片，让底部批量工具条进入可用状态。"
        case .step3_toolbarExplanation: return "底部这排就是批量编辑常用操作：删除、复制、更多、全选。更多里还能继续做标签、品牌、颜色、尺码、状态等批量处理。"
        case .step4_finishSelection: return "现在不用继续操作了，直接点右上角的完成勾选，退出这次批量编辑体验。"
        }
    }

    var showCatPaw: Bool {
        switch self {
        case .step1_clickMoreMenu, .step3_toolbarExplanation: return true
        default: return false
        }
    }
}

// MARK: - 空间手帐引导步骤
// 根据流程图，分为两个阶段：
// 阶段1：未解锁时（前置任务引导 - 共5步）
// 阶段2：已解锁后（完整引导 - 共7步）
enum SpaceBookGuideStep: Int, CaseIterable, GuideStepDescribable {
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

enum WealthGuideStep: Int, CaseIterable, GuideStepDescribable {
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
            return "「请签」会给出今日心愿提醒，适合像茶会开场一样轻轻打卡。"
        case .step4_moneyCounting:
            return "「数钱」会把衣橱总值、心愿定金和小匣储蓄变成沉浸式账本。"
        case .step5_wealthStorage:
            return "「安财」可查看黄金、白银、萌宠货币和尾款心愿小匣。"
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
