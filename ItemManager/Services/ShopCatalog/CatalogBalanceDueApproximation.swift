// iOS 业务入口；纯日期算法在 SharedCatalog，供 Mac 录入预览共用。
import Foundation

nonisolated enum CatalogBalanceDueApproximation {
    typealias Window = CatalogBalanceDueEstimate.Window

    static func estimatedDate(text: String, anchor: Date,
                              calendar: Calendar = .current) -> Date? {
        CatalogBalanceDueEstimate.estimatedDate(text: text, anchor: anchor, calendar: calendar)
    }

    static func declaredWindow(kind: CatalogBalanceDueKind?, text: String?, endText: String?,
                               at: Date?, endAt: Date?, anchor: Date?,
                               calendar: Calendar = .current) -> Window? {
        CatalogBalanceDueEstimate.declaredWindow(kind: kind, text: text, endText: endText,
            at: at, endAt: endAt, anchor: anchor, calendar: calendar)
    }

    static func declaredWindow(of series: CatalogSeries, anchor: Date?,
                               calendar: Calendar = .current) -> Window? {
        CatalogBalanceDueEstimate.declaredWindow(of: series, anchor: anchor, calendar: calendar)
    }
}
