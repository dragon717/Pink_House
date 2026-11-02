import AppKit
import SwiftData
import SwiftUI
@testable import PinkHouseOps

@MainActor
enum OpsSalePhaseSnapshots {
    static func run(into directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let workspace = OpsWorkspace(context: store.mainContext)
        let end = Date().addingTimeInterval(-3600)
        workspace.catalog.series = [CatalogSeries(id: "s", shopID: "shop", name: "预约已结束，尾款待公布",
            salePhase: .reservationActive, reservationEndAt: end,
            reservationBatches: [CatalogReservationBatch(name: "先行团", balanceDueKind: .approximate, balanceDueText: "圣诞节前")])]
        try capture(SeriesConfigSheet(workspace: workspace, seriesID: "s").modelContainer(store),
                    at: directory.appendingPathComponent("ended-awaiting-balance.png"))
        workspace.catalog.series[0].reservationBatches = [CatalogReservationBatch(name: "一团", balanceDueKind: .exact, balanceDueAt: end.addingTimeInterval(60))]
        try capture(SeriesConfigSheet(workspace: workspace, seriesID: "s").modelContainer(store),
                    at: directory.appendingPathComponent("balance-started.png"))

        // 使用与正式页面完全相同的时间驱动容器，保持同一个窗口跨过两个边界。
        let reservationEnd = Date().addingTimeInterval(2)
        let balanceStart = reservationEnd.addingTimeInterval(2)
        let value = CatalogSeries(id: "clock", shopID: "shop", name: "自动流转",
            salePhase: .reservationActive, reservationEndAt: reservationEnd,
            balanceDueKind: .exact, balanceDueAt: balanceStart)
        var observed: [CatalogSeriesSalePhase?] = []
        let view = OpsSeriesPhaseTimeline(series: [value]) { now in
            let phase = CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: now)
            Text("当前阶段：\(phase?.displayName ?? "未声明")")
                .onChange(of: phase, initial: true) { _, newValue in observed.append(newValue) }
        }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        let window = NSWindow(contentRect: host.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: balanceStart.addingTimeInterval(0.4))
        let expected: [CatalogSeriesSalePhase?] = [.reservationActive, .reservationEnded, .balancePending]
        guard observed == expected else { throw NSError(domain: "OpsSalePhaseClock", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "未持续自动流转：\(observed)"]) }
        try "通过：同一页面依次显示预约中、预约已结束、尾款中，无手动刷新、保存或网络请求。\n"
            .write(to: directory.appendingPathComponent("live-transition.txt"), atomically: true, encoding: .utf8)
    }

    private static func capture<V: View>(_ view: V, at path: URL) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark)
            .frame(width: 640, height: 620).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 620)
        let window = NSWindow(contentRect: host.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "OpsSalePhaseSnapshot", code: 1) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: path)
    }
}
