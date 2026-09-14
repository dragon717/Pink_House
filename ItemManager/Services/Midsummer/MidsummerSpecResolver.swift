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

  // MARK: - 完整性

  static func isComplete(_ selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> Bool {
    let groups = groups(of: item)
    guard !groups.isEmpty else { return true }
    return groups.allSatisfy { selection[$0.id] != nil }
  }

  /// 还没选的组名，用于「请选择 尺码」这类提示。
  static func missingGroupNames(_ selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> [String] {
    groups(of: item)
      .filter { selection[$0.id] == nil }
      .map(\.name)
  }

  // MARK: - 展示值

  /// 命中 SKU 表里的**完整**组合（缺组或组合不存在都返回 nil）。
  ///
  /// ⚠️ 与 `isAvailable` 必须是**同一条**规则：SKU 没提及的组不参与匹配。
  /// 归集商品里「小物」这类款本来就**没有尺码**（它的 SKU 只有款式 + 颜色），
  /// 早期这里要求每组都对上，结果小物永远命中不了自己的 SKU，
  /// 明明写了价却退回「价格待补充」——和 `isAvailable` 的口径自相矛盾。
  static func matchedSKU(_ selection: MidsummerSpecSelection, of item: MidsummerItemDTO) -> MidsummerSKU? {
    let groups = groups(of: item)
    guard !groups.isEmpty, isComplete(selection, of: item) else { return nil }
    return skus(of: item).first { sku in
      // 一条约束都不写的 SKU 不构成「命中」，否则它会匹配掉所有选择。
      guard !sku.options.isEmpty else { return false }
      return groups.allSatisfy { group in
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
}
