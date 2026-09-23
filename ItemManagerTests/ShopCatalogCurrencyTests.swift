//
//  ShopCatalogCurrencyTests.swift
//  ItemManagerTests
//
//  第三版收口 R02「打通金额与币种」回归防线
//
//  背景（旧实现的三个失效形态）：
//   1. 旧迁移把 `priceJPY / salePriceJPY / regularPriceJPY` 直接写进没有币种语义的
//      `price`，于是「¥24800」在商品档案里是 24800 元人民币、在衣橱草稿里被当成
//      24800 元——金额与币种脱钩；
//   2. 跨币种直接做减法：`现货 1580 CNY − 预约 24800 JPY` 会算出一个既不是日元
//      也不是人民币的「差价」；
//   3. 旧数据无币种字段时全局默认 CNY，把「来源不明」伪装成「确定是人民币」。
//
//  本套用例锁定口径：
//   · 源金额 + 源币种 → Catalog 展示 → 用户选择 → 个人记录金额 + 同币种；
//   · 日元不按人民币入库；来源不明标「币种待确认」；
//   · 不隐式换汇：跨币种不比较、不合计；
//   · 修价不是换币种，跨币种修正 / 追加必须被拒绝。
//
//  ⚠️ 测试隔离（2026-09-21 事故）：一律先 `ShopCatalogStorage.useTemporaryForTesting()`，
//     tearDown 还原；任何情况下不触碰宿主 App 真实沙盒。
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogCurrencyTests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        CreatorAccess.setTestOverride(.creator)
        ShopCatalogDraftStore.shared.loadDrafts()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    // MARK: 工具

    private func publish(name: String,
                        reservation: Decimal? = nil,
                        deposit: Decimal? = nil,
                        stock: Decimal? = nil,
                        currency: CatalogCurrency? = nil,
                        startAt: Date? = nil) throws -> CatalogProduct {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.newShopName = "\(name)店家"
        draft.newSeriesName = "\(name)系列"
        draft.price = reservation.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
        draft.deposit = deposit.map { NSDecimalNumber(decimal: $0).doubleValue }
        draft.stockPrice = stock.map { NSDecimalNumber(decimal: $0).doubleValue }
        draft.currency = currency
        draft.startAt = startAt
        let draftStore = ShopCatalogDraftStore.shared
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        _ = try draftStore.publish(d, store: store)
        // `correctCurrentPrice` / `appendSaleRecord` 走 `ShopCatalogStore.shared`
        // 解析既有币种，测试里必须让它读到同一份覆盖层，否则会误判为「来源不明」
        ShopCatalogStore.shared.reloadWithOverlay()
        return try XCTUnwrap(store.product(named: name))
    }

    private func day(_ offsetDays: Int) -> Date {
        Date(timeIntervalSinceNow: Double(offsetDays) * 86400)
    }

    // MARK: A. 币种枚举与展示

    func testCurrencyDisplayAndClothingCodeAlignment() {
        XCTAssertEqual(CatalogCurrency.cny.displayName, "人民币")
        XCTAssertEqual(CatalogCurrency.jpy.displayName, "日元")
        XCTAssertEqual(CatalogCurrency.unknown.displayName, "币种待确认")

        // unknown 必须能被识别出来，而不是被当成 CNY 静默放行
        XCTAssertTrue(CatalogCurrency.unknown.isUnknown)
        XCTAssertFalse(CatalogCurrency.jpy.isUnknown)

        // 与衣橱既有枚举对齐：JPY 必须落到 JPY，不能塌成 CNY
        XCTAssertEqual(CatalogCurrency.jpy.clothingCurrencyCode, "JPY")
        XCTAssertEqual(CatalogCurrency.cny.clothingCurrencyCode, "CNY")

        let jpy = CatalogMoney(amount: 24800, currency: .jpy)
        XCTAssertTrue(jpy.displayText.contains("JP¥"), "日元必须带可辨识符号：\(jpy.displayText)")
        let unknown = CatalogMoney(amount: 24800, currency: .unknown)
        XCTAssertTrue(unknown.displayText.contains("币种待确认"),
                      "来源不明必须显式提示，不能呈现成确定币种：\(unknown.displayText)")
        XCTAssertFalse(CatalogMoney(amount: 1, currency: .unknown)
            .isSameCurrency(as: CatalogMoney(amount: 1, currency: .cny)),
            "币种待确认不参与同币种判定")
    }

    // MARK: B. 旧数据兼容：缺币种 → 待确认，不是默认人民币

    func testLegacyEventWithoutCurrencyIsUnknownNotCNY() throws {
        let product = try publish(name: "旧数据无币种款", reservation: 300, stock: 380)
        let archive = store.priceArchive(forProduct: product.id)

        // 旧 JSON 没有 currency 键 → decodeIfPresent 兜底为 nil → 生效币种「待确认」
        XCTAssertEqual(archive.currentCurrency, .unknown,
                       "缺币种字段时必须落到「待确认」，不得默认 CNY")
        XCTAssertEqual(archive.reservation?.effectiveCurrency, .unknown)

        XCTAssertNil(archive.deltaUnavailableReason, "只有一侧有价格时本来就谈不上差价")
    }

    /// 两侧都是存量旧数据（都没标币种）→ 仍回答差价。
    /// 若一并拒绝，V1.1 的「预约‑现货差价」会对所有存量商品整体失效。
    func testLegacyBothSidesUnknownStillComputesDelta() {
        let reservation = CatalogSaleEvent(id: "ev-r", productID: "px", type: .reservation,
                                           price: 300, deposit: 100, balance: 200,
                                           startAt: day(-10), endAt: day(-1))
        let stock = CatalogSaleEvent(id: "ev-s", productID: "px", type: .stock,
                                     price: 380, deposit: nil, balance: nil,
                                     startAt: day(0), endAt: nil)
        let archive = CatalogPriceArchive(events: [reservation, stock], correction: nil)
        XCTAssertEqual(archive.currentCurrency, .unknown, "不声明币种，但也不冒充 CNY")
        XCTAssertFalse(archive.isMixedKnownUnknownCurrency)
        XCTAssertEqual(archive.stockOverReservationDelta, 80, "两侧同为未标注 → 仍可比较")
        XCTAssertNil(archive.deltaUnavailableReason)
    }

    /// 一侧明确、一侧待确认 → 真不知道该按哪种钱算，必须拒绝并说明
    func testMixedKnownAndUnknownCurrencyRefusesDelta() {
        let reservation = CatalogSaleEvent(id: "ev-r", productID: "px", type: .reservation,
                                           price: 24800, deposit: 5000, balance: 19800,
                                           startAt: day(-10), endAt: day(-1), currency: .jpy)
        let stock = CatalogSaleEvent(id: "ev-s", productID: "px", type: .stock,
                                     price: 1580, deposit: nil, balance: nil,
                                     startAt: day(0), endAt: nil)
        let archive = CatalogPriceArchive(events: [reservation, stock], correction: nil)
        XCTAssertTrue(archive.isMixedKnownUnknownCurrency)
        XCTAssertNil(archive.stockOverReservationDelta)
        XCTAssertNotNil(archive.deltaUnavailableReason)
    }

    func testCurrencyDecodesFromJSONAndRoundTrips() throws {
        var event = CatalogSaleEvent(id: "ev-x", productID: "p1", type: .reservation,
                                     price: 24800, deposit: 5000, balance: 19800,
                                     startAt: day(0), endAt: nil,
                                     currency: .jpy)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CatalogSaleEvent.self, from: data)
        XCTAssertEqual(decoded.currency, .jpy)
        XCTAssertEqual(decoded.effectiveCurrency, .jpy)

        // 旧 JSON（无 currency 键）必须能解码，不能整条记录丢失。
        // 样本由真实编码器产出后删掉 currency 键——手写残缺 JSON 测的只是样本本身。
        var legacy = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(legacy)
        legacy?.removeValue(forKey: "currency")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy!)
        let legacyEvent = try ShopCatalogJSONCoding.decoder()
            .decode(CatalogSaleEvent.self, from: legacyData)
        XCTAssertNil(legacyEvent.currency)
        XCTAssertEqual(legacyEvent.effectiveCurrency, .unknown, "旧数据不得被解读为确定币种")
        XCTAssertEqual(legacyEvent.price, 24800, "缺币种不得连带丢掉金额")
    }

    // MARK: C. 跨币种：不比较、不合计

    func testCrossCurrencyDeltaIsRefusedWithReason() throws {
        // 预约 24800 JPY / 现货 1580 CNY —— 旧实现会算出 -23220 的「差价」
        let product = try publish(name: "跨币种差价款", reservation: 24800, currency: .jpy)
        try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .stock, price: 1580,
            startAt: day(1), currency: .jpy)
        store.reloadWithOverlay()

        // 先验证同币种时差价可算（对照组）
        let sameCurrency = store.priceArchive(forProduct: product.id)
        XCTAssertFalse(sameCurrency.isCrossCurrency)
        XCTAssertEqual(sameCurrency.currentCurrency, .jpy)

        // 构造真实跨币种档案（JPY 预约 + CNY 现货）做纯逻辑断言
        let reservation = CatalogSaleEvent(id: "ev-r", productID: "px", type: .reservation,
                                           price: 24800, deposit: 5000, balance: 19800,
                                           startAt: day(-10), endAt: day(-1), currency: .jpy)
        let stock = CatalogSaleEvent(id: "ev-s", productID: "px", type: .stock,
                                     price: 1580, deposit: nil, balance: nil,
                                     startAt: day(0), endAt: nil, currency: .cny)
        let archive = CatalogPriceArchive(events: [reservation, stock], correction: nil)

        XCTAssertTrue(archive.isCrossCurrency, "日元预约 + 人民币现货必须识别为跨币种")
        XCTAssertNil(archive.stockOverReservationDelta, "跨币种不得直接相减")
        XCTAssertNil(archive.stockOverReservationDeltaPercent)
        XCTAssertEqual(archive.deltaUnavailableReason, "预约与现货币种不同，不计算差价")

        // 但两侧原始金额仍要能各自展示（不因为算不出差价就把价格也丢了）
        XCTAssertEqual(archive.currentReservationPrice, 24800)
        XCTAssertEqual(archive.currentStockPrice, 1580)
    }

    func testSameCurrencyDeltaStillComputes() {
        let reservation = CatalogSaleEvent(id: "ev-r", productID: "px", type: .reservation,
                                           price: 300, deposit: 100, balance: 200,
                                           startAt: day(-10), endAt: day(-1), currency: .cny)
        let stock = CatalogSaleEvent(id: "ev-s", productID: "px", type: .stock,
                                     price: 380, deposit: nil, balance: nil,
                                     startAt: day(0), endAt: nil, currency: .cny)
        let archive = CatalogPriceArchive(events: [reservation, stock], correction: nil)
        XCTAssertFalse(archive.isCrossCurrency)
        XCTAssertEqual(archive.stockOverReservationDelta, 80)
        XCTAssertNil(archive.deltaUnavailableReason)
    }

    // MARK: D. 写入侧的币种约束

    func testPublishCarriesCurrencyIntoEvents() throws {
        let product = try publish(name: "日元发布款", reservation: 24800, deposit: 5000,
                                  currency: .jpy)
        let events = store.saleEvents(forProduct: product.id)
        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.allSatisfy { $0.effectiveCurrency == .jpy },
                      "发布时必须把草稿币种带进销售事件：\(events.map(\.effectiveCurrency))")
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentCurrency, .jpy)
    }

    func testAppendSaleRecordInheritsExistingCurrency() throws {
        let product = try publish(name: "币种继承款", reservation: 24800, currency: .jpy)
        // 再贩记录不显式传币种 → 沿用商品既有币种，而不是塌成「待确认」或 CNY
        let event = try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .stock, price: 26000, startAt: day(30))
        XCTAssertEqual(event.effectiveCurrency, .jpy, "追加记录必须继承商品既有币种")
    }

    func testAppendSaleRecordFallsBackToUnknownWhenNoSource() throws {
        let product = try publish(name: "无来源币种款", reservation: 300)
        let event = try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .stock, price: 380, startAt: day(30))
        XCTAssertEqual(event.effectiveCurrency, .unknown,
                       "没有任何币种来源时必须标「待确认」，不得默认 CNY")
    }

    func testCrossCurrencyAppendIsRejected() throws {
        let product = try publish(name: "跨币种追加款", reservation: 24800, currency: .jpy)
        XCTAssertThrowsError(
            try ShopCatalogDraftStore.appendSaleRecord(
                productID: product.id, type: .stock, price: 1580,
                startAt: day(30), currency: .cny)
        ) { error in
            guard case ShopCatalogPriceEditError.crossCurrency = error else {
                return XCTFail("应抛跨币种错误，实际：\(error)")
            }
        }
        // 被拒绝后不得留下半条记录
        store.reloadWithOverlay()
        XCTAssertEqual(store.saleEvents(forProduct: product.id).count, 1)
    }

    func testCrossCurrencyCorrectionIsRejected() throws {
        let product = try publish(name: "跨币种修正款", reservation: 24800, currency: .jpy)
        XCTAssertThrowsError(
            try ShopCatalogDraftStore.correctCurrentPrice(
                productID: product.id, reservationPrice: 24800, stockPrice: 1580,
                deposit: 5000, balance: 19800, currency: .cny)
        ) { error in
            guard case ShopCatalogPriceEditError.crossCurrency = error else {
                return XCTFail("修价不是换币种，应抛跨币种错误，实际：\(error)")
            }
        }
    }

    func testSameCurrencyCorrectionKeepsCurrency() throws {
        let product = try publish(name: "同币种修正款", reservation: 24800, deposit: 5000,
                                  currency: .jpy)
        let correction = try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: 26000, stockPrice: nil,
            deposit: 6000, balance: 20000, currency: .jpy)
        XCTAssertEqual(correction.currency, .jpy)
        store.reloadWithOverlay()
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentCurrency, .jpy)
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentReservationPrice, 26000)
    }

    func testCorrectionOnUnknownCurrencyCanDeclareCurrency() throws {
        // 币种待确认的商品，允许在修正时把币种补明确（这是唯一合法的「改币种」入口）
        let product = try publish(name: "补币种款", reservation: 300)
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentCurrency, .unknown)

        _ = try ShopCatalogDraftStore.correctCurrentPrice(
            productID: product.id, reservationPrice: 24800, stockPrice: nil,
            deposit: nil, balance: nil, currency: .jpy)
        store.reloadWithOverlay()
        XCTAssertEqual(store.priceArchive(forProduct: product.id).currentCurrency, .jpy,
                       "待确认币种补齐后应生效，而不是继续按人民币解释")
    }

    // MARK: E. 去重指纹含币种

    func testAppendFingerprintDistinguishesCurrency() throws {
        let product = try publish(name: "指纹币种款", reservation: 300, currency: .cny)
        _ = try ShopCatalogDraftStore.appendSaleRecord(
            productID: product.id, type: .stock, price: 380, startAt: day(10), currency: .cny)
        store.reloadWithOverlay()
        let before = store.saleEvents(forProduct: product.id).count

        // 同价格同批次日但币种不同的记录，字面数值撞车但语义不同，必须单独成记录
        let jpy = CatalogSaleEvent(id: "ev-jpy", productID: product.id, type: .stock,
                                   price: 380, deposit: nil, balance: nil,
                                   startAt: day(10), endAt: nil, currency: .jpy)
        let cny = CatalogSaleEvent(id: "ev-cny", productID: product.id, type: .stock,
                                   price: 380, deposit: nil, balance: nil,
                                   startAt: day(10), endAt: nil, currency: .cny)
        XCTAssertNotEqual(jpy.appendFingerprint, cny.appendFingerprint,
                          "同数值不同币种不得判为同一条记录")
        XCTAssertEqual(before, 2)
    }

    // MARK: F. 分档价格（R05）

    func testPriceTierIsCarriedButNotFaked() {
        let tiered = CatalogSaleEvent(id: "ev-t", productID: "px", type: .reservation,
                                      price: 21800, deposit: 5000, balance: 16800,
                                      startAt: day(0), endAt: nil, currency: .jpy,
                                      priceTierMin: 21800, priceTierMax: 24800)
        XCTAssertTrue(tiered.hasPriceTier)
        XCTAssertEqual(tiered.priceTierMin, 21800)
        XCTAssertEqual(tiered.priceTierMax, 24800)

        let single = CatalogSaleEvent(id: "ev-1", productID: "px", type: .stock,
                                      price: 380, deposit: nil, balance: nil,
                                      startAt: day(0), endAt: nil, currency: .cny)
        XCTAssertFalse(single.hasPriceTier, "单一价格不得伪造区间")
        XCTAssertNil(single.priceTierMin)
        XCTAssertNil(single.priceTierMax)
    }
}
