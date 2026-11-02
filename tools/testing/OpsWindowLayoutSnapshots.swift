import AppKit
import SwiftData
import SwiftUI
import PinkHouseOpsCore
@testable import PinkHouseOps

/// 固定窗口内容尺寸的实际 AppKit 布局验收，不修改日常草稿。
@MainActor
enum OpsWindowLayoutSnapshots {
    static func run(into directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let workspace = OpsWorkspace(context: store.mainContext)
        let shop = workspace.addShopReturningID(name: "布局验收店家")!
        let series = workspace.addSeriesReturningID(shopID: shop, name: "长名称系列与多类型布局验收", year: 2026, month: 11, season: nil)!
        _ = workspace.addProductReturningID(shopID: shop, seriesID: series, name: "款式名称较长的商品", category: "OP")
        workspace.seriesEntry = OpsSeriesEntryDraft(shopID: shop, seriesID: series,
            typeEntries: (0..<16).map { index in
                OpsSeriesTypeEntry(category: index % 2 == 0 ? "OP" : "JSK", designName: "验收款式\(index)",
                    chartColumnsText: CatalogChartTemplate.SizeChart.columnsText,
                    chartRowsText: CatalogChartTemplate.SizeChart.rowsText, stockPriceText: "200",
                    colors: [OpsSeriesColorSKU(name: "粉色", selectedSizes: CatalogChartTemplate.SizeChart.sizeLabels)])
            })
        var progress = OpsCatalogEditProgress(requestID: "layout-fixture", revision: 1)
        progress.confirm(environment: "development", releaseSeq: 1)
        progress.confirm(environment: "production", releaseSeq: 2)
        workspace.catalogEditSyncProgress = progress
        for size in [NSSize(width: 980, height: 620), NSSize(width: 1120, height: 720), NSSize(width: 1600, height: 900)] {
            try capture(OpsMainView(workspace: workspace, initialWizardStep: .typeEntries).modelContainer(store),
                        size: size, name: "wizard-\(Int(size.width))x\(Int(size.height))", directory: directory, checkNavigation: true)
        }
        for section in [OpsSection.catalog, .products, .preview, .publishQueue] {
            try capture(OpsMainView(workspace: workspace, initialSection: section).modelContainer(store),
                        size: NSSize(width: 980, height: 620), name: section.rawValue + "-980x620", directory: directory)
        }
        progress.fail(String(repeating: "很长的同步失败详情。", count: 50))
        workspace.catalogEditSyncProgress = progress
        try capture(OpsMainView(workspace: workspace, initialWizardStep: .typeEntries).modelContainer(store),
                    size: NSSize(width: 980, height: 620), name: "wizard-long-status-980x620", directory: directory, checkNavigation: true)
        try capture(OpsFormFrame(title: "较小表单窗口", subtitle: "内容可以滚动，取消与保存必须保留。", width: 560, contentHeight: 440,
                    content: { ForEach(0..<30) { Text("表单内容 \($0)") } }, onCancel: {}, onConfirm: { false }),
                    size: NSSize(width: 560, height: 400), name: "form-560x400", directory: directory)
        try capture(OpsColorImagesSheet(workspace: workspace, entry: workspace.seriesEntry.typeEntries[0]),
                    size: NSSize(width: 760, height: 440), name: "color-images-760x440", directory: directory)
    }

    private static func capture<V: View>(_ view: V, size: NSSize, name: String, directory: URL, checkNavigation: Bool = false) throws {
        OpsWindowLayoutDiagnostics.isEnabled = checkNavigation
        OpsWindowLayoutDiagnostics.frames = [:]
        defer { OpsWindowLayoutDiagnostics.isEnabled = false }
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark).frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw NSError(domain: "OpsWindowLayout", code: 1) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        if checkNavigation {
            let frames = OpsWindowLayoutDiagnostics.frames
            let bounds = CGRect(origin: .zero, size: size)
            let failures = ["ops.wizard.previous", "ops.wizard.next"].filter { identifier in
                guard let frame = frames[identifier] else { return true }
                return frame.width <= 0 || frame.height <= 0 || !bounds.contains(frame)
            }
            let report = "\(name) frames=\(frames) failures=\(failures) bounds=\(bounds)\n"
            try report.write(to: directory.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
            if !failures.isEmpty { throw NSError(domain: "OpsWindowLayout", code: 2, userInfo: [NSLocalizedDescriptionKey: report]) }
        }

    }
}
