
import SwiftUI
import Observation

enum CurrencyType: String, CaseIterable, Identifiable {
    case rmb = "人民币"
    case jpy = "日元"
    
    var id: String { rawValue }
    
    var symbol: String {
        switch self {
        case .rmb: return "CN¥"
        case .jpy: return "JP¥"
        }
    }
}

struct Denomination: Identifiable, Hashable {
    let id = UUID()
    let value: Int
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
    var exchangeRate: Double = 21.0 // Default estimation
    var isFetchingRate: Bool = false
    var lastUpdatedDate: String? = nil
    
    // Legacy support for binding if needed, but we prefer computed
    var inputAmount: String {
        get { "\(totalAmount)" }
        set { 
            // Read-only in this mode, but if we wanted to support input:
            // if let val = Int(newValue) { baseAmountCNY = Decimal(val) }
        }
    }
    
    var totalAmount: Int {
        switch selectedCurrency {
        case .rmb:
            return NSDecimalNumber(decimal: baseAmountCNY).intValue
        case .jpy:
            let converted = baseAmountCNY * Decimal(exchangeRate)
            return NSDecimalNumber(decimal: converted).intValue
        }
    }
    
    func fetchExchangeRate() async {
        guard !isFetchingRate else { return }
        isFetchingRate = true
        
        // Using a public free API for exchange rates
        guard let url = URL(string: "https://api.exchangerate-api.com/v4/latest/CNY") else {
            isFetchingRate = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rates = json["rates"] as? [String: Double],
               let jpyRate = rates["JPY"] {
                
                await MainActor.run {
                    self.exchangeRate = jpyRate
                    self.isFetchingRate = false
                    
                    if let dateStr = json["date"] as? String {
                        self.lastUpdatedDate = dateStr
                    }
                }
            }
        } catch {
            print("Failed to fetch exchange rate: \(error)")
            await MainActor.run {
                self.isFetchingRate = false
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
    
    var currentDenominations: [Denomination] {
        switch selectedCurrency {
        case .rmb: return rmbDenominations
        case .jpy: return jpyDenominations
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
