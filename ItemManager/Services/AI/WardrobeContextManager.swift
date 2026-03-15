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
        let totalBalance = depositPlans.reduce(Decimal(0)) { $0 + ($1.balance * Decimal($1.stock)) }

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

        // 添加所有可用单品列表（包含ID，供AI选择搭配）
        summary += "\n\n【可用单品列表】（请从以下物品中选择搭配，使用物品的ID）：\n"
        for item in clothings {
            let brandName = item.brand?.name ?? "未知品牌"
            summary += "- ID: \(item.id.uuidString) | 名称: \(item.name) | 品牌: \(brandName) | 价格: ¥\(NSDecimalNumber(decimal: item.price).stringValue)\n"
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
