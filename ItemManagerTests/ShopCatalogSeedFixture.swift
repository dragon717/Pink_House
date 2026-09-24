//
//  ShopCatalogSeedFixture.swift
//  ItemManagerTests
//
//  合成种子夹具（2026-09-24）：原 Bundle 种子里 Alice Girl / UNNIQ 两家的完整子图
//  （店家/系列/商品/规格/尺码表/销售事件/资源），随种子连根清理一并迁出 Bundle，
//  改由测试注入 `ShopCatalogStore(baseCatalog:)` —— 断言与 id 保持原样，语义不变。
//

import Foundation
@testable import ItemManager

enum ShopCatalogSeedFixture {

    /// 原种子子图 JSON（ISO8601 日期，与 Bundle 种子同构）
    static let jsonString = #"""
{"version":1,"shops":[{"id":"shop-alice-girl","name":"Alice Girl","aliases":["AG","爱丽丝少女"],"logo":"archive-catalog-27.jpg","cover":"archive-catalog-29.jpg","description":"国产 Lolita 品牌原创工作室"},{"id":"shop-unniq","name":"UNNIQ 许愿池原创","aliases":["UNNIQ","许愿池"],"logo":"archive-catalog-43.jpg","cover":"archive-catalog-46.jpg","description":"许愿池原创设计，主打轻日常"}],"series":[{"id":"series-ag-xueguo-2026","shopID":"shop-alice-girl","name":"雪国来信","year":2026,"season":"冬","cover":"archive-catalog-12.jpg","description":"2026 冬季主打系列"},{"id":"series-ag-xingwu-2025","shopID":"shop-alice-girl","name":"星屑圆舞曲","year":2025,"season":"冬","cover":"archive-catalog-18.jpg"},{"id":"series-unniq-yunduo-2026","shopID":"shop-unniq","name":"云朵邮局","year":2026,"season":"夏","cover":"archive-catalog-34.jpg"}],"products":[{"id":"prod-ag-xueguo-jsk","shopID":"shop-alice-girl","seriesID":"series-ag-xueguo-2026","name":"雪国来信 JSK","category":"JSK","images":["asset-ag-jsk-1","asset-ag-jsk-2","asset-ag-jsk-3"],"description":"雪花提花布 + 蕾丝拼接，含可拆蝴蝶结"},{"id":"prod-ag-xueguo-kc","shopID":"shop-alice-girl","seriesID":"series-ag-xueguo-2026","name":"雪国来信 KC","category":"KC","images":["asset-ag-kc-1"]},{"id":"prod-ag-xueguo-armwarmer","shopID":"shop-alice-girl","seriesID":"series-ag-xueguo-2026","name":"雪国来信 袖套","category":"小物","images":["asset-ag-arm-1"]},{"id":"prod-ag-xueguo-bag","shopID":"shop-alice-girl","seriesID":"series-ag-xueguo-2026","name":"雪国来信 单肩包","category":"包","images":["asset-ag-bag-1"]},{"id":"prod-ag-xingwu-jsk","shopID":"shop-alice-girl","seriesID":"series-ag-xingwu-2025","name":"星屑圆舞曲 JSK","category":"JSK","images":["asset-ag-xw-1","asset-ag-xw-2"]},{"id":"prod-unniq-yunduo-op","shopID":"shop-unniq","seriesID":"series-unniq-yunduo-2026","name":"云朵邮局 OP","category":"OP","images":["asset-unniq-op-1"]}],"variants":[{"id":"var-jsk-blue-s","productID":"prod-ag-xueguo-jsk","color":"夜空蓝","size":"S"},{"id":"var-jsk-blue-m","productID":"prod-ag-xueguo-jsk","color":"夜空蓝","size":"M"},{"id":"var-jsk-blue-l","productID":"prod-ag-xueguo-jsk","color":"夜空蓝","size":"L"},{"id":"var-jsk-white-s","productID":"prod-ag-xueguo-jsk","color":"初雪白","size":"S"},{"id":"var-jsk-white-m","productID":"prod-ag-xueguo-jsk","color":"初雪白","size":"M"},{"id":"var-jsk-white-l","productID":"prod-ag-xueguo-jsk","color":"初雪白","size":"L"},{"id":"var-kc-blue","productID":"prod-ag-xueguo-kc","color":"夜空蓝"},{"id":"var-kc-white","productID":"prod-ag-xueguo-kc","color":"初雪白"},{"id":"var-arm-white","productID":"prod-ag-xueguo-armwarmer","color":"初雪白"},{"id":"var-bag-blue","productID":"prod-ag-xueguo-bag","color":"夜空蓝"},{"id":"var-xw-blue-m","productID":"prod-ag-xingwu-jsk","color":"星屑蓝","size":"M"},{"id":"var-xw-blue-l","productID":"prod-ag-xingwu-jsk","color":"星屑蓝","size":"L"},{"id":"var-yd-op-s","productID":"prod-unniq-yunduo-op","size":"S"},{"id":"var-yd-op-m","productID":"prod-unniq-yunduo-op","size":"M"},{"id":"var-yd-op-l","productID":"prod-unniq-yunduo-op","size":"L"}],"sizeCharts":[{"id":"sizechart-ag-jsk","productID":"prod-ag-xueguo-jsk","unit":"cm","columns":["S","M","L"],"rows":[{"label":"胸围","values":["80-84","84-88","88-92"]},{"label":"腰围","values":["64-68","68-72","72-76"]},{"label":"裙长","values":["92","94","96"]}],"sourceImage":"asset-ag-jsk-size"}],"saleEvents":[{"id":"ev-ag-jsk-resv-2026","productID":"prod-ag-xueguo-jsk","type":"reservation","price":428,"deposit":128,"balance":300,"startAt":"2026-09-10T00:00:00Z","endAt":"2026-09-28T23:59:59Z"},{"id":"ev-ag-jsk-stock-2026","productID":"prod-ag-xueguo-jsk","type":"stock","price":568,"startAt":"2026-11-01T00:00:00Z"},{"id":"ev-ag-kc-resv-2026","productID":"prod-ag-xueguo-kc","type":"reservation","price":128,"startAt":"2026-09-10T00:00:00Z","endAt":"2026-09-28T23:59:59Z"},{"id":"ev-ag-arm-resv-2026","productID":"prod-ag-xueguo-armwarmer","type":"reservation","price":88,"startAt":"2026-09-10T00:00:00Z","endAt":"2026-09-28T23:59:59Z"},{"id":"ev-ag-bag-stock-2026","productID":"prod-ag-xueguo-bag","type":"stock","price":238,"startAt":"2026-09-10T00:00:00Z"},{"id":"ev-ag-xw-stock-2025","productID":"prod-ag-xingwu-jsk","type":"stock","price":398,"startAt":"2025-12-01T00:00:00Z","endAt":"2026-01-15T23:59:59Z"},{"id":"ev-unniq-op-stock-2026","productID":"prod-unniq-yunduo-op","type":"stock","price":356,"startAt":"2026-07-01T00:00:00Z","endAt":"2026-08-31T23:59:59Z"}],"assets":[{"id":"asset-ag-jsk-1","type":"productImage","originalURL":"archive-catalog-12.jpg"},{"id":"asset-ag-jsk-2","type":"productImage","originalURL":"archive-catalog-14.jpg"},{"id":"asset-ag-jsk-3","type":"productImage","originalURL":"archive-catalog-16.jpg"},{"id":"asset-ag-kc-1","type":"productImage","originalURL":"archive-catalog-25.jpg"},{"id":"asset-ag-arm-1","type":"productImage","originalURL":"archive-catalog-32.jpg"},{"id":"asset-ag-bag-1","type":"productImage","originalURL":"archive-catalog-37.jpg"},{"id":"asset-ag-xw-1","type":"productImage","originalURL":"archive-catalog-18.jpg"},{"id":"asset-ag-xw-2","type":"productImage","originalURL":"archive-catalog-39.jpg"},{"id":"asset-unniq-op-1","type":"productImage","originalURL":"archive-catalog-34.jpg"},{"id":"asset-ag-jsk-size","type":"sizeChartImage","originalURL":"archive-catalog-53.jpg"}]}
"""#

    static func makeCatalog() -> ShopCatalog {
        let catalog = try! ShopCatalogJSONCoding.decoder()
            .decode(ShopCatalog.self, from: Data(jsonString.utf8))
        return catalog
    }

    /// 注入合成种子的独立 Store（种子语义 = Bundle 只读基底，isSeed* 守卫生效）
    /// ShopCatalogStore 是 @MainActor，测试类均已标注主线程隔离
    @MainActor
    static func makeStore() -> ShopCatalogStore {
        ShopCatalogStore(baseCatalog: makeCatalog())
    }
}
