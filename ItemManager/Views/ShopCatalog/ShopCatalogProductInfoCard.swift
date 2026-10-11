import SwiftUI

struct ShopCatalogProductInfoCard: View {
    let title: ShopCatalogProductTitle?
    let name: String
    let shopName: String?
    let yearMonth: String?
    let season: String?
    let category: String?
    let colors: [String]
    let sizes: [String]
    let fabric: String?
    let description: String?
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题 = 款式名（与点菜页卡片、商品管理款式组同一口径）；
            // 颜色只在下方「配色」行与轮播颜色胶囊里单独呈现。
            if let title {
                ShopCatalogProductTitleLabel(
                    title: title,
                    font: .title2.bold(),
                    textColor: themeManager.primaryTextColor,
                    annotationColor: themeManager.tertiaryTextColor,
                    lineLimit: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(name)
                    .font(.title2.bold())
                    .foregroundStyle(themeManager.primaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                if let shopName { Text(shopName) }
                if let yearMonth { Text("· \(yearMonth)") }
                if let season, !season.isEmpty { Text("· \(season)") }
                if let category { Text("· \(category)") }
            }
            .font(.caption)
            .foregroundStyle(themeManager.secondaryTextColor)

            Divider().background(themeManager.tertiaryTextColor.opacity(0.3))

            if !colors.isEmpty {
                specRow(label: "配色", values: colors)
            }
            if !sizes.isEmpty {
                specRow(label: "尺码", values: sizes)
            }
            // 面料 / 款式描述：**款式级公共属性**（2026-09-23 录入端重构）——
            // 读的是款式档案，同款各颜色显示同一份；不再是「每个颜色各存一份描述」。
            // 款式描述对旧数据回退 `product.description`（重构前描述写在商品上）。
            if let fabric {
                specRow(label: "面料", values: [fabric])
            }
            if let desc = description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 13))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSkinSectionCard(cornerRadius: 16)
    }

    @ViewBuilder
    private func specRow(label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.appLocalized)
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
            ShopCatalogFlowChips(values: values)
        }
    }

}
