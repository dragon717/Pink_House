import SwiftUI

// MARK: - 规格选择面板（仿淘宝「加入购物车」）
//
// 形态：覆盖在商品详情页上的**底部抽屉**（不是新的 push 页、也不是嵌套 sheet）——
// 与淘宝一致：加购不会离开详情页，抽屉升起、选完即收。
//
// 与淘宝的三点**刻意差异**（产品决策，也写在界面上让使用者看得见）：
//   · 面向所有使用者，不要求登录
//   · 不限入库数量（默认 1，无上限）
//   · 入库不影响品牌库存，也不扣减自身条目
//
// 选中交互（与淘宝一致，也是使用者的明确要求）：
//   **点已选项 = 取消选中**，款式 / 颜色分类 / 尺码三组同一条规则，且允许一组都不选。
//   走 `MidsummerSpecResolver.toggling`，不要在这里自己改 `selection`。
//
// 版式上刻意用「换行网格」而不是「横向滚动条」装选项：
//   1. 抽屉里再套一层横向滚动，手势容易和纵向滚动打架
//   2. `ImageRenderer` 渲染不了 `ScrollView` 内容，横向滚动会让快照核对变成空图
//   3. 颜色分类一般只有 3–6 个，换行网格一行看得全

/// 入库意图：决定面板主按钮的文案与点击后的去向。
nonisolated enum MidsummerWardrobeInsertIntent: Hashable, Sendable {
  /// 直接在详情页落库
  case quickInsert
  /// 跳衣橱编辑页并预填
  case openEditor

  var confirmTitle: String {
    switch self {
    case .quickInsert: return "加入衣橱"
    case .openEditor: return "下一步：确认并编辑"
    }
  }

  var drawerTitle: String { "选择规格" }
}

// MARK: - 选项名展示口径
//
// 淘宝采集的归集选项名带「现 」档位前缀（如「现 sk 粉色」），界面展示时剥掉——
// 使用者口径（2026-09-16）：款式名前的「现」字不要。
// 只剥「现 + 空格」：「现货价」这类词不含空格、不受影响；
// 选项 id / 图映射 / SKU 匹配 / 入库备注等数据层一律仍用全名。

/// 单个选项名的展示形态：「现 sk 粉色」→「sk 粉色」。
private func midsummerOptionDisplayName(_ name: String) -> String {
  name.hasPrefix("现 ") ? String(name.dropFirst("现 ".count)) : name
}

/// 整段已选 / 确认文案里的选项名统一剥前缀。
private func midsummerSpecDisplayText(_ text: String) -> String {
  text.replacingOccurrences(of: "现 ", with: "")
}

// MARK: - 抽屉外壳

/// 半透明背板 + 从底部升起的规格面板。点背板或右上角 ✕ 收起。
struct MidsummerSpecDrawer: View {
  let item: MidsummerItemDTO
  let series: MidsummerSeriesDTO
  var intent: MidsummerWardrobeInsertIntent = .quickInsert
  /// 当前预售相位（nil = 不走状态机）。定金期把确认按钮改成「加入定金」。
  var presalePhase: MidsummerPresalePhase? = nil
  let onConfirm: (MidsummerSpecSelection, Int) -> Void
  let onClose: () -> Void
  /// 多选配一套（用户 2026-09-16）：勾选多件款式一次入库为同一套。
  /// 为 nil 时抽屉不出现多选入口（单选流程完全不变）。
  var onMultiConfirm: (([MidsummerSpecSelection], Int) -> Void)? = nil

  var body: some View {
    ZStack(alignment: .bottom) {
      MidsummerTheme.scrim
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityIdentifier("spec-drawer-backdrop")
        .accessibilityLabel("关闭规格选择")
        .accessibilityAddTraits(.isButton)

      MidsummerSpecPanel(
        item: item,
        series: series,
        intent: intent,
        presalePhase: presalePhase,
        onConfirm: onConfirm,
        onClose: onClose,
        onMultiConfirm: onMultiConfirm
      )
      .transition(.move(edge: .bottom))
    }
  }
}

// MARK: - 面板本体

struct MidsummerSpecPanel: View {
  let item: MidsummerItemDTO
  let series: MidsummerSeriesDTO
  var intent: MidsummerWardrobeInsertIntent = .quickInsert
  /// 当前预售相位（nil = 不走状态机）。定金期确认按钮文案变「加入定金」。
  var presalePhase: MidsummerPresalePhase? = nil
  let onConfirm: (MidsummerSpecSelection, Int) -> Void
  let onClose: () -> Void
  /// 多选配一套：一次带回「每件勾选项一条单品级选择」的数组。nil = 不提供多选。
  var onMultiConfirm: (([MidsummerSpecSelection], Int) -> Void)? = nil

  @State private var selection: MidsummerSpecSelection
  @State private var quantity: Int
  /// 多选配一套：开启后款式组的点击改为「勾选/取消勾选」，确认时按勾选项
  /// 逐条生成单品级选择交给 `onMultiConfirm`。尺码 / 价格档位仍单选，
  /// 作为整套的共同规格（无尺码的小物会在入库时自动不带尺码）。
  @State private var isMultiSelect = false
  @State private var multiPicks: Set<String> = []

  init(
    item: MidsummerItemDTO,
    series: MidsummerSeriesDTO,
    intent: MidsummerWardrobeInsertIntent = .quickInsert,
    presalePhase: MidsummerPresalePhase? = nil,
    onConfirm: @escaping (MidsummerSpecSelection, Int) -> Void,
    onClose: @escaping () -> Void,
    onMultiConfirm: (([MidsummerSpecSelection], Int) -> Void)? = nil
  ) {
    self.item = item
    self.series = series
    self.intent = intent
    self.presalePhase = presalePhase
    self.onConfirm = onConfirm
    self.onClose = onClose
    self.onMultiConfirm = onMultiConfirm
    // 打开即预选主推组合：淘宝也是这么做的，避免使用者先面对一个「请选择」的空面板。
    _selection = State(initialValue: MidsummerSpecResolver.defaultSelection(of: item))
    _quantity = State(initialValue: 1)
  }

  private var isComplete: Bool { MidsummerSpecResolver.isComplete(selection, of: item) }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(MidsummerTheme.divider)

      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 18) {
          if showsMultiSelectEntry {
            multiSelectRow
          }
          MidsummerSpecGroupsSection(
            item: item,
            series: series,
            selection: selection,
            onPick: pick,
            isMultiSelect: isMultiSelect,
            multiPicks: multiPicks
          )
          quantityRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
      }
      .frame(maxHeight: 330)

      Divider().overlay(MidsummerTheme.divider)
      confirmBar
    }
    .background(MidsummerTheme.surface)
    .clipShape(
      .rect(topLeadingRadius: 18, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 18)
    )
    // 主题皮肤（ThemeSkin）：抽屉刻意**不**用 `themeSkinAdaptiveSectionCard`——
    // 那个修饰符会把四个角都圆掉，而底部抽屉的下沿必须贴着屏幕边，
    // 圆角会在屏幕最下方露出页底色。所以这里只取 `.filterSheet` 槽位的
    // **深色可读性背板**（皮肤启用 + 深色模式才生效），版式一行不动。
    .themeSkinLegibilityBackdrop(
      level: .preview,
      slot: MidsummerThemeSlot.specDrawer,
      cornerRadius: 18
    )
    // ⚠️ 刻意**不**给整个面板挂 `accessibilityIdentifier`。
    // 实测：容器上的 identifier 会**覆盖掉直接子元素自己的 identifier**——
    // 确认按钮明明写了 `.accessibilityIdentifier("spec-confirm")`，
    // 层级里却变成了容器的标识，UI 测试直接找不到它。
    // 「面板是否打开」的判据请用 `spec-confirm` / `spec-option-*` 这类**叶子元素**，
    // 不要依赖容器标识。
  }

  // MARK: 多选配一套（用户 2026-09-16）

  /// 款式组（角色 variant）。多选勾选发生在这一组：裙 + 开衫 + 胸针都在「颜色分类」里。
  private var multiVariantGroup: MidsummerSpecGroup? {
    MidsummerSpecResolver.groups(of: item).first { $0.resolvedRole == .variant }
  }

  /// 多选入口的出现条件：一键入库意图 + 有款式组 + 款式 ≥ 2（单款没有「配一套」可言）。
  private var showsMultiSelectEntry: Bool {
    intent == .quickInsert
      && onMultiConfirm != nil
      && (multiVariantGroup?.options.count ?? 0) > 1
  }

  private var multiSelectRow: some View {
    Button {
      withAnimation(.snappy(duration: 0.16)) {
        isMultiSelect.toggle()
        if !isMultiSelect { multiPicks = [] }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: isMultiSelect ? "checkmark.square.fill" : "plus.square.on.square")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(isMultiSelect ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText)
        Text("多选配一套")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(isMultiSelect ? MidsummerTheme.brandOrange : MidsummerTheme.primaryText)
        Text(
          isMultiSelect
            ? "已开启：勾选多件，一次入库为同一套"
            : "勾选多件（如裙 + 开衫 + 胸针），一次入库为同一套"
        )
        .font(.system(size: 10))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(isMultiSelect ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(isMultiSelect ? MidsummerTheme.brandOrange : MidsummerTheme.divider, lineWidth: isMultiSelect ? 1 : 0.5)
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("spec-multi-toggle")
    .accessibilityLabel("多选配一套")
    .accessibilityValue(isMultiSelect ? "已开启" : "未开启")
  }

  // MARK: 顶部：选中图 + 价格 + 已选文案

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      MidsummerSpecThumbnail(
        imageName: MidsummerSpecResolver.image(for: selection, of: item),
        series: series,
        size: 84,
        cornerRadius: 10
      )

      VStack(alignment: .leading, spacing: 5) {
        Text(MidsummerSpecResolver.priceTextWithKind(for: selection, of: item))
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(
            MidsummerSpecResolver.price(for: selection, of: item) == nil
              ? MidsummerTheme.secondaryText : MidsummerTheme.priceRed
          )
          .themeSkinLegibleText(level: .badge, slot: MidsummerThemeSlot.specDrawer)

        Text(midsummerSpecDisplayText(
          MidsummerSpecResolver.selectionSummaryText(selection, of: item)))
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(isComplete ? MidsummerTheme.primaryText : MidsummerTheme.brandOrange)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.specDrawer)

        Text("不限入库数量 · 不影响品牌库存")
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.specDrawer)
      }

      Spacer(minLength: 0)

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .themeSkinLegibleSymbol(level: .badge, slot: MidsummerThemeSlot.iconButton)
          .frame(width: 26, height: 26)
          .background(MidsummerTheme.subtleFill, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("spec-close")
      .accessibilityLabel("收起规格选择")
    }
    .padding(16)
  }

  // MARK: 数量（无上限）

  private var quantityRow: some View {
    HStack(spacing: 10) {
      Text("入库数量")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(MidsummerTheme.primaryText)
        .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.card)

      Text("不限")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(MidsummerTheme.brandOrange)
        .themeSkinLegibleText(level: .chip, slot: MidsummerThemeSlot.specOption)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(MidsummerTheme.orangeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

      Spacer(minLength: 0)

      HStack(spacing: 0) {
        quantityButton(
          systemName: "minus",
          identifier: "spec-quantity-minus",
          label: "减少数量",
          enabled: quantity > 1
        ) {
          quantity = max(1, quantity - 1)
        }

        Text("\(quantity)")
          .font(.system(size: 14, weight: .semibold).monospacedDigit())
          .foregroundStyle(MidsummerTheme.primaryText)
          .themeSkinLegibleText(level: .chip, slot: MidsummerThemeSlot.card)
          .frame(minWidth: 38)
          .accessibilityIdentifier("spec-quantity-value")
          .accessibilityLabel("入库数量 \(quantity)")

        // 刻意没有上限：这里不写 `quantity < max` 之类的判断，也就没有「点不动」的档位。
        quantityButton(
          systemName: "plus",
          identifier: "spec-quantity-plus",
          label: "增加数量",
          enabled: true
        ) {
          quantity += 1
        }
      }
      // 步进器是「分组卡片」形态：无皮肤时 fallback 为透明（与改动前逐像素一致），
      // 皮肤启用时才换成卡面。放在 `.overlay` 之前，描边才压在卡面之上。
      .themeSkinAdaptiveSectionCard(
        slot: MidsummerThemeSlot.card,
        cornerRadius: 8,
        showsDecoration: false
      ) {
        Color.clear
      }
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(MidsummerTheme.divider, lineWidth: 1)
      )
    }
  }

  private func quantityButton(
    systemName: String,
    identifier: String,
    label: String,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(enabled ? MidsummerTheme.primaryText : MidsummerTheme.secondaryText.opacity(0.4))
        .frame(width: 40, height: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityIdentifier(identifier)
    .accessibilityLabel(label)
  }

  // MARK: 底部确认

  private var confirmBar: some View {
    VStack(spacing: 6) {
      Button {
        confirmSelection()
      } label: {
        Text(confirmTitle)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MidsummerTheme.onAccent)
          .themeSkinLegibleText(level: .badge, slot: MidsummerThemeSlot.primaryButton)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 13)
          // ⚠️ 刻意**不**在未选全时禁用按钮。
          // 使用者的交互规则是「允许不选中任何选项」，禁用会直接把这条规则作废——
          // 取消选择之后反而卡在面板里出不去。缺的规格由 `wardrobeMapping`
          // 回退到单品自带的配色 / 尺码，落库结果依然成立。
          .background(MidsummerTheme.brandOrange)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("spec-confirm")
      .accessibilityLabel(confirmTitle)

      // 定金期语义（用户 2026-09-19）：入库 = 加定金 + 进衣橱 + 同步心愿尾款，
      // 写在面板上让使用者确认前就能看到，不靠入库后的吐司补说。
      if intent == .quickInsert, presalePhase == .deposit {
        Text("定金期入库：商品加入衣橱，并同步到心愿尾款，尾款期再付尾款")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.brandOrange)
          .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.specDrawer)
          .accessibilityIdentifier("spec-deposit-hint")
      }

      if !isComplete {
        // 提示从「请先选择…」改成陈述句：现在是**可继续**的状态，不是被拦下。
        Text(
          "未选\(MidsummerSpecResolver.missingGroupNames(selection, of: item).joined(separator: "、"))，将按商品默认信息入库"
        )
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.specDrawer)
        .accessibilityIdentifier("spec-missing-hint")
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 14)
  }

  /// 主按钮的基础动作词。定金期（用户 2026-09-19 一键入库分阶段口径）：
  /// 这一阶段付的是定金，文案如实写「加入定金」——入库后同步心愿尾款。
  private var insertActionTitle: String {
    if intent == .quickInsert, presalePhase == .deposit { return "加入定金" }
    return intent.confirmTitle
  }

  private var confirmTitle: String {
    if isMultiSelect, !multiPicks.isEmpty {
      return "\(insertActionTitle)（\(multiPicks.count) 件一套）"
    }
    guard let summary = MidsummerSpecResolver.summary(selection, of: item) else {
      return insertActionTitle
    }
    return "\(insertActionTitle)（\(midsummerSpecDisplayText(summary))）"
  }

  private func pick(groupID: String, optionID: String) {
    withAnimation(.snappy(duration: 0.16)) {
      if isMultiSelect, groupID == multiVariantGroup?.id {
        // 多选模式：款式组的点击 = 勾选/取消勾选一件，不影响单选状态；
        // 尺码 / 价格档位仍走单选规则（整套共同规格）。
        if multiPicks.contains(optionID) {
          multiPicks.remove(optionID)
        } else {
          multiPicks.insert(optionID)
        }
      } else {
        // 一律走 resolver：点已选中的项 = 取消选中（`toggling`），
        // 并且它会把「因联动而失效的其它组选择」一并清掉，
        // 避免留下高亮着、却组合不成立的假选中状态。
        selection = MidsummerSpecResolver.toggling(
          groupID: groupID,
          optionID: optionID,
          in: selection,
          of: item
        )
      }
    }
  }

  /// 确认：多选开启且至少勾了一件 → 按勾选顺序逐条生成单品级选择，
  /// 走 `onMultiConfirm`（套装入库）；否则维持原单选路径，行为不变。
  private func confirmSelection() {
    if isMultiSelect, !multiPicks.isEmpty, let onMultiConfirm,
      let variantGroup = multiVariantGroup
    {
      let orderedIDs = variantGroup.options.filter { multiPicks.contains($0.id) }.map(\.id)
      let selections = orderedIDs.map {
        MidsummerSpecResolver.perVariantSelection(for: $0, base: selection, of: item)
      }
      onMultiConfirm(selections, quantity)
    } else {
      onConfirm(selection, quantity)
    }
  }
}

// MARK: - 规格缩略图
//
// 与 `MidsummerCoverView` 的区别：**没有图时要明确显示「无图」**，
// 而不是品牌的粉色水印渐变——否则使用者分不清「这个规格有专属图」和「这个规格还没图」。

struct MidsummerSpecThumbnail: View {
  let imageName: String?
  var series: MidsummerSeriesDTO?
  var size: CGFloat = 54
  var cornerRadius: CGFloat = 7

  private var hasImage: Bool {
    guard let imageName else { return false }
    return !imageName.isEmpty
  }

  var body: some View {
    Group {
      if hasImage {
        MidsummerCoverView(
          imageName: imageName,
          series: series,
          cornerRadius: cornerRadius,
          showsWatermark: false
        )
      } else {
        ZStack {
          MidsummerTheme.pageBackground
          Image(systemName: "photo")
            .font(.system(size: size * 0.26, weight: .light))
            .foregroundStyle(MidsummerTheme.secondaryText.opacity(0.55))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(MidsummerTheme.divider, lineWidth: 0.5)
        )
      }
    }
    .frame(width: size, height: size)
  }
}

// MARK: - 规格组区块
//
// 刻意**不含 ScrollView**：`ImageRenderer` 渲染滚动容器只会得到空框架，
// 拆出这一层才能让快照测试真的核对到选项 chip 与缩略图。
// （同一模式见 `MidsummerYearRailContent`。）

struct MidsummerSpecGroupsSection: View {
  let item: MidsummerItemDTO
  var series: MidsummerSeriesDTO?
  let selection: MidsummerSpecSelection
  let onPick: (String, String) -> Void
  /// 多选配一套（用户 2026-09-16）：开启后款式组按勾选态渲染，其余组仍单选。
  /// 带默认值——快照测试等既有调用点不传这两个参数时行为与旧版逐像素一致。
  var isMultiSelect: Bool = false
  var multiPicks: Set<String> = []

  private var groups: [MidsummerSpecGroup] { MidsummerSpecResolver.groups(of: item) }

  private var variantGroupID: String? {
    groups.first { $0.resolvedRole == .variant }?.id
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if groups.isEmpty {
        // 规格缺省：不要留白，明确告诉使用者「没有规格要选，直接入库」。
        HStack(spacing: 8) {
          Image(systemName: "checkmark.seal")
            .font(.system(size: 13))
            .foregroundStyle(MidsummerTheme.brandOrange)
            .themeSkinLegibleSymbol(level: .chip, slot: MidsummerThemeSlot.emptyState)
          Text("该单品暂无规格可选，将按单品信息直接加入衣橱。")
            .font(.system(size: 12))
            .foregroundStyle(MidsummerTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.emptyState)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MidsummerTheme.orangeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("spec-empty-hint")
      } else {
        ForEach(groups) { group in
          groupBlock(group)
        }

        // 可发现性：改动前点已选项是「重选同一个值」，看上去像没反应，
        // 所以必须把「能取消」这件事写在界面上，而不是只放在文档里。
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "hand.tap")
            .font(.system(size: 11))
          Text("点击选中；再次点击已选项即可取消，也可以一组都不选。")
            .font(.system(size: 10))
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(MidsummerTheme.secondaryText)
        .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.specDrawer)
        .accessibilityIdentifier("spec-toggle-hint")

        // 灰化的含义整段只解释一次。
        // 早期写在各组下面，两个组都灰时同一句话会连着出现两遍，反而像噪音。
        if hasUnavailableOptions {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
              .font(.system(size: 11))
            Text("灰掉的选项与当前已选无法组成同一套规格（与库存无关）")
              .font(.system(size: 10))
              .fixedSize(horizontal: false, vertical: true)
          }
          .foregroundStyle(MidsummerTheme.secondaryText)
          .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.specDrawer)
          .accessibilityIdentifier("spec-linkage-hint")
        }
      }
    }
  }

  private var hasUnavailableOptions: Bool {
    groups.contains { group in
      group.options.contains { option in !isAvailable(group: group, option: option) }
    }
  }

  private func groupBlock(_ group: MidsummerSpecGroup) -> some View {
    // 只要组里**任意**一个选项有图，整组就用带缩略图的版式，
    // 避免同组里「有图 / 无图」两种格子混排导致高度参差。
    let usesThumbnails = group.options.contains { option in
      guard let image = option.image else { return false }
      return !image.isEmpty
    }

    return VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 6) {
        Text(group.name)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MidsummerTheme.primaryText)
          .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.specDrawer)

        // 淘宝商品页口径：组名后带选项总数（「颜色分类（16）」）
        if group.options.count > 1 {
          Text("(\(group.options.count))")
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
            .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.specDrawer)
        }

        if isMultiSelect, group.id == variantGroupID {
          if !multiPicks.isEmpty {
            Text("已勾选 \(multiPicks.count) 件")
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.brandOrange)
              .themeSkinLegibleText(level: .chip, slot: MidsummerThemeSlot.specOption)
              .lineLimit(1)
          }
        } else if let picked = selection[group.id],
          let name = MidsummerSpecResolver.option(picked, in: group)?.name
        {
          Text("已选 \(midsummerOptionDisplayName(name))")
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.brandOrange)
            .themeSkinLegibleText(level: .chip, slot: MidsummerThemeSlot.specOption)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }

      if usesThumbnails {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 74), spacing: 8)],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(group.options) { option in
            if isAvailable(group: group, option: option) {
              thumbnailCell(group: group, option: option)
            } else {
              thumbnailCell(group: group, option: option).disabled(true).opacity(0.35)
            }
          }
        }
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 66), spacing: 8)],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(group.options) { option in
            if isAvailable(group: group, option: option) {
              textChip(group: group, option: option)
            } else {
              textChip(group: group, option: option).disabled(true).opacity(0.35)
            }
          }
        }
      }
    }
  }

  private func isAvailable(group: MidsummerSpecGroup, option: MidsummerSpecOption) -> Bool {
    MidsummerSpecResolver.isAvailable(
      groupID: group.id,
      optionID: option.id,
      given: selection,
      of: item
    )
  }

  /// 该选项自身的挂牌价：取 SKU 表里命中该选项的第一条带价组合。
  /// 淘宝口径下同组合各尺码同价，取第一条即可；无价返回 nil（不显示价格行）。
  private func optionPrice(group: MidsummerSpecGroup, option: MidsummerSpecOption) -> Int? {
    (item.skus ?? []).first {
      $0.options[group.id] == option.id && $0.price != nil
    }?.price
  }

  private func isSelected(group: MidsummerSpecGroup, option: MidsummerSpecOption) -> Bool {
    selection[group.id] == option.id
  }

  /// 选项的「高亮」判据：多选模式下款式组看勾选篮，其余组与单选模式同规则。
  private func isMarked(group: MidsummerSpecGroup, option: MidsummerSpecOption) -> Bool {
    if isMultiSelect, group.id == variantGroupID {
      return multiPicks.contains(option.id)
    }
    return isSelected(group: group, option: option)
  }

  private func thumbnailCell(group: MidsummerSpecGroup, option: MidsummerSpecOption) -> some View {
    let selected = isMarked(group: group, option: option)
    // 淘宝商品页口径：每个颜色分类选项卡直接带自己的挂牌价（同组合各尺码同价）。
    let optionPrice = optionPrice(group: group, option: option)
    return Button {
      onPick(group.id, option.id)
    } label: {
      VStack(spacing: 4) {
        MidsummerSpecThumbnail(imageName: option.image, series: series, size: 54, cornerRadius: 7)

        Text(midsummerOptionDisplayName(option.name))
          .font(.system(size: 10, weight: selected ? .semibold : .regular))
          .foregroundStyle(selected ? MidsummerTheme.brandOrange : MidsummerTheme.primaryText)
          .themeSkinLegibleText(level: selected ? .chip : .inline, slot: MidsummerThemeSlot.specOption)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .padding(.horizontal, 2)

        if let optionPrice {
          Text("¥\(optionPrice)")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(MidsummerTheme.priceRed)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 2)
        }
      }
      .padding(3)
      // 与 `MultiDimensionalFilterSheet` 的筛选 chip 完全同构：
      // 底色交给 fallback（无皮肤时就是原来的橙底 / 卡面），描边留在 overlay 里
      // 承担选中信号——皮肤启用时卡面会换掉 fallback，但橙色描边仍在，选中态不会丢。
      .themeSkinAdaptiveSectionCard(
        slot: MidsummerThemeSlot.specOption,
        cornerRadius: 9,
        showsDecoration: false
      ) {
        selected ? MidsummerTheme.orangeSurface : MidsummerTheme.surface
      }
      .overlay(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .stroke(
            selected ? MidsummerTheme.brandOrange : MidsummerTheme.divider,
            lineWidth: selected ? 1.5 : 0.5
          )
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("spec-option-\(group.id)-\(option.id)")
    .accessibilityLabel(midsummerOptionDisplayName(option.name))
    .accessibilityValue(selected ? "已选中" : "未选中")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func textChip(group: MidsummerSpecGroup, option: MidsummerSpecOption) -> some View {
    let selected = isMarked(group: group, option: option)
    return Button {
      onPick(group.id, option.id)
    } label: {
      Text(midsummerOptionDisplayName(option.name))
        .font(.system(size: 12, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? MidsummerTheme.brandOrange : MidsummerTheme.primaryText)
        .themeSkinLegibleText(level: selected ? .chip : .inline, slot: MidsummerThemeSlot.specOption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .themeSkinAdaptiveSectionCard(
          slot: MidsummerThemeSlot.specOption,
          cornerRadius: 8,
          showsDecoration: false
        ) {
          selected ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill
        }
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(selected ? MidsummerTheme.brandOrange : Color.clear, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("spec-option-\(group.id)-\(option.id)")
    .accessibilityLabel(midsummerOptionDisplayName(option.name))
    .accessibilityValue(selected ? "已选中" : "未选中")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
