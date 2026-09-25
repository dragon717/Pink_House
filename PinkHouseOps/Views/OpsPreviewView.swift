//
//  OpsPreviewView.swift
//  PinkHouseOps
//
//  本地预览：把当前草稿按「店家 → 系列 → 商品」摊开，确认结构、图片和价格。
//
//  ## 这个预览**不是**最终视觉
//
//  iOS 端的商品页要过 `ThemeSkin` 主题皮肤、同款颜色分组、尺码表共享、
//  发售阶段推导等一整套展示逻辑；那套代码没有（也不该）迁进共享包。
//  所以这里只回答三个问题：
//
//    1. 层级对不对？（这个商品挂在正确的店家 / 系列下面吗）
//    2. 图有没有？引用解不解得开？（`local:` 能读到文件，`thmedia:` 只能显示标记）
//    3. 价格档案算出来是什么？（走 `CatalogPriceArchive`，与 iOS 同一份推导）
//
//  价格这里**刻意复用 `CatalogPriceArchive`**（而不是自己按 saleEvents 排序取最新）：
//  预约价 / 现货价 / 差价的口径（含跨币种不比较、缺失一律「暂无」）只有一处定义，
//  预览自己再推一遍就会变成第二个口径。
//
//  ## 缩略图是同步加载的
//
//  `NSImage(contentsOf:)` 在主线程上跑。这里图数量是运营手选的几十张量级、
//  且只读本机文件，可以接受；真要放到上千张再谈异步，现在引入缓存层
//  只会增加出错面。
//

import SwiftUI

struct OpsPreviewView: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var shopFilter: String = ""
    @State private var searchText: String = ""

    private var visibleShops: [CatalogShop] {
        workspace.catalog.shops.filter { shopFilter.isEmpty || $0.id == shopFilter }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                filterCard
                if workspace.catalog.products.isEmpty {
                    OpsCard(title: "预览", systemImage: "eye") {
                        Text("还没有商品。到「目录编辑」里先建店家、系列和商品。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(visibleShops) { shop in
                        shopSection(shop)
                    }
                }
                disclaimerCard
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 过滤

    private var filterCard: some View {
        OpsCard(title: "预览范围", systemImage: "line.3.horizontal.decrease.circle") {
            HStack(spacing: 12) {
                Picker("店家", selection: $shopFilter) {
                    Text("全部店家").tag("")
                    ForEach(workspace.catalog.shops) { shop in
                        Text(shop.name).tag(shop.id)
                    }
                }
                .frame(maxWidth: 280)
                TextField("搜索商品名 / 品类", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 店家 → 系列 → 商品

    private func shopSection(_ shop: CatalogShop) -> some View {
        let series = workspace.catalog.series.filter { $0.shopID == shop.id }
        let looseProducts = products(ofShop: shop.id, seriesID: nil)
            .filter { product in
                !series.contains { $0.id == product.seriesID }
            }
        return OpsCard(title: shop.name, systemImage: "storefront") {
            VStack(alignment: .leading, spacing: 16) {
                if series.isEmpty && looseProducts.isEmpty {
                    Text("这个店家下面还没有内容。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(series) { item in
                    seriesBlock(item)
                }
                if !looseProducts.isEmpty {
                    // 商品的 seriesID 指向一个不存在的系列时会落到这里。
                    // 发布门禁也会拦，但预览页先把它显出来，省得运营到处找。
                    VStack(alignment: .leading, spacing: 8) {
                        Label("系列归属不明（seriesID 找不到对应系列）", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        ForEach(looseProducts) { product in
                            productRow(product)
                        }
                    }
                }
            }
        }
    }

    private func seriesBlock(_ series: CatalogSeries) -> some View {
        let products = products(ofShop: series.shopID, seriesID: series.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(series.name).font(.headline)
                if let yearMonth = yearMonthText(series) {
                    Text(yearMonth)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                }
                if let phase = series.salePhase {
                    Text("声明阶段：\(phase.displayName)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 4)
                Text("\(products.count) 商品")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if products.isEmpty {
                Text("这个系列下还没有商品。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(products) { product in
                    productRow(product)
                }
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 2)
        }
    }

    private func products(ofShop shopID: String, seriesID: String?) -> [CatalogProduct] {
        workspace.catalog.products.filter { product in
            guard product.shopID == shopID else { return false }
            if let seriesID, product.seriesID != seriesID { return false }
            guard !searchText.isEmpty else { return true }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return product.name.lowercased().contains(query)
                || product.category.lowercased().contains(query)
        }
    }

    // MARK: 商品行

    private func productRow(_ product: CatalogProduct) -> some View {
        let assets = product.images.compactMap { workspace.asset(for: $0) }
        let archive = CatalogPriceArchive(
            events: workspace.catalog.saleEvents.filter { $0.productID == product.id },
            correction: product.priceCorrection)
        return HStack(alignment: .top, spacing: 12) {
            thumbnailStrip(assets)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(product.name).font(.callout.weight(.medium)).lineLimit(2)
                    if !product.category.isEmpty {
                        Text(product.category)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }
                HStack(spacing: 12) {
                    labelled("预约价", value: moneyText(
                        archive.currentReservationPrice, archive.currentCurrency))
                    labelled("现货价", value: moneyText(
                        archive.currentStockPrice, archive.currentCurrency))
                    if let percent = archive.stockOverReservationDeltaPercent {
                        labelled("差价", value: String(format: "%+.1f%%", percent))
                    } else if let reason = archive.deltaUnavailableReason {
                        labelled("差价", value: reason)
                    }
                }
                HStack(spacing: 12) {
                    labelled("图片", value: "\(product.images.count) 张（本机可读 \(assets.count)）")
                    labelled("规格", value: "\(variantCount(of: product.id)) 条")
                    labelled("尺码表", value: sizeChartText(of: product.id))
                    if let batch = latestBatch(of: product.id) {
                        labelled("批次", value: batch)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func thumbnailStrip(_ assets: [CatalogAsset]) -> some View {
        HStack(spacing: 4) {
            ForEach(assets.prefix(3)) { asset in
                ReferenceThumbnail(
                    url: workspace.stagedFileURL(forReference: asset.originalURL),
                    reference: asset.originalURL)
            }
            if assets.isEmpty {
                ReferenceThumbnail(url: nil, reference: "")
            }
        }
    }

    private func labelled(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption).lineLimit(1)
        }
    }

    // MARK: 推导辅助

    private func moneyText(_ amount: Decimal?, _ currency: CatalogCurrency?) -> String {
        guard let amount else { return "暂无" }
        return CatalogMoney(amount: amount, currency: currency ?? .unknown).displayText
    }

    private func variantCount(of productID: String) -> Int {
        workspace.catalog.variants.filter { $0.productID == productID }.count
    }

    private func sizeChartText(of productID: String) -> String {
        guard let chart = workspace.catalog.sizeCharts.first(where: { $0.productID == productID }) else {
            return "无"
        }
        return chart.hasStructuredContent
            ? "\(chart.columns.count) 列 / \(chart.rows.count) 行"
            : "仅原图"
    }

    private func latestBatch(of productID: String) -> String? {
        workspace.catalog.saleEvents
            .filter { $0.productID == productID }
            .max { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }?
            .batchDisplay
    }

    private func yearMonthText(_ series: CatalogSeries) -> String? {
        switch (series.year, series.month) {
        case let (year?, month?): return String(format: "%04d-%02d", year, month)
        case let (year?, nil): return "\(year)"
        default: return series.season
        }
    }

    // MARK: 免责说明

    private var disclaimerCard: some View {
        OpsCard(title: "这个预览不代表最终效果", systemImage: "exclamationmark.bubble") {
            VStack(alignment: .leading, spacing: 8) {
                Text("· 不套 `ThemeSkin` 主题皮肤，也没有 iOS 端的同款颜色分组、"
                     + "尺码表共享、发售阶段「读取时推导」等展示逻辑；\n"
                     + "· 系列这里只显示**运营声明的**阶段（`salePhase`）；"
                     + "iOS 端还会按当前时间推导生效阶段（预约中 → 预约已结束 → 尾款中）；\n"
                     + "· `thmedia:` / `http(s)://` 的图在这里只能显示标记，"
                     + "本机没有那份字节；\n"
                     + "· 价格走 `CatalogPriceArchive`，与 iOS 端同一份口径。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 缩略图

private struct ReferenceThumbnail: View {
    let url: URL?
    let reference: String

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.secondary.opacity(0.10)
                    VStack(spacing: 2) {
                        Image(systemName: reference.isEmpty
                              ? "photo" : "questionmark.square.dashed")
                            .foregroundStyle(.secondary)
                        Text(badgeText)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.20), lineWidth: 1))
        .help(reference.isEmpty ? "没有绑定图片" : reference)
    }

    private var badgeText: String {
        if reference.isEmpty { return "无图" }
        if reference.hasPrefix("local:") { return "文件缺失" }
        if reference.hasPrefix("thmedia:") { return "远端" }
        if reference.hasPrefix("http") { return "外链" }
        return "内置"
    }
}
