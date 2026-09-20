import SwiftUI

// MARK: - 时光馆主页（品牌列表 · 参考图一）
//
// 图一范式 = 「关注店铺列表」，逐项对应关系：
//
//   ┌──────┬──────────────────────────────┬────────┬─────┐
//   │ 方图  │ 品牌名                        │  进店   │  ⋯  │
//   │ ┌新┐ │  N件新品 │ N天前关注            │        │     │
//   └──────┴──────────────────────────────┴────────┴─────┘
//
// · 缩略图：60×60、圆角 14、左下角绿色「新」角标（仅有可核验上新时出现）
// · 品牌名：17pt semibold、近黑色
// · 副行  ：绿字主指标 + 1×10 竖线 + 灰字时间；主指标优先「N件新品」，
//           没有可核验上新数据时退化为真实在售件数（绝不编造新品）
// · 「进店」：浅橙底 + 橙字、圆角 6
// · 「⋯」 ：灰色省略号，展开二级菜单
//
// 顶部另加搜索框与筛选条（图一未截到，但为本次要求的「筛选和搜索」而加）。
// 列表用 `ScrollView + LazyVStack`（不用 `List`）：既能上下滑动，
// 也便于用 `ImageRenderer` 做区块快照核对版式。

// MARK: - 配色令牌

enum TimeHallBrandListTheme {
  static let pageBackground = Color.white
  static let primaryText = Color(red: 0.10, green: 0.10, blue: 0.10)
  static let secondaryText = Color(red: 0.60, green: 0.60, blue: 0.62)
  static let freshGreen = Color(red: 0.24, green: 0.78, blue: 0.35)
  static let enterText = Color(red: 1.00, green: 0.42, blue: 0.21)
  static let enterSurface = Color(red: 1.00, green: 0.94, blue: 0.90)
  static let separator = Color(red: 0.90, green: 0.90, blue: 0.91)
  static let searchSurface = Color(red: 0.96, green: 0.96, blue: 0.97)
  static let chevron = Color(red: 0.78, green: 0.78, blue: 0.80)

  /// 首字母占位底的配色。与 `TimeHallStoreTheme.accent` 的观感保持一致，
  /// 但此处独立定义，避免主页依赖 `TimeHallView.swift` 里的私有枚举。
  static func placeholderColors(for brandID: String) -> [Color] {
    switch brandID {
    case "pinkHouse":
      return [
        Color(red: 0.98, green: 0.91, blue: 0.82), Color(red: 0.86, green: 0.72, blue: 0.60),
      ]
    case "angelicPretty":
      return [
        Color(red: 1.00, green: 0.90, blue: 0.95), Color(red: 0.95, green: 0.73, blue: 0.86),
      ]
    case "babyStarsShineBright":
      return [
        Color(red: 0.99, green: 0.91, blue: 0.91), Color(red: 0.87, green: 0.62, blue: 0.64),
      ]
    case "julietteEtJustine":
      return [
        Color(red: 0.94, green: 0.89, blue: 0.82), Color(red: 0.76, green: 0.66, blue: 0.54),
      ]
    case "wunderweltFleur":
      return [
        Color(red: 0.91, green: 0.87, blue: 0.96), Color(red: 0.72, green: 0.63, blue: 0.85),
      ]
    case "midsummerTale":
      return [
        Color(red: 1.00, green: 0.90, blue: 0.86), Color(red: 0.97, green: 0.70, blue: 0.62),
      ]
    default:
      return [
        Color(red: 0.94, green: 0.94, blue: 0.95), Color(red: 0.80, green: 0.80, blue: 0.83),
      ]
    }
  }
}

// MARK: - 宿主

/// 时光馆主页。只依赖 `TimeHallBrandListing`，不直接依赖品牌枚举，
/// 因此可以脱离 `TimeHallView` 单独渲染与快照。
struct TimeHallBrandListHome: View {
  let listings: [TimeHallBrandListing]
  let onEnter: (String) -> Void
  /// 「⋯」菜单里的「访问官网」。为 nil 时该行不显示「⋯」。
  var onOpenWebsite: ((String) -> Void)? = nil
  /// 「店家上新」入口（计划 §8：时光馆内部新增，不重做时光馆）。为 nil 时不显示入口卡片。
  var onOpenShopCatalog: (() -> Void)? = nil

  @State private var keyword = ""
  @State private var filter: TimeHallBrandListFilter = .all
  @State private var now = Date()

  private var visibleListings: [TimeHallBrandListing] {
    TimeHallBrandListQuery.apply(listings, keyword: keyword, filter: filter)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      controlBar
      content
    }
    .background(TimeHallBrandListTheme.pageBackground)
  }

  // MARK: 顶部标题

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("我的品牌".appLocalized)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(TimeHallBrandListTheme.primaryText)
      Text("\(listings.count)" + "个品牌".appLocalized)
        .font(.system(size: 13))
        .foregroundStyle(TimeHallBrandListTheme.secondaryText)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 10)
  }

  // MARK: 搜索 + 筛选

  private var controlBar: some View {
    VStack(spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(TimeHallBrandListTheme.secondaryText)

        TextField("搜索品牌名或关键词".appLocalized, text: $keyword)
          .font(.system(size: 15))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.search)

        if !keyword.isEmpty {
          Button {
            keyword = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 15))
              .foregroundStyle(TimeHallBrandListTheme.chevron)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("清除搜索".appLocalized)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(TimeHallBrandListTheme.searchSurface)
      )

      filterStrip
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 12)
  }

  private var filterStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(TimeHallBrandListFilter.allCases) { item in
          TimeHallBrandFilterChip(
            title: item.title,
            isSelected: item == filter,
            action: { filter = item }
          )
        }

        if !visibleListings.isEmpty {
          Text("\(visibleListings.count)" + "个".appLocalized)
            .font(.system(size: 12))
            .foregroundStyle(TimeHallBrandListTheme.secondaryText)
            .padding(.leading, 2)
        }
      }
      .padding(.horizontal, 1)
    }
  }

  // MARK: 列表

  @ViewBuilder
  private var content: some View {
    if visibleListings.isEmpty {
      emptyState
    } else {
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 0) {
          if let onOpenShopCatalog {
            ShopCatalogEntryCard(onTap: onOpenShopCatalog)
              .padding(.horizontal, 16)
              .padding(.bottom, 10)
          }
          ForEach(visibleListings) { listing in
            TimeHallBrandListRow(
              listing: listing,
              now: now,
              onEnter: { onEnter(listing.id) },
              onOpenWebsite: onOpenWebsite.map { handler in { handler(listing.id) } }
            )
          }
        }
        .padding(.bottom, 96)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 26))
        .foregroundStyle(TimeHallBrandListTheme.chevron)
      Text("没有符合条件的品牌".appLocalized)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(TimeHallBrandListTheme.secondaryText)
      Text("试试换个关键词或筛选条件".appLocalized)
        .font(.system(size: 13))
        .foregroundStyle(TimeHallBrandListTheme.chevron)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 56)
    .padding(.bottom, 96)
  }
}

// MARK: - 单行（图一核心）

struct TimeHallBrandListRow: View {
  let listing: TimeHallBrandListing
  var now: Date = Date()
  let onEnter: () -> Void
  var onOpenWebsite: (() -> Void)? = nil

  @State private var showsMoreMenu = false

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      TimeHallBrandThumbnail(
        imageName: listing.thumbnailImage,
        brandID: listing.id,
        displayName: listing.displayName,
        showsNewBadge: listing.hasVerifiedNewItems
      )

      VStack(alignment: .leading, spacing: 5) {
        Text(listing.displayName)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(TimeHallBrandListTheme.primaryText)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 6) {
          Text(listing.headlineMetricText)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(
              listing.hasVerifiedNewItems
                ? TimeHallBrandListTheme.freshGreen
                : TimeHallBrandListTheme.secondaryText
            )
            .lineLimit(1)

          Rectangle()
            .fill(TimeHallBrandListTheme.separator)
            .frame(width: 1, height: 10)

          Text(listing.followedText(now: now))
            .font(.system(size: 13))
            .foregroundStyle(TimeHallBrandListTheme.secondaryText)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      TimeHallBrandEnterButton(action: onEnter)

      if let onOpenWebsite {
        // 用 Button + confirmationDialog 而不是 Menu：Menu 在 `ImageRenderer`
        // 下无法栅格化（会渲染成系统禁止符号），换成弹窗后快照仍可人工核对版式。
        Button {
          showsMoreMenu = true
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(TimeHallBrandListTheme.chevron)
            .frame(width: 26, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多操作".appLocalized)
        .confirmationDialog(
          listing.displayName,
          isPresented: $showsMoreMenu,
          titleVisibility: .visible
        ) {
          Button("进入品牌档案".appLocalized) { onEnter() }
          Button("访问官网".appLocalized) { onOpenWebsite() }
          Button("取消".appLocalized, role: .cancel) {}
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }
}

// MARK: - 缩略图（含左下绿色「新」角标）

struct TimeHallBrandThumbnail: View {
  let imageName: String?
  let brandID: String
  let displayName: String
  var showsNewBadge: Bool = false
  var size: CGFloat = 60

  @ObservedObject private var store = TimeHallCatalogStore.shared

  private var resolvedImage: UIImage? {
    if let imageName, !imageName.isEmpty {
      if let image = store.image(named: imageName) { return image }
      if let image = UIImage(named: imageName) { return image }
    }
    return nil
  }

  private var initial: String {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return "?" }
    // 拉丁字母取首字母，中文取首字
    return String(first).uppercased()
  }

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Group {
        if let image = resolvedImage {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
        } else {
          LinearGradient(
            colors: TimeHallBrandListTheme.placeholderColors(for: brandID),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          .overlay {
            Text(initial)
              .font(.system(size: size * 0.42, weight: .bold))
              .foregroundStyle(.white.opacity(0.92))
          }
        }
      }
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.black.opacity(0.04), lineWidth: 1)
      }

      if showsNewBadge {
        Text("新".appLocalized)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 4)
          .padding(.vertical, 1.5)
          .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(TimeHallBrandListTheme.freshGreen)
          )
          .padding(.leading, 1)
          .padding(.bottom, 3)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

// MARK: - 「进店」按钮

struct TimeHallBrandEnterButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text("进店".appLocalized)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(TimeHallBrandListTheme.enterText)
        .padding(.horizontal, 15)
        .padding(.vertical, 7)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(TimeHallBrandListTheme.enterSurface)
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("进入品牌档案".appLocalized)
  }
}

// MARK: - 筛选胶囊

struct TimeHallBrandFilterChip: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(
          isSelected ? TimeHallBrandListTheme.enterText : TimeHallBrandListTheme.secondaryText
        )
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(
          Capsule(style: .continuous)
            .fill(
              isSelected
                ? TimeHallBrandListTheme.enterSurface
                : TimeHallBrandListTheme.searchSurface
            )
        )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
