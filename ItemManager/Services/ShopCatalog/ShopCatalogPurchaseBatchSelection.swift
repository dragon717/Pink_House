import Foundation

/// 入橱前的购买批次确认。团次和批次均使用运营配置的名称与稳定 ID。
/// 即便只有一个批次，也由用户明确选择；不沿用尾款解析器的单团兜底。
struct ShopCatalogPurchaseBatchSelection: Equatable {
    var selectedIDs: [String: String] = [:]

    static func requirements(in series: [CatalogSeries]) -> [CatalogSeries] {
        var seen = Set<String>()
        return series.filter { !($0.reservationBatches ?? []).isEmpty && seen.insert($0.id).inserted }
    }

    func canConfirm(for series: [CatalogSeries]) -> Bool {
        Self.requirements(in: series).allSatisfy { series in
            guard let selected = selectedIDs[series.id] else { return false }
            return series.reservationBatches?.contains { $0.id == selected } == true
        }
    }

    func requiresSelection(for series: [CatalogSeries]) -> Bool {
        !canConfirm(for: series)
    }
}
