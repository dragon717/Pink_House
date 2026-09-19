import Foundation

// MARK: - 规格选择的纯逻辑层
//
// 为什么单独抽出来：规格选择有四种容易出错的状态迁移，而且都**不该**靠点界面来验证——
//   1. 规格缺省：单品没有规格组 → 直接可入库
//   2. 有规格组但没有 SKU 表：任意搭配都合法（不做联动约束）
//   3. 多规格联动：某个选项在「其它组已选」的前提下可能无法组成任何合法组合 → 禁用
//   4. 选中状态变化：改了 A 组之后，B 组原来的选择可能失效 → 必须自动清掉而不是留着假选中
//
// 这一层全部 `nonisolated` + 无副作用，因此可以脱离 UI 单测（见 `MidsummerSpecResolverTests`）。
//
// ⚠️ 与淘宝「加入购物车」的三点差异（产品决策，不要照搬淘宝逻辑）：
//   · 面向**所有**用户，不要求登录、不做任何权限闸门
//   · **不限**入库数量（默认 1，可加到任意大，没有上限）
//   · 入库**不校验也不扣减**任何库存；`MidsummerSKU` 里因此**没有** stock 字段。
//     选项永远不会因为「卖完了」而变灰——变灰只可能来自上面的第 3 条（组合不存在）。

/// 一次规格选择：`groupID -> optionID`。
nonisolated struct MidsummerSpecSelection: Hashable, Sendable {
  var picks: [String: String]

  init(picks: [String: String] = [:]) {
    self.picks = picks
  }

  static let empty = MidsummerSpecSelection()

  subscript(groupID: String) -> String? {
    get { picks[groupID] }
    set {
      if let newValue {
        picks[groupID] = newValue
      } else {
        picks.removeValue(forKey: groupID)
      }
    }
  }
}

nonisolated enum MidsummerSpecResolver {

  // MARK: - 基础读取

  /// 有效的规格组：过滤掉没有任何选项的空组（创作者漏填时不该渲染出一个空标题）。
  static func groups(of item: MidsummerItemDTO) -> [MidsummerSpecGroup] {
    (item.specGroups ?? []).filter { !$0.options.isEmpty }
  }

  static func skus(of item: MidsummerItemDTO) -> [MidsummerSKU] {
    item.skus ?? []
  }

  /// 该单品是否有规格可选。`false` 时详情页不弹规格面板，直接入库。
  static func hasSpecs(_ item: MidsummerItemDTO) -> Bool {
    !groups(of: item).isEmpty
  }

  static func option(_ optionID: String, in group: MidsummerSpecGroup) -> MidsummerSpecOption? {
    group.options.first { $0.id == optionID }
  }

  // MARK: - 默认选择

  /// 默认选择：优先用 SKU 表的第一条（那是创作者标注的主推组合），
  /// 没有 SKU 表时退化为「每组第一项」。
  static func defaultSelection(of item: MidsummerItemDTO) -> MidsummerSpecSelection {
    let groups = groups(of: item)
    guard !groups.isEmpty else { return .empty }

    if let firstSKU = skus(of: item).first {
      var selection = MidsummerSpecSelection()
      for group in groups {
        if let picked = firstSKU.options[group.id] { selection[group.id] = picked }
      }
      if isComplete(selection, of: item) { return selection }
    }

    var selection = MidsummerSpecSelection()
    for group in groups {
      selection[group.id] = group.options.first?.id
    }
    return normalized(selection, of: item)
  }

  // MARK: - 多规格联动

  /// 选项在「其它组当前选择」的前提下是否还能组成合法组合。
  ///
  /// · 没有 SKU 表 → 恒 `true`（无约束）
  /// · 某条 SKU **没有提及**某个组 → 该组不参与这条 SKU 的约束判定
  ///   （这样「只写了颜色的 SKU」不会把尺码组整组判死）
  static func isAvailable(
    groupID: String,
    optionID: String,
    given selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> Bool {
    let table = skus(of: item)
    guard !table.isEmpty else { return true }

    return table.contains { sku in
      // 注意这里用 `if let`：SKU 没写这个组时**不构成否决**，而不是当成不匹配。
      // 早期写成 `guard sku.options[groupID] == optionID else { return false }`，
      // 结果是「只标注了颜色的 SKU 把整个尺码组灰掉」，被单测逮到。
      if let constraint = sku.options[groupID], constraint != optionID { return false }
      for (otherGroupID, picked) in selection.picks where otherGroupID != groupID {
        if let constraint = sku.options[otherGroupID], constraint != picked {
          return false
        }
      }
      return true
    }
  }

  /// 归一化：丢掉「选项已不存在」和「与其它组选择冲突」的项。
  ///
  /// 按组顺序处理，先处理的组先占位；被清掉的组会给后处理的组让出约束，
  /// 这样结果是确定的（不依赖字典遍历顺序）。
  static func normalized(
    _ selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> MidsummerSpecSelection {
    var result = MidsummerSpecSelection()
    for group in groups(of: item) {
      guard let picked = selection[group.id] else { continue }
      guard group.options.contains(where: { $0.id == picked }) else { continue }
      if isAvailable(groupID: group.id, optionID: picked, given: result, of: item) {
        result[group.id] = picked
      }
    }
    return result
  }

  /// 改选某一组后，其余组自动重新归一化。
  ///
  /// 界面里所有「点了某个选项」都必须走这里，**不要**直接改 `picks`——
  /// 否则会留下「尺码高亮着 M、但新配色并没有 M」的假选中状态。
  static func selecting(
    groupID: String,
    optionID: String,
    in selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> MidsummerSpecSelection {
    var next = selection
    next[groupID] = optionID
    return normalized(next, of: item)
  }

  /// 点击一个选项：**没选过就选中，已经选中就取消**。
  ///
  /// 使用者的要求是「选中印花后再次点击同一项应取消选中」，颜色分类与尺码同理，
  /// 并且允许一组都不选。所以三组走的是同一条规则，不存在「必选组」。
  ///
  /// 取消后同样要归一化：少了一组约束只会让组合更宽松，因此**其它组的已选不会被牵连清掉**，
  /// 使用者点掉一个尺码，不会连带把刚挑好的配色也弄丢。
  ///
  /// 注意不要写成 `selecting(...)` 加一个 if：`selecting` 恒定赋值，
  /// 取消语义必须显式 `removeValue`。
  static func toggling(
    groupID: String,
    optionID: String,
    in selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> MidsummerSpecSelection {
    var next = selection
    if selection[groupID] == optionID {
      next[groupID] = nil
    } else {
      next[groupID] = optionID
    }
    return normalized(next, of: item)
  }

  // MARK: - 必选组与标注组

  /// 参与「必选」判定的组：SKU 表为空时是全部组；否则是**至少被一条 SKU 提及**的组。
  ///
  /// 背景（价格档位组，用户 2026-09-16）：「现货价 / 预约价 / 定金 / 尾款」这类
  /// **标注组**不参与 SKU 组合（没有任何 SKU 提及它），只作为入库备注的档位标记。
  /// 它与 `isAvailable` / `matchedSKU` 的「SKU 没提及 → 不构成否决」是同一条规则
  /// 在**完整性**维度的延伸：没被 SKU 提及的组，也不该把「没选它」当成缺失——
  /// 否则使用者点掉价格档位的已选项，顶部就会因为「未选全」丢失命中 SKU 的价格。
  static func requiredGroups(of item: MidsummerItemDTO) -> [MidsummerSpecGroup] {
    let groups = groups(of: item)
    let table = skus(of: item)
    guard !table.isEmpty else { return groups }
    let mentioned = Set(table.flatMap { $0.options.keys })
    return groups.filter { mentioned.contains($0.id) }
  }

  // MARK: - 完整性

  static func isComplete(_ selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> Bool {
    let groups = groups(of: item)
    guard !groups.isEmpty else { return true }
    return requiredGroups(of: item).allSatisfy { selection[$0.id] != nil }
  }

  /// 还没选的组名，用于「请选择 尺码」这类提示。标注组（SKU 未提及）不算缺失。
  static func missingGroupNames(_ selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> [String] {
    requiredGroups(of: item)
      .filter { selection[$0.id] == nil }
      .map(\.name)
  }

  // MARK: - 展示值

  /// 命中 SKU 表里的组合：该 SKU **提及的每一组**都与当前选择一致。
  ///
  /// ⚠️ 与 `isAvailable` 是**同一条**规则：SKU 没提及的组（含没选的必选组、
  /// 标注组）不构成否决。以前这里用 `isComplete` 做闸门，多选套装入库时
  /// 「胸针（无尺码款，不写尺码）」被判不完整，命中不了自己 ¥59 的 SKU——
  /// 无尺码小物必须在未选尺码时也能命中价格，所以闸门拿掉、逐组判定。
  static func matchedSKU(_ selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> MidsummerSKU? {
    let allGroups = groups(of: item)
    guard !allGroups.isEmpty else { return nil }
    return skus(of: item).first { sku in
      // 一条约束都不写的 SKU 不构成「命中」，否则它会匹配掉所有选择。
      guard !sku.options.isEmpty else { return false }
      return allGroups.allSatisfy { group in
        guard let constraint = sku.options[group.id] else { return true }
        return constraint == selection[group.id]
      }
    }
  }

  /// 当前选择的展示图。回退链：
  ///   1. 命中 SKU 的组合图（「内搭奶白色S1粉色」这种跨组专属图）
  ///   2. 已选选项里第一个带图的（通常就是颜色分类那张）
  ///   3. 单品封面（`item.coverImage`，可能仍是 nil → 由界面渲染品牌水印占位）
  static func image(for selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> String? {
    if let skuImage = matchedSKU(selection, of: item)?.image, !skuImage.isEmpty {
      return skuImage
    }
    for group in groups(of: item) {
      guard let picked = selection[group.id],
        let option = option(picked, in: group),
        let image = option.image,
        !image.isEmpty
      else { continue }
      return image
    }
    return item.coverImage
  }

  /// 当前选择的价格：SKU 自己的价优先（逐款定价），否则沿用单品的「参考价 / 现货价」。
  /// 注意用 `primaryPrice` 而不是 `price` —— 只有尾款没有现货价的单品也得给得出数字。
  static func price(for selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> Int? {
    matchedSKU(selection, of: item)?.price ?? item.primaryPrice
  }

  /// 「¥119」；无价返回「价格待补充」，与单品卡片口径一致。
  static func priceText(for selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> String {
    guard let price = price(for: selection, of: item) else { return "价格待补充" }
    return "¥\(price)"
  }

  /// 「尾款 ¥400」/「参考价 ¥329」；命中的 SKU 没写口径时退化为裸价格。
  ///
  /// 规格抽屉的顶部价格用这个而不是 `priceText`：归集商品里同一个链接的不同款
  /// 可能一边是参考价、一边是尾款（如卢瓦尔葡萄园 3.0 的 400 / 160 都是尾款），
  /// 只显示「¥400」会让使用者按全款估预算。
  static func priceTextWithKind(
    for selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> String {
    guard let price = price(for: selection, of: item) else { return "价格待补充" }
    guard let kind = matchedSKU(selection, of: item)?.priceKind else { return "¥\(price)" }
    return "\(kind.labelZH) ¥\(price)"
  }

  /// 「Sk粉色 / M」；规格缺省时返回 nil。
  static func summary(_ selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> String? {
    let names = groups(of: item).compactMap { group -> String? in
      guard let picked = selection[group.id] else { return nil }
      return option(picked, in: group)?.name
    }
    return names.isEmpty ? nil : names.joined(separator: " / ")
  }

  /// 已选文案：
  ///   · 规格缺省 → `该单品暂无规格可选`
  ///   · 选全了   → `已选：Sk粉色 / S`
  ///   · 选了一部分 → `已选 Sk粉色 · 请选择 尺码`
  ///   · 一个都没选 → `请选择：颜色分类、尺码`
  ///
  /// 早期版本只要「至少选了一组」就回报 `已选：…`，于是使用者看到
  /// 「已选 Sk粉色」以为已经选好了，实际还差尺码——单测逮到后改成现在这样。
  static func selectionSummaryText(_ selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> String {
    if !hasSpecs(item) { return "该单品暂无规格可选" }

    let missing = missingGroupNames(selection, of: item)
    let pickedNames = summary(selection, of: item)

    if missing.isEmpty { return "已选：\(pickedNames ?? "")" }
    if let pickedNames {
      return "已选 \(pickedNames) · 请选择 \(missing.joined(separator: "、"))"
    }
    return "请选择：\(missing.joined(separator: "、"))"
  }

  // MARK: - 映射到衣橱字段

  /// 把规格选择落到衣橱的「配色 / 尺码」，并给出完整规格文案。
  ///
  /// 规则：
  ///   · `role == .color` 的组 → `colors`；没有该组时沿用单品自带配色
  ///   · `role == .size` 的组 → `sizes`；没有该组时沿用单品自带尺码
  ///   · `role == .other` 的组只进 `specText`（衣橱没有对应字段，不能硬塞进配色）
  static func wardrobeMapping(
    _ selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> (colors: String, sizes: String, specText: String?) {
    var colors: String?
    var sizes: String?

    for group in groups(of: item) {
      guard let picked = selection[group.id],
        let name = option(picked, in: group)?.name
      else { continue }
      switch group.resolvedRole {
      case .color: colors = name
      case .size: sizes = name
      // 款式与「其它」都不映射到衣橱字段（衣橱没有「款式」列），只进 specText。
      // 但款式会进**入库名称**——见 `displayName(_:selection:)`。
      case .variant, .other: break
      }
    }

    return (
      colors: colors ?? item.colors.joined(separator: ", "),
      sizes: sizes ?? item.sizes.joined(separator: ", "),
      specText: summary(selection, of: item)
    )
  }

  // MARK: - 入库名称

  /// 衣橱记录的显示名。
  ///
  /// 归集商品（一个链接含多款，如「樱花小羊」）必须把款式拼进名字，
  /// 否则 9 个款式入库后全叫「樱花小羊」，衣橱里根本分不清。
  /// 没有款式组时就是单品名本身。
  static func displayName(_ item: MidsummerItemDTO, selection: MidsummerSpecSelection) -> String {
    guard let variantGroup = groups(of: item).first(where: { $0.resolvedRole == .variant }),
      let picked = selection[variantGroup.id],
      let name = option(picked, in: variantGroup)?.name,
      !item.name.contains(name)
    else { return item.name }
    return "\(item.name) \(name)"
  }

  /// 已选款式名；无款式组返回 nil。
  static func selectedVariantName(
    _ selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> String? {
    guard let variantGroup = groups(of: item).first(where: { $0.resolvedRole == .variant }),
      let picked = selection[variantGroup.id]
    else { return nil }
    return option(picked, in: variantGroup)?.name
  }

  // MARK: - 款式名解析（类型 / 颜色 → 衣橱字段，用户 2026-09-18）

  /// 从款式名解析「类型 + 颜色」，入库时一一对应衣橱的类型 / 颜色字段。
  ///
  /// 解析规则（纯函数，供单测）：
  ///   · 先剥「现 」前缀（种子款式名如「现 sk 粉色」——「现」是现货标记，不是颜色）；
  ///   · 在剩余串里**大小写不敏感**地找分类短标，长词优先——「jsk」不能被它
  ///     内部的「sk」截胡；
  ///   · 类型 = 命中短标对应的分类；颜色 = 短标**之后**的剩余文本（剥掉
  ///     分隔符与空白）。短标前面的修饰（如「无腰」）属于款式名本身，
  ///     保留在入库名称里，不混进颜色；
  ///   · 找不到任何短标 → (nil, nil)，调用方回退单品自带值（不猜）。
  ///
  /// 例：
  ///   「sk 粉色」   → (SK, 粉色)
  ///   「无腰op粉色」 → (OP, 粉色)
  ///   「段段jsk蓝色」→ (JSK, 蓝色)
  ///   「现 sk 粉色」 → (SK, 粉色)
  ///   「库洛米」     → (nil, nil)
  static func parseVariantFields(_ raw: String) -> (type: MidsummerItemKind?, color: String?) {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("现 ") { value = String(value.dropFirst("现 ".count)) }

    let lowered = value.lowercased()
    // 长词优先：「无腰op粉色」里 "op" 命中；"jsk" 里的 "sk" 不许抢先。
    let tokens = MidsummerItemKind.allCases
      .map { $0.shortLabel.lowercased() }
      .sorted { $0.count > $1.count }

    var best: (range: Range<String.Index>, kind: MidsummerItemKind)?
    for token in tokens where !token.isEmpty {
      guard let range = lowered.range(of: token) else { continue }
      let kind = MidsummerItemKind.allCases.first {
        $0.shortLabel.lowercased() == token
      }
      guard let kind else { continue }
      if let current = best {
        // 更靠前优先；同起点时长词优先（tokens 已按长度降序，先到先得）。
        if range.lowerBound < current.range.lowerBound {
          best = (range, kind)
        }
      } else {
        best = (range, kind)
      }
    }

    guard let hit = best else { return (nil, nil) }
    var color = String(value[hit.range.upperBound...])
    // 剥颜色前的分隔符：「sk - 粉色」「op·粉色」都归一成「粉色」。
    while let first = color.first, " -—·、_/".contains(first) {
      color.removeFirst()
    }
    color = color.trimmingCharacters(in: .whitespacesAndNewlines)
    return (hit.kind, color.isEmpty ? nil : color)
  }

  /// 显式选中的颜色分类名（role == .color 的组）；没选该组返回 nil。
  ///
  /// 与 `wardrobeMapping` 的 fallback 语义区分开：入库时「用户显式选的颜色」
  /// 优先级最高，其次才是从款式名解析的颜色、单品自带配色。
  static func selectedColorName(
    _ selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> String? {
    guard let colorGroup = groups(of: item).first(where: { $0.resolvedRole == .color }),
      let picked = selection[colorGroup.id]
    else { return nil }
    return option(picked, in: colorGroup)?.name
  }

  /// 显式选中的尺码名（role == .size 的组）；没选该组返回 nil。
  static func selectedSizeName(
    _ selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> String? {
    guard let sizeGroup = groups(of: item).first(where: { $0.resolvedRole == .size }),
      let picked = selection[sizeGroup.id]
    else { return nil }
    return option(picked, in: sizeGroup)?.name
  }

  // MARK: - 价格档位选择（一键入库分阶段口径，用户 2026-09-19）

  /// 规格面板「价格档位」组的显式选择结果。
  /// 按选项**名称**识别——种子档位组与 `makeItemDTO` 自建档位组的选项 id
  /// 各不相同，但「现货价 / 预约价 / 定金 / 尾款」四个名称是统一口径。
  nonisolated enum MidsummerPriceTierPick: String, Sendable {
    case spot  // 现货价
    case preorder  // 预约价
    case deposit  // 定金
    case balance  // 尾款
  }

  /// 当前规格选择里显式选中的价格档位；没选（或组不存在）返回 nil。
  ///
  /// 注意「标注组不构成缺失」的既有规则：价格档位组不被 SKU 提及，
  /// 使用者可以一组都不选，所以 nil 是合法常态，调用方必须自带默认档。
  static func selectedPriceTier(
    _ selection: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> MidsummerPriceTierPick? {
    for group in groups(of: item) where group.resolvedRole == .other {
      guard let picked = selection[group.id],
        let name = option(picked, in: group)?.name
      else { continue }
      switch name {
      case "现货价": return .spot
      case "预约价": return .preorder
      case "定金": return .deposit
      case "尾款": return .balance
      default: continue
      }
    }
    return nil
  }

  // MARK: - 多选套装入库

  /// 多选配一套（用户 2026-09-16）：为某个**已勾选**的款式选项生成单品级选择。
  ///
  /// 场景：粉色 SK 的 S 码 + 开衫 + 胸针配成一套 → 多选这些款式后一次入库，
  /// 每个勾选项各落一条衣橱记录，凭共同的套装标记归为同一套。
  ///
  /// 其余组的勾选是否带上这条单品级选择，按两条规则：
  ///   · **必选组**（尺码等）：只有该款式存在提及该组的 SKU 才沿用——
  ///     小物/胸针这类无尺码款不该把「S码」写进它的记录；
  ///   · **标注组**（价格档位等，`requiredGroups` 之外）：SKU 从不提及，
  ///     恒定沿用——档位备注对套装里每一件都成立。
  static func perVariantSelection(
    for variantOptionID: String,
    base: MidsummerSpecSelection,
    of item: MidsummerItemDTO
  ) -> MidsummerSpecSelection {
    let allGroups = groups(of: item)
    guard let variantGroup = allGroups.first(where: { $0.resolvedRole == .variant }),
      variantGroup.options.contains(where: { $0.id == variantOptionID })
    else { return base }

    var selection = MidsummerSpecSelection()
    selection[variantGroup.id] = variantOptionID
    let requiredIDs = Set(requiredGroups(of: item).map(\.id))
    let table = skus(of: item)

    for group in allGroups where group.id != variantGroup.id {
      guard let picked = base[group.id] else { continue }
      let mentionedByVariant = table.contains { sku in
        sku.options[variantGroup.id] == variantOptionID && sku.options[group.id] != nil
      }
      let isAnnotationGroup = !requiredIDs.contains(group.id)
      if mentionedByVariant || isAnnotationGroup {
        selection[group.id] = picked
      }
    }
    return selection
  }
}
