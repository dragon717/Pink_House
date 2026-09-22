//
//  ShopCatalogPriceFlowSeparationTests.swift
//  ItemManagerTests
//
//  价格双流程拆分（2026-09-22）行为契约：
//
//   A. 价格修正 correctCurrentPrice
//      1. 覆盖当前价：展示值变为修正值
//      2. 不产生历史记录：saleEvents 数量与内容完全不变
//      3. 再次修正 = 再次覆盖，只留最新状态（不累积）
//      4. 完整快照：弹窗预填当前生效值，未改字段带原值提交
//      5. 留空 = 清除该价格（不跳过、不回退历史）；全空 = 清除全部，合法
//      6. 定金 + 尾款 ≠ 预约价 / 价格 ≤ 0 / 清预约价却留定金尾款 → 校验拦截
//      7. 撤销修正：回到历史推导值，销售记录一条不动
//
//   B. 追加销售记录 appendSaleRecord
//      7. append-only：多批次记录按时间排序共存，既有记录不可变
//      8. 时间维度：startAt / batchLabel / recordedAt 正确落库
//      9. 重复提交防护：同商品 / 同类型 / 同价格 / 同批次日 → 抛错且不新增
//     10. 不同批次日 / 不同价格视为不同记录，可正常追加
//     11. 价格 ≤ 0 → 拦截
//
//   C. 两条流程互不干扰
//     12. 修正后再追加：修正值保持生效，历史记录只增不减
//     13. 追加后修正：历史记录仍完整保留，只是展示值被覆盖
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogPriceFlowSeparationTests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        CreatorAccess.setTestOverride(.creator)
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    // MARK: 工具

    private func publish(name: String, reservation: Decimal? = nil,
                        deposit: Decimal? = nil, stock: Decimal? = nil,
                        startAt: Date? = nil) throws -> CatalogProduct {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.newShopName = "\(name)店家"
        draft.newSeriesName = "\(name)系列"
        draft.price = reservation.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
        draft.deposit = deposit.map { NSDecimalNumber(decimal: $0).doubleValue }
        draft.stockPrice = stock.map { NSDecimalNumber(decimal: $0).doubleValue }
        draft.startAt = startAt
        let draftStore = ShopCatalogDraftStore.shared
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        _ = try draftStore.publish(d, store: store)
        return try XCTUnwrap(store.product(named: name))
    }

    private func day(_ offsetDays: Int) -> Date {
        Date(timeIntervalSinceNow: Double(offsetDays) * 86400)
    }

    // MARK: A. 价格修正

    func testCorrectionOverwritesCurrentPriceWithoutHistory() throws {
        let product = try publish(name: "修正覆盖款", reservation: 300, deposit: 100, stock: 380)
        let beforeEvents = store.saleEvents(forProduct: product.id)
        XCTAssertFalse(beforeEvents.isEmpty)

        // 修正弹窗按完整快照提交：想保留的字段带原值，只改现货价
        try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: 300, stockPrice: 420,
            deposit: 100, balance: 200)
        store.reloadWithOverlay()

        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertEqual(archive.currentStockPrice, 420, "修正后展示最新现货价")
        XCTAssertEqual(archive.currentReservationPrice, 300, "预填原值的字段保持不变")
        XCTAssertTrue(archive.isCorrected)

        // 硬约束：修正不产生任何历史记录
        let afterEvents = store.saleEvents(forProduct: product.id)
        XCTAssertEqual(afterEvents.count, beforeEvents.count, "修正不得新增销售记录")
        XCTAssertEqual(Set(afterEvents.map(\.id)), Set(beforeEvents.map(\.id)), "既有记录一条都不能被改写")
    }

    func testSecondCorrectionKeepsOnlyLatestState() throws {
        let product = try publish(name: "多次修正款", stock: 100)

        try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: nil, stockPrice: 200,
            deposit: nil, balance: nil)
        store.reloadWithOverlay()
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentStockPrice, 200)

        try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: nil, stockPrice: 260,
            deposit: nil, balance: nil)
        store.reloadWithOverlay()
        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertEqual(archive.currentStockPrice, 260, "只保留最新状态，不累积")
        XCTAssertEqual(store.saleEvents(forProduct: product.id).count, 1, "仍然只有发布时的那条记录")
    }

    func testCorrectionIsFullSnapshotOfCurrentPrices() throws {
        let product = try publish(name: "快照修正款", reservation: 500, deposit: 150, stock: 600)
        // 完整快照提交：四个字段一起给，各自对号入座
        try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: 500, stockPrice: 600,
            deposit: 120, balance: 380)
        store.reloadWithOverlay()

        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertEqual(archive.currentDeposit, 120)
        XCTAssertEqual(archive.currentBalance, 380)
        XCTAssertEqual(archive.currentStockPrice, 600, "未改字段按预填原值保留")
        XCTAssertEqual(archive.currentReservationPrice, 500)
    }

    // MARK: A2. 留空 = 清除（2026-09-22 语义调整）

    func testEmptySubmissionClearsPricesInsteadOfSkipping() throws {
        let product = try publish(name: "留空清除款", reservation: 300, deposit: 100, stock: 380)
        let beforeEvents = store.saleEvents(forProduct: product.id)

        // 全部留空提交 = 清除全部当前价格（不再抛 noChange、不再跳过）
        try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: nil, stockPrice: nil,
            deposit: nil, balance: nil)
        store.reloadWithOverlay()

        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertTrue(archive.isCorrected, "全清也是一次有效修正")
        XCTAssertNil(archive.currentReservationPrice, "预约价应被清除而不是回退历史")
        XCTAssertNil(archive.currentStockPrice, "现货价应被清除而不是回退历史")
        XCTAssertNil(archive.currentDeposit)
        XCTAssertNil(archive.currentBalance)

        // 清除不动历史记录
        let afterEvents = store.saleEvents(forProduct: product.id)
        XCTAssertEqual(Set(afterEvents.map(\.id)), Set(beforeEvents.map(\.id)))
    }

    func testClearingSinglePriceKeepsOtherSubmittedValues() throws {
        let product = try publish(name: "单清现货款", reservation: 300, deposit: 100, stock: 380)
        // 只清现货价：预约价/定金/尾款按预填原值一起提交
        try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: 300, stockPrice: nil,
            deposit: 100, balance: 200)
        store.reloadWithOverlay()

        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertNil(archive.currentStockPrice, "留空的现货价应被清除")
        XCTAssertEqual(archive.currentReservationPrice, 300)
        XCTAssertEqual(archive.currentDeposit, 100)
        XCTAssertEqual(archive.currentBalance, 200)
    }

    func testClearingReservationRequiresClearingDepositBalance() throws {
        let product = try publish(name: "清预约留定金款", reservation: 400, deposit: 100)
        XCTAssertThrowsError(try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: nil, stockPrice: 300,
            deposit: 100, balance: nil)) { error in
                guard case ShopCatalogPriceEditError.depositBalanceMismatch = error else {
                    return XCTFail("应抛 depositBalanceMismatch，实际：\(error)")
                }
                XCTAssertTrue(error.localizedDescription.contains("一并留空"),
                              "提示必须可读：\(error.localizedDescription)")
            }
    }

    func testCorrectionRejectsNonPositivePrice() throws {
        let product = try publish(name: "非法修正款", stock: 100)
        XCTAssertThrowsError(try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: nil, stockPrice: 0,
            deposit: nil, balance: nil)) { error in
                guard case ShopCatalogPriceEditError.invalidPrice = error else {
                    return XCTFail("应抛 invalidPrice，实际：\(error)")
                }
            }
    }

    func testCorrectionRejectsMismatchedDepositBalance() throws {
        let product = try publish(name: "对账失败款", reservation: 400, deposit: 100)
        XCTAssertThrowsError(try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: 400, stockPrice: nil,
            deposit: 100, balance: 999)) { error in
                guard case ShopCatalogPriceEditError.depositBalanceMismatch = error else {
                    return XCTFail("应抛 depositBalanceMismatch，实际：\(error)")
                }
            }
    }

    func testClearingCorrectionFallsBackToHistory() throws {
        let product = try publish(name: "撤销修正款", stock: 320)
        try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: nil, stockPrice: 999,
            deposit: nil, balance: nil)
        store.reloadWithOverlay()
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentStockPrice, 999)

        let before = store.saleEvents(forProduct: product.id).count
        try ShopCatalogDraftStore.clearPriceCorrection(productID: product.id)
        store.reloadWithOverlay()

        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertFalse(archive.isCorrected)
        XCTAssertEqual(archive.currentStockPrice, 320, "撤销后回到历史推导值")
        XCTAssertEqual(store.saleEvents(forProduct: product.id).count, before, "撤销不动销售记录")
    }

    // MARK: B. 追加销售记录

    func testAppendOnlyKeepsAllRecordsSortedByTime() throws {
        let product = try publish(name: "再贩多批次款", reservation: 400, deposit: 100,
                                  stock: 480, startAt: day(-800))

        try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 520,
            deposit: nil, balance: nil, startAt: day(-400),
            endAt: nil, batchLabel: "2024 再贩第一批")
        try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 560,
            deposit: nil, balance: nil, startAt: day(-30),
            endAt: nil, batchLabel: "2025 再贩第二批")
        store.reloadWithOverlay()

        let history = store.saleHistory(forProduct: product.id)
        XCTAssertGreaterThanOrEqual(history.count, 3, "同一商品保留多条记录")
        // 时间倒序：最近的批次排在最前
        let dates = history.compactMap(\.startAt)
        XCTAssertEqual(dates, dates.sorted(by: >), "历史必须按批次时间倒序")

        let rereleases = history.filter { $0.type == .rerelease }
        XCTAssertEqual(rereleases.count, 2)
        XCTAssertEqual(rereleases.first?.batchLabel, "2025 再贩第二批")
        XCTAssertEqual(rereleases.first?.price, 560)
        XCTAssertNotNil(rereleases.first?.recordedAt, "追加记录必须带写入时间")

        // 不可变：首发的预约/现货记录仍在
        XCTAssertTrue(history.contains { $0.type == .reservation && $0.price == 400 })
        XCTAssertTrue(history.contains { $0.type == .stock && $0.price == 480 })
    }

    func testDuplicateAppendIsRejected() throws {
        let product = try publish(name: "重复提交款", stock: 100)
        let date = day(-10)

        try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 333,
            deposit: nil, balance: nil, startAt: date,
            endAt: nil, batchLabel: "同批次")
        store.reloadWithOverlay()
        let afterFirst = store.saleEvents(forProduct: product.id).count

        // 完全相同的业务维度再提交一次 → 拦截
        XCTAssertThrowsError(try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 333,
            deposit: nil, balance: nil, startAt: date,
            endAt: nil, batchLabel: "换个批次名也没用")) { error in
                guard case ShopCatalogPriceEditError.duplicateRecord = error else {
                    return XCTFail("应抛 duplicateRecord，实际：\(error)")
                }
                XCTAssertTrue(error.localizedDescription.contains("重复提交"),
                              "提示必须可读：\(error.localizedDescription)")
            }
        store.reloadWithOverlay()
        XCTAssertEqual(store.saleEvents(forProduct: product.id).count, afterFirst,
                      "重复提交不得写出第二条记录")
    }

    func testDifferentBatchOrPriceIsNotDuplicate() throws {
        let product = try publish(name: "不同批次款", stock: 100)
        try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 333,
            deposit: nil, balance: nil, startAt: day(-10),
            endAt: nil, batchLabel: "第一批")

        // 同价不同批次日 → 不同记录
        try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 333,
            deposit: nil, balance: nil, startAt: day(-5),
            endAt: nil, batchLabel: "第二批")
        // 同批次日不同价 → 不同记录
        try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 388,
            deposit: nil, balance: nil, startAt: day(-10),
            endAt: nil, batchLabel: "第一批补录")
        store.reloadWithOverlay()

        let rereleases = store.saleEvents(forProduct: product.id).filter { $0.type == .rerelease }
        XCTAssertEqual(rereleases.count, 3)
    }

    func testAppendRejectsNonPositivePrice() throws {
        let product = try publish(name: "非法追加款", stock: 100)
        XCTAssertThrowsError(try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 0,
            deposit: nil, balance: nil, startAt: day(-1),
            endAt: nil, batchLabel: nil)) { error in
                guard case ShopCatalogPriceEditError.invalidPrice = error else {
                    return XCTFail("应抛 invalidPrice，实际：\(error)")
                }
            }
    }

    func testAppendFingerprintIgnoresBatchLabelAndRecordedAt() throws {
        let base = CatalogSaleEvent(id: "a", productID: "p", type: .rerelease,
                                    price: 100, deposit: nil, balance: nil,
                                    startAt: day(-3), endAt: nil,
                                    batchLabel: "批次A", recordedAt: Date())
        var variant = base
        variant.id = "b"
        variant.batchLabel = "批次B"
        variant.recordedAt = Date(timeIntervalSinceNow: 3600)
        XCTAssertEqual(base.appendFingerprint, variant.appendFingerprint,
                      "批次名与写入时间不参与去重判定")

        var otherDay = base
        otherDay.startAt = day(-2)
        XCTAssertNotEqual(base.appendFingerprint, otherDay.appendFingerprint, "批次日不同 = 不同记录")
    }

    // MARK: C. 两条流程互不干扰

    func testCorrectionThenAppendKeepsBothIntact() throws {
        let product = try publish(name: "先修正后追加款", reservation: 400, deposit: 100, stock: 480)
        // 完整快照：预约价/定金/尾款带原值，只改现货价
        try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: 400, stockPrice: 520,
            deposit: 100, balance: 300)
        store.reloadWithOverlay()

        let beforeAppend = store.saleEvents(forProduct: product.id).count
        try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 450,
            deposit: nil, balance: nil, startAt: day(-20),
            endAt: nil, batchLabel: "再贩批次")
        store.reloadWithOverlay()

        XCTAssertEqual(store.saleEvents(forProduct: product.id).count, beforeAppend + 1)
        // 修正值仍然生效（追加不回退修正），快照里带原值的字段也保持
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentStockPrice, 520)
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentReservationPrice, 400)
    }

    func testAppendThenCorrectionKeepsHistoryIntact() throws {
        let product = try publish(name: "先追加后修正款", stock: 300)
        try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .rerelease, price: 360,
            deposit: nil, balance: nil, startAt: day(-100),
            endAt: nil, batchLabel: "往期再贩")
        store.reloadWithOverlay()
        let historyBefore = Set(store.saleEvents(forProduct: product.id).map(\.id))

        try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: nil, stockPrice: 399,
            deposit: nil, balance: nil)
        store.reloadWithOverlay()

        let historyAfter = Set(store.saleEvents(forProduct: product.id).map(\.id))
        XCTAssertEqual(historyBefore, historyAfter, "修正不得影响任何历史记录")
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentStockPrice, 399)
        XCTAssertEqual(store.saleHistory(forProduct: product.id).count, 2)
    }

    func testProductDecodeWithoutPriceCorrectionIsBackwardCompatible() throws {
        let json = """
        {"id":"prod-old","shopID":"s","seriesID":"sr","name":"旧商品","category":"JSK"}
        """
        let product = try JSONDecoder().decode(CatalogProduct.self, from: Data(json.utf8))
        XCTAssertNil(product.priceCorrection, "旧 JSON 无 priceCorrection 键应自动置 nil")

        let archive = CatalogPriceArchive(events: [], correction: nil)
        XCTAssertFalse(archive.isCorrected)
        XCTAssertNil(archive.currentStockPrice)
    }
}
