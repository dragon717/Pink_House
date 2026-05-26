import Foundation

enum OutfitRecommendabilityReason: String {
    case reservation
    case pendingFulfillment
}

enum OutfitRecommendability {
    private static let pendingFulfillmentHints = [
        "未发货", "全款未发货", "待发货", "未到货", "待收货",
        "待补尾款", "补尾款", "待补款", "补款", "尾款未补",
        "待补邮费", "补邮费", "邮费未补"
    ]

    private static let resolvedFulfillmentHints = [
        "已发货", "已到货", "已收货", "已补尾款", "已补款", "已补邮费"
    ]

    static func recommendableClothings(from clothings: [Clothing]) -> [Clothing] {
        clothings.filter(isRecommendable)
    }

    static func isRecommendable(_ clothing: Clothing) -> Bool {
        exclusionReasons(for: clothing).isEmpty
    }

    static func exclusionReasons(for clothing: Clothing) -> [OutfitRecommendabilityReason] {
        var reasons: [OutfitRecommendabilityReason] = []

        if clothing.reservationKind != .owned {
            reasons.append(.reservation)
        }

        if hasPendingFulfillmentSignal(clothing) {
            reasons.append(.pendingFulfillment)
        }

        return reasons
    }

    static func hasPendingFulfillmentSignal(_ clothing: Clothing) -> Bool {
        let text = searchableStatusText(for: clothing)

        guard !text.isEmpty else {
            return false
        }

        if resolvedFulfillmentHints.contains(where: { text.contains($0) }) &&
            !pendingFulfillmentHints.contains(where: { text.contains($0) }) {
            return false
        }

        return pendingFulfillmentHints.contains(where: { text.contains($0) })
    }

    private static func searchableStatusText(for clothing: Clothing) -> String {
        [
            clothing.name,
            clothing.note,
            clothing.tags?.map(\.name).joined(separator: ",") ?? ""
        ]
        .joined(separator: ",")
        .lowercased()
    }
}
