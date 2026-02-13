import Foundation
import SwiftData

class WardrobeContextManager {
    static let shared = WardrobeContextManager()
    
    private init() {}
    
    func generateWardrobeSummary(clothings: [Clothing]) -> String {
        guard !clothings.isEmpty else {
            return "用户的衣橱目前是空的。"
        }
        
        // 1. 基础统计
        let totalCount = clothings.reduce(0) { $0 + $1.stock }
        let totalValue = clothings.reduce(Decimal(0)) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }
        
        // 2. 最贵单品 (包含小物)
        let mostExpensiveItem = clothings.max(by: { ($0.price + $0.accessoriesPrice) < ($1.price + $1.accessoriesPrice) })
        let mostExpensivePrice = mostExpensiveItem.map { $0.price + $0.accessoriesPrice } ?? 0
        
        // 3. 尾款天使统计
        let depositPlans = clothings.filter { $0.isDepositPlan }
        let totalDeposit = depositPlans.reduce(Decimal(0)) { $0 + ($1.deposit * Decimal($1.stock)) }
        let totalBalance = depositPlans.reduce(Decimal(0)) { $0 + ($1.balance * Decimal($1.stock)) } // 注意：这里简化了小物尾款，如果 AccessoyItem 有独立 balance 需累加
        
        // 4. 品牌分布
        // var brandCounts: [String: Int] = [:]
        // for clothing in clothings {
        //     let brandName = clothing.brand?.name ?? "未知品牌"
        //     brandCounts[brandName, default: 0] += clothing.stock
        // }
        // let topBrands = brandCounts.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key)(\($0.value)件)" }.joined(separator: ", ")
        
        // 构建 Context String
        var summary = """
        【衣橱数据概览】
        - 总件数：\(totalCount) 件
        - 衣橱总价值：¥\(NSDecimalNumber(decimal: totalValue).stringValue)
        """
        
        if let maxItem = mostExpensiveItem {
            summary += "\n- 最贵单品：\(maxItem.name) (¥\(NSDecimalNumber(decimal: mostExpensivePrice).stringValue))"
        }
        
        if !depositPlans.isEmpty {
            summary += """
            \n- 尾款天使（预定中）：\(depositPlans.count) 款
            - 已付定金总额：¥\(NSDecimalNumber(decimal: totalDeposit).stringValue)
            - 待付尾款总额：¥\(NSDecimalNumber(decimal: totalBalance).stringValue)
            """
        }
        
        // 添加最近购买的几件（比如最近3件），增加话题性
        let recentItems = clothings.sorted(by: { $0.purchaseDate > $1.purchaseDate }).prefix(3)
        if !recentItems.isEmpty {
            summary += "\n- 最近入手：\n"
            for item in recentItems {
                let dateStr = item.purchaseDate.formatted(date: .abbreviated, time: .omitted)
                summary += "  * \(item.name) (\(dateStr))\n"
            }
        }
        
        return summary
    }
    
    // 生成单品详细描述 (用于拖拽识别后)
    func generateItemDetail(clothing: Clothing) -> String {
        var detail = """
        【单品详情】
        名称：\(clothing.name)
        价格：¥\(NSDecimalNumber(decimal: clothing.price).stringValue)
        """
        
        if clothing.accessoriesPrice > 0 {
            detail += "\n小物总价：¥\(NSDecimalNumber(decimal: clothing.accessoriesPrice).stringValue)"
        }
        
        if !clothing.types.isEmpty {
            detail += "\n类型：\(clothing.types)"
        }
        
        if clothing.isDepositPlan {
            detail += "\n状态：预定中 (定金 ¥\(NSDecimalNumber(decimal: clothing.deposit).stringValue), 尾款 ¥\(NSDecimalNumber(decimal: clothing.balance).stringValue))"
            if let finalDate = clothing.finalPaymentDate {
                let dateStr = finalDate.formatted(date: .abbreviated, time: .omitted)
                detail += "\n补款时间：\(dateStr)"
            }
        }
        
        return detail
    }
}
