import SwiftUI
import UIKit

// MARK: - 仲夏物语 · 视觉令牌
//
// 取值直接对照用户提供的两张参考图：
//   图一（品牌页）：橙红价格 / 橙色选中态 / 浅灰分割 / 白底
//   图二（系列列表）：浅橙按钮底 / 绿色「新」角标 / 大留白行高
//
// 规则（与全 app 的主题口径一致，改样式只改这里）：
//   1. **不要把颜色写死在各个视图里**——包括 `Color.white` / `Color.black.opacity(…)`
//      这类「看起来无害」的写法：它们锁死了亮色皮肤，深色模式下会变成白底黑字糊在一起。
//   2. 每个令牌都是**深浅色自适应**的，取值来自 `adaptive(light:dark:)`。
//      亮色取值与设计图逐一对齐，深色取值只做同色系压暗，不改变版式。
//   3. 需要参与主题皮肤（ThemeSkin）的容器 / 按钮，除了这里的令牌之外还要挂
//      对应槽位的 `themeSkin*` 修饰符，见 `MidsummerThemeSlot`。

nonisolated enum MidsummerTheme {

  // MARK: 品牌色

  /// 主橙，用于选中态与按钮文字（图一的「全部」chip、图二的「进店」）
  static let brandOrange = adaptive(
    light: Color(red: 1.00, green: 0.42, blue: 0.00),
    dark: Color(red: 1.00, green: 0.54, blue: 0.16)
  )
  /// 价格橙红，比主橙更红（图一 ¥119 的颜色）
  static let priceRed = adaptive(
    light: Color(red: 1.00, green: 0.31, blue: 0.00),
    dark: Color(red: 1.00, green: 0.45, blue: 0.19)
  )
  /// 浅橙底，用于 chip 选中背景与按钮背景
  static let orangeSurface = adaptive(
    light: Color(red: 1.00, green: 0.95, blue: 0.91),
    dark: Color(red: 0.30, green: 0.17, blue: 0.09)
  )
  /// 绿色「新」角标
  static let freshGreen = adaptive(
    light: Color(red: 0.31, green: 0.76, blue: 0.12),
    dark: Color(red: 0.46, green: 0.84, blue: 0.30)
  )

  // MARK: 底色与文字

  /// 卡片 / 抽屉 / 行背景。**替代裸写的 `Color.white`**。
  static let surface = adaptive(
    light: .white,
    dark: Color(red: 0.14, green: 0.14, blue: 0.15)
  )
  /// 抽屉背板遮罩
  static let scrim = adaptive(
    light: Color.black.opacity(0.35),
    dark: Color.black.opacity(0.58)
  )
  /// 「未选中 chip / 待补充标签」这类极浅填充。**替代裸写的 `Color.black.opacity(0.04~0.05)`**。
  static let subtleFill = adaptive(
    light: Color.black.opacity(0.05),
    dark: Color.white.opacity(0.10)
  )
  /// 橙色按钮上的文字色
  static let onAccent = Color.white
  /// 图标按钮投影
  static let shadow = adaptive(
    light: Color.black.opacity(0.18),
    dark: Color.black.opacity(0.45)
  )
  /// 分割线
  static let divider = adaptive(
    light: Color.black.opacity(0.07),
    dark: Color.white.opacity(0.12)
  )
  /// 页面底色
  static let pageBackground = adaptive(
    light: Color(red: 0.97, green: 0.96, blue: 0.96),
    dark: Color(red: 0.09, green: 0.09, blue: 0.10)
  )
  /// 左侧年份栏底色（选中项比它更浅）
  static let railBackground = adaptive(
    light: Color(red: 0.94, green: 0.92, blue: 0.91),
    dark: Color(red: 0.15, green: 0.14, blue: 0.14)
  )
  /// 主要文字
  static let primaryText = adaptive(
    light: Color(red: 0.13, green: 0.13, blue: 0.13),
    dark: Color(red: 0.95, green: 0.94, blue: 0.93)
  )
  /// 次要文字
  static let secondaryText = adaptive(
    light: Color(red: 0.60, green: 0.60, blue: 0.60),
    dark: Color(red: 0.68, green: 0.67, blue: 0.66)
  )

  // MARK: 无图占位渐变
  //
  // 以前是三段写死的粉紫渐变（只在亮色下成立）。拆成三个令牌后由
  // `MidsummerCoverView` 自己拼 `LinearGradient`，深色下压暗同样的色相。

  static let coverPlaceholderTop = adaptive(
    light: Color(red: 1.00, green: 0.93, blue: 0.95),
    dark: Color(red: 0.24, green: 0.17, blue: 0.19)
  )
  static let coverPlaceholderMid = adaptive(
    light: Color(red: 0.99, green: 0.90, blue: 0.94),
    dark: Color(red: 0.22, green: 0.16, blue: 0.18)
  )
  static let coverPlaceholderBottom = adaptive(
    light: Color(red: 0.97, green: 0.94, blue: 0.99),
    dark: Color(red: 0.19, green: 0.17, blue: 0.22)
  )

  static let cornerRadius: CGFloat = 12

  // MARK: 自适应构造

  /// 同一个令牌的亮 / 深两套取值。
  ///
  /// 用 `UIColor` 的 trait provider 而不是 `@Environment(\.colorScheme)`：
  /// 调用点（`MidsummerTheme.primaryText`）因此**完全不用改**，
  /// 现有几十处引用一行不动就获得了深色支持；快照测试里
  /// `ImageRenderer` 会带上 `\.colorScheme`，取值也随之正确。
  static func adaptive(light: Color, dark: Color) -> Color {
    Color(
      UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
      }
    )
  }
}

// MARK: - 主题皮肤槽位映射
//
// 这是「新功能 ↔ 现有主题规范」的**唯一落点**。仲夏物语是新模块，
// 但它不是孤岛：主题皮肤（ThemeSkin）启用后，以下结构面必须走 app 已有的 18 个槽位，
// 否则会出现「皮肤开着、只有这一页还是素底」的割裂。
//
// 两条硬约束（来自 AGENTS.md）：
//   · 皮肤未启用时**不得泄漏任何装饰** —— 靠 `.themeSkinAdaptiveSectionCard` 的
//     `fallbackBackground` 分支保证：没皮肤就走我们自己的令牌底色。
//   · 槽位只在**结构性容器**上挂，不往每个叶子视图上撒。

nonisolated enum MidsummerThemeSlot {
  /// 规格抽屉（底部升起）——与 `MultiDimensionalFilterSheet` 同一个槽位，
  /// 两者是同一种形态：带背板的筛选 / 选择面板。
  static let specDrawer: ThemeSkinSlot = .filterSheet
  /// 规格选项（chip / 缩略图格）
  static let specOption: ThemeSkinSlot = .filterChip
  /// 主按钮「加入衣橱 / 下一步」
  static let primaryButton: ThemeSkinSlot = .primaryButton
  /// 关闭 ✕ 这类圆形图标按钮
  static let iconButton: ThemeSkinSlot = .iconCircleButton
  /// 分组卡片 / 行卡片
  static let card: ThemeSkinSlot = .sectionCard
  /// 年份栏与系列 chip 所在的筛选条
  static let filterBar: ThemeSkinSlot = .filterChip
  /// 空状态
  static let emptyState: ThemeSkinSlot = .emptyState
  /// 顶栏容器
  static let topBar: ThemeSkinSlot = .topBarMain
  /// 顶栏返回 / 关闭
  static let topBarIconButton: ThemeSkinSlot = .topBarIconButton
  /// 顶栏「上传上新」
  static let topBarAddButton: ThemeSkinSlot = .topBarAddButton
}

// MARK: - 封面图
//
// 种子数据里的 `coverImage` 为 nil：仲夏物语是国牌，我们没有可再分发的官方图，
// 也不能直接引用淘宝图（防盗链 + 版权）。因此默认渲染一张带品牌水印的示意底图，
// 创作者上传后由 CloudKit 的 CKAsset 接管（`MidsummerCloudImage`）。

struct MidsummerCoverView: View {
  let imageName: String?
  let series: MidsummerSeriesDTO?
  var cornerRadius: CGFloat = MidsummerTheme.cornerRadius
  var showsWatermark: Bool = true

  var body: some View {
    ZStack {
      if let url = remoteURL {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFill()
          default:
            placeholder
          }
        }
      } else if let imageName, !imageName.isEmpty,
        let resolved = Self.resolvedImage(named: imageName)
      {
        Image(uiImage: resolved).resizable().scaledToFill()
      } else {
        placeholder
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(MidsummerTheme.divider, lineWidth: 0.5)
    )
  }

  private var remoteURL: URL? {
    guard let imageName, imageName.hasPrefix("http") else { return nil }
    return URL(string: imageName)
  }

  /// 封面名解析：先按资源名找（Asset Catalog / Bundle 内置文件），
  /// 再回退 `ImageManager` 的 Images 目录（种子图导入件、云端上传的本地文件名）。
  /// 两条路都落空才渲染水印占位——种子图导入是启动后的异步任务，
  /// 兜底保证首启的短暂窗口内也不会白屏。
  @MainActor
  private static func resolvedImage(named name: String) -> UIImage? {
    UIImage(named: name) ?? ImageManager.shared.loadImage(fileName: name)
  }

  /// 无图时的示意底：柔和粉色渐变 + 品牌水印，视觉上接近参考图里的图注样式。
  /// 渐变取自 `coverPlaceholder*` 三个令牌，因此深色模式下不会突然亮一块。
  private var placeholder: some View {
    LinearGradient(
      colors: [
        MidsummerTheme.coverPlaceholderTop,
        MidsummerTheme.coverPlaceholderMid,
        MidsummerTheme.coverPlaceholderBottom,
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .overlay {
      VStack(spacing: 4) {
        Image(systemName: series?.stage.symbolName ?? "sparkles")
          .font(.system(size: 20, weight: .light))
          .foregroundStyle(MidsummerTheme.brandOrange.opacity(0.55))
        if let series, showsWatermark {
          Text(series.name)
            .font(.system(size: 10, weight: .medium, design: .serif))
            .foregroundStyle(MidsummerTheme.brandOrange.opacity(0.75))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
        }
      }
    }
    .overlay(alignment: .topLeading) {
      if showsWatermark {
        Text("仲夏物语")
          .font(.system(size: 9, weight: .semibold, design: .serif))
          .foregroundStyle(MidsummerTheme.onAccent.opacity(0.92))
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(MidsummerTheme.brandOrange.opacity(0.35))
          .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
          .padding(5)
      }
    }
  }
}

// MARK: - 阶段标签

struct MidsummerStageBadge: View {
  let stage: MidsummerStage
  var filled: Bool = false

  var body: some View {
    Text(stage.labelZH)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(filled ? MidsummerTheme.onAccent : MidsummerTheme.brandOrange)
      .padding(.horizontal, 5)
      .padding(.vertical, 1.5)
      .background(filled ? MidsummerTheme.brandOrange : MidsummerTheme.orangeSurface)
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
  }
}

// MARK: - 「待补充」标记
//
// 网络信息天然不完整（用户已明确这一点），所以缺项要**看得见**，
// 而不是静默留空——它同时也是对上上传入口的引导。

struct MidsummerPendingTag: View {
  var text: String = "待补充"

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(MidsummerTheme.secondaryText)
      .padding(.horizontal, 5)
      .padding(.vertical, 1.5)
      .background(MidsummerTheme.subtleFill)
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
  }
}

// MARK: - 尺码行

struct MidsummerSizesRow: View {
  let sizes: [String]
  var compact: Bool = false

  var body: some View {
    if sizes.isEmpty {
      MidsummerPendingTag(text: "尺码待补充")
    } else {
      HStack(spacing: 4) {
        ForEach(sizes, id: \.self) { size in
          Text(size)
            .font(.system(size: compact ? 9 : 10, weight: .medium))
            .foregroundStyle(MidsummerTheme.secondaryText)
            .padding(.horizontal, compact ? 4 : 5)
            .padding(.vertical, 1.5)
            .background(MidsummerTheme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
      }
    }
  }
}

// MARK: - 左侧年份栏（图一左竖排）
//
// 图一的左栏：宽约 86pt，年份竖排；选中项 = 橙字 + 左侧 3pt 橙竖条 + 白底，
// 未选中项沿用 railBackground，形成「选中项从栏里浮起来」的观感。
// 抽成独立组件是为了能被快照测试单独渲染——整页在 ScrollView 里，
// ImageRenderer 只会渲染可视区框架，拿不到真实内容。

struct MidsummerYearRail: View {
  let entries: [MidsummerYearEntry]
  let activeYear: Int?
  let onSelect: (Int) -> Void

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      MidsummerYearRailContent(entries: entries, activeYear: activeYear, onSelect: onSelect)
    }
    .frame(width: 86)
    .background(MidsummerTheme.railBackground)
    .overlay(alignment: .trailing) {
      Rectangle().fill(MidsummerTheme.divider).frame(width: 0.5)
    }
  }
}

/// 年份栏的**内容本体**，刻意不含 `ScrollView`。
///
/// 拆出来的原因：`ImageRenderer` 渲染不了 `ScrollView` 的内容（只出空框架），
/// 所以快照测试直接渲染这个 VStack，才能真的看到年份与选中态。
struct MidsummerYearRailContent: View {
  let entries: [MidsummerYearEntry]
  let activeYear: Int?
  let onSelect: (Int) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(entries) { entry in
        yearButton(entry)
      }
    }
    .padding(.vertical, 6)
  }

  private func yearButton(_ entry: MidsummerYearEntry) -> some View {
    let isActive = entry.year == activeYear
    return Button {
      onSelect(entry.year)
    } label: {
      HStack(spacing: 0) {
        Rectangle()
          .fill(isActive ? MidsummerTheme.brandOrange : .clear)
          .frame(width: 3)

        VStack(spacing: 2) {
          Text(entry.title)
            .font(.system(size: isActive ? 15 : 14, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText)
            .themeSkinLegibleText(level: isActive ? .chip : .inline, slot: MidsummerThemeSlot.filterBar)

          // 图一副标题：有预约的年份写「新品预约」，否则「新品」。
          // 颜色只在**选中**时用橙色——否则多个未选中项都染橙，会和选中态抢焦点，
          // 左侧栏「选中即橙」的信号就废了（快照核对时发现并修正）。
          Text(entry.subtitle)
            .font(.system(size: 9, weight: isActive ? .medium : .regular))
            .foregroundStyle(
              isActive ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText.opacity(0.75)
            )
            .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.filterBar)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
      }
      .background(isActive ? MidsummerTheme.surface : .clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(entry.year) 年")
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}

// MARK: - 系列 chip（图一顶部横排）
//
// 文案是「月.日 系列名」（如「2.9 小熊博物馆系列」），由调用方拼好；
// 选中态用浅橙底 + 橙字，未选中是灰字 + 极浅灰底。

struct MidsummerSeriesChip: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText)
        .themeSkinLegibleText(level: isSelected ? .chip : .inline, slot: MidsummerThemeSlot.filterBar)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(isSelected ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - 橙色按钮（图二的「进店」）

struct MidsummerOrangeButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(MidsummerTheme.brandOrange)
      .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.filterBar)
      .frame(width: 58, height: 30)
      .background(MidsummerTheme.orangeSurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}
