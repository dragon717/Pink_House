//
//  ShopCatalogPriceChartDisplayTests.swift
//  ItemManagerTests
//
//  价格表展示修复契约（2026-09-22，Request 14，用户反馈）：
//    A. `ShopCatalogImageResolver.isUnavailable` 诊断口径：
//       空引用 / local: 文件丢失 → 不可用；http(s) → 交给网络层（视为可用）；
//       刚落盘的 local: 文件 → 可用（对应「上传后应能正常显示」）
//    B. 上传 → 落盘 → 引用回填 → 系列价格表持久化 → 重载后仍可解析（端到端闭环）：
//       修复「点击查看原价格表图片无法显示」的完整链路
//    C. 测试隔离：一律 ShopCatalogStorage.useTemporaryForTesting()，
//       绝不触碰生产 Application Support 路径
//

import UIKit
import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogPriceChartDisplayTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        ShopCatalogStore.shared.reloadWithOverlay()
        super.tearDown()
    }

    /// 生成一张最小可用 JPEG（1x1 粉色像素）
    private func makeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.systemPink.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    // MARK: A. isUnavailable 诊断口径

    func testUnavailableForEmptyAndWhitespaceReferences() {
        XCTAssertTrue(ShopCatalogImageResolver.isUnavailable(nil))
        XCTAssertTrue(ShopCatalogImageResolver.isUnavailable(""))
        XCTAssertTrue(ShopCatalogImageResolver.isUnavailable("   "))
    }

    func testAvailableForHTTPReference() {
        // http(s) 引用本地无法判定存在性，交给网络层 → 视为可用
        XCTAssertFalse(ShopCatalogImageResolver.isUnavailable("https://example.com/price.jpg"))
        XCTAssertFalse(ShopCatalogImageResolver.isUnavailable("http://example.com/price.jpg"))
    }

    func testUnavailableForMissingLocalFile() {
        // local: 引用能解析出 URL，但文件不存在（模拟沙盒重置后数据丢失）→ 明确「不可用」
        XCTAssertTrue(ShopCatalogImageResolver.isUnavailable("local:img-deleted.jpg"))
    }

    func testAvailableForFreshlySavedLocalFile() {
        // 刚落盘的 local: 引用必须立即可解析（上传后应能正常显示）
        let ref = ShopCatalogImageStore.save(makeJPEGData())
        XCTAssertNotNil(ref, "图片落盘成功应返回 local: 引用")
        XCTAssertFalse(ShopCatalogImageResolver.isUnavailable(ref))
    }

    // MARK: B. 上传 → 持久化 → 重载 端到端

    func testPriceChartSourceImageSurvivesSeriesReload() throws {
        // 模拟系列编辑页的完整保存路径：上传图 → local: 引用写入 priceChart.sourceImage
        // → upsertEntity 持久化 → 重载 → 引用不变且对应文件仍可解析
        let reference = try XCTUnwrap(ShopCatalogImageStore.save(makeJPEGData()))

        var series = CatalogSeries(id: "series-pricedisplay-\(UUID().uuidString.prefix(6))",
                                   shopID: "shop-test", name: "价格表展示测试系列")
        var chart = CatalogPriceChart(id: "pricechart-\(series.id)",
                                      seriesID: series.id)
        chart.sourceImage = reference
        chart.columns = ["款式", "预约价", "定金", "尾款"]
        chart.rows = [CatalogSizeRow(label: "测试连衣裙", values: ["318", "91", "227"])]
        series.priceChart = chart

        try ShopCatalogDraftStore.upsertEntity(series, keyPath: \.series)

        // 直接读盘（绕过内存缓存）确认 JSON 已落盘
        let data = try Data(contentsOf: ShopCatalogStorage.directory
            .appendingPathComponent("shop-catalog-override.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let seriesList = (json?["series"] as? [[String: Any]]) ?? []
        XCTAssertTrue(seriesList.contains {
            ($0["id"] as? String) == series.id && $0["priceChart"] != nil
        }, "价格表应随系列持久化到覆盖层 JSON")

        // 重载后 store 视图里仍能取到，且引用对应的文件真实存在
        ShopCatalogStore.shared.reloadWithOverlay()
        let reloaded = ShopCatalogStore.shared.series(id: series.id)
        XCTAssertEqual(reloaded?.priceChart?.sourceImage, reference)
        XCTAssertFalse(ShopCatalogImageResolver.isUnavailable(reloaded?.priceChart?.sourceImage),
                       "重载后的价格表原图必须可解析，详情页才能正常显示")
    }
}
