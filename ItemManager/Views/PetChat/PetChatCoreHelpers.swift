import Foundation

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

func activePetPersonaProfile(petName: String) -> PetPersonaProfile {
    guard let petId = PetDataManager.shared.status.selectedPetId,
          let character = PetCharacter(rawValue: petId) else {
        return PetPersonaRegistry.profile(for: .kitten, petName: petName)
    }
    return PetPersonaRegistry.profile(for: character.aiRole, petName: petName)
}

func activePetRole() -> PetRole {
    guard let petId = PetDataManager.shared.status.selectedPetId,
          let character = PetCharacter(rawValue: petId) else {
        return .kitten
    }
    return character.aiRole
}

func wardrobeContextBudget(for intent: PetChatIntent) -> Int {
    switch intent {
    case .outfitSuggestion, .weatherGuidance:
        return 10
    case .wardrobeStats, .search, .depositPlan, .lastOutfitPrice:
        return 8
    case .currencyOverview, .petStatusOverview, .secondPetAdoption, .switchPetCompanion, .meowCoinTopUp, .moodSupport, .generalChat:
        return 6
    }
}

enum PetStatusPanelKind: CaseIterable {
    case all
    case hunger
    case hydration
    case hygiene
    case mood
    case intimacy

    var title: String {
        switch self {
        case .all: return "全部状态"
        case .hunger: return "饱食"
        case .hydration: return "饮水"
        case .hygiene: return "清洁"
        case .mood: return "心情"
        case .intimacy: return "亲密度"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "rectangle.stack.fill"
        case .hunger: return "fork.knife.circle.fill"
        case .hydration: return "drop.circle.fill"
        case .hygiene: return "sparkles"
        case .mood: return "face.smiling.fill"
        case .intimacy: return "heart.fill"
        }
    }

    var command: String {
        switch self {
        case .all: return "pet_status_all"
        case .hunger: return "pet_status_hunger"
        case .hydration: return "pet_status_hydration"
        case .hygiene: return "pet_status_hygiene"
        case .mood: return "pet_status_mood"
        case .intimacy: return "pet_status_intimacy"
        }
    }
}

enum PetCurrencyPanelKind: CaseIterable {
    case all
    case meowCoin
    case fishCoin
    case boneCoin

    var title: String {
        switch self {
        case .all: return "全部货币"
        case .meowCoin: return "喵币"
        case .fishCoin: return "鱼币"
        case .boneCoin: return "骨头币"
        }
    }

    var command: String {
        switch self {
        case .all: return "pet_currency_all"
        case .meowCoin: return "pet_currency_meow"
        case .fishCoin: return "pet_currency_fish"
        case .boneCoin: return "pet_currency_bone"
        }
    }

    var currencies: [PetCurrency] {
        switch self {
        case .all: return [.meowCoin, .fishCoin, .boneCoin]
        case .meowCoin: return [.meowCoin]
        case .fishCoin: return [.fishCoin]
        case .boneCoin: return [.boneCoin]
        }
    }
}

enum PetEmbeddedPanelIntent {
    case currency(PetCurrencyPanelKind)
    case inventory
    case shop
    case moneyCounter(CurrencyType)
    case divination
    case status(PetStatusPanelKind)
}

enum PetCurrencyExchangeDirection: String, CaseIterable, Identifiable {
    case fishToBone
    case boneToFish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fishToBone: return "鱼币 → 骨头币"
        case .boneToFish: return "骨头币 → 鱼币"
        }
    }

    var sourceCurrency: PetCurrency {
        switch self {
        case .fishToBone: return .fishCoin
        case .boneToFish: return .boneCoin
        }
    }

    var targetCurrency: PetCurrency {
        switch self {
        case .fishToBone: return .boneCoin
        case .boneToFish: return .fishCoin
        }
    }
}

private func normalizedPetChatIntentText(_ text: String) -> String {
    text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
}

private func containsAnyKeyword(_ text: String, keywords: [String]) -> Bool {
    keywords.contains { text.contains($0) }
}

private func isCurrencyInquiry(_ text: String) -> Bool {
    containsAnyKeyword(text, keywords: [
        "查看", "看看", "看", "显示", "余额", "财务", "货币", "钱包", "资产", "多少", "剩多少", "还有多少", "存款", "查查"
    ])
}

private func isAddressingPet(in text: String, petName: String) -> Bool {
    let normalized = normalizedPetChatIntentText(text)
    let markers = [petName.lowercased(), "萌宠", "宠物", "宝宝", "崽崽", "小家伙", "管家"]
    return markers.contains { !$0.isEmpty && normalized.contains($0) }
}

private func detectMoneyCounterCurrency(from normalizedText: String) -> CurrencyType {
    if containsAnyKeyword(normalizedText, keywords: ["美钞", "美元", "美刀", "美金", "usd", "$"]) {
        return .usd
    }
    if containsAnyKeyword(normalizedText, keywords: ["日元", "日钞", "jpy", "yen", "円"]) {
        return .jpy
    }
    return .rmb
}

func detectEmbeddedPanelIntent(from text: String, petName: String) -> PetEmbeddedPanelIntent? {
    let normalized = normalizedPetChatIntentText(text)
    guard !normalized.isEmpty else { return nil }

    if let fuzzyStatusKind = detectFuzzyStatusPanelKind(from: normalized, petName: petName) {
        return .status(fuzzyStatusKind)
    }

    if containsAnyKeyword(normalized, keywords: ["所有的财务情况", "所有财务情况", "所有的货币", "所有货币", "全部货币", "全部财务", "货币总览", "财务总览"])
        || (isCurrencyInquiry(normalized) && containsAnyKeyword(normalized, keywords: ["全部", "所有"]) && containsAnyKeyword(normalized, keywords: ["货币", "财务", "余额", "钱包"])) {
        return .currency(.all)
    }

    if isCurrencyInquiry(normalized) && containsAnyKeyword(normalized, keywords: ["喵币"]) {
        return .currency(.meowCoin)
    }

    if isCurrencyInquiry(normalized) && normalized.contains("鱼币") {
        return .currency(.fishCoin)
    }

    if isCurrencyInquiry(normalized) && normalized.contains("骨头币") {
        return .currency(.boneCoin)
    }

    let asksSpecificCurrencyCounting = normalized.contains("数")
        && containsAnyKeyword(normalized, keywords: ["人民币", "日元", "美元", "美钞", "美刀", "美金", "rmb", "cny", "jpy", "usd"])
    let isMoneyCounterIntent = containsAnyKeyword(normalized, keywords: ["数钱", "数钞", "数钞票", "点钱", "裙装总价值", "总价值"])
        || (normalized.contains("数") && normalized.contains("钞"))
        || asksSpecificCurrencyCounting
    if isMoneyCounterIntent {
        return .moneyCounter(detectMoneyCounterCurrency(from: normalized))
    }

    if containsAnyKeyword(normalized, keywords: ["求签", "请签", "抽签", "签文", "今日运势", "今日一签"]) {
        return .divination
    }

    if containsAnyKeyword(normalized, keywords: ["背包", "道具", "库存", "猫粮还有", "罐头还有", "仓库"]) {
        return .inventory
    }

    if containsAnyKeyword(normalized, keywords: ["商店", "小卖部", "买点", "补货", "购买道具", "卖点"]) {
        return .shop
    }

    let petAddressed = isAddressingPet(in: normalized, petName: petName)
    let explicitAllStatus = containsAnyKeyword(normalized, keywords: ["全部状态", "萌宠现状", "宠物现状", "状态总览", "状态面板"])
        || (containsAnyKeyword(normalized, keywords: ["展示", "显示"]) && normalized.contains("状态") && normalized.contains("全部"))

    if explicitAllStatus {
        return .status(.all)
    }

    guard petAddressed else { return nil }

    if containsAnyKeyword(normalized, keywords: ["饿了", "饥饿", "饱食", "吃饱", "肚子饿"]) {
        return .status(.hunger)
    }
    if containsAnyKeyword(normalized, keywords: ["渴了", "口渴", "饮水", "想喝水", "没水了"]) {
        return .status(.hydration)
    }
    if containsAnyKeyword(normalized, keywords: ["脏了", "清洁", "洗澡", "脏兮兮", "该洗洗"]) {
        return .status(.hygiene)
    }
    if containsAnyKeyword(normalized, keywords: ["心情", "不开心", "开心吗", "emo", "郁闷", "高兴"]) {
        return .status(.mood)
    }
    if containsAnyKeyword(normalized, keywords: ["亲密度", "关系值", "喜欢我吗", "亲近", "桃心"]) {
        return .status(.intimacy)
    }

    return nil
}

func displayName(for pet: PetCharacter, in status: PetStatus) -> String {
    let customName = (status.petNames[pet.id] ?? "")
        .replacingOccurrences(of: "\"", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return customName.isEmpty ? pet.displayName : customName
}

private func currencyAmount(for type: PetCurrency, status: PetStatus) -> Int {
    switch type {
    case .meowCoin: return status.meowCoin
    case .fishCoin: return status.fishCoin
    case .boneCoin: return status.boneCoin
    }
}

private func currencySubtitle(for status: PetStatus, kind: PetCurrencyPanelKind) -> String {
    switch kind {
    case .all:
        return "这里是\(status.displayName)当前全部货币，包括喵币、鱼币、骨头币。"
    case .meowCoin:
        return "这里先看喵币，方便你看领养二宝和充值相关余额。"
    case .fishCoin:
        return "这里先看鱼币，方便看日常道具和工作收益。"
    case .boneCoin:
        return "这里先看骨头币，这是毛毛偏爱的币种。"
    }
}

private func currencyMetrics(for status: PetStatus, kind: PetCurrencyPanelKind) -> [PetWidgetMetric] {
    kind.currencies.map { currency in
        PetWidgetMetric(name: currency.rawValue, value: "\(currencyAmount(for: currency, status: status))")
    }
}

func makeCurrencyPanelWidget(status: PetStatus, kind: PetCurrencyPanelKind, feedback: String? = nil) -> PetWidgetData {
    PetWidgetData(
        type: .currencyPanel,
        title: kind == .all ? "当前货币余额" : "当前\(kind.title)",
        subtitle: feedback ?? currencySubtitle(for: status, kind: kind),
        metrics: currencyMetrics(for: status, kind: kind)
    )
}

private func inventoryOptions(status: PetStatus, limit: Int? = nil) -> [PetWidgetOption] {
    let allItems = status.inventory
        .filter { $0.value > 0 }
        .compactMap { entry -> PetWidgetOption? in
            guard let item = PetConfigManager.shared.getItem(byId: entry.key) else { return nil }
            return PetWidgetOption(
                title: "\(item.name) x\(entry.value)",
                command: "use_item:\(item.id)",
                icon: item.icon
            )
        }
        .sorted { $0.title < $1.title }
    
    if let limit {
        return Array(allItems.prefix(limit))
    }
    return allItems
}

func makeInventoryPanelWidget(status: PetStatus, feedback: String? = nil) -> PetWidgetData {
    let options = inventoryOptions(status: status)
    return PetWidgetData(
        type: .inventoryPanel,
        title: "\(status.displayName)的背包",
        subtitle: feedback ?? (options.isEmpty ? "现在没有库存道具。" : "点一下就能使用，也可以拖到投喂区。"),
        options: options
    )
}

private func shopOptions(limit: Int? = nil) -> [PetWidgetOption] {
    let sortedItems = PetConfigManager.shared.items
        .sorted { $0.sortIndex < $1.sortIndex }
    
    let visibleItems: [PetItemDefinition]
    if let limit {
        visibleItems = Array(sortedItems.prefix(limit))
    } else {
        visibleItems = sortedItems
    }
    
    return visibleItems.map { item in
        let currencyName = item.petCurrency.rawValue
        return PetWidgetOption(
            title: "\(item.name) · \(item.price)\(currencyName)",
            command: "buy_item:\(item.id)",
            icon: item.icon
        )
    }
}

func makeShopPanelWidget(status: PetStatus, feedback: String? = nil) -> PetWidgetData {
    return PetWidgetData(
        type: .shopPanel,
        title: "萌宠道具商店",
        options: shopOptions()
    )
}

private func moneyCounterDisplayAmount(from amountCNY: Int, currency: CurrencyType) -> Int {
    let safeAmount = max(1, amountCNY)
    switch currency {
    case .rmb:
        return safeAmount
    case .jpy:
        return max(1, Int((Double(safeAmount) * 21.0).rounded()))
    case .usd:
        return max(1, Int((Double(safeAmount) * 0.14).rounded()))
    case .gold, .silver:
        return safeAmount
    }
}

private func moneyCounterSymbol(for currency: CurrencyType) -> String {
    switch currency {
    case .rmb: return "¥"
    case .jpy: return "¥"
    case .usd: return "$"
    case .gold: return "Gold "
    case .silver: return "Silver "
    }
}

func makeMoneyCounterWidget(totalValue: Decimal, currency: CurrencyType = .rmb) -> PetWidgetData {
    let totalCNY = NSDecimalNumber(decimal: totalValue).intValue
    let displayAmount = moneyCounterDisplayAmount(from: totalCNY, currency: currency)
    let symbol = moneyCounterSymbol(for: currency)

    return PetWidgetData(
        type: .moneyCounter,
        title: "裙装总价值数钱台（\(currency.rawValue)）",
        subtitle: "来，和我一起数数今天的小金库～",
        options: [
            PetWidgetOption(title: "看看全部状态", command: "pet_status_all", icon: "heart.text.square.fill"),
            PetWidgetOption(title: "打开萌宠背包", command: "pet_inventory_panel", icon: "shippingbox.fill")
        ],
        metrics: [
            PetWidgetMetric(name: PetMoneyCounterMetricKey.currency, value: currency.rawValue),
            PetWidgetMetric(name: PetMoneyCounterMetricKey.amount, value: "\(displayAmount)"),
            PetWidgetMetric(name: "裙装总价值", value: "\(symbol)\(displayAmount)")
        ]
    )
}

func makeDivinationWidget() -> PetWidgetData {
    PetWidgetData(
        type: .divinationPanel,
        title: "今日求签",
        subtitle: "请签求好运，福气就在这条对话里～",
        options: [
            PetWidgetOption(title: "请签求好运", command: "pet_divination_panel", icon: "wand.and.stars"),
            PetWidgetOption(title: "去数数小金库", command: "pet_money_counter", icon: "yensign.circle.fill")
        ]
    )
}

struct PetFeedVideoAssetDescriptor: Equatable {
    let resourceName: String
    let fileExtension: String
    let supportsAlphaChannel: Bool
}

struct PetFeedAnimationPayload: Equatable {
    let itemId: String
    let itemName: String
    let emoji: String
    let videoAsset: PetFeedVideoAssetDescriptor?
}

struct PetItemCommandResult {
    let feedback: String
    let feedAnimation: PetFeedAnimationPayload?
}

struct PetDirectFeedIntent {
    let preferredItemId: String?
}

private func isFeedableItem(_ item: PetItemDefinition) -> Bool {
    item.category == "food" || item.category == "water"
}

private func emojiForFeedItem(_ item: PetItemDefinition) -> String {
    if item.isDrink {
        if item.id == "goatMilk" { return "🥛" }
        return "💧"
    }
    if item.name.contains("鱼") || item.id == "freezeDried" {
        return "🐟"
    }
    if item.name.contains("肉") {
        return "🍖"
    }
    if item.id == "cannedFood" {
        return "🥫"
    }
    return "🍽️"
}

private func feedVideoAssetDescriptor(for item: PetItemDefinition) -> PetFeedVideoAssetDescriptor? {
    let descriptor = PetFeedVideoAssetDescriptor(
        resourceName: "pet_feed_\(item.id)_alpha",
        fileExtension: "mov",
        supportsAlphaChannel: true
    )
    let exists = Bundle.main.url(forResource: descriptor.resourceName, withExtension: descriptor.fileExtension) != nil
    return exists ? descriptor : nil
}

private func feedAnimationPayload(for item: PetItemDefinition) -> PetFeedAnimationPayload {
    PetFeedAnimationPayload(
        itemId: item.id,
        itemName: item.name,
        emoji: emojiForFeedItem(item),
        videoAsset: feedVideoAssetDescriptor(for: item)
    )
}

func detectDirectFeedIntent(from text: String) -> PetDirectFeedIntent? {
    let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }

    let feedMarkers = ["喂", "投喂", "给你吃", "给它吃", "给你喝", "给它喝", "你吃", "它吃", "你喝", "它喝"]
    let foodMarkers = [
        "小鱼干", "鱼干", "罐头", "猫条", "冻干", "猫饭", "猫粮", "鸡胸肉", "生骨肉",
        "水", "白开水", "温水", "山羊奶", "肉泥"
    ]

    let hasFeedMarker = feedMarkers.contains { normalized.contains($0) }
    let hasFoodMarker = foodMarkers.contains { normalized.contains($0) }
    guard hasFeedMarker && hasFoodMarker else { return nil }

    let keywordMappings: [([String], [String])] = [
        (["小鱼干", "鱼干"], ["freezeDried", "catStrip", "cannedFood"]),
        (["罐头"], ["cannedFood"]),
        (["猫条"], ["catStrip"]),
        (["冻干"], ["freezeDried"]),
        (["猫饭"], ["catRice"]),
        (["猫粮"], ["catFood"]),
        (["鸡胸肉"], ["chickenBreast"]),
        (["生骨肉", "肉泥"], ["rawMeat"]),
        (["山羊奶"], ["goatMilk"]),
        (["白开水"], ["boiledWater"]),
        (["温水"], ["warmWater"])
    ]

    for mapping in keywordMappings {
        if mapping.0.contains(where: { normalized.contains($0) }) {
            let matchedId = mapping.1.first(where: { PetConfigManager.shared.getItem(byId: $0) != nil })
            return PetDirectFeedIntent(preferredItemId: matchedId)
        }
    }

    if let namedItem = PetConfigManager.shared.items.first(where: { normalized.contains($0.name.lowercased()) }) {
        return PetDirectFeedIntent(preferredItemId: namedItem.id)
    }

    return PetDirectFeedIntent(preferredItemId: nil)
}

func resolveDirectFeedItem(intent: PetDirectFeedIntent, status: PetStatus) -> PetItemDefinition? {
    let feedableItems = PetConfigManager.shared.items.filter(isFeedableItem)
    guard !feedableItems.isEmpty else { return nil }

    if let preferredId = intent.preferredItemId,
       let preferred = PetConfigManager.shared.getItem(byId: preferredId),
       isFeedableItem(preferred) {
        if status.inventory[preferred.id, default: 0] > 0 {
            return preferred
        }
        return preferred
    }

    if let inventoryItem = feedableItems.first(where: { status.inventory[$0.id, default: 0] > 0 }) {
        return inventoryItem
    }
    return feedableItems.first
}

func purchasePetItemResult(itemId: String, autoFeedWhenPossible: Bool = true) -> PetItemCommandResult {
    guard let item = PetConfigManager.shared.getItem(byId: itemId) else {
        return PetItemCommandResult(feedback: "这个商品我暂时没找到，稍后再试试吧。", feedAnimation: nil)
    }

    var status = PetDataManager.shared.status
    switch item.petCurrency {
    case .fishCoin:
        guard status.fishCoin >= item.price else {
            return PetItemCommandResult(feedback: "鱼币不够，先攒一点再来买\(item.name)吧。", feedAnimation: nil)
        }
        status.fishCoin -= item.price
    case .meowCoin:
        guard status.meowCoin >= item.price else {
            return PetItemCommandResult(feedback: "喵币不够，先充一点再来买\(item.name)吧。", feedAnimation: nil)
        }
        status.meowCoin -= item.price
    case .boneCoin:
        guard status.boneCoin >= item.price else {
            return PetItemCommandResult(feedback: "骨头币不够，这个是给毛毛用的币种喔。", feedAnimation: nil)
        }
        status.boneCoin -= item.price
    }

    status.inventory[item.id, default: 0] += 1
    PetDataManager.shared.saveStatus(status)

    if autoFeedWhenPossible && isFeedableItem(item) {
        let consumeResult = consumePetItemResult(itemId: item.id)
        return PetItemCommandResult(
            feedback: "买好就喂啦～\(consumeResult.feedback)",
            feedAnimation: consumeResult.feedAnimation
        )
    }

    var refreshed = PetDataManager.shared.status
    refreshed.intimacy = min(100, refreshed.intimacy + 1)
    PetDataManager.shared.saveStatus(refreshed)
    return PetItemCommandResult(feedback: "买好啦，\(item.name)已经放进\(refreshed.displayName)的背包里。", feedAnimation: nil)
}

func consumePetItemResult(itemId: String) -> PetItemCommandResult {
    guard let item = PetConfigManager.shared.getItem(byId: itemId) else {
        return PetItemCommandResult(feedback: "这个道具我暂时没识别出来。", feedAnimation: nil)
    }

    var status = PetDataManager.shared.status
    guard let count = status.inventory[item.id], count > 0 else {
        return PetItemCommandResult(feedback: "\(item.name)已经用完了，要不要我帮你去商店补货？", feedAnimation: nil)
    }

    if item.id == "renameCard" {
        return PetItemCommandResult(feedback: "改名项圈先留着吧，这个需要走专门的改名流程。", feedAnimation: nil)
    }

    status.inventory[item.id] = count - 1

    if item.id == "energyPill" {
        let oldEnergy = status.energy
        status.energy = min(100, status.energy + item.recoveryValue)
        status.mood = min(100, status.mood + 5)
        status.intimacy = min(100, status.intimacy + 1)
        PetDataManager.shared.saveStatus(status)
        let recovered = Int(status.energy - oldEnergy)
        let feedback = recovered > 0 ? "\(status.displayName)精神回来啦，精力恢复了 \(recovered) 点。" : "\(status.displayName)现在精力已经满满的啦。"
        return PetItemCommandResult(feedback: feedback, feedAnimation: nil)
    }

    if item.isToy {
        let energyCost = Double(item.energyCost ?? 0)
        guard status.energy >= energyCost else {
            status.inventory[item.id] = count
            return PetItemCommandResult(feedback: "\(status.displayName)现在太累了，不想玩\(item.name)。", feedAnimation: nil)
        }
        status.energy = max(0, status.energy - energyCost)
        status.mood = min(100, status.mood + item.recoveryValue)
        status.intimacy = min(100, status.intimacy + 2)
        PetDataManager.shared.saveStatus(status)
        return PetItemCommandResult(feedback: "\(status.displayName)玩得很开心，心情明显变好了。", feedAnimation: nil)
    }

    let moodRecovery = item.recoveryValue * 0.2
    status.mood = min(100, status.mood + moodRecovery)
    if item.isDrink {
        status.energy = min(100, status.energy + item.recoveryValue)
    } else {
        status.hunger = min(100, status.hunger + item.recoveryValue)
    }
    status.intimacy = min(100, status.intimacy + 1.5)
    PetDataManager.shared.saveStatus(status)

    let animation = isFeedableItem(item) ? feedAnimationPayload(for: item) : nil
    if item.isDrink {
        return PetItemCommandResult(feedback: "\(status.displayName)喝下\(item.name)啦，饮水状态回升了一些。", feedAnimation: animation)
    }
    return PetItemCommandResult(feedback: "\(status.displayName)吃掉了\(item.name)，饱食度恢复了一些。", feedAnimation: animation)
}

func cleanPetStatusNow() -> String {
    var status = PetDataManager.shared.status
    let oldValue = status.hygiene
    guard oldValue < 100 else {
        return "\(status.displayName)已经香香的啦，不用再洗啦。"
    }
    status.hygiene = 100
    status.mood = min(100, status.mood + 10)
    status.intimacy = min(100, status.intimacy + 1)
    PetDataManager.shared.saveStatus(status)
    return "\(status.displayName)已经洗香香啦，清洁度补满了。"
}
