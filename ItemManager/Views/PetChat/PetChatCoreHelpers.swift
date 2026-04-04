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

private func hasShoppingIntent(_ text: String) -> Bool {
    if containsAnyKeyword(text, keywords: [
        "商店", "商城", "商品", "小卖部", "补货", "补给", "买点", "买东西", "购物", "货架", "上货", "囤货"
    ]) {
        return true
    }

    guard text.contains("商") else { return false }
    return containsAnyKeyword(text, keywords: ["店", "城", "品", "货", "买", "购", "补", "逛"])
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

private func isPriceQueryForOutfitFollowUp(_ text: String) -> Bool {
    containsAnyKeyword(text, keywords: [
        "价格", "总价", "合计", "一共", "多少钱", "多少元", "预算"
    ])
}

private func hasExplicitCurrencyPanelIntent(_ text: String) -> Bool {
    if containsAnyKeyword(text, keywords: ["喵币", "鱼币", "骨头币", "货币", "余额", "钱包", "财务", "充值"]) {
        return true
    }
    return containsAnyKeyword(text, keywords: ["数钱", "数钞", "数钞票", "点钱", "美元", "日元", "人民币", "usd", "jpy", "cny"])
}

private func hasOutfitReferenceInQuery(_ text: String) -> Bool {
    containsAnyKeyword(text, keywords: [
        "推荐", "清单", "列表", "单品", "搭配", "这套", "那套", "这几件", "刚刚", "上一套", "衣服"
    ])
}

func recentPetConversationMessages(_ messages: [PetChatMessage], dialogueTurns: Int = 2) -> [PetChatMessage] {
    guard dialogueTurns > 0, !messages.isEmpty else { return [] }

    var userTurns = 0
    var collected: [PetChatMessage] = []
    for message in messages.reversed() {
        collected.append(message)
        if message.isUser {
            userTurns += 1
            if userTurns >= dialogueTurns {
                break
            }
        }
    }
    return collected.reversed()
}

func latestRecentOutfitSuggestion(in messages: [PetChatMessage], dialogueTurns: Int = 2) -> OutfitSuggestionData? {
    let window = recentPetConversationMessages(messages, dialogueTurns: dialogueTurns)
    return window.reversed().compactMap(\.outfitSuggestion).first
}

func buildOutfitPriceSummary(clothings: [Clothing], detailLimit: Int = 6) -> String? {
    guard !clothings.isEmpty else { return nil }

    let details = clothings.prefix(detailLimit).map { item in
        let unitPrice = NSDecimalNumber(decimal: item.unitTotalPrice).stringValue
        return "\(item.name)(¥\(unitPrice))"
    }.joined(separator: "、")

    let suffix = clothings.count > detailLimit ? "等\(clothings.count)件" : ""
    let total = clothings.reduce(Decimal(0)) { $0 + $1.unitTotalPrice }
    let totalText = NSDecimalNumber(decimal: total).stringValue
    return "最近搭配：\(details)\(suffix)；合计¥\(totalText)"
}

func shouldTreatAsOutfitPriceFollowUp(
    query: String,
    recentMessages: [PetChatMessage],
    dialogueTurns: Int = 2
) -> Bool {
    let normalized = normalizedPetChatIntentText(query)
    guard !normalized.isEmpty else { return false }
    guard isPriceQueryForOutfitFollowUp(normalized) else { return false }
    guard !hasExplicitCurrencyPanelIntent(normalized) else { return false }

    if hasOutfitReferenceInQuery(normalized) {
        return true
    }

    let recentWindow = recentPetConversationMessages(recentMessages, dialogueTurns: dialogueTurns)
    if recentWindow.contains(where: { !$0.isUser && $0.outfitSuggestion != nil }) {
        return true
    }

    return recentWindow.contains { message in
        let text = normalizedPetChatIntentText(message.text)
        return containsAnyKeyword(text, keywords: ["搭配", "推荐", "单品", "清单", "列表"])
    }
}

func detectEmbeddedPanelIntent(
    from text: String,
    petName: String,
    recentMessages: [PetChatMessage] = []
) -> PetEmbeddedPanelIntent? {
    let normalized = normalizedPetChatIntentText(text)
    guard !normalized.isEmpty else { return nil }

    if shouldTreatAsOutfitPriceFollowUp(
        query: normalized,
        recentMessages: recentMessages,
        dialogueTurns: 2
    ) {
        return nil
    }

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

    if containsAnyKeyword(normalized, keywords: ["求签", "请签", "抽签", "抽一签", "来一签", "签文", "今日运势", "今日一签"]) {
        return .divination
    }

    if containsAnyKeyword(normalized, keywords: ["背包", "道具", "库存", "猫粮还有", "罐头还有", "仓库"]) {
        return .inventory
    }

    if hasShoppingIntent(normalized) {
        return .shop
    }

    let petAddressed = isAddressingPet(in: normalized, petName: petName)
    let explicitAllStatus = containsAnyKeyword(normalized, keywords: ["全部状态", "萌宠现状", "宠物现状", "状态总览", "状态面板"])
        || (containsAnyKeyword(normalized, keywords: ["展示", "显示"]) && normalized.contains("状态") && normalized.contains("全部"))

    if explicitAllStatus {
        return .status(.all)
    }

    guard petAddressed else { return nil }

    if containsAnyKeyword(normalized, keywords: ["饿了", "饥饿", "饱食", "吃饱", "肚子饿", "饱不饱", "吃得够吗"]) {
        return .status(.hunger)
    }
    if containsAnyKeyword(normalized, keywords: ["渴了", "口渴", "饮水", "想喝水", "没水了", "喝水够吗", "缺水吗"]) {
        return .status(.hydration)
    }
    if containsAnyKeyword(normalized, keywords: ["脏了", "清洁", "洗澡", "脏兮兮", "该洗洗", "要洗澡吗", "身上脏吗"]) {
        return .status(.hygiene)
    }
    if containsAnyKeyword(normalized, keywords: [
        "心情", "心情怎么样", "心情咋样", "你现在心情", "情绪", "情绪怎么样", "情绪如何",
        "不开心", "开心吗", "高兴吗", "还开心吗", "emo", "emo了", "郁闷", "低落",
        "难过", "委屈", "烦躁", "状态好吗", "还好吗"
    ]) {
        return .status(.mood)
    }
    if containsAnyKeyword(normalized, keywords: ["亲密度", "关系值", "喜欢我吗", "亲近", "桃心", "黏我吗", "跟我亲吗"]) {
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
        return "这是我现在的小金库，喵币、鱼币和骨头币都在这儿。"
    case .meowCoin:
        return "这是我的喵币，领养二宝和充值时会先看它。"
    case .fishCoin:
        return "这是我的鱼币，买日常道具和看打工收益都会用到。"
    case .boneCoin:
        return "这是我的骨头币，毛毛会更常用这个币种。"
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
        title: kind == .all ? "我的货币余额" : "我的\(kind.title)",
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
        title: "我的背包",
        subtitle: feedback ?? (options.isEmpty ? "我现在还没有囤货呢。" : "这些都是我现在有的东西，点一下就能用，也可以直接拖去投喂区。"),
        options: options
    )
}

private struct PetShopPanelPresentation {
    let title: String
    let subtitle: String
    let introMessage: String
}

private func selectedPetCharacter(from status: PetStatus) -> PetCharacter {
    guard let petId = status.selectedPetId,
          let pet = PetCharacter(rawValue: petId) else {
        return .naicha
    }
    return pet
}

private func feedableShopItems() -> [PetItemDefinition] {
    PetConfigManager.shared.items.filter(isFeedableItem)
}

private func preferredShopItems(for pet: PetCharacter, limit: Int = 3) -> [PetItemDefinition] {
    let availableItems = PetConfigManager.shared.items
    guard !availableItems.isEmpty else { return [] }

    let preferredIDs: [String]
    switch pet {
    case .naicha:
        preferredIDs = ["freezeDried", "cannedFood", "catStrip", "catFood", "catRice", "goatMilk", "yarnBall"]
    case .maomao:
        preferredIDs = ["rawMeat", "chickenBreast", "goatMilk", "warmWater", "boiledWater", "yarnBall"]
    }

    let mappedPreferred = preferredIDs.compactMap { id in
        availableItems.first(where: { $0.id == id })
    }

    let feedableFallback = feedableShopItems().filter { item in
        !mappedPreferred.contains(where: { $0.id == item.id })
    }
    let genericFallback = availableItems.filter { item in
        !mappedPreferred.contains(where: { $0.id == item.id })
            && !feedableFallback.contains(where: { $0.id == item.id })
    }

    return Array((mappedPreferred + feedableFallback + genericFallback).prefix(limit))
}

private func naturalListText(_ names: [String]) -> String {
    let filtered = names.filter { !$0.isEmpty }
    switch filtered.count {
    case 0:
        return ""
    case 1:
        return filtered[0]
    case 2:
        return "\(filtered[0])和\(filtered[1])"
    default:
        let head = filtered.dropLast().joined(separator: "、")
        return "\(head)和\(filtered.last!)"
    }
}

private func shopPanelPresentation(status: PetStatus, feedback: String? = nil) -> PetShopPanelPresentation {
    let pet = selectedPetCharacter(from: status)
    let petName = displayName(for: pet, in: status)
    let featuredItems = preferredShopItems(for: pet)
    let featuredNames = featuredItems.map(\.name)
    let featuredList = naturalListText(featuredNames)
    let fallbackNames = PetConfigManager.shared.items.prefix(3).map(\.name)
    let fallbackList = naturalListText(fallbackNames)
    let displayList = featuredList.isEmpty ? fallbackList : featuredList

    let title: String
    let subtitle: String
    let introMessage: String

    switch pet {
    case .naicha:
        title = displayList.isEmpty ? "\(petName)的宠物商店" : "\(petName)想吃这些"
        if let feedback {
            subtitle = feedback
        } else if displayList.isEmpty {
            subtitle = "我先帮你把宠物商店打开啦，等店里补货了我们再来挑。"
        } else {
            subtitle = "我刚刚盯过货架啦，现在店里有\(displayList)。点一下先放进背包，拖到投喂区就能马上给我吃喝。"
        }

        if displayList.isEmpty {
            introMessage = "快带我去宠物商店看看嘛，我想补点吃的和喝的喵~"
        } else {
            introMessage = "快带我去宠物商店嘛，我想吃\(displayList)～给我买一点好不好喵？"
        }
    case .maomao:
        title = displayList.isEmpty ? "\(petName)的宠物商店" : "\(petName)想补这些"
        if let feedback {
            subtitle = feedback
        } else if displayList.isEmpty {
            subtitle = "我先把宠物商店打开啦，等店里补货我们再冲进去挑！"
        } else {
            subtitle = "我已经先闻过货架啦，现在店里有\(displayList)。点一下先放进背包，拖到投喂区就能马上给我享用。"
        }

        if displayList.isEmpty {
            introMessage = "主人，我们先去宠物商店看看吧！给我补点吃的喝的就更开心啦汪！"
        } else {
            introMessage = "主人，我们去宠物商店补给吧！我想吃\(displayList)，给我买一点好不好汪！"
        }
    }

    return PetShopPanelPresentation(
        title: title,
        subtitle: subtitle,
        introMessage: introMessage
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
    let presentation = shopPanelPresentation(status: status, feedback: feedback)
    return PetWidgetData(
        type: .shopPanel,
        title: presentation.title,
        subtitle: presentation.subtitle,
        options: shopOptions()
    )
}

func shopPanelIntroMessage(status: PetStatus) -> String {
    shopPanelPresentation(status: status).introMessage
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
        title: "我的裙装小金库（\(currency.rawValue)）",
        subtitle: "来陪我一起数数今天的小金库～",
        options: [
            PetWidgetOption(title: "看看我的全部状态", command: "pet_status_all", icon: "heart.text.square.fill"),
            PetWidgetOption(title: "打开我的背包", command: "pet_inventory_panel", icon: "shippingbox.fill")
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

struct PetDirectPlayIntent {
    let preferredItemId: String?
}

struct PetDirectUseIntent {
    let preferredItemId: String?
}

private func isFeedableItem(_ item: PetItemDefinition) -> Bool {
    item.category == "food" || item.category == "water"
}

private func isQuickUsePetItem(_ item: PetItemDefinition) -> Bool {
    isFeedableItem(item) || item.isToy || item.id == "energyPill"
}

func shopGuidanceText(for item: PetItemDefinition) -> String {
    if item.id == "yarnBall" {
        return "背包里还没有毛线球喔，我先把商店打开给你。记得一直往下拉到最下面，毛线球在商店最底层，买好后点一下会先收进背包，也可以直接拖过来陪我玩。"
    }
    return "\(item.name)现在不在背包里，我先把商店打开给你补货吧。"
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

    let feedMarkers = [
        "喂", "投喂", "吃", "喝", "用",
        "给你吃", "给它吃", "给你喝", "给它喝", "你吃", "它吃", "你喝", "它喝"
    ]
    let foodMarkers = [
        "小鱼干", "鱼干", "猫罐头", "罐头", "猫条", "冻干", "猫饭", "猫粮", "鸡胸肉", "生骨肉",
        "喝水", "水", "白开水", "温水", "山羊奶", "肉泥"
    ]

    let hasFeedMarker = feedMarkers.contains { normalized.contains($0) }
    let hasFoodMarker = foodMarkers.contains { normalized.contains($0) }
    let genericEatDrinkPrompt = normalized.contains("吃什么") || normalized.contains("喝什么")
    guard (hasFeedMarker && hasFoodMarker) || genericEatDrinkPrompt else { return nil }

    let keywordMappings: [([String], [String])] = [
        (["小鱼干", "鱼干"], ["freezeDried", "catStrip", "cannedFood"]),
        (["猫罐头", "罐头"], ["cannedFood"]),
        (["猫条"], ["catStrip"]),
        (["冻干"], ["freezeDried"]),
        (["猫饭"], ["catRice"]),
        (["猫粮"], ["catFood"]),
        (["鸡胸肉"], ["chickenBreast"]),
        (["生骨肉", "肉泥"], ["rawMeat"]),
        (["山羊奶"], ["goatMilk"]),
        (["喝水", "水"], ["warmWater", "boiledWater", "goatMilk"]),
        (["白开水"], ["boiledWater"]),
        (["温水"], ["warmWater"])
    ]

    for mapping in keywordMappings {
        if mapping.0.contains(where: { normalized.contains($0) }) {
            let matchedId = mapping.1.first(where: { PetConfigManager.shared.getItem(byId: $0) != nil })
            return PetDirectFeedIntent(preferredItemId: matchedId)
        }
    }

    if let namedItem = PetConfigManager.shared.items.first(where: { isFeedableItem($0) && normalized.contains($0.name.lowercased()) }) {
        return PetDirectFeedIntent(preferredItemId: namedItem.id)
    }

    return PetDirectFeedIntent(preferredItemId: nil)
}

func detectDirectPlayIntent(from text: String) -> PetDirectPlayIntent? {
    let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }

    let playMarkers = ["玩", "陪我玩", "陪你玩", "玩一会", "玩会", "玩具", "毛线球", "线球", "yarnball", "yarn ball"]
    guard playMarkers.contains(where: { normalized.contains($0) }) else { return nil }

    let preferredToy = PetConfigManager.shared.items.first { item in
        guard item.isToy else { return false }
        return normalized.contains(item.name.lowercased())
            || normalized.contains(item.id.lowercased())
            || (item.id == "yarnBall" && (normalized.contains("毛线球") || normalized.contains("线球") || normalized.contains("yarn")))
    }

    return PetDirectPlayIntent(preferredItemId: preferredToy?.id ?? (normalized.contains("玩") ? "yarnBall" : nil))
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

func resolveDirectPlayItem(intent: PetDirectPlayIntent, status: PetStatus) -> PetItemDefinition? {
    let playableItems = PetConfigManager.shared.items.filter(\.isToy)
    guard !playableItems.isEmpty else { return nil }

    if let preferredId = intent.preferredItemId,
       let preferred = PetConfigManager.shared.getItem(byId: preferredId),
       preferred.isToy {
        if status.inventory[preferred.id, default: 0] > 0 {
            return preferred
        }
        return preferred
    }

    if let inventoryItem = playableItems.first(where: { status.inventory[$0.id, default: 0] > 0 }) {
        return inventoryItem
    }
    return PetConfigManager.shared.getItem(byId: "yarnBall") ?? playableItems.first
}

func detectDirectUseIntent(from text: String) -> PetDirectUseIntent? {
    let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }

    let useMarkers = ["用", "使用", "来一个", "来个", "来点", "补一个", "补点"]
    let genericUsePrompt = normalized.contains("用什么") || normalized.contains("有什么能用")

    let directMappings: [(keywords: [String], itemId: String)] = [
        (["毛线球", "线球", "yarnball", "yarn ball"], "yarnBall"),
        (["猫罐头", "罐头"], "cannedFood"),
        (["猫粮"], "catFood"),
        (["生骨肉", "肉泥"], "rawMeat"),
        (["山羊奶"], "goatMilk"),
        (["白开水"], "boiledWater"),
        (["温水"], "warmWater"),
        (["精力药丸"], "energyPill")
    ]

    if let matched = directMappings.first(where: { mapping in
        mapping.keywords.contains(where: { normalized.contains($0) })
    }) {
        return PetDirectUseIntent(preferredItemId: matched.itemId)
    }

    if let item = PetConfigManager.shared.items.first(where: { item in
        isQuickUsePetItem(item) && (normalized.contains(item.name.lowercased()) || normalized.contains(item.id.lowercased()))
    }) {
        return PetDirectUseIntent(preferredItemId: item.id)
    }

    if genericUsePrompt || useMarkers.contains(where: { normalized.contains($0) && normalized.contains("什么") }) {
        return PetDirectUseIntent(preferredItemId: nil)
    }

    return nil
}

func resolveDirectUseItem(intent: PetDirectUseIntent, status: PetStatus) -> PetItemDefinition? {
    let quickUseItems = PetConfigManager.shared.items.filter(isQuickUsePetItem)
    guard !quickUseItems.isEmpty else { return nil }

    if let preferredId = intent.preferredItemId,
       let preferred = PetConfigManager.shared.getItem(byId: preferredId),
       isQuickUsePetItem(preferred) {
        return preferred
    }

    if let inventoryItem = quickUseItems.first(where: { status.inventory[$0.id, default: 0] > 0 }) {
        return inventoryItem
    }
    return quickUseItems.first
}

func purchasePetItemResult(itemId: String, autoFeedWhenPossible: Bool = true) -> PetItemCommandResult {
    guard let item = PetConfigManager.shared.getItem(byId: itemId) else {
        return PetItemCommandResult(feedback: "这个东西我暂时没找到，稍后再帮我看看吧。", feedAnimation: nil)
    }

    var status = PetDataManager.shared.status
    switch item.petCurrency {
    case .fishCoin:
        guard status.fishCoin >= item.price else {
            return PetItemCommandResult(feedback: "我的鱼币不够啦，先帮我攒一点再来买\(item.name)吧。", feedAnimation: nil)
        }
        status.fishCoin -= item.price
    case .meowCoin:
        guard status.meowCoin >= item.price else {
            return PetItemCommandResult(feedback: "我的喵币不够啦，先帮我充一点再来买\(item.name)吧。", feedAnimation: nil)
        }
        _ = StoreManager.spendMeowCoins(item.price, in: &status)
    case .boneCoin:
        guard status.boneCoin >= item.price else {
            return PetItemCommandResult(feedback: "我的骨头币不够啦，这个币种更适合毛毛用喔。", feedAnimation: nil)
        }
        status.boneCoin -= item.price
    }

    status.inventory[item.id, default: 0] += 1
    PetDataManager.shared.saveStatus(status)

    if autoFeedWhenPossible && isQuickUsePetItem(item) {
        let consumeResult = consumePetItemResult(itemId: item.id)
        return PetItemCommandResult(
            feedback: "买好就马上给我用啦～\(consumeResult.feedback)",
            feedAnimation: consumeResult.feedAnimation
        )
    }

    var refreshed = PetDataManager.shared.status
    refreshed.intimacy = min(100, refreshed.intimacy + 1)
    PetDataManager.shared.saveStatus(refreshed)
    return PetItemCommandResult(feedback: "买好啦，\(item.name)我已经收进背包啦。", feedAnimation: nil)
}

func consumePetItemResult(itemId: String) -> PetItemCommandResult {
    guard let item = PetConfigManager.shared.getItem(byId: itemId) else {
        return PetItemCommandResult(feedback: "这个道具我暂时没认出来。", feedAnimation: nil)
    }

    var status = PetDataManager.shared.status
    guard let count = status.inventory[item.id], count > 0 else {
        return PetItemCommandResult(feedback: "\(item.name)已经被我用完啦，要不要带我去商店补货？", feedAnimation: nil)
    }

    if item.id == "renameCard" {
        return PetItemCommandResult(feedback: "改名项圈先留着吧，我得走专门的改名流程。", feedAnimation: nil)
    }

    status.inventory[item.id] = count - 1

    if item.id == "energyPill" {
        let oldEnergy = status.energy
        status.energy = min(100, status.energy + item.recoveryValue)
        status.mood = min(100, status.mood + 5)
        status.intimacy = min(100, status.intimacy + 1)
        PetDataManager.shared.saveStatus(status)
        let recovered = Int(status.energy - oldEnergy)
        let feedback = recovered > 0 ? "我精神回来啦，精力恢复了 \(recovered) 点。" : "我现在精力已经满满的啦。"
        return PetItemCommandResult(feedback: feedback, feedAnimation: nil)
    }

    if item.isToy {
        let energyCost = Double(item.energyCost ?? 0)
        guard status.energy >= energyCost else {
            status.inventory[item.id] = count
            return PetItemCommandResult(feedback: "我现在太累啦，不想玩\(item.name)。", feedAnimation: nil)
        }
        status.energy = max(0, status.energy - energyCost)
        status.mood = min(100, status.mood + item.recoveryValue)
        status.intimacy = min(100, status.intimacy + 2)
        PetDataManager.shared.saveStatus(status)
        return PetItemCommandResult(feedback: "我抱着\(item.name)玩得好开心呀，心情一下就变好了。", feedAnimation: nil)
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
        return PetItemCommandResult(feedback: "我把\(item.name)喝掉啦，感觉没那么渴了。", feedAnimation: animation)
    }
    return PetItemCommandResult(feedback: "我把\(item.name)吃掉啦，肚子舒服多了。", feedAnimation: animation)
}

func cleanPetStatusNow() -> String {
    var status = PetDataManager.shared.status
    let oldValue = status.hygiene
    guard oldValue < 100 else {
        return "我已经香香的啦，不用再洗啦。"
    }
    status.hygiene = 100
    status.mood = min(100, status.mood + 10)
    status.intimacy = min(100, status.intimacy + 1)
    PetDataManager.shared.saveStatus(status)
    return "我已经洗香香啦，清洁度补满了。"
}
