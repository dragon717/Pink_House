
import SwiftUI
import Observation

enum CurrencyType: String, CaseIterable, Identifiable {
    case rmb = "人民币"
    case jpy = "日元"
    case gold = "黄金"
    
    var id: String { rawValue }
    
    var symbol: String {
        switch self {
        case .rmb: return "CN¥"
        case .jpy: return "JP¥"
        case .gold: return "Gold"
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
    var goldPriceCNYPerGram: Double = 600.0 // CNY per Gram
    var goldPriceSource: String = "模拟数据"
    
    var isFetchingRate: Bool = false
    var isGoldReady: Bool = false
    var lastUpdatedDate: String? = nil
    
    // Gold Configuration
    let goldBeanWeightGrams: Double = 1.0 // 1g per bean
    
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
        switch selectedCurrency {
        case .rmb:
            return NSDecimalNumber(decimal: baseAmountCNY).intValue
        case .jpy:
            let converted = baseAmountCNY * Decimal(exchangeRateJPY)
            return NSDecimalNumber(decimal: converted).intValue
        case .gold:
            // This is just a placeholder, we won't use this Int for Gold display likely
            let grams = totalGoldWeightGrams
            return Int(grams)
        }
    }
    
    var totalGoldWeightGrams: Double {
        let cny = NSDecimalNumber(decimal: baseAmountCNY).doubleValue
        guard goldPriceCNYPerGram > 0 else { return 0 }
        return cny / goldPriceCNYPerGram
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
    
    func fetchExchangeRate() async {
        guard !isFetchingRate else { return }
        isFetchingRate = true
        
        // Fetch JPY Rate
        await fetchJPYRate()
        // Fetch Gold Price
        await fetchGoldPrice()
        
        await MainActor.run {
            self.isFetchingRate = false
            self.isGoldReady = true
        }
    }
    
    private func fetchJPYRate() async {
        guard let url = URL(string: "https://api.exchangerate-api.com/v4/latest/CNY") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rates = json["rates"] as? [String: Double],
               let jpyRate = rates["JPY"] {
                
                await MainActor.run {
                    self.exchangeRateJPY = jpyRate
                    if let dateStr = json["date"] as? String {
                        self.lastUpdatedDate = dateStr
                    }
                }
            }
        } catch {
            print("Failed to fetch JPY rate: \(error)")
        }
    }
    
    private func fetchGoldPrice() async {
        // Using goldprice.org API
        // Returns price per Ounce in CNY
        guard let url = URL(string: "https://data-asg.goldprice.org/dbXRates/CNY") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Expected JSON: {"items":[{"curr":"CNY","xauPrice":20000.0,...}]}
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]],
               let firstItem = items.first,
               let xauPriceOunce = firstItem["xauPrice"] as? Double {
                
                // Convert Ounce to Gram (1 Troy Ounce = 31.1034768 Grams)
                let pricePerGram = xauPriceOunce / 31.1034768
                
                await MainActor.run {
                    self.goldPriceCNYPerGram = pricePerGram
                    self.goldPriceSource = "数据来源: GoldPrice.org"
                    // Update date if available, otherwise keep existing or current
                }
            }
        } catch {
            print("Failed to fetch Gold rate: \(error)")
            await MainActor.run {
                self.goldPriceSource = "获取失败，使用默认值"
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
    
    // Gold Beans don't have "denominations" in the same way, but for the stack view fallback (if we used it)
    // we could define something. But we will use Physics View for Gold.
    
    var currentDenominations: [Denomination] {
        switch selectedCurrency {
        case .rmb: return rmbDenominations
        case .jpy: return jpyDenominations
        case .gold: return [] // Not used for Gold
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
        if selectedCurrency == .gold { return [] }
        
        var remaining = totalAmount
        var result: [MoneyPile] = []
        
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
        return result
    }
}
