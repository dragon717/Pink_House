//
//  ShopCatalogChartPresentation.swift
//  ItemManager
//
//  商品详情「尺码表 / 预约价格表」两张图表卡的展示决策唯一口径。
//
//  ## 为什么需要这个文件（2026-09-23 根因修复）
//
//  事故形态：尺码表原图在商品详情页**永远不显示**，而价格表原图正常内嵌。
//  用户看不到尺码表图，页面上唯一能看见的图表图是价格表的 —— 于是一并报成
//  「尺码图不显示，或者错误显示为价格图」。
//
//  根因不在数据（迁移产物里 24 张尺码表的 columns/rows/sourceImage 都齐全），
//  而在**展示层两张卡各写各的分支**：
//    · 价格表卡：`priceChartImageSection(sourceRef)` —— 原图内嵌渲染；
//    · 尺码表卡：只有 `if hasStructuredContent { 表格 }`，**没有任何图片分支**，
//      原图只能通过「查看原尺码表 >」进全屏查看器才能看到。
//
//  而模型自己的契约写得很清楚（`CatalogSizeChart.hasStructuredContent` 注释）：
//    「只有原图时为 false，此时商品详情**仅展示原图**」
//  —— 展示层没有兑现这条契约，也没有兑现方案 §15「尺码表卡：结构化表格 + 原始图」。
//
//  修法不是给尺码表卡补一个 if，而是把「这张卡该展示什么」抽成**同一个纯函数**，
//  两张卡都只允许消费同一个 `Plan`：决策同源，两张卡就不可能再各偏一边。
//  nonisolated 纯逻辑，可单测（见 ShopCatalogChartPresentationTests）。
//
//  ## 第二层：尺码表原图的**折叠/展开**（Request D）
//
//  用户反馈：尺码表原图直接铺在详情页里，占满大半屏、且不点不知道有多长。
//  要求「默认收起，仅留一个可点击入口，点开看完整内容，再点/关闭可收起」。
//
//  折叠状态同理不能让视图自己 `if` 拼：`ShopCatalogChartDisclosure` 由
//  `Plan.image` + 展开标记 推导出「入口形态 / 是否渲染图 / 是否渲染丢失警示」，
//  仍然 nonisolated 纯逻辑，可单测。**折叠只决定「什么时候给用户看」，
//  绝不改变「内容是否存在」**——`Plan.isEmpty` 的判定不受折叠影响。
//

import Foundation

// MARK: - 价格表多图录入文本口径（2026-09-24 需求）

/// 价格表多图的录入/回填文本承载：**每行一个引用**（与商品图片多行文本同交互）。
/// 上传按钮按行追加「local:文件名」，编辑页 onAppear 把 sourceImages 按行回填，
/// 落库时按行拆回列表 —— 拆分口径只有这一份，录入端与测试共用。
nonisolated enum CatalogPriceChartImageText {
    static func references(fromText text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - 引用解析（sourceImage 的两种合法口径）
/// `sizeChart.sourceImage` / `priceChart.sourceImage` 的引用解析。
///
/// 同一个字段在仓库里确实存在两种合法写法，**都必须支持**：
///   · **CatalogAsset id**（模型注释的约定，迁移脚本产物）→ 需经 assets 表拿 originalURL；
///     例：`ms-asset-9178173883a7-45efeb67a7` → `seed-sakura-chart-sk.jpg`
///   · **文件名 / `local:` / `http(s)`**（运营端手填或上传产物）→ 原样交给图片解析器
///     例：`local:img-1a2b3c4d.jpg`、`seed-sakura-chart-sk.jpg`
///
/// 判定顺序：先按 asset id 查表，查到且 originalURL 非空就用它；否则原样返回。
/// 两者都不是时返回 nil（无可展示引用）。
nonisolated enum ShopCatalogChartReference {

    static func resolve(_ raw: String?, assetURL: (String) -> String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        if let mapped = assetURL(trimmed)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !mapped.isEmpty {
            return mapped
        }
        return trimmed
    }
}

// MARK: - 展示决策

/// 图表卡的展示计划：**尺码表与价格表共用同一套判定**。
nonisolated enum ShopCatalogChartPresentation {

    /// 原图状态
    enum ImageState: Equatable {
        /// 没有原图引用
        case none
        /// 有引用且能解析出本地/远程图 → 内嵌渲染
        case ready(reference: String)
        /// 有引用但解析不到文件（沙盒重置丢了 local:、Bundle 找不到等）→ 明确提示
        case unavailable(reference: String)
    }

    struct Plan: Equatable {
        /// 是否渲染结构化表格
        var showsTable: Bool
        /// 原图状态
        var image: ImageState

        /// 整张卡是否「什么都没有」——此时才该提示「暂无数据」。
        /// 注意：**只有原图**也算有内容（模型契约：仅展示原图），不得报「暂无」。
        var isEmpty: Bool {
            !showsTable && image == .none
        }
    }

    /// 由「有无结构化内容 + 已解析的引用 + 引用可用性」推导展示计划。
    ///
    /// - Parameters:
    ///   - hasStructuredContent: columns 与 rows 是否都非空
    ///   - reference: 已过 `ShopCatalogChartReference.resolve` 的引用（nil = 无图）
    ///   - isImageUnavailable: 引用可用性判定（生产注入 `ShopCatalogImageResolver.isUnavailable`）
    static func plan(hasStructuredContent: Bool,
                     reference: String?,
                     isImageUnavailable: (String) -> Bool) -> Plan {
        guard let reference else {
            return Plan(showsTable: hasStructuredContent, image: .none)
        }
        let image: ImageState = isImageUnavailable(reference)
            ? .unavailable(reference: reference)
            : .ready(reference: reference)
        return Plan(showsTable: hasStructuredContent, image: image)
    }
}

// MARK: - 折叠/展开（尺码表原图，Request D）

/// 尺码表原图的折叠交互口径。
///
/// 需求原文：默认收起（隐藏），**仅显示一个可点击的触发入口**；点击入口展开完整原图，
/// 再次点击或通过关闭操作收起；展开/收起切换流畅、状态明确，兼顾桌面端与移动端。
///
/// 由此推出三条不可动摇的规则，全部体现在 `plan(image:isExpanded:)` 里：
/// 1. **默认收起**：`isExpanded == false` 时 `showsImage` 必为 false，调用方不需要
///    自己记默认值——视图只持有用户意图，形态一律由这里推导。
/// 2. **收起态只有一个入口**：`trigger` 是唯一可点项。所以原先头部那个
///    「查看原尺码表 >」（直接进全屏查看器）不再与入口并列存在，否则收起态会出现
///    两个可点目标，违反「仅显示一个触发入口」。全屏查看改由「展开 → 点图片」到达。
/// 3. **丢失警示不折叠**：`.unavailable` 是「图登记过但文件没了」的**待办提示**，
///    不是图片内容。若也折叠起来，用户不点入口就永远不知道要重新上传 → 始终直出。
///
/// 注意：本类型只回答「什么时候给用户看」，不回答「有没有内容」。
/// 「有没有内容」永远由 `ShopCatalogChartPresentation.Plan.isEmpty` 回答，
/// 折叠状态的切换不得影响它。
nonisolated enum ShopCatalogChartDisclosure {

    /// 折叠入口的形态。文案由视图本地化，纯逻辑不持有 copy。
    enum Trigger: Equatable {
        /// 无入口（没有原图，或只有无需折叠的警示）
        case none
        /// 可展开：`isExpanded == false` 且存在可展示原图
        case expand
        /// 可收起：`isExpanded == true` 且存在可展示原图
        case collapse
    }

    struct Plan: Equatable {
        var trigger: Trigger
        /// 是否渲染原图（收起态恒为 false）
        var showsImage: Bool
        /// 是否渲染「原图文件已丢失，请重新上传」警示（不受折叠状态影响）
        var showsMissingHint: Bool

        /// 收起态唯一入口是否可见
        var showsTrigger: Bool { trigger != .none }
    }

    /// 由原图状态 + 用户展开意图推导折叠计划。
    ///
    /// - Parameters:
    ///   - image: 来自 `ShopCatalogChartPresentation.Plan.image`
    ///   - isExpanded: 用户当前的展开意图（视图 `@State`；默认必须传 false）
    static func plan(image: ShopCatalogChartPresentation.ImageState,
                     isExpanded: Bool) -> Plan {
        switch image {
        case .none:
            // 没有原图 → 没有入口可点，也不该出现空的白框
            return Plan(trigger: .none, showsImage: false, showsMissingHint: false)
        case .unavailable:
            // 待办提示：不折叠、不给展开入口（没有图可展开）
            return Plan(trigger: .none, showsImage: false, showsMissingHint: true)
        case .ready:
            return Plan(trigger: isExpanded ? .collapse : .expand,
                        showsImage: isExpanded,
                        showsMissingHint: false)
        }
    }
}
