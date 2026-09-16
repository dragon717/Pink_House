import SwiftUI

// MARK: - 款式分类与尺码表（原生页）
//
// 对齐此前 HTML 版的信息结构（15 个分类、24 张色卡、16 张尺码表），
// 以原生 SwiftUI 实现：顶部目录 chips 快速跳转、色卡横滑、尺码表用
// `Grid` 原生排版、原图点按全屏放大。样式一律走 `MidsummerTheme` 令牌，
// 深浅色自适应。

struct MidsummerStyleChartCatalogView: View {
  private let catalog: MidsummerStyleChartCatalog?

  /// 全屏放大的尺码表原图
  @State private var zoomedImageName: ZoomTarget?

  init(catalog: MidsummerStyleChartCatalog? = MidsummerStyleChartCatalog.loadFromBundle()) {
    self.catalog = catalog
  }

  var body: some View {
    Group {
      if let catalog {
        content(catalog)
      } else {
        ContentUnavailableView(
          "资料尚未就绪",
          systemImage: "ruler",
          description: Text("款式分类与尺码表数据缺失，请确认安装包完整性。")
        )
      }
    }
    .background(MidsummerTheme.pageBackground)
    .fullScreenCover(item: $zoomedImageName) { imageName in
      MidsummerChartZoomView(imageName: imageName.value)
    }
  }

  private func content(_ catalog: MidsummerStyleChartCatalog) -> some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 14, pinnedViews: []) {
          headerCard(catalog)
          tocChips(catalog, proxy: proxy)
          ForEach(catalog.categories) { category in
            MidsummerStyleCategoryCard(
              category: category,
              onTapChartImage: { zoomedImageName = ZoomTarget(name: $0) }
            )
            .id(category.id)
          }
          footerNote(catalog)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 28)
      }
    }
  }

  // MARK: 页头

  private func headerCard(_ catalog: MidsummerStyleChartCatalog) -> some View {
    VStack(spacing: 6) {
      Image(systemName: "ruler.fill")
        .font(.system(size: 22, weight: .light))
        .foregroundStyle(MidsummerTheme.brandOrange)
      Text("樱花小羊 · 款式分类与尺码表")
        .font(.system(size: 19, weight: .bold))
        .foregroundStyle(MidsummerTheme.primaryText)
      Text("同一款式的不同颜色归为一类；尺码表数据转录自各商品详情页原图")
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
      ForEach(Array(catalog.sources.enumerated()), id: \.offset) { _, source in
        VStack(spacing: 2) {
          Text(source.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
          Text("\(source.shopName) · 采集于 \(source.capturedOn)")
            .font(.system(size: 10))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
        .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .padding(.horizontal, 14)
    .background(MidsummerTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  // MARK: 目录 chips

  private func tocChips(
    _ catalog: MidsummerStyleChartCatalog,
    proxy: ScrollViewProxy
  ) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(catalog.categories) { category in
          Button {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(category.id, anchor: .top) }
          } label: {
            Text(cleanChipName(category.name))
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MidsummerTheme.brandOrange)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(
                MidsummerTheme.orangeSurface,
                in: Capsule()
              )
              .overlay(Capsule().stroke(MidsummerTheme.divider, lineWidth: 0.5))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("midsummer-chart-toc-\(category.id)")
        }
      }
      .padding(.horizontal, 2)
      .padding(.vertical, 4)
    }
  }

  /// 「① SK」→「SK」，chip 里不必带序号
  private func cleanChipName(_ name: String) -> String {
    if let idx = name.firstIndex(where: { $0.isNumber }), name.contains("　") || name.contains(" ") {
      return String(name[name.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
    }
    return name
  }

  private func footerNote(_ catalog: MidsummerStyleChartCatalog) -> some View {
    Text("本页为衣橱搭配参考整理，不提供购买；所有数据以淘宝商品详情页原文为准（\(catalog.generatedAt) 整理）。")
      .font(.system(size: 10))
      .foregroundStyle(MidsummerTheme.secondaryText)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.top, 6)
  }
}

// MARK: - 单个分类卡片

struct MidsummerStyleCategoryCard: View {
  let category: MidsummerStyleChartCatalog.Category
  let onTapChartImage: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // 分类头：名称 / 价格 / 尺码
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(category.name)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(MidsummerTheme.primaryText)
          if let price = category.price {
            Text(price)
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(MidsummerTheme.priceRed)
          }
          Spacer(minLength: 0)
          if let sizes = category.sizes, !sizes.isEmpty {
            Text(sizes)
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.secondaryText)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("midsummer-chart-cat-\(category.id)")

        if let fabrics = category.fabrics, !fabrics.isEmpty {
          Text(fabrics)
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
      }

      // 分类级色卡
      if !category.swatches.isEmpty {
        MidsummerSwatchRow(swatches: category.swatches)
      }

      // 分类级温馨提示
      ForEach(Array(category.headerTips.enumerated()), id: \.offset) { _, tip in
        Text(tip)
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.priceRed.opacity(0.85))
      }

      // 尺码表（一个分类可能有多张，如「小物」= 立体小脸包 + bb帽）
      ForEach(Array(category.charts.enumerated()), id: \.offset) { _, chart in
        MidsummerChartSection(chart: chart, onTapImage: onTapChartImage)
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
}

// MARK: - 色卡行

struct MidsummerSwatchRow: View {
  let swatches: [MidsummerStyleChartCatalog.Swatch]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in
          VStack(spacing: 4) {
            Group {
              if let image = MidsummerStyleChartData.resolvedImage(named: swatch.imageName) {
                Image(uiImage: image)
                  .resizable()
                  .scaledToFill()
              } else {
                Rectangle().fill(MidsummerTheme.subtleFill)
              }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MidsummerTheme.divider, lineWidth: 0.5)
            )
            .accessibilityHidden(true)

            Text(swatch.name)
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.primaryText)
              .lineLimit(1)
          }
        }
      }
      .padding(.vertical, 2)
    }
  }
}

// MARK: - 单张尺码表区块

struct MidsummerChartSection: View {
  let chart: MidsummerStyleChartCatalog.Chart
  let onTapImage: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      // 表标题（左侧橙色竖条的强调样式）
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Rectangle()
          .fill(MidsummerTheme.priceRed)
          .frame(width: 3, height: 14)
        Text(chart.title)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(MidsummerTheme.primaryText)
        if let priceNote = chart.priceNote {
          Text(priceNote)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(MidsummerTheme.priceRed)
        }
        Spacer(minLength: 0)
      }
      .padding(.top, 4)
      .accessibilityElement(children: .combine)
      // identifier 用 ASCII 文件名（中文在 XCUITest 层级里会被截断）
      .accessibilityIdentifier("midsummer-chart-table-\(chart.imageName)")

      if let fabrics = chart.fabrics, !fabrics.isEmpty {
        Text(fabrics)
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }

      if let swatches = chart.swatches, !swatches.isEmpty {
        MidsummerSwatchRow(swatches: swatches)
      }

      if !chart.headers.isEmpty {
        MidsummerChartTable(headers: chart.headers, rows: chart.rows)
      }

      // 原尺码表图（点按全屏放大）
      if let image = MidsummerStyleChartData.resolvedImage(named: chart.imageName) {
        Button {
          onTapImage(chart.imageName)
        } label: {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MidsummerTheme.divider, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看\(chart.title)原图")
        // identifier 用 ASCII 的文件名（中文在 XCUITest 层级里会被截断）
        .accessibilityIdentifier("midsummer-chart-image-\(chart.imageName)")
      }

      ForEach(Array(chart.tips.enumerated()), id: \.offset) { _, tip in
        Text(tip)
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.priceRed.opacity(0.85))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

// MARK: - 原生尺码表（Grid 排版）

struct MidsummerChartTable: View {
  let headers: [String]
  let rows: [[String]]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
        GridRow {
          ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
            cell(header, isHeader: true, isFirstColumn: false)
          }
        }
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          GridRow {
            ForEach(Array(row.enumerated()), id: \.offset) { col, value in
              cell(value, isHeader: false, isFirstColumn: col == 0)
            }
          }
        }
      }
      .background(MidsummerTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(MidsummerTheme.divider, lineWidth: 0.5)
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(tableAccessibilityLabel)
  }

  private func cell(_ text: String, isHeader: Bool, isFirstColumn: Bool) -> some View {
    Text(text)
      .font(.system(size: 12, weight: isHeader || isFirstColumn ? .semibold : .regular))
      .foregroundStyle(MidsummerTheme.primaryText)
      .frame(minWidth: 64, maxWidth: .infinity, minHeight: 34)
      .padding(.horizontal, 8)
      .background(
        (isHeader || isFirstColumn) ? MidsummerTheme.orangeSurface.opacity(0.6) : Color.clear
      )
      .overlay(
        Rectangle()
          .stroke(MidsummerTheme.divider, lineWidth: 0.5)
      )
      .lineLimit(3)
      .multilineTextAlignment(.center)
  }

  private var tableAccessibilityLabel: String {
    let head = headers.joined(separator: "、")
    let body = rows.map { $0.joined(separator: " ") }.joined(separator: "；")
    return "尺码表：\(head)。\(body)"
  }
}

// MARK: - 尺码表原图全屏放大

/// `String` 的 Identifiable 包装，供 fullScreenCover(item:) 使用
struct ZoomTarget: Identifiable {
  let name: String
  var id: String { name }
  var value: String { name }
}

struct MidsummerChartZoomView: View {
  let imageName: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if let image = MidsummerStyleChartData.resolvedImage(named: imageName) {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .padding(12)
        }
      }
      VStack {
        HStack {
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 26))
              .foregroundStyle(.white.opacity(0.85))
          }
          .padding(16)
          .accessibilityIdentifier("midsummer-chart-zoom-close")
        }
        Spacer()
      }
    }
    .onTapGesture { dismiss() }
  }
}
