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

      // 行内主操作：编辑（状态与危险操作收进菜单，避免误触）。
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
