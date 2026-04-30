import SwiftUI
import Observation

enum FinalPaymentVaultMascot: String, CaseIterable, Identifiable {
    case miniVault = "miniVault"
    case fortuneCat = "fortuneCat"
    case piggyBank = "piggyBank"
    case goldPig = "goldPig"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .miniVault: return "心愿小匣"
        case .fortuneCat: return "招财猫"
        case .piggyBank: return "存钱猪猪"
        case .goldPig: return "金币小猪"
        }
    }

    var subtitle: String {
        switch self {
        case .miniVault: return "把每一笔心愿温柔收好"
        case .fortuneCat: return "招财猫陪伴，备款更安心"
        case .piggyBank: return "珍珠点点，慢慢存起"
        case .goldPig: return "金币闪闪，账本更甜"
        }
    }

    var symbolName: String {
        switch self {
        case .miniVault: return "lock.shield.fill"
        case .fortuneCat: return "cat.fill"
        case .piggyBank: return "banknote.fill"
        case .goldPig: return "yensign.circle.fill"
        }
    }

    var assetName: String {
        switch self {
        case .miniVault: return "wealth_mini_vault"
        case .fortuneCat: return "wealth_fortune_cat"
        case .piggyBank: return "wealth_piggy_bank"
        case .goldPig: return "wealth_gold_pig"
        }
    }
}

enum WealthExperienceCopy {
    static let pageTitle = "马上来财"
    static let pageSubtitle = "蔷薇茶会里，把心愿账本慢慢点亮"

    enum Fortune {
        static let startAction = "请一枚心愿签"
        static let replayAction = "再请一枚"
        static let petPanelTitle = "今日心愿签"
        static let petPanelSubtitle = "请一枚茶会签，听听今天的温柔提醒～"
        static let petPanelPrimaryAction = "请心愿签"
        static let petIntroMessage = "茶会签筒抱来啦，我们听听今天的小提醒～"

        static let cards: [(isPrime: Bool, text: String, description: String, detail: String)] = [
            (true, "上上签", "蔷薇开席，心愿有光", "今日适合整理账本、确认预算，把想要的心愿一步步排好。"),
            (true, "上上签", "珍珠入匣，灵感轻落", "小小记录会带来安心感，适合为喜欢的裙装留出一笔温柔预算。"),
            (true, "上上签", "缎带系好，步调顺顺", "今天适合把零散计划收拢成清单，慢慢推进也会很漂亮。"),
            (false, "上签", "茶香正暖，账页清清", "保持稳稳的节奏，先完成一件小事，心愿账本会更有方向。"),
            (false, "上签", "玫瑰轻响，慢慢靠近", "适合复盘近期开销与待付尾款，给自己留一点从容余量。"),
            (false, "上签", "蕾丝微光，心情柔软", "不用着急，把今日的期待写下来，下一步会更清楚。")
        ]
    }

    enum Counting {
        static let sourceLine = "衣橱总值 + 心愿尾款定金 + 小匣储蓄"
        static let emptyTitle = "暂时还没有衣橱总值"
        static let emptyDescription = "去衣橱记录第一件心愿单品，来财茶会就能开始点亮账本。"
        static let finishedInline = "缎带账页已点亮"
        static let petTitlePrefix = "我的裙装账本"
        static let petSubtitle = "来陪我把今日心愿账本轻轻点亮～"
        static let petIntroMessage = "来，我们就在这儿翻开今日心愿账本～"
        static let navigationQuestion = "要跳转到「来财」数钱页吗？"
        static let navigationAction = "现在去点亮账本"
        static let navigationMessage = "这个场景需要跳转，我先征求你确认～"
        static let navigationConfirm = "走吧，我们去「来财」把账本点亮一下～"
    }

    enum Storage {
        static let goldPrice = "黄金参考价"
        static let silverPrice = "白银参考价"
        static let calculatingGold = "正在换算黄金重量..."
        static let calculatingSilver = "正在换算白银重量..."
        static let virtualTitle = "萌宠茶会货币"
        static let rechargeAction = "去补充"
        static let exchangeAction = "去兑换"
    }

    enum Vault {
        static let heroSuffix = "心愿小匣"
        static let heroDescription = "为裙装一笔笔系上缎带，或先放进未指定小匣；都会计入马上来财统计。"
        static let savedTitle = "已收好"
        static let linkedTitle = "指定裙装"
        static let unassignedTitle = "未指定"
        static let manageUnassigned = "管理未指定小匣"
        static let quickSaveTitle = "存一笔到心愿小匣"
        static let quickSaveDescription = "不指定裙装也可以先存，之后来财统计会一起计算。"
        static let quickSaveAction = "未指定存钱"
        static let emptyTitle = "还没有小匣存款"
        static let emptyDescription = "可以先不指定裙装存一笔，也可以去心愿尾款列表为目标裙装存钱。"
        static let listTitle = "裙装备款进度"
        static let depositProgressLabel = "定金 + 小匣存款 / 当前总价"
        static let normalProgressLabel = "小匣存款 / 当前总价"
        static let unassignedSheetTitle = "未指定小匣"
        static let unassignedSheetDescriptionPrefix = "当前未指定 "
        static let unassignedSheetDescriptionSuffix = "，可填充到心愿尾款裙装，且只会存到上限。"
        static let unassignedEmptyTitle = "还没有可填充的心愿尾款裙装"
        static let unassignedEmptyDescription = "未指定存款会继续留在小匣里，不会自动绑定。"
        static let sheetUnassignedTitle = "不指定裙装存钱"
        static let sheetTargetTitle = "为裙装存一笔"
        static let sheetUnassignedDescription = "先存进自由小匣，暂不绑定具体裙装。"
        static let amountTitle = "存入金额"
        static let currentSaved = "当前已存"
        static let capTitle = "指定存款上限"
        static let remainingTitle = "还能存入"
        static let fullHint = "这条裙装已达上限，后续可在安财里把超额转回未指定。"
        static let clampHintPrefix = "超过上限的部分不会存入，本次将存入 "
        static let clampHintSuffix = "。"
        static let capHint = "若输入超过剩余额度，会自动只存到上限。"
        static let unassignedNoCapHint = "未指定小匣不设单条上限，之后可在安财里填充到心愿尾款裙装。"
        static let sheetNavigationTitle = "存一笔到心愿小匣"
        static let celebrationPrefix = "已收好 "
        static let accessibilitySuffix = "尾款心愿小匣"
    }

    enum Settings {
        static let pageTitle = "马上来财设置"
        static let paperStyleTitle = "纸币与背景样式"
        static let paperStyleDescription = "自定义不同面额纸币的显示图片"
        static let mascotLockedMessage = "尾款心愿小匣形象是 VIP 专属个性化能力。开通 VIP 后可切换心愿小匣、招财猫、存钱猪猪、金币小猪。"
        static let mascotTitle = "尾款心愿小匣形象"
        static let mascotFooter = "选择后会应用到马上来财「安财 → 尾款」里的主形象。"
    }

    enum VIP {
        static let benefitSubtitle = "心愿小匣形象 · 纸币背景"
        static let ownedMessage = "你已拥有来财个性化权益。可在「我 → 马上来财设置」中切换尾款心愿小匣形象，并继续自定义纸币与背景样式。"
        static let lockedMessage = "开通 VIP 后即可解锁尾款心愿小匣形象切换，支持心愿小匣、招财猫、存钱猪猪、金币小猪，并享受更多来财个性化装扮能力。"
    }

    enum PetChat {
        static let currencyAllMessage = "我的随身钱袋都在这儿啦～"
        static func currencySingleMessage(_ title: String) -> String { "这是我的\(title)，给你看看呀～" }
        static let currencyAllSubtitle = "这是我现在的随身钱袋，喵币、鱼币和骨头币都在这儿。"
        static let quickMoneyLabel = "去来财点账本"
        static let quickFortuneLabel = "今日心愿签"
    }
}

enum WealthExperienceStyle {
    static let rose = Color(hex: "C94C72")
    static let blush = Color(hex: "F7DDE8")
    static let cream = Color(hex: "FFF7EA")
    static let pearl = Color(hex: "FFFDF8")
    static let tea = Color(hex: "B77A8D")
    static let gold = Color(hex: "D9A441")

    static var roseGoldGradient: LinearGradient {
        LinearGradient(
            colors: [rose, Color(hex: "E9A4B8"), gold],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var softPanelGradient: LinearGradient {
        LinearGradient(
            colors: [cream.opacity(0.76), blush.opacity(0.46), pearl.opacity(0.68)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension CurrencyType {
    var displayTitle: String {
        switch self {
        case .rmb: return "人民币"
        case .jpy: return "日元"
        case .usd: return "美元"
        case .gold: return "黄金"
        case .silver: return "白银"
        }
    }
}

@Observable
class WealthAppearanceManager {
    static let shared = WealthAppearanceManager()
    
    // MARK: - Properties
    // Dictionary to store images per currency and denomination
    // Key format: "CurrencyType_DenominationValue"
    // e.g. "rmb_100", "jpy_10000"
    var customImages: [String: UIImage] = [:]
    
    // Dictionary to store dominant colors per currency and denomination
    var customColors: [String: Color] = [:]
    
    // Custom container background image
    var containerBackgroundImage: UIImage?
    
    // MARK: - Settings
    static let finalPaymentVaultMascotKey = "wealth.finalPaymentVaultMascot"

    var shouldShowWealthContainerBackground: Bool {
        didSet {
            UserDefaults.standard.set(shouldShowWealthContainerBackground, forKey: "shouldShowWealthContainerBackground")
        }
    }

    var finalPaymentVaultMascot: FinalPaymentVaultMascot {
        didSet {
            UserDefaults.standard.set(finalPaymentVaultMascot.rawValue, forKey: Self.finalPaymentVaultMascotKey)
        }
    }
    
    // MARK: - Initialization
    init() {
        self.shouldShowWealthContainerBackground = UserDefaults.standard.object(forKey: "shouldShowWealthContainerBackground") as? Bool ?? false
        let mascotRawValue = UserDefaults.standard.string(forKey: Self.finalPaymentVaultMascotKey)
        self.finalPaymentVaultMascot = mascotRawValue.flatMap(FinalPaymentVaultMascot.init(rawValue:)) ?? .fortuneCat
        loadImages()
    }
    
    // MARK: - Helper
    private func imageKey(currency: CurrencyType, denominationValue: Int) -> String {
        return "\(currency.rawValue)_\(denominationValue)"
    }
    
    private func imageURL(currency: CurrencyType, denominationValue: Int) -> URL? {
        let filename = "wealth_\(currency.rawValue)_\(denominationValue).png"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(filename)
    }
    
    private var containerBackgroundImageURL: URL? {
        let filename = "wealth_container_background.png"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(filename)
    }
    
    // MARK: - Methods
    
    func setContainerBackgroundImage(_ image: UIImage) {
        if let data = image.pngData(), let url = containerBackgroundImageURL {
            try? data.write(to: url)
        }
        self.containerBackgroundImage = image
    }
    
    func removeContainerBackgroundImage() {
        if let url = containerBackgroundImageURL {
            try? FileManager.default.removeItem(at: url)
        }
        self.containerBackgroundImage = nil
    }
    
    func setCustomImage(currency: CurrencyType, denominationValue: Int, image: UIImage) {
        // Save to disk
        if let data = image.pngData(), let url = imageURL(currency: currency, denominationValue: denominationValue) {
            try? data.write(to: url)
        }
        
        // Update memory
        let key = imageKey(currency: currency, denominationValue: denominationValue)
        customImages[key] = image
        
        // Extract and cache color
        if let color = image.averageColor {
            customColors[key] = Color(uiColor: color)
        }
    }
    
    func removeCustomImage(currency: CurrencyType, denominationValue: Int) {
        // Remove from disk
        if let url = imageURL(currency: currency, denominationValue: denominationValue) {
            try? FileManager.default.removeItem(at: url)
        }
        
        // Update memory
        let key = imageKey(currency: currency, denominationValue: denominationValue)
        customImages.removeValue(forKey: key)
        customColors.removeValue(forKey: key)
    }
    
    func getCustomImage(currency: CurrencyType, denominationValue: Int) -> UIImage? {
        let key = imageKey(currency: currency, denominationValue: denominationValue)
        return customImages[key]
    }
    
    func getCustomColor(currency: CurrencyType, denominationValue: Int) -> Color? {
        let key = imageKey(currency: currency, denominationValue: denominationValue)
        return customColors[key]
    }
    
    private func loadImages() {
        // Pre-load common denominations to avoid IO on main thread during scroll?
        // Or just load on demand?
        // For now, let's load all known possible denominations if we can, or just iterate file system?
        // Iterating file system might be safer to catch all.

        // Known denominations
        let rmbDenominations = [100, 50, 20, 10, 5, 1]
        let jpyDenominations = [10000, 5000, 1000] // Common JPY notes
        let usdDenominations = [100, 50, 20, 10, 5, 2, 1] // USD notes (包括2美元)

        for val in rmbDenominations {
            loadSingleImage(currency: .rmb, val: val)
        }

        for val in jpyDenominations {
            loadSingleImage(currency: .jpy, val: val)
        }

        for val in usdDenominations {
            loadSingleImage(currency: .usd, val: val)
        }

        // Load container background
        if let url = containerBackgroundImageURL,
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            self.containerBackgroundImage = image
        }
    }
    
    private func loadSingleImage(currency: CurrencyType, val: Int) {
        if let url = imageURL(currency: currency, denominationValue: val),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            let key = imageKey(currency: currency, denominationValue: val)
            customImages[key] = image
            
            // Extract color on load
            if let color = image.averageColor {
                customColors[key] = Color(uiColor: color)
            }
        }
    }
}
