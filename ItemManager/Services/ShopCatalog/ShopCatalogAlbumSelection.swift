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

    func visibleSeries(_ series: [CatalogSeries]) -> [CatalogSeries] {
        let inYear = seriesInYear(series)
        guard let seriesID else { return inYear }
        return inYear.filter { $0.id == seriesID }
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
