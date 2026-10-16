import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import ItemManager

@MainActor
final class ShopCatalogPurchaseBatchSelectionTests: XCTestCase {
    private func series(_ id: String = "series", batches: [CatalogReservationBatch]? = nil) -> CatalogSeries {
        CatalogSeries(id: id, shopID: "shop", name: "购买批次系列", reservationBatches: batches)
    }

    func testUnpartitionedProductsContinueWithoutAnyExtraChoice() {
        let selection = ShopCatalogPurchaseBatchSelection()
        XCTAssertFalse(selection.requiresSelection(for: [series()]))
        XCTAssertTrue(selection.canConfirm(for: [series()]))
        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }

    func testGroupAndBatchNamesRequireSelectionButNoSeparateContinueStep() {
        let required = [series(batches: [.init(id: "group", name: "先行团"), .init(id: "p2", name: "2P")])]
        var selection = ShopCatalogPurchaseBatchSelection()
        XCTAssertTrue(selection.requiresSelection(for: required))
        XCTAssertFalse(selection.canConfirm(for: required))
        selection.selectedIDs["series"] = "p2"
        XCTAssertTrue(selection.canConfirm(for: required))
        XCTAssertFalse(selection.requiresSelection(for: required), "选完即可在同页确认入橱")
        XCTAssertEqual(required[0].reservationBatches?.map(\.name), ["先行团", "2P"], "运营实际批次名称保留")
    }

    func testOnlyOneConfiguredBatchStillRequiresExplicitChoice() {
        let required = [series(batches: [.init(id: "only", name: "1P")])]
        var selection = ShopCatalogPurchaseBatchSelection()
        XCTAssertEqual(required[0].reservationBatch(id: nil)?.id, "only")
        XCTAssertTrue(selection.requiresSelection(for: required))
        selection.selectedIDs["series"] = "only"
        XCTAssertTrue(selection.canConfirm(for: required))
    }

    func testMultipleSeriesCannotReuseAnotherSeriesChoiceEvenWithSameBatchIDs() {
        let required = [series("a", batches: [.init(id: "1", name: "一团")]),
                        series("b", batches: [.init(id: "1", name: "1P"), .init(id: "2", name: "2P")])]
        var selection = ShopCatalogPurchaseBatchSelection()
        selection.selectedIDs["a"] = "1"
        XCTAssertFalse(selection.canConfirm(for: required))
        selection.selectedIDs["b"] = "2"
        XCTAssertTrue(selection.canConfirm(for: required))
        XCTAssertEqual(selection.selectedIDs, ["a": "1", "b": "2"])
    }

    func testChangingOrClearingChoiceUpdatesReadinessImmediately() {
        let required = [series(batches: [.init(id: "p1", name: "1P"), .init(id: "p2", name: "2P")])]
        var selection = ShopCatalogPurchaseBatchSelection()
        selection.selectedIDs["series"] = "p1"
        XCTAssertTrue(selection.canConfirm(for: required))
        selection.selectedIDs["series"] = "p2"
        XCTAssertTrue(selection.canConfirm(for: required))
        selection.selectedIDs["series"] = nil
        XCTAssertTrue(selection.requiresSelection(for: required))
    }

    func testRemovedBatchDoesNotFallBackToRemainingBatchAndNewSeriesMustBeChosen() {
        var current = series(batches: [.init(id: "p1", name: "1P"), .init(id: "p2", name: "2P")])
        var selection = ShopCatalogPurchaseBatchSelection()
        selection.selectedIDs[current.id] = "p2"
        XCTAssertTrue(selection.canConfirm(for: [current]))
        current.reservationBatches?.removeLast()
        XCTAssertTrue(selection.requiresSelection(for: [current]))
        selection.selectedIDs[current.id] = "p1"
        XCTAssertTrue(selection.canConfirm(for: [current]))
        let additional = series("additional", batches: [.init(id: "first", name: "一团")])
        XCTAssertTrue(selection.requiresSelection(for: [current, additional]))
        XCTAssertFalse(selection.requiresSelection(for: [current]), "取消小物不影响已选主衣物批次")
    }

    func testDateOrNameUpdateUsesStableSelectedIDWithoutSwitchingToAnotherBatch() {
        var current = series(batches: [.init(id: "p1", name: "1P"), .init(id: "p2", name: "2P")])
        var selection = ShopCatalogPurchaseBatchSelection()
        selection.selectedIDs[current.id] = "p2"
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        current.reservationBatches?[1].name = "第二批（更名）"
        current.reservationBatches?[1].balanceDueKind = .exact
        current.reservationBatches?[1].balanceDueAt = date
        XCTAssertFalse(selection.requiresSelection(for: [current]))
        XCTAssertEqual(current.paymentSchedule(batchID: selection.selectedIDs[current.id])?.balanceDueAt, date)
    }

    func testRequirementsDeduplicateOnlyIncludedSeriesAndKeepConfiguredOrder() {
        let first = series("a", batches: [.init(id: "a1", name: "一团")])
        let second = series("b", batches: [.init(id: "b1", name: "1P")])
        XCTAssertEqual(ShopCatalogPurchaseBatchSelection.requirements(in: [second, first, second, series()]).map(\.id), ["b", "a"])
    }

    func testRenderInlinePickerAndCompactScheduleDisclosure() async throws {
        let configured = series(batches: [
            .init(id: "group", name: "先行团", balanceDueKind: .approximate,
                  balanceDueText: "2026年圣诞节前", balanceDueEndText: "一个月"),
            .init(id: "p2", name: "非圣诞先行团", balanceDueKind: .approximate,
                  balanceDueText: "2027年2月中上旬", balanceDueEndText: "一个月"),
            .init(id: "pending", name: "第三批")
        ])
        for selected: String? in [nil, "p2"] {
            try await capture(NavigationStack {
                Form {
                    Section("加入方式") { Text("加入心愿尾款（定金＋尾款）") }
                    Section { ShopCatalogPurchaseBatchPicker(series: configured, selectedID: .constant(selected)) }
                    Section { Text("请选择主衣物") }
                }.navigationTitle("加入少女衣橱")
            }, name: selected == nil ? "inline-batch-unselected" : "inline-batch-selected")
        }
        try await capture(NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("系列详情").font(.title2)
                    ShopCatalogSeriesScheduleDisclosure(series: configured)
                    Text("商品列表")
                }.padding(16)
            }
        }, name: "schedule-disclosure-collapsed")
        try await capture(NavigationStack {
            ScrollView { ShopCatalogSeriesScheduleDetails(series: configured).padding(16) }
                .navigationTitle("团次与尾款")
        }, name: "schedule-expanded-details")
    }

    private func capture<Content: View>(_ content: Content, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.overrideUserInterfaceStyle = .light
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let host = UIHostingController(rootView: content.environment(ThemeManager.shared).environment(\.colorScheme, .light))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name + ".png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testActualMergeEntryRendersPublishedGroupsOverStaleLocalSeries() async throws {
        ShopCatalogStorage.useTemporaryForTesting()
        defer { ShopCatalogStorage.restoreDefaultForTesting() }
        let id = "series-ops-19AAE8DD"
        let productID = "prod-ops-C921A336"
        let local = CatalogSeries(id: id, shopID: "shop", name: "小狗仪仗队",
            balanceDueKind: .approximate, balanceDueText: "先行团圣诞节前，另团次年2月")
        try ShopCatalogDraftStore.replaceOverlay(with: ShopCatalog(series: [local]))
        var online = local
        online.reservationBatches = [
            .init(id: "early", name: "先行团", balanceDueKind: .approximate,
                  balanceDueText: "2026年圣诞节前", balanceDueEndText: "一个月"),
            .init(id: "later", name: "非圣诞先行团", balanceDueKind: .approximate,
                  balanceDueText: "2027年2月中上旬", balanceDueEndText: "一个月")]
        let store = ShopCatalogStore(baseCatalog: ShopCatalog())
        store.reloadWithOverlay()
        store.installRemoteCatalog(ShopCatalog(shops: [.init(id: "shop", name: "夜鸢 iris de nuit")],
            series: [online], products: [.init(id: productID, shopID: "shop", seriesID: id,
                name: "红色托胸贴布绣Jsk", category: "JSK")],
            saleEvents: [.init(id: "sale", productID: productID, type: .reservation,
                price: 478, deposit: 95, balance: 383, currency: .cny)]))
        XCTAssertNil(store.series(id: id)?.reservationBatches)
        let purchase = try XCTUnwrap(store.seriesForPurchase(id: id))
        XCTAssertTrue(ShopCatalogPurchaseBatchSelection().requiresSelection(for: [purchase]))
        let container = try ModelContainer(for: Schema([Clothing.self, Brand.self, Tag.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.overrideUserInterfaceStyle = .light
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let host = UIHostingController(rootView: NavigationStack {
            ShopCatalogWardrobeMergeView(selectedProductIDs: [productID], store: store, onFinished: { _ in
                XCTFail("选择团次不应产生入橱记录")
            })
        }.environment(ThemeManager.shared).modelContainer(container))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "actual-merge-inline-batches-over-local-copy.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try await capture(ShopCatalogSeriesMenuView(store: store, seriesID: id).modelContainer(container),
            name: "actual-series-compact-schedule")
        try await capture(NavigationStack {
            ShopCatalogProductView(productID: productID, store: store)
        }.modelContainer(container), name: "actual-product-compact-schedule")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Clothing>()), 0)
    }
}
