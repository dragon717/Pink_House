import Foundation

/// Read-only browsing state: years and series are separate dimensions.
nonisolated struct ShopCatalogAlbumSelection: Equatable {
    nonisolated enum Year: Hashable, Identifiable, Sendable {
        case all, year(Int), unspecified
        var id: String {
            switch self {
            case .all: return "all"
            case .year(let value): return String(value)
            case .unspecified: return "unspecified"
            }
        }
        var title: String {
            switch self {
            case .all: return "全部年份"
            case .year(let value): return String(value)
            case .unspecified: return "未标年份"
            }
        }
    }

    var year: Year = .all
    var seriesID: String?
    var keyword: String = ""

    var hasSearch: Bool { !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func years(in series: [CatalogSeries]) -> [Year] {
        [.all] + Set(series.compactMap(\.year)).sorted(by: >).map(Year.year)
            + (series.contains { $0.year == nil } ? [.unspecified] : [])
    }

    func seriesInYear(_ series: [CatalogSeries]) -> [CatalogSeries] {
        series.filter { entry in
            switch year {
            case .all: return true
            case .year(let value): return entry.year == value
            case .unspecified: return entry.year == nil
            }
        }
    }

    func visibleSeries(_ series: [CatalogSeries], products: [CatalogProduct] = []) -> [CatalogSeries] {
        let inYear = seriesInYear(series)
        let selected = inYear.filter { seriesID == nil || $0.id == seriesID }
        let terms = Self.normalized(keyword).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return selected }
        let bySeries = Dictionary(grouping: products.filter { $0.archivedAt == nil }, by: \.seriesID)
        return selected.filter { entry in
            let names = (bySeries[entry.id] ?? []).filter { $0.shopID == entry.shopID }
                .flatMap { [$0.name, $0.designName ?? "", $0.category] }
            let text = Self.normalized(([entry.name] + names).joined(separator: " "))
            return terms.allSatisfy { text.contains($0) }
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "zh_CN"))
    }

    mutating func selectYear(_ year: Year) {
        self.year = year
        seriesID = nil
    }

    mutating func reconcile(with series: [CatalogSeries]) {
        if !Self.years(in: series).contains(year) { year = .all }
        if let seriesID, !seriesInYear(series).contains(where: { $0.id == seriesID }) { self.seriesID = nil }
    }
}
