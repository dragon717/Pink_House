import AppKit
import SwiftData
import SwiftUI
import PinkHouseOpsCore
@testable import PinkHouseOps

/// 当前构建的团次上传页与检查页；临时存储，不发起网络发布。
@MainActor
enum OpsReservationBatchSnapshots {
    static func run(into directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let workspace = OpsWorkspace(context: container.mainContext)
        workspace.catalogEditSyncQueue = OpsCatalogEditSyncQueue(
            pending: { nil }, isBusy: { false }, publish: { _ in .failed("fixture") }, finished: { _, _ in })
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }
        guard let shopID = workspace.addShopReturningID(name: "团次示例店家"),
              let seriesID = workspace.addSeriesReturningID(shopID: shopID, name: "同款商品", year: 2026, month: 10, season: nil) else {
            throw NSError(domain: "ReservationBatchSnapshot", code: 1)
        }
        let start = Date(timeIntervalSince1970: 1_798_761_600) // 2027-01-01 UTC
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
        workspace.seriesEntry = OpsSeriesEntryDraft(shopID: shopID, seriesID: seriesID,
            reservationBatches: [
                .init(id: "early", name: "先行团", balanceDueKind: .approximate,
                    balanceDueText: "圣诞节前", balanceDueEndText: "一个月", balanceDueReferenceAt: reference),
                .init(id: "second", name: "二团", balanceDueKind: .approximate,
                    balanceDueText: "2月中旬", balanceDueEndText: "十五天", balanceDueReferenceAt: reference),
                .init(id: "third", name: "三团", balanceDueKind: .approximate,
                    balanceDueText: "3月下旬", balanceDueEndText: "十天", balanceDueReferenceAt: reference),
                .init(id: "exact", name: "具体日期示例", balanceDueKind: .exact,
                    balanceDueAt: start, balanceDueEndAt: start.addingTimeInterval(86400 * 7))],
            typeEntries: [OpsSeriesTypeEntry(category: "JSK", designName: "同款不同团",
                usesSizeChart: false, reservationPriceText: "570", depositText: "100", balanceText: "470",
                colors: [.init(name: "白色")])])
        try capture(OpsSeriesWizardView(workspace: workspace, initialStep: .seriesProfile).modelContainer(container),
            size: NSSize(width: 1040, height: 1900), at: directory.appendingPathComponent("upload-reservation-batches.png"))
        try capture(VStack(alignment: .leading, spacing: 12) {
            Text("预约团次与尾款时间").font(.headline)
            OpsReservationBatchEditor(batches: Binding(
                get: { workspace.seriesEntry.reservationBatches ?? [] },
                set: { workspace.seriesEntry.reservationBatches = $0 }))
        }.padding(20), size: NSSize(width: 650, height: 1650),
            at: directory.appendingPathComponent("approximate-tail-editor.png"))
        try capture(OpsSeriesWizardView(workspace: workspace, initialStep: .review).modelContainer(container),
            size: NSSize(width: 1040, height: 940), at: directory.appendingPathComponent("upload-reservation-batches-review.png"))
        _ = workspace.updateSeriesSalePhase(id: seriesID, phase: nil, reservationStartAt: nil,
            reservationEndAt: nil, balanceDueKind: nil, balanceDueText: nil, balanceDueAt: nil,
            balanceDueEndAt: nil, reservationBatches: workspace.seriesEntry.reservationBatches)
        workspace.draft?.catalogSyncRequestID = "fixture-not-sent"
        workspace.draft?.catalogSyncSeriesUpdatesJSON = Data("[]".utf8)
        workspace.draft?.catalogSyncError = "Development 已确认发布号 24；Production 网络连接失败"
        workspace.catalogEditSyncMessage = "本地已保存，自动同步未完成：Development 已确认发布号 24；Production 网络连接失败"
        try capture(SeriesConfigSheet(workspace: workspace, seriesID: seriesID).modelContainer(container),
            size: NSSize(width: 640, height: 640), at: directory.appendingPathComponent("series-sync-retry-entry.png"))
    }

    private static func capture<V: View>(_ view: V, size: NSSize, at file: URL) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height).background(Color.white))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "ReservationBatchSnapshot", code: 2)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ReservationBatchSnapshot", code: 3)
        }
        try data.write(to: file)
    }
}
