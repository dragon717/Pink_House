import SwiftUI

// MARK: - 链接原始信息（原生页）
//
// 对齐此前 HTML 版「链接原始信息」报告的信息结构：每个淘宝链接一节，
// 呈现标题 / 商品 ID / 店铺 / 销量 / 价格区间 / 出售状态等原始字段，
// 颜色分类逐项列出（缩略图 + 尺码 + 挂牌价 + 物流口径），
// SKU 明细折叠展示。全部为纯静态资料展示，不提供购买。

struct MidsummerLinkReportView: View {
  private let report: MidsummerLinkReport?

  init(report: MidsummerLinkReport? = MidsummerLinkReport.loadFromBundle()) {
    self.report = report
  }

  var body: some View {
    Group {
      if let report {
        ScrollView(.vertical, showsIndicators: false) {
          LazyVStack(spacing: 18, pinnedViews: []) {
            ForEach(report.links) { link in
              MidsummerLinkCard(link: link)
            }
            Text("以上信息严格按淘宝商品页原文整理（\(report.generatedAt)），不做增删改。")
              .font(.system(size: 10))
              .foregroundStyle(MidsummerTheme.secondaryText)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
              .padding(.bottom, 28)
          }
          .padding(.horizontal, 14)
          .padding(.top, 12)
        }
      } else {
        ContentUnavailableView(
          "资料尚未就绪",
          systemImage: "link",
          description: Text("链接原始信息数据缺失，请确认安装包完整性。")
        )
      }
    }
    .background(MidsummerTheme.pageBackground)
  }
}

// MARK: - 单个链接卡片

struct MidsummerLinkCard: View {
  let link: MidsummerLinkReport.Link

  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // 标题区
      VStack(alignment: .leading, spacing: 6) {
        Text(link.title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(MidsummerTheme.primaryText)
          .fixedSize(horizontal: false, vertical: true)
        Text("价格区间 \(link.priceRange) · 已售 \(link.sellCount)")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MidsummerTheme.priceRed)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("midsummer-link-title-\(link.itemID)")

      // 原始字段
      VStack(alignment: .leading, spacing: 5) {
        fieldRow("店铺", link.shopName)
        fieldRow("商品 ID", link.itemID)
        fieldRow("采集时间", link.capturedOn)
        fieldRow("详情图", "\(link.detailImageCount) 张")
      }

      // 链接行（复制 + Safari 打开）
      HStack(spacing: 10) {
        Text(link.url)
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          UIPasteboard.general.string = link.shortURL ?? link.url
          copied = true
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
        } label: {
          Text(copied ? "已复制" : "复制")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MidsummerTheme.brandOrange)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("midsummer-link-copy-\(link.itemID)")

        if let short = link.shortURL, let url = URL(string: short) {
          Link(destination: url) {
            Image(systemName: "safari")
              .font(.system(size: 13))
              .foregroundStyle(MidsummerTheme.brandOrange)
          }
          .accessibilityLabel("在 Safari 打开商品链接")
        }
      }
      .padding(.vertical, 7)
      .padding(.horizontal, 10)
      .background(MidsummerTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      // 出售状态等强调参数 chips
      if !link.emphParams.isEmpty {
        FlowChips(items: link.emphParams.map { "\($0.label)：\($0.value)" })
      }

      // 颜色分类
      VStack(alignment: .leading, spacing: 8) {
        Text("颜色分类（\(link.colorOptions.count)）")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(MidsummerTheme.primaryText)
        ForEach(link.colorOptions) { option in
          colorOptionRow(option)
        }
      }

      // SKU 明细（折叠）
      if !link.skuRows.isEmpty {
        DisclosureGroup {
          VStack(spacing: 0) {
            skuHeaderRow
            ForEach(Array(link.skuRows.enumerated()), id: \.offset) { index, row in
              skuRow(row, zebra: index.isMultiple(of: 2))
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(MidsummerTheme.divider, lineWidth: 0.5)
          )
        } label: {
          Text("SKU 明细（\(link.skuRows.count) 行）")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(MidsummerTheme.primaryText)
        }
        .accessibilityIdentifier("midsummer-link-sku-\(link.itemID)")
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MidsummerTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(MidsummerTheme.divider, lineWidth: 0.5)
    )
  }

  // MARK: 子组件

  private func fieldRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(label)
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .frame(width: 56, alignment: .leading)
      Text(value)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(MidsummerTheme.primaryText)
        .textSelection(.enabled)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  private func colorOptionRow(_ option: MidsummerLinkReport.ColorOption) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Group {
        if let image = MidsummerStyleChartData.resolvedImage(named: option.imageName) {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
        } else {
          Rectangle().fill(MidsummerTheme.subtleFill)
        }
      }
      .frame(width: 44, height: 44)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(MidsummerTheme.divider, lineWidth: 0.5)
      )
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(option.name)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MidsummerTheme.primaryText)
        Text("\(option.sizes.joined(separator: " / "))｜¥\(option.prices.joined(separator: "/¥"))")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
        if !option.logistics.isEmpty {
          Text(option.logistics.joined(separator: "；"))
            .font(.system(size: 10))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
  }

  private var skuHeaderRow: some View {
    HStack(spacing: 0) {
      skuCell("颜色分类", weight: .semibold, alignment: .leading)
      skuCell("尺码", weight: .semibold)
      skuCell("价格", weight: .semibold)
      skuCell("库存", weight: .semibold)
    }
    .background(MidsummerTheme.orangeSurface.opacity(0.6))
  }

  private func skuRow(_ row: MidsummerLinkReport.SKURow, zebra: Bool) -> some View {
    HStack(spacing: 0) {
      skuCell(row.color, alignment: .leading)
      skuCell(row.size)
      skuCell("¥\(row.price)")
      skuCell(row.quantity)
    }
    .background(zebra ? Color.clear : MidsummerTheme.subtleFill.opacity(0.5))
  }

  private func skuCell(
    _ text: String,
    weight: Font.Weight = .regular,
    alignment: HorizontalAlignment = .center
  ) -> some View {
    Text(text)
      .font(.system(size: 10, weight: weight))
      .foregroundStyle(MidsummerTheme.primaryText)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .overlay(alignment: .trailing) {
        Rectangle().fill(MidsummerTheme.divider).frame(width: 0.5)
      }
  }
}

// MARK: - 简易流式 chips

/// 强调参数（品牌 / 款式 / 出售状态…）的流式排布。
/// SwiftUI 没有原生 FlowLayout，这里用固定两列的换行策略即可满足条目量。
struct FlowChips: View {
  let items: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        Text(item)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(MidsummerTheme.brandOrange)
          .padding(.horizontal, 9)
          .padding(.vertical, 4)
          .background(MidsummerTheme.orangeSurface, in: Capsule())
      }
    }
  }
}
