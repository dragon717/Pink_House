
import SwiftUI
import Observation

enum CurrencyType: String, CaseIterable, Identifiable {
    case rmb = "人民币"
    case jpy = "日元"
    case usd = "美刀"
    case gold = "黄金"
    case silver = "白银"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .rmb: return "CN¥"
        case .jpy: return "JP¥"
        case .usd: return "$"
        case .gold: return "Gold"
        case .silver: return "Silver"
        }
    }
}

struct Denomination: Identifiable, Hashable {
    let id = UUID()
    let value: Int // For Gold, this can represent weight in mg or count
    let color: Color
    let name: String
    
    // Custom hash function to conform to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Denomination, rhs: Denomination) -> Bool {
        lhs.id == rhs.id
    }
}

@Observable
class WealthViewModel {
    var selectedCurrency: CurrencyType = .rmb
    var baseAmountCNY: Decimal = 0.0
    
    // Exchange Rates
    var exchangeRateJPY: Double = 21.0 // CNY to JPY
    var exchangeRateUSD: Double = 0.14 // CNY to USD (1 CNY ≈ 0.14 USD)
    var goldPriceCNYPerGram: Double = 600.0 // CNY per Gram
    var goldPriceSource: String = "模拟数据"
    
    var silverPriceCNYPerGram: Double = 7.0 // CNY per Gram
    var silverPriceSource: String = "模拟数据"
    
    var isFetchingRate: Bool = false
    var isGoldReady: Bool = false
    var isSilverReady: Bool = false
    var lastUpdatedDate: String? = nil

    init() {
        let exchangeService = CurrencyExchangeRateService.shared
        exchangeRateJPY = exchangeService.cnyToJPYRate
        exchangeRateUSD = exchangeService.cnyToUSDRate
        lastUpdatedDate = exchangeService.lastProviderDate
    }
    
    // Gold Configuration
    let goldBeanWeightGrams: Double = 1.0 // 1g per bean
    let silverBeanWeightGrams: Double = 50.0 // 50g per silver bean (1两)
    
    // Legacy support for binding if needed, but we prefer computed
    var inputAmount: String {
        get { "\(totalAmount)" }
        set { 
            // Read-only in this mode
        }
    }
    
    // For numeric display (Integer part)
    // Note: For Gold, this might not be sufficient if we want decimals.
    // We'll add a specific formatted string or value for Gold.
    var totalAmount: Int {
        let safeBaseAmountCNY = sanitizedBaseAmountCNY
        switch selectedCurrency {
        case .rmb:
            return NSDecimalNumber(decimal: safeBaseAmountCNY).intValue
        case .jpy:
            let converted = safeBaseAmountCNY * Decimal(exchangeRateJPY)
            return NSDecimalNumber(decimal: converted).intValue
        case .usd:
            let converted = safeBaseAmountCNY * Decimal(exchangeRateUSD)
            return NSDecimalNumber(decimal: converted).intValue
        case .gold:
            // This is just a placeholder, we won't use this Int for Gold display likely
            let grams = totalGoldWeightGrams
            return Int(grams)
        case .silver:
            let grams = totalSilverWeightGrams
            return Int(grams)
        }
    }
    
    var totalGoldWeightGrams: Double {
        let cny = NSDecimalNumber(decimal: sanitizedBaseAmountCNY).doubleValue
        guard goldPriceCNYPerGram > 0 else { return 0 }
        return cny / goldPriceCNYPerGram
    }
    
    var totalSilverWeightGrams: Double {
        let cny = NSDecimalNumber(decimal: sanitizedBaseAmountCNY).doubleValue
        guard silverPriceCNYPerGram > 0 else { return 0 }
        return cny / silverPriceCNYPerGram
    }

    var sanitizedBaseAmountCNY: Decimal {
        let sanitized = FinancialDataSanitizer.aggregateMoney(baseAmountCNY)
        if sanitized != baseAmountCNY {
            print("💰 WealthViewModel: sanitized baseAmountCNY raw=\(baseAmountCNY), sanitized=\(sanitized)")
        }
        return sanitized
    }

    static func calculateBaseAmountCNY(
        clothings: [Clothing],
        wealthSavingEntries: [WealthSavingEntry]
    ) -> Decimal {
        let wardrobeTotal = clothings.reduce(Decimal(0)) { partialResult, clothing in
            guard !clothing.isDeleted && clothing.deletedAt == nil else { return partialResult }
            logNegativeFinancialFieldsIfNeeded(clothing)
            return partialResult + sanitizedWardrobeContribution(for: clothing)
        }
        let rawSavingTotal = WealthSavingLedger.activeTotal(in: wealthSavingEntries)
        let sanitizedSavingTotal = FinancialDataSanitizer.aggregateMoney(rawSavingTotal)
        if sanitizedSavingTotal != rawSavingTotal {
            print("💰 WealthViewModel: sanitized wealth saving total raw=\(rawSavingTotal), sanitized=\(sanitizedSavingTotal)")
        }

        let rawTotal = wardrobeTotal + sanitizedSavingTotal
        let sanitizedTotal = FinancialDataSanitizer.aggregateMoney(rawTotal)
        if sanitizedTotal != rawTotal {
            print("💰 WealthViewModel: sanitized aggregate total raw=\(rawTotal), sanitized=\(sanitizedTotal)")
        }
        return sanitizedTotal
    }

    static func sanitizedWardrobeContribution(for clothing: Clothing) -> Decimal {
        let safeStock = Decimal(FinancialDataSanitizer.stock(clothing.stock))
        let safeShippingFee = FinancialDataSanitizer.money(clothing.shippingFee)

        if clothing.isDepositPlan {
            let safeDeposit = FinancialDataSanitizer.money(clothing.deposit)
            let safeAccessoryDeposit = FinancialDataSanitizer.money(
                clothing.accessoryItems?.reduce(Decimal(0)) { $0 + $1.deposit } ?? 0
            )
            return ((safeDeposit + safeAccessoryDeposit) * safeStock) + safeShippingFee
        } else {
            let safePrice = FinancialDataSanitizer.money(clothing.price)
            let safeAccessoriesPrice = FinancialDataSanitizer.money(clothing.resolvedAccessoriesPrice)
            return (safePrice * safeStock) + safeAccessoriesPrice + safeShippingFee
        }
    }

    private static func logNegativeFinancialFieldsIfNeeded(_ clothing: Clothing) {
        let negativeFields = [
            clothing.price < 0 ? "price" : nil,
            clothing.deposit < 0 ? "deposit" : nil,
            clothing.balance < 0 ? "balance" : nil,
            clothing.shippingFee < 0 ? "shippingFee" : nil,
            clothing.stock < 0 ? "stock" : nil
        ].compactMap { $0 }

        guard !negativeFields.isEmpty else { return }
        print(
            """
            💰 WealthViewModel: negative clothing financial fields \
            id=\(clothing.id.uuidString), name=\(clothing.name), \
            price=\(clothing.price), deposit=\(clothing.deposit), \
            balance=\(clothing.balance), shippingFee=\(clothing.shippingFee), \
            stock=\(clothing.stock), negativeFields=\(negativeFields.joined(separator: ","))
            """
        )
    }
    
    // Gold Display Logic
    struct GoldDisplayValue {
        let value: Double
        let unit: String
    }
    
    var goldDisplayValue: GoldDisplayValue {
        let grams = totalGoldWeightGrams
        
        if grams >= 500 * 1000 { // > 1000 Jin = 500,000g -> Ton (1 Ton = 2000 Jin = 1,000,000g ?? Wait)
            // User said: 1 Jin = 500g.
            // 1 Ton = 2000 Jin.
            // 2000 Jin * 500g/Jin = 1,000,000g = 1 Tonne (Metric Ton).
            // User: "当黄金总斤数超过1000斤时，自动将其转换为“吨”"
            // 1000 Jin = 500,000g = 0.5 Ton.
            // So if > 1000 Jin (500kg), show in Tons?
            // "当黄金总斤数超过1000斤时" -> > 1000 Jin.
            // 1000 Jin = 500kg.
            
            // Let's follow user exact rule:
            // > 1000g -> Jin
            // > 1000 Jin -> Ton
            
            let jin = grams / 500.0
            if jin > 1000 {
                let tons = jin / 2000.0
                return GoldDisplayValue(value: tons, unit: "吨")
            } else {
                return GoldDisplayValue(value: jin, unit: "斤")
            }
        } else if grams > 1000 {
             // > 1000g -> Jin
            let jin = grams / 500.0
            return GoldDisplayValue(value: jin, unit: "斤")
        } else {
            return GoldDisplayValue(value: grams, unit: "克")
        }
    }
    
    var silverDisplayValue: GoldDisplayValue {
        let grams = totalSilverWeightGrams
        // 1两 = 50g
        // 1吨 = 1,000,000g = 20,000两
        
        // 当白银总两数足够大时（例如超过1吨），显示吨
        // 这里阈值设为 20,000两 (1吨)
        if grams >= 1_000_000 {
            let tons = grams / 1_000_000.0
            return GoldDisplayValue(value: tons, unit: "吨")
        } else {
            let liang = grams / 50.0
            return GoldDisplayValue(value: liang, unit: "两")
        }
    }
    
    func fetchExchangeRate() async {
        guard !isFetchingRate else { return }
        isFetchingRate = true

        let exchangeResult = await CurrencyExchangeRateService.shared.refreshCNYRates(force: true)
        if let errorMessage = exchangeResult.errorMessage {
            print("WealthViewModel: failed to fetch CNY exchange rates: \(errorMessage)")
        } else {
            exchangeRateJPY = exchangeResult.snapshot.cnyToJPYRate
            exchangeRateUSD = exchangeResult.snapshot.cnyToUSDRate
            lastUpdatedDate = exchangeResult.snapshot.providerDate
        }

        // Fetch Gold Price
        await fetchGoldPrice()
        // Fetch Silver Price
        await fetchSilverPrice()
        
        await MainActor.run {
            self.isFetchingRate = false
            self.isGoldReady = true
            self.isSilverReady = true
        }
    }
    
    /// 获取USD到CNY的汇率，用于黄金/白银价格转换
    /// 返回 1 USD = ? CNY
    private func fetchUSDTocnyRate() async -> Double {
        guard let url = URL(string: "https://api.exchangerate-api.com/v4/latest/USD") else {
            return 7.0 // 默认汇率
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rates = json["rates"] as? [String: Double],
               let cnyRate = rates["CNY"] {
                return cnyRate
            }
        } catch {
            print("Failed to fetch USD to CNY rate: \(error)")
        }
        return 7.0 // 默认汇率
    }
    
    private func fetchGoldPrice() async {
        // 使用 gold-api.com 获取黄金价格（美元/盎司），然后转换为人民币/克
        guard let url = URL(string: "https://api.gold-api.com/price/XAU") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Expected JSON: {"name":"Gold","price":5086.9,"symbol":"XAU","updatedAt":"..."}
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let priceUSDPerOunce = json["price"] as? Double {
                
                // 获取USD到CNY的汇率
                let usdToCNY = await fetchUSDTocnyRate()
                
                // 转换为人民币/盎司，然后转换为人民币/克
                let priceCNYPerOunce = priceUSDPerOunce * usdToCNY
                let pricePerGram = priceCNYPerOunce / 31.1034768 // 1 Troy Ounce = 31.1034768 Grams
                
                await MainActor.run {
                    self.goldPriceCNYPerGram = pricePerGram
                    self.goldPriceSource = "数据来源: Gold-API.com"
                }
            }
        } catch {
            print("Failed to fetch Gold rate: \(error)")
            await MainActor.run {
                self.goldPriceSource = "获取失败，使用默认值"
            }
        }
    }
    
    private func fetchSilverPrice() async {
        // 使用 gold-api.com 获取白银价格（美元/盎司），然后转换为人民币/克
        guard let url = URL(string: "https://api.gold-api.com/price/XAG") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Expected JSON: {"name":"Silver","price":82.85,"symbol":"XAG","updatedAt":"..."}
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let priceUSDPerOunce = json["price"] as? Double {
                
                // 获取USD到CNY的汇率
                let usdToCNY = await fetchUSDTocnyRate()
                
                // 转换为人民币/盎司，然后转换为人民币/克
                let priceCNYPerOunce = priceUSDPerOunce * usdToCNY
                let pricePerGram = priceCNYPerOunce / 31.1034768 // 1 Troy Ounce = 31.1034768 Grams
                
                await MainActor.run {
                    self.silverPriceCNYPerGram = pricePerGram
                    self.silverPriceSource = "数据来源: Gold-API.com"
                }
            }
        } catch {
            print("Failed to fetch Silver rate: \(error)")
            await MainActor.run {
                self.silverPriceSource = "获取失败，使用默认值"
            }
        }
    }
    
    // Configurable denominations
    let rmbDenominations: [Denomination] = [
        Denomination(value: 100, color: Color(red: 0.9, green: 0.3, blue: 0.3), name: "100"), // Red
        Denomination(value: 50, color: Color(red: 0.3, green: 0.7, blue: 0.5), name: "50"), // Green
        Denomination(value: 20, color: Color(red: 0.6, green: 0.4, blue: 0.2), name: "20"), // Brown
        Denomination(value: 10, color: Color(red: 0.3, green: 0.5, blue: 0.8), name: "10"), // Blue
        Denomination(value: 5, color: Color(red: 0.6, green: 0.3, blue: 0.7), name: "5"),  // Purple
        Denomination(value: 1, color: Color(red: 0.7, green: 0.7, blue: 0.3), name: "1")   // Yellow-ish
    ]
    
    let jpyDenominations: [Denomination] = [
        Denomination(value: 10000, color: Color(red: 0.5, green: 0.3, blue: 0.2), name: "10000"), // Brown
        Denomination(value: 5000, color: Color(red: 0.5, green: 0.2, blue: 0.6), name: "5000"),  // Purple
        Denomination(value: 1000, color: Color(red: 0.2, green: 0.4, blue: 0.7), name: "1000")   // Blue
    ]

    // 美元面额：100刀、50刀、20刀、10刀、5刀、2刀、1刀（根据联网信息，2美元也是流通面额）
    let usdDenominations: [Denomination] = [
        Denomination(value: 100, color: Color(red: 0.1, green: 0.4, blue: 0.2), name: "100"), // 墨绿色
        Denomination(value: 50, color: Color(red: 0.2, green: 0.3, blue: 0.5), name: "50"),   // 深蓝色
        Denomination(value: 20, color: Color(red: 0.4, green: 0.2, blue: 0.2), name: "20"),   // 深红色
        Denomination(value: 10, color: Color(red: 0.2, green: 0.3, blue: 0.2), name: "10"),   // 橄榄绿
        Denomination(value: 5, color: Color(red: 0.3, green: 0.2, blue: 0.4), name: "5"),     // 紫色
        Denomination(value: 2, color: Color(red: 0.3, green: 0.4, blue: 0.6), name: "2"),     // 蓝灰色（2美元特殊颜色）
        Denomination(value: 1, color: Color(red: 0.2, green: 0.5, blue: 0.3), name: "1")      // 绿色
    ]
    
    // Gold Beans don't have "denominations" in the same way, but for the stack view fallback (if we used it)
    // we could define something. But we will use Physics View for Gold.
    
    var currentDenominations: [Denomination] {
        switch selectedCurrency {
        case .rmb: return rmbDenominations
        case .jpy: return jpyDenominations
        case .usd: return usdDenominations
        case .gold: return [] // Not used for Gold
        case .silver: return [] // Not used for Silver
        }
    }
    
    struct MoneyPile: Identifiable, Hashable {
        let id = UUID()
        let denomination: Denomination
        let count: Int
    }
    
    // Logic to calculate stacks (Piles of max 1000)
    // Returns a flattened list of Piles
    func calculateStacks() -> [MoneyPile] {
        if selectedCurrency == .gold || selectedCurrency == .silver { return [] }
        
        var remaining = totalAmount
        var result: [MoneyPile] = []
        
        print("💰 calculateStacks: selectedCurrency=\(selectedCurrency), baseAmountCNY=\(baseAmountCNY), totalAmount=\(totalAmount), remaining=\(remaining)")

        guard remaining > 0 else {
            print("💰 calculateStacks: skip splitting because sanitized remaining=\(remaining)")
            return []
        }
        
        for denom in currentDenominations {
            let totalCountForDenom = remaining / denom.value
            
            if totalCountForDenom > 0 {
                // Split into piles of 1000
                let fullPiles = totalCountForDenom / 1000
                let remainderPile = totalCountForDenom % 1000
                
                // Add full piles (limit loop for performance safety if needed, but 1B / 100 / 1000 = 10,000 items is fine)
                for _ in 0..<fullPiles {
                    result.append(MoneyPile(denomination: denom, count: 1000))
                }
                
                // Add remainder
                if remainderPile > 0 {
                    result.append(MoneyPile(denomination: denom, count: remainderPile))
                }
                
                remaining %= denom.value
            }
        }
        print("💰 calculateStacks: result.count=\(result.count)")
        return result
    }
}
