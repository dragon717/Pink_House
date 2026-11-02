import AppKit
import SwiftUI

/// 打开页面时立即按当前时间求值，此后只在真实阶段边界刷新。
struct OpsSeriesPhaseTimeline<Content: View>: View {
    let series: [CatalogSeries]
    @ViewBuilder var content: (Date) -> Content
    @State private var now = Date()
    @State private var refreshGeneration = 0

    var body: some View {
        let dates = Array(Set(series.flatMap { CatalogSeriesSalePhasePolicy.transitionDates(of: $0) })).sorted()
        content(now)
            .task(id: RefreshID(dates: dates, generation: refreshGeneration)) {
                now = Date()
                for date in dates where date > now {
                    do {
                        // 系统唤醒可能有延迟，始终重新读取实际时间；取消时不更新已关闭的页面。
                        while date > Date() {
                            try await Task.sleep(for: .seconds(date.timeIntervalSinceNow))
                        }
                        try Task.checkCancellation()
                        now = Date()
                    } catch { return }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshGeneration += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
                refreshGeneration += 1
            }
    }

    private struct RefreshID: Equatable {
        let dates: [Date]
        let generation: Int
    }
}
