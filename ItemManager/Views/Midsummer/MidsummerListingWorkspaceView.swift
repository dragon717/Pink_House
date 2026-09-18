import PhotosUI
import SwiftUI

// MARK: - 上新工作台（用户 2026-09-16，App 内唯一的上新上传链路）
//
// 围绕单个系列的「商品上传上新系统」，与衣橱深度结合：
//   · 录入：名称 / 分类 / 关联款式 / 尺码 / 价格四档 / 备注 / 出处；
//   · 图片：主图宫格（最多 5 张，第 1 张为主图），落盘 ImageManager Images 目录；
//   · 状态管理：草稿 → 已上架 ⇄ 已下架，上架商品自动并入系列 feed——
//     品牌页卡片、详情页、规格抽屉、一键入库（含多选配一套）全部走既有链路。
//
// 入口：系列详情页「上新管理」，仲夏物语全部系列无条件开放（2026-09-16 深夜起去掉
// canContribute 三态门控与单系列限制；旧投稿表单 MidsummerContributeView 已删除）。
// 视觉沿用 MidsummerTheme 的组件形态：wizardCard 白卡、橙色主按钮、chip 多选、
// 主图宫格，保证界面风格统一。

struct MidsummerListingWorkspaceView: View {
  @ObservedObject var store: MidsummerStore
  let series: MidsummerSeriesDTO

  @ObservedObject private var listingStore = MidsummerListingStore.shared
  @Environment(\.dismiss) private var dismiss

  @State private var editingListing: MidsummerListing?
  @State private var showingForm = false
  @State private var toast: String?
  /// 改价入口（用户 2026-09-18）：价格总表行 / 商品行「改价」按钮共用。
  @State private var priceEditingListing: MidsummerListing?

  private var seriesListings: [MidsummerListing] {
    // 预售相位排序：定金期 → 尾款期 → 预售结束 → 其它，流转状态一眼可读。
    let phaseRank: [MidsummerPresalePhase?: Int] = [.deposit: 0, .balance: 1, .ended: 2, nil: 3]
    return listingStore.sortedListings
      .filter { $0.seriesID == series.id }
      .sorted { phaseRank[$0.presalePhase()] ?? 3 < phaseRank[$1.presalePhase()] ?? 3 }
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 12) {
          publishCard
          priceTableCard
          if let toast {
            Text(toast)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MidsummerTheme.freshGreen)
              .frame(maxWidth: .infinity, alignment: .leading)
              .transition(.opacity)
          }
          if seriesListings.isEmpty {
            emptyState
          } else {
            ForEach(seriesListings) { listing in
              listingRow(listing)
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 24)
      }
      .background(MidsummerTheme.pageBackground)
      .navigationTitle("上新管理")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("完成") { dismiss() }
        }
      }
      .sheet(isPresented: $showingForm) {
        MidsummerListingFormView(store: store, series: series)
      }
      .sheet(item: $editingListing) { listing in
        MidsummerListingFormView(store: store, series: series, existing: listing)
      }
      // 改价（用户 2026-09-18）：价格总表行 / 商品行「改价」进入同一编辑面板，
      // 保存后 upsert 触发 updatedAt → feed 重算，行内金额立即刷新。
      .sheet(item: $priceEditingListing) { listing in
        MidsummerListingPriceEditSheet(listing: listing) { message in
          showToast(message)
        }
      }
      .animation(.easeOut(duration: 0.18), value: toast)
      // 进入工作台补一次预售流转（与系列页同一兜底），行内徽章显示当前相位。
      .onAppear { listingStore.refreshPresaleTransitions() }
    }
  }

  // MARK: 发布入口卡

  private var publishCard: some View {
    Button {
      editingListing = nil
      showingForm = true
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "plus.square.on.square")
          .font(.system(size: 16, weight: .medium))
        VStack(alignment: .leading, spacing: 2) {
          Text("发布新商品")
            .font(.system(size: 14, weight: .semibold))
          Text("主图 → 阶段 → 尺码 → 单品与价格；上架后自动进入「\(series.name)」并可一键加入衣橱")
            .font(.system(size: 10))
            .foregroundStyle(MidsummerTheme.onAccent.opacity(0.85))
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(MidsummerTheme.onAccent)
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MidsummerTheme.brandOrange)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("listing-open-form")
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "shippingbox")
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(MidsummerTheme.secondaryText)
      Text("还没有上新记录")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MidsummerTheme.secondaryText)
      Text("点上方「发布新商品」开始第一次上新。")
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  // MARK: 系列价格总表（用户 2026-09-18）
  //
  // 本系列**全部上新商品**（含草稿 / 已上架 / 已下架）的价格汇总，分组口径与
  // 系列详情页价格总表一致：现货价 / 全款预约 / 定金尾款预约 / 待补价格。
  // 每行可点，直接进改价面板——改完保存，这里与系列详情页的总表一起刷新。

  private struct WorkspacePriceRow: Identifiable {
    let listing: MidsummerListing
    let amount: String
    var id: String { listing.id }
  }

  private struct WorkspacePriceGroup: Identifiable {
    let header: String
    let rows: [WorkspacePriceRow]
    var id: String { header }
  }

  /// 上新商品 → 价格分组。判定顺序与系列详情页 priceGroups 同源：
  /// 定金/尾款 → 定金尾款组；预约价 → 全款预约组；现货价 → 现货价组；全空 → 待补。
  private var workspacePriceGroups: [WorkspacePriceGroup] {
    var spot: [WorkspacePriceRow] = []
    var fullPreorder: [WorkspacePriceRow] = []
    var depositBalance: [WorkspacePriceRow] = []
    var pending: [WorkspacePriceRow] = []
    for listing in seriesListings {
      switch (listing.deposit, listing.balance) {
      case (let deposit?, let balance?):
        depositBalance.append(
          WorkspacePriceRow(listing: listing, amount: "定金 ¥\(deposit) · 尾款 ¥\(balance)"))
      case (let deposit?, nil):
        depositBalance.append(
          WorkspacePriceRow(
            listing: listing,
            amount: listing.preorderPrice != nil
              ? "定金 ¥\(deposit) · 尾款自动（预约价 − 定金）" : "定金 ¥\(deposit) · 尾款待填"))
      case (nil, let balance?):
        // 只有尾款没有定金：仍属预约链路，单独标口径，不伪装成现货价。
        depositBalance.append(WorkspacePriceRow(listing: listing, amount: "尾款 ¥\(balance)"))
      case (nil, nil):
        if let preorder = listing.preorderPrice {
          fullPreorder.append(WorkspacePriceRow(listing: listing, amount: "预约价 ¥\(preorder)"))
        } else if let price = listing.price {
          spot.append(WorkspacePriceRow(listing: listing, amount: "¥\(price)"))
        } else {
          pending.append(WorkspacePriceRow(listing: listing, amount: "待填写"))
        }
      }
    }
    var groups: [WorkspacePriceGroup] = []
    if !spot.isEmpty { groups.append(WorkspacePriceGroup(header: "现货价", rows: spot)) }
    if !fullPreorder.isEmpty {
      groups.append(WorkspacePriceGroup(header: "预约价 · 全款预约", rows: fullPreorder))
    }
    if !depositBalance.isEmpty {
      groups.append(WorkspacePriceGroup(header: "预约价 · 定金尾款预约", rows: depositBalance))
    }
    if !pending.isEmpty {
      groups.append(WorkspacePriceGroup(header: "价格待补充", rows: pending))
    }
    return groups
  }

  private var priceTableCard: some View {
    let groups = workspacePriceGroups
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Text("系列价格总表")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MidsummerTheme.primaryText)
        Text("点行直接改价")
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.brandOrange)
        Spacer(minLength: 0)
      }

      if groups.isEmpty {
        Text("还没有上新商品价格；点上方「发布新商品」开始。")
          .font(.system(size: 12))
          .foregroundStyle(MidsummerTheme.secondaryText)
      } else {
        ForEach(groups) { group in
          VStack(alignment: .leading, spacing: 4) {
            Text(group.header)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(MidsummerTheme.brandOrange)
            ForEach(group.rows) { row in
              Button {
                priceEditingListing = row.listing
              } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                  Text(row.listing.name)
                    .font(.system(size: 12))
                    .foregroundStyle(MidsummerTheme.primaryText)
                    .lineLimit(1)
                  if row.listing.status != .listed {
                    Text(row.listing.status.labelZH)
                      .font(.system(size: 9, weight: .semibold))
                      .foregroundStyle(MidsummerTheme.secondaryText)
                      .padding(.horizontal, 4)
                      .padding(.vertical, 1)
                      .background(MidsummerTheme.subtleFill)
                      .clipShape(Capsule())
                  }
                  Spacer(minLength: 8)
                  Text(row.amount)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(MidsummerTheme.priceRed)
                    .lineLimit(1)
                  Image(systemName: "square.and.pencil")
                    .font(.system(size: 10))
                    .foregroundStyle(MidsummerTheme.secondaryText)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("listing-price-row-\(row.id)")
            }
          }
          .padding(.vertical, 4)
          if group.header != groups.last?.header {
            Rectangle()
              .fill(MidsummerTheme.divider)
              .frame(height: 0.5)
          }
        }
      }

      Text("口径：现货价即买即得；全款预约一次付清；定金尾款预约需付两次。")
        .font(.system(size: 10))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .themeSkinAdaptiveSectionCard(
      slot: MidsummerThemeSlot.card,
      cornerRadius: 14,
      showsDecoration: true
    ) {
      MidsummerTheme.surface
    }
    .accessibilityIdentifier("workspace-price-table")
  }

  // MARK: listing 行

  private func listingRow(_ listing: MidsummerListing) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Group {
        if let cover = listing.imageFiles.first,
          let image = ImageManager.shared.loadImage(fileName: cover)
        {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          ZStack {
            MidsummerTheme.subtleFill
            Image(systemName: "photo")
              .font(.system(size: 14, weight: .light))
              .foregroundStyle(MidsummerTheme.secondaryText)
          }
        }
      }
      .frame(width: 56, height: 56)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          statusChip(listing.status)
          // 预售相位徽章：定金期 / 尾款期 / 预售结束（含截止时间）。
          if let phase = listing.presalePhase() {
            Text(phaseChipText(listing, phase: phase))
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(MidsummerTheme.brandOrange)
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(MidsummerTheme.orangeSurface)
              .clipShape(Capsule())
          }
          Text(listing.name)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
            .lineLimit(2)
        }
        Text("\(listing.kinds.map(\.shortLabel).joined(separator: "/")) · \(listing.priceSummary) · 关联 \(listing.variantOptionNames.count) 个款式")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      // 行内主操作：改价（直接进价格编辑）+ 编辑（进完整表单），
      // 状态与危险操作收进菜单，避免误触。
      VStack(spacing: 8) {
        Button {
          editingListing = listing
        } label: {
          Text("编辑")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MidsummerTheme.brandOrange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MidsummerTheme.orangeSurface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("listing-edit-\(listing.id)")

        Button {
          priceEditingListing = listing
        } label: {
          HStack(spacing: 3) {
            Image(systemName: "yensign.circle")
              .font(.system(size: 10, weight: .semibold))
            Text("改价")
              .font(.system(size: 12, weight: .medium))
          }
          .foregroundStyle(MidsummerTheme.brandOrange)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(MidsummerTheme.orangeSurface)
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("listing-price-\(listing.id)")
        .accessibilityLabel("改价")
      }

      Menu {
        switch listing.status {
        case .draft, .delisted:
          Button("上架") { listingStore.updateStatus(of: listing.id, to: .listed) }
            .accessibilityIdentifier("listing-menu-list-\(listing.id)")
        case .listed:
          Button("下架") { listingStore.updateStatus(of: listing.id, to: .delisted) }
            .accessibilityIdentifier("listing-menu-delist-\(listing.id)")
        }
        Button("删除", role: .destructive) {
          listingStore.delete(listing.id)
          showToast("已删除「\(listing.name)」")
        }
        .accessibilityIdentifier("listing-menu-delete-\(listing.id)")
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.system(size: 16))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }
      .accessibilityIdentifier("listing-more-\(listing.id)")
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .themeSkinAdaptiveSectionCard(
      slot: MidsummerThemeSlot.card,
      cornerRadius: 12,
      showsDecoration: false
    ) {
      MidsummerTheme.surface
    }
  }

  private func statusChip(_ status: MidsummerListingStatus) -> some View {
    let color: Color = {
      switch status {
      case .draft: return MidsummerTheme.secondaryText
      case .listed: return MidsummerTheme.freshGreen
      case .delisted: return MidsummerTheme.brandOrange
      }
    }()
    return Text(status.labelZH)
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(color.opacity(0.12))
      .clipShape(Capsule())
  }

  /// 相位徽章文案：带阶段归属，临近截止再带剩余天数，流转时机一目了然。
  private func phaseChipText(_ listing: MidsummerListing, phase: MidsummerPresalePhase) -> String {
    let now = Date()
    let deadline: Date? = {
      switch phase {
      case .deposit: return listing.depositEndsAt
      case .balance: return listing.balanceEndsAt
      case .ended: return nil
      }
    }()
    guard let deadline else { return phase.labelZH }
    let days = Int(ceil(deadline.timeIntervalSince(now) / 86_400))
    return days > 0 ? "\(phase.labelZH) · 余 \(days) 天" : phase.labelZH
  }

  private func showToast(_ message: String) {
    toast = message
    Task {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      withAnimation(.easeOut(duration: 0.2)) { toast = nil }
    }
  }
}
