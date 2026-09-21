//
//  ShopCatalogStorageIsolationTests.swift
//  ItemManagerTests
//
//  回归防线（2026-09-21 事故）：
//  事故根因 = 多个测试套件在 tearDown 里删除宿主 App 真实沙盒中的
//  shop-catalog-override.json / shop-catalog-drafts.json / shop-catalog-batches.json，
//  导致用户发布的系列在每轮回归测试后被清掉（「发布的系列刷新后消失」）。
//  修复 = ShopCatalogStorage.useTemporaryForTesting() 全量重定向到临时目录。
//  本文件验证：注入生效、发布只写临时目录、生产目录零触碰、还原后路径正确。
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogStorageIsolationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
    }

    override func tearDown() {
        ShopCatalogStorage.restoreDefaultForTesting()
        CreatorAccess.setTestOverride(nil)
        super.tearDown()
    }

    // MARK: 注入生效

    func testOverlayAndDraftURLsRedirectToTemporaryWhenOverridden() {
        XCTAssertTrue(ShopCatalogStorage.isTestOverridden)
        XCTAssertEqual(ShopCatalogDraftStore.overlayURL.deletingLastPathComponent(),
                       ShopCatalogStorage.directory)
        XCTAssertTrue(ShopCatalogDraftStore.overlayURL.path.contains("ShopCatalogTests-"),
                      "覆盖层应落在临时目录，实际：\(ShopCatalogDraftStore.overlayURL.path)")
        XCTAssertFalse(ShopCatalogDraftStore.overlayURL.path.contains("Application Support"))
        XCTAssertFalse(ShopCatalogImageStore.directory.path.contains("Application Support"),
                       "图片目录同样必须被重定向")
    }

    // MARK: 发布只写临时目录，生产目录零触碰

    func testPublishWritesOnlyToTestDirectoryProductionUntouched() throws {
        let prodDir = ShopCatalogStorage.productionDirectory
        let prodBefore = (try? FileManager.default.contentsOfDirectory(atPath: prodDir.path)) ?? []

        let store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        let draftStore = ShopCatalogDraftStore.shared

        var draft = CatalogProductDraft()
        draft.name = "隔离回归款"
        draft.saleKind = .stock
        draft.price = 199
        draft.newShopName = "隔离回归店家"
        draft.newSeriesName = "隔离回归系列"
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        _ = try draftStore.publish(d, store: store)

        // 覆盖层 + 草稿都落在临时目录
        XCTAssertTrue(FileManager.default.fileExists(atPath: ShopCatalogDraftStore.overlayURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ShopCatalogStorage.directory
            .appendingPathComponent("shop-catalog-drafts.json").path))

        // 生产目录内容零变化（不新增、不删除）
        let prodAfter = (try? FileManager.default.contentsOfDirectory(atPath: prodDir.path)) ?? []
        XCTAssertEqual(prodAfter, prodBefore, "发布不得改动生产沙盒中的任何文件")
    }

    // MARK: 还原行为

    func testRestoreRevertsToProductionAndRemovesTempDirectory() {
        let tempURL = ShopCatalogStorage.directory
        XCTAssertTrue(tempURL.path.contains("ShopCatalogTests-"))
        ShopCatalogStorage.restoreDefaultForTesting()
        XCTAssertFalse(ShopCatalogStorage.isTestOverridden)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "临时目录应在还原时被整体清理")
        // 供 tearDown 再次还原不误伤：重新注入
        _ = ShopCatalogStorage.useTemporaryForTesting()
    }

    func testEachInjectionGetsIndependentTemporaryDirectory() {
        let first = ShopCatalogStorage.directory
        ShopCatalogStorage.restoreDefaultForTesting()
        ShopCatalogStorage.useTemporaryForTesting()
        let second = ShopCatalogStorage.directory
        XCTAssertNotEqual(first, second, "两次注入应是独立临时目录，避免跨套件串扰")
    }
}
