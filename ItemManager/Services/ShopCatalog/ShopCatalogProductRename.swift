//
//  ShopCatalogProductRename.swift
//  ItemManager
//
//  「商品改名」唯一口径（2026-09-24 需求：修改名称后，相关信息未发生任何变化）。
//
//  ── 事故复盘（用户三张截图，一步步可复现）────────────────────────────────
//    ① 商品管理页（系列「蜜糖邦尼兔联名系列」）长按「背心裙 [黄色]」这一颜色行 →
//       菜单「编辑基础（名称/分类）」；
//    ② 「编辑商品」弹窗把名称改成「黄色蜜糖邦尼背心裙」→ 保存，提示「已更新商品…」；
//    ③ **点菜式选购页的卡片标题依然是「背心裙」**，商品管理里的款式行标题也没变
//       —— 看起来「改名没生效」。
//
//  ── 根因（两处叠加，缺一不可）──────────────────────────────────────────
//    1. **展示侧只认款式名**（`ShopCatalogTitlePresentation.swift` 收口口径 1）：
//       所有标题都走 `ShopCatalogTitleResolver` → `ShopCatalogSameDesignGrouper.designName(of:)`
//       = 「显式 `designName` 优先，否则按 `name` 剥离颜色词派生」。
//    2. **写入侧从不改款式名**：发布路径无条件写
//       `designName = resolveDesignName(explicit:name:)`，而 `resolveDesignName`
//       **永不返回 nil**（`baseName(for:)` 识别不出颜色词时兜底回退整名）。
//       于是发布之后 `designName` 恒为非空显式值 → **`name` 被永久遮蔽**：
//       改名只会写进一个没有任何界面读的字段。
//       两条写入路径（`upsertEntity`「基础编辑」/ `updatePublishedProduct`「深度编辑」）
//       都只写 `name` + `category`，**没有一个字节碰 `designName`**。
//
//  ── 收口结论：改名 = 款式（SPU）级操作，一次落盘、整款生效 ──────────────
//    1. 款式名由新名称**派生**（`baseName(for:)` 剥离颜色词），与录入端
//       「`draft.name = 颜色 + 款式名`」（`ShopCatalogStyleEntryView`）同一套口径；
//       所以「名称」字段继续是**完整 SKU 名**（用户截图里填的正是「黄色蜜糖邦尼背心裙」），
//       而各界面标题显示的是剥掉颜色词的款式名 —— 这是既有硬规则，不是本次新引入。
//    2. **扇出到同款全部颜色**：`designName` 是款式身份
//       （`designKey` = 品类|款式名，`ShopCatalogSameDesignGrouper.designKey`），
//       只改被点中的那一个颜色会把「2 色一款」**当场拆成两个单色款**，并让尺码表
//       （`ShopCatalogSizeChartSharing.designScope`）与款式档案
//       （`ShopCatalogStyleProfileSharing.styleKey`）的共享范围一起断链。
//    3. 兄弟颜色的名字做**定向替换**（旧款名 → 新款名），颜色词与其所在位置原样保留；
//       旧名里找不到旧款名（历史脏数据）时，保住颜色词再拼新款名。
//    4. **分类一起走**：`designKey` 含品类，品类也是款式级属性 ——
//       只改一个颜色的品类同样会拆组，所以整款跟着改。
//    5. 款式档案 `CatalogStyleProfile` 的 `id` **就是**款式键（系列|品类|款式名），
//       改名后必须**整体改键**（删旧 id + 写新 id），否则面料 / 款式描述变孤儿
//       —— 界面上表现为「改个名字，面料突然空白了」。
//    6. 尺码表本身**不需要迁移**：它的行按 `productID` 存，共享范围由款式键现算；
//       只要整款一起改，款式键仍是同一个等价类，范围自然跟着走。
//       ⚠️ 但写入时必须**先把整款写进覆盖层、再算范围**，否则范围里只有自己一个颜色。
//    7. 衣橱 / 心愿记录**不跟着改**：它们是加入时的名字快照，属于
//       `ShopCatalogTitlePresentation.swift` 口径 3 的刻意例外，而且 `Clothing`
//       是按 `catalogProductID` 引用商品的（改名不断链）。改名必须**如实告知**
//       有多少条这种记录，不许静默。
//

import Foundation

// MARK: - 改名计划

nonisolated enum ShopCatalogProductRename {

    /// 款式档案改键产物（`id` 就是款式键，只能整体替换，不能原地改）
    struct StyleProfilePlan: Equatable {
        /// 要删掉的旧档案 id（旧款式键）
        var removals: [String] = []
        /// 改键后的档案（0 或 1 条；旧档为空则不写空壳）
        var upserts: [CatalogStyleProfile] = []
    }

    /// 一次改名的完整写入计划。**预检（弹窗文案）与执行共用这一份**，
    /// 不允许界面上另算一套 —— 那正是「弹窗说改 2 色、实际只改 1 色」的来源。
    struct Plan: Equatable {
        /// 改名前的款式名（文案 / 断言用）
        let designNameBefore: String
        /// 改名后的款式名：进入 `designName`，也是各处标题**将要显示的文字**
        let designNameAfter: String
        let categoryBefore: String
        /// 改名后的品类（整款统一）
        let categoryAfter: String
        /// 要写回的商品：**第 1 个恒为被编辑的那一个**，其余是同款兄弟颜色
        let products: [CatalogProduct]
        /// 兄弟颜色数量（不含本人）
        let siblingCount: Int
        /// 款式档案改键产物
        let styleProfile: StyleProfilePlan

        /// 整款颜色数（含被编辑的那一个）
        var totalColorCount: Int { products.count }
        /// 款式名是否真的变了（没变就不必动款式档案，避免无谓改键）
        var changesDesignName: Bool { designNameBefore != designNameAfter }
        /// 品类是否真的变了
        var changesCategory: Bool { categoryBefore != categoryAfter }
        /// 是否是空操作（名字与品类都没变）
        var isNoop: Bool { !changesDesignName && !changesCategory }
    }

    // MARK: - 计划生成

    /// 生成改名计划（唯一入口）。
    ///
    /// - Parameters:
    ///   - edited: **已经带好新名称 / 新品类**的那一份商品。除 `name` / `category` 外的
    ///     字段（图片、描述、价格修正…）由它原样带进计划的第一项，所以深度编辑路径
    ///     刚算好的图片绑定不会被改名覆盖掉。
    ///   - stored: **改名前的基准**。款式名取自它，「名称是否被改动」也以它为参照
    ///     —— 这一点必须有独立的入参：深度编辑页传进来的 `edited` 里 `name` 已经是新值，
    ///     拿它自己跟自己比，「改了名」会被误判成「没改名」。
    ///   - allProducts: 同系列**全部**商品（合并视图，含居住在只读种子里的颜色）。
    ///     只传覆盖层会漏掉同款的颜色，扇出就会退化成「只改自己」。
    ///   - profiles: 现有款式档案（合并视图）；用于把旧键档案改键到新键。
    static func plan(edited: CatalogProduct,
                     basedOn stored: CatalogProduct,
                     among allProducts: [CatalogProduct],
                     profiles: [CatalogStyleProfile] = [],
                     now: Date = Date()) -> Plan {
        let designBefore = ShopCatalogSameDesignGrouper.designName(of: stored)
        let categoryBefore = stored.category

        let trimmedName = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? stored.name : trimmedName
        // 款式名 = 名称剥离颜色词。
        //
        // ⚠️ 名称**没被改动**时一律沿用现有款式名，不重新派生：存量数据里存在
        // 「款式名 ≠ 名称剥离颜色词」的显式指定（例如名称「粉色款」+ 款式名「花花款」），
        // 重新派生会把这类人工命名**无声改掉**。深度编辑页只改了图片 / 尺码表时
        // 走的正是这条分支 —— 不动名称就不该动款式名。
        let designAfter = resolvedName == stored.name
            ? designBefore
            : ShopCatalogSameDesignGrouper.baseName(for: resolvedName)

        let trimmedCategory = edited.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryAfter = trimmedCategory.isEmpty ? categoryBefore : trimmedCategory

        // 同款范围按**改名之前**的款式键取（品类 + 款式名），含已归档：
        // 归档颜色若留在旧款名上，等它被复活时就会把一款拆成两款。
        let siblings = allProducts.filter { candidate in
            candidate.id != stored.id
                && candidate.seriesID == stored.seriesID
                && candidate.category == categoryBefore
                && ShopCatalogSameDesignGrouper.designName(of: candidate) == designBefore
        }

        var head = edited
        head.name = resolvedName
        head.category = categoryAfter
        head.designName = designAfter

        let renamedSiblings = siblings.map { sibling -> CatalogProduct in
            var migrated = sibling
            migrated.name = renamedName(oldName: sibling.name,
                                       designBefore: designBefore,
                                       designAfter: designAfter)
            migrated.category = categoryAfter
            migrated.designName = designAfter
            return migrated
        }

        return Plan(designNameBefore: designBefore,
                    designNameAfter: designAfter,
                    categoryBefore: categoryBefore,
                    categoryAfter: categoryAfter,
                    products: [head] + renamedSiblings,
                    siblingCount: renamedSiblings.count,
                    styleProfile: styleProfilePlan(seriesID: stored.seriesID,
                                                   designBefore: designBefore,
                                                   designAfter: designAfter,
                                                   categoryBefore: categoryBefore,
                                                   categoryAfter: categoryAfter,
                                                   profiles: profiles,
                                                   now: now))
    }

    /// 便捷入口（界面弹窗用）：直接给「新名称 / 新品类」，基准 = 原商品。
    ///
    /// - Parameters:
    ///   - product: 改名前的商品（`name` / `category` / `designName` 都是旧值）
    ///   - newName: 用户在「名称」里填的**完整 SKU 名**（可含颜色词，如「黄色蜜糖邦尼背心裙」）。
    ///     空串 = 不改名（只改品类）。
    ///   - newCategory: 新品类；空串 = 不改品类。
    static func plan(product: CatalogProduct,
                     newName: String,
                     newCategory: String,
                     among allProducts: [CatalogProduct],
                     profiles: [CatalogStyleProfile] = [],
                     now: Date = Date()) -> Plan {
        var edited = product
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { edited.name = trimmedName }
        let trimmedCategory = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCategory.isEmpty { edited.category = trimmedCategory }
        return plan(edited: edited, basedOn: product, among: allProducts,
                    profiles: profiles, now: now)
    }

    /// 名字里的颜色词（识别不出 → nil）。**不含**「回退整名」的兜底 ——
    /// 与 `ShopCatalogColorPresentation.derivedLabel(forName:)` 的区别：那个口径要求
    /// 「剥离后必须与原名不同」，因此名字**恰好就是一个颜色词**时它会返回 nil
    /// （对「这个名字还能不能当颜色标签用」是正确的，对「改名时别把颜色弄丢」不是）。
    static func colorWord(in name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ShopCatalogSameDesignGrouper.colorWords.first { trimmed.contains($0) }
    }

    // MARK: - 兄弟颜色的名字

    /// 兄弟颜色改名：把名字里的**旧款名**换成新款名，颜色词及其位置原样保留。
    ///
    /// 「粉色背心裙」+ (背心裙 → 蜜糖邦尼背心裙) = 「粉色蜜糖邦尼背心裙」；
    /// 旧名里找不到旧款名（历史脏数据 / 名字就是颜色词本身）时，保住颜色词再拼新款名。
    static func renamedName(oldName: String, designBefore: String, designAfter: String) -> String {
        let old = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !designBefore.isEmpty else { return old }
        guard designBefore != designAfter else { return old }

        if old.contains(designBefore) {
            return old.replacingOccurrences(of: designBefore, with: designAfter)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 旧名里没有旧款名：用颜色词兜住「这一条是哪个颜色」
        if let color = colorWord(in: old) {
            return "\(color)\(designAfter)"
        }
        return designAfter
    }

    // MARK: - 款式档案改键

    /// 款式档案改键计划。
    ///
    /// 款式档案的 `id` **就是**款式键（`seriesID|category|designName`），所以改名不是
    /// 「改个字段」而是「换主键」：必须删旧 id + 写新 id，否则读取侧
    /// （`ShopCatalogStyleProfileSharing.profile(for:among:profiles:)` 按键命中）
    /// 再也找不到它，界面上就是「改完名字，面料 / 款式描述不见了」。
    ///
    /// 空档案（面料与描述都空）只删不写 —— 与 `writePlan` 的「不留空壳行」同口径。
    private static func styleProfilePlan(seriesID: String,
                                         designBefore: String,
                                         designAfter: String,
                                         categoryBefore: String,
                                         categoryAfter: String,
                                         profiles: [CatalogStyleProfile],
                                         now: Date) -> StyleProfilePlan {
        guard designBefore != designAfter || categoryBefore != categoryAfter else {
            return StyleProfilePlan()
        }
        let oldKey = ShopCatalogStyleProfileSharing.styleKey(seriesID: seriesID,
                                                            category: categoryBefore,
                                                            designName: designBefore)
        // 旧款式的档案行：按字段比对（款式键就是这三个字段拼出来的），
        // 同时并上「按旧键算出来的 id」—— 存量里可能有 id 与字段不完全对得上的脏行
        let existing = profiles.filter {
            $0.id == oldKey
                || ($0.seriesID == seriesID && $0.category == categoryBefore
                    && $0.designName == designBefore)
        }
        guard !existing.isEmpty else { return StyleProfilePlan() }

        var plan = StyleProfilePlan(removals: Array(Set(existing.map(\.id))).sorted())
        // 取最后一条（与读取侧「取最后一条即为最新」同口径）作为迁移源
        guard let source = existing.last, !source.isEmpty else { return plan }

        let newKey = ShopCatalogStyleProfileSharing.styleKey(seriesID: seriesID,
                                                            category: categoryAfter,
                                                            designName: designAfter)
        if let target = profiles.last(where: { $0.id == newKey }) {
            // 目标键上已有档案（改成与另一款同名 → 两者在数据上已是同一款）：
            // **以目标档案为准，只补它缺的字段** —— 无损、且结果唯一，
            // 不会留下两条同键行让读取侧的「取最后一条」变成随机胜负
            var merged = target
            if merged.fabric == nil { merged.fabric = source.fabric }
            if merged.styleDescription == nil { merged.styleDescription = source.styleDescription }
            merged.updatedAt = now
            plan.upserts = [merged]
        } else {
            var migrated = source
            migrated.id = newKey
            migrated.category = categoryAfter
            migrated.designName = designAfter
            migrated.updatedAt = now
            plan.upserts = [migrated]
        }
        return plan
    }

    // MARK: - 弹窗预览文案（让用户看见结果，不许静默）

    /// 弹窗里的结果预览。改名前把「款式名会变成什么、影响几个颜色、
    /// 面料等公共资料会跟着迁移」讲清楚 —— 用户截图里的困惑正是「改完什么都没变」，
    /// 而真实规则是「标题只显示款式名（不含颜色词）」，这两件事必须让他提前看到。
    ///
    /// 返回 nil 表示无话可说（名称为空且品类没变），此时弹窗不显示 message。
    static func previewText(_ plan: Plan, typedName: String) -> String? {
        var lines: [String] = []

        if plan.changesDesignName {
            lines.append("款式名：\(plan.designNameBefore) → \(plan.designNameAfter)")
        } else {
            lines.append("款式名不变：\(plan.designNameAfter)")
        }
        if plan.changesCategory {
            lines.append("品类：\(plan.categoryBefore) → \(plan.categoryAfter)")
        }
        if plan.siblingCount > 0 {
            lines.append("同款其余 \(plan.siblingCount) 个颜色一并更新（整款共 \(plan.totalColorCount) 色）")
        }
        if !plan.styleProfile.upserts.isEmpty {
            lines.append("款式公共资料（面料 / 款式描述）随款式名一起迁移")
        }

        // 标题不含颜色词是既有硬规则；这条提示把「颜色从哪来」讲明白
        let trimmed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let color = ShopCatalogColorPresentation.derivedLabel(forName: trimmed) {
                lines.append("颜色标签：\(color)（标题文字不含颜色）")
            } else {
                lines.append("⚠️ 新名称里没有颜色词，该商品将不再显示颜色标签")
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// 保存成功后的提示尾巴：如实说明衣橱 / 心愿记录的名字是**快照**、不跟着改。
    /// - Parameter referencedRecordCount: 引用了本次改名商品的衣橱 / 心愿记录条数
    static func referenceNote(referencedRecordCount: Int) -> String? {
        guard referencedRecordCount > 0 else { return nil }
        return "；已加入衣橱 / 心愿的 \(referencedRecordCount) 条记录保留加入时的名字（可在衣橱内单独改）"
    }
}
