import AppKit
import SwiftData
import SwiftUI
import PinkHouseOpsCore
@testable import PinkHouseOps

/// CLI-only visual fixtures; ephemeral stores and staged media, never a real publication.
@MainActor
enum OpsCatalogEditorSnapshots {
    static func run(into directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let workspace = OpsWorkspace(context: container.mainContext)
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }
        let source = directory.appendingPathComponent("fixture-logo.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32)!
        let pink = NSColor(calibratedRed: 0.8, green: 0.3, blue: 0.5, alpha: 1)
        for x in 0..<32 { for y in 0..<32 { bitmap.setColor(pink, atX: x, y: y) } }
        try bitmap.representation(using: .png, properties: [:])!.write(to: source)
        guard let assetID = workspace.importSingleImage(from: source),
              let shopID = workspace.addShopReturningID(name: "测试店家", aliases: ["Pink House"], logo: assetID),
              let seriesID = workspace.addSeriesReturningID(shopID: shopID, name: "测试系列", year: 2026, month: 9, season: nil) else {
            throw NSError(domain: "OpsSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: workspace.statusText ?? "fixture failed"])
        }
        _ = workspace.updateSeriesCover(seriesID: seriesID, assetID: assetID)
        try capture(OpsCatalogEditorView(workspace: workspace).modelContainer(container),
            size: NSSize(width: 1120, height: 780), at: directory.appendingPathComponent("series-list-with-cover.png"))
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        _ = workspace.updateSeriesSalePhase(id: seriesID, phase: nil,
            reservationStartAt: nil, reservationEndAt: nil, balanceDueKind: .exact,
            balanceDueText: nil, balanceDueAt: start, balanceDueEndAt: start.addingTimeInterval(86400 * 90))
        _ = workspace.saveDraft()
        try capture(ShopFormSheet(workspace: workspace, existingID: shopID, onSaved: { _ in })
            .modelContainer(container), size: NSSize(width: 460, height: 340),
            at: directory.appendingPathComponent("shop-logo-editor.png"))
        workspace.seriesEntry = OpsSeriesEntryDraft(createsNewShop: true,
            newShopName: "新店家", managesShopLogo: true, shopLogoReference: assetID, newSeriesName: "新系列")
        try capture(OpsSeriesWizardView(workspace: workspace).modelContainer(container),
            size: NSSize(width: 1040, height: 780), at: directory.appendingPathComponent("series-entry-shop-logo.png"))
        try capture(SeriesConfigSheet(workspace: workspace, seriesID: seriesID).modelContainer(container),
            size: NSSize(width: 640, height: 640), at: directory.appendingPathComponent("series-config-dates.png"))
        workspace.seriesEntry = OpsSeriesEntryDraft(shopID: shopID, seriesID: seriesID,
            typeEntries: [OpsSeriesTypeEntry(category: "JSK", designName: "问题款式", stockPriceText: "100",
                colors: (1...80).map { OpsSeriesColorSKU(name: "配色\($0)", imageAssetID: "missing-image-\($0)") })])
        let report = workspace.commitSeriesEntry()
        guard !report.allOK, workspace.lastError != nil else {
            throw NSError(domain: "OpsSnapshot", code: 3)
        }
        try capture(OpsMainView(workspace: workspace, initialWizardStep: .publish).modelContainer(container),
            size: NSSize(width: 1120, height: 780), at: directory.appendingPathComponent("series-submit-long-error.png"))
        workspace.clearError()
        if let productID = workspace.catalog.products.first?.id {
            try capture(OpsProductTablesSheet(workspace: workspace, productID: productID),
                size: NSSize(width: 680, height: 660), at: directory.appendingPathComponent("product-tables-missing.png"))
            _ = workspace.applyPriceCorrection(productID: productID, reservationPrice: 570,
                stockPrice: 699, deposit: 100, balance: 470, currency: .cny)
            _ = workspace.updateSeriesPriceChart(seriesID: seriesID, unit: "元",
                columns: ["预约价", "定金", "尾款"], rows: [.init(label: "JSK", values: ["570", "100", "470"])], sourceImages: [])
            _ = workspace.setSizeChart(productID: productID, unit: "cm", columns: ["胸围", "裙长"],
                rows: [.init(label: "S", values: ["88", "98"]), .init(label: "M", values: ["92", "100"])], sourceImage: nil)
            try capture(OpsProductTablesSheet(workspace: workspace, productID: productID),
                size: NSSize(width: 680, height: 660), at: directory.appendingPathComponent("product-tables-filled.png"))
            try capture(SizeChartFormSheet(workspace: workspace, productID: productID, syncOnSave: true),
                size: NSSize(width: 560, height: 520), at: directory.appendingPathComponent("product-size-supplement.png"))
            try capture(OpsSeriesPriceChartEditor(workspace: workspace, seriesID: seriesID),
                size: NSSize(width: 620, height: 580), at: directory.appendingPathComponent("series-price-supplement.png"))
        }
        workspace.seriesEntry = OpsSeriesEntryDraft(createsNewShop: true, newShopName: "完成店家",
            newSeriesName: "完成系列", typeEntries: [OpsSeriesTypeEntry(category: "JSK", designName: "完成款式",
                stockPriceText: "100", colors: [OpsSeriesColorSKU(name: "白色")])])
        try capture(OpsMainView(workspace: workspace, initialWizardStep: .publish).modelContainer(container),
            size: NSSize(width: 1120, height: 780), at: directory.appendingPathComponent("series-save-reset-to-first-step.png"),
            afterDisplay: { precondition(workspace.saveSeriesEntryToDraft().allOK) })
        try capture(OpsMainView(workspace: workspace, initialSection: .publishQueue).modelContainer(container),
            size: NSSize(width: 1120, height: 780), at: directory.appendingPathComponent("series-saved-in-publish-queue.png"))
        workspace.seriesEntry = OpsSeriesEntryDraft(createsNewShop: true, newShopName: "完成店家",
            newSeriesName: "第二个完成系列", typeEntries: [OpsSeriesTypeEntry(category: "JSK", designName: "第二个款式",
                stockPriceText: "200", colors: [OpsSeriesColorSKU(name: "粉色")])])
        precondition(workspace.saveSeriesEntryToDraft().allOK)
        let selectedIDs = Set(workspace.seriesPublishJobs().map(\.id))
        try capture(OpsSeriesPublishQueueView(workspace: workspace, selectedJobIDs: selectedIDs).modelContainer(container),
            size: NSSize(width: 880, height: 780), at: directory.appendingPathComponent("series-queue-multiple-selected.png"))
        // 新 workspace 模拟退出后重新打开，上传历史仍在，未点配图确认也可查看。
        let reopened = OpsWorkspace(context: ModelContext(container))
        reopened.catalogEditSyncQueue = OpsCatalogEditSyncQueue(
            pending: { nil }, isBusy: { false }, publish: { _ in .failed("fixture") }, finished: { _, _ in })
        let colorEntry = OpsSeriesTypeEntry(category: "JSK", designName: "历史素材复用",
            colors: [OpsSeriesColorSKU(name: "粉色"), OpsSeriesColorSKU(name: "蓝色")])
        reopened.seriesEntry.typeEntries = [colorEntry]
        try capture(OpsColorImagesSheet(workspace: reopened, entry: colorEntry).modelContainer(container),
            size: NSSize(width: 960, height: 650), at: directory.appendingPathComponent("color-upload-history-after-reopen.png"))
        workspace.seriesEntry.typeEntries = [OpsSeriesTypeEntry(category: "OP", designName: "纯色 OP",
            chartUnit: "cm", chartColumnsText: "胸围,裙长", chartRowsText: "S = 84, 92",
            reservationPriceText: "570", depositText: "100", balanceText: "470", stockPriceText: "699",
            colors: [.init(name: "白色", imageAssetID: assetID, selectedSizes: [])])]
        let styleID = workspace.seriesEntry.typeEntries[0].id
        try capture(OpsSeriesWizardTypeEntriesView(workspace: workspace).modelContainer(container),
            size: NSSize(width: 1040, height: 780), at: directory.appendingPathComponent("style-copy-option.png"),
            afterDisplay: { precondition(workspace.duplicateSeriesTypeEntry(id: styleID) != nil) })
        try verifyBackgroundSync(workspace: workspace, container: container, shopID: shopID, directory: directory)
    }

    private static func verifyBackgroundSync(workspace: OpsWorkspace, container: ModelContainer,
                                             shopID: String, directory: URL) throws {
        let model = OpsCloudSyncModel.shared
        let previous = (model.isSyncing, model.syncReport)
        let controller = OpsSyncProgressWindowController.shared
        defer {
            // 清除临时保存意图，再恢复 idle；fixture 绝不触发真实发布。
            workspace.draft?.catalogSyncRequestID = nil
            controller.runInBackground()
            model.isSyncing = previous.0
            model.syncReport = previous.1
        }
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else {
                throw NSError(domain: "OpsBackgroundSyncAcceptance", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        var report = OpsSyncReport(draftID: workspace.draft!.id,
                                   environment: model.targetEnvironment.rawValue)
        report.update(.download, state: .running, detail: "回读线上发布头", progress: 0.6)
        model.syncReport = report
        model.isSyncing = true // fixture status only; no network task
        controller.syncDidStart()
        guard let window = controller.window else {
            throw NSError(domain: "OpsBackgroundSyncAcceptance", code: 2)
        }
        try require(window.isVisible && window.isMovable && !window.isSheet && NSApp.modalWindow == nil,
                    "同步进度必须是可移动的非模态窗口")
        let origin = NSPoint(x: 120, y: 150)
        window.setFrameOrigin(origin)
        try require(window.frame.origin == origin, "同步窗口应能移开")
        controller.runInBackground()
        try require(!window.isVisible && model.isSyncing, "后台运行应隐藏窗口且保留同步状态")
        controller.syncDidStart()
        try require(!window.isVisible, "后续同步不应打断后台编辑")
        report.update(.download, state: .completed, detail: "目录和图片下载完成")
        report.update(.upload, state: .running, detail: "正在上传本地变更", progress: 0.4)
        model.syncReport = report
        controller.showProgress(activate: false)
        try require(window === controller.window && window.isVisible && window.frame.origin == origin,
                    "重新查看应复用原窗口并保留位置")
        try capture(OpsSyncProgressWindowContent(model: model, onBackground: controller.runInBackground),
                    size: NSSize(width: 620, height: 420),
                    at: directory.appendingPathComponent("sync-progress-background.png"))
        window.performClose(nil)
        try require(!window.isVisible && model.isSyncing && controller.runsInBackground,
                    "系统关闭按钮只收起进度，不结束同步")
        try require(workspace.updateShopProfile(id: shopID, name: "同步时继续编辑的店家",
                                               aliases: [], logo: workspace.catalog.shops.first?.logo),
                    "同步中应能继续编辑店家")
        try require(workspace.saveCatalogEditorChanges(), "同步中应能保存新的编辑")
        try require(workspace.draft?.catalogSyncRequestID != nil && model.isSyncing,
                    "新保存应保留待同步意图且不结束当前同步")
        try capture(OpsMainView(workspace: workspace, initialSection: .catalog).modelContainer(container),
                    size: NSSize(width: 1120, height: 780),
                    at: directory.appendingPathComponent("catalog-while-syncing.png"))
        try require(!window.isVisible, "回主页面编辑不应重新弹出同步窗口")
        try "通过：原生窗口可移动且非模态；后台运行和关闭均保留同步状态；重新查看保留位置；后台更新进度；同步中编辑保存排队；主页面不再出现进度遮罩。\n验证使用临时数据和模拟进度，不发送网络发布。\n"
            .write(to: directory.appendingPathComponent("background-sync-acceptance.txt"), atomically: true, encoding: .utf8)
    }

    private static func capture<V: View>(_ view: V, size: NSSize, at file: URL,
                                         afterDisplay: (() -> Void)? = nil) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light)
            .tint(Color(red: 0.8, green: 0.3, blue: 0.5))
            .frame(width: size.width, height: size.height).background(Color.white))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        if let afterDisplay {
            afterDisplay()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "OpsSnapshot", code: 2)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: file)
    }
}
