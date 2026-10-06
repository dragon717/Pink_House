//
//  CatalogChartTemplate.swift
//  SharedCatalog
//
//  **标准模板**（尺码表 / 预约价格表）—— 「照抄就能过」的那一份。
//
//  ## 为什么值得进共享包
//
//  1. 它是**纯文本**，没有平台依赖，放这里两端都能用；
//  2. 放这里才能在 `swift test` 里**秒级验证**「模板还能过识别吗」——
//     Mac 的 App 宿主式测试在本机跑不起来（`xcodebuild test` 挂起，
//     取证见 skill `pink-house-xcodebuild-acceptance`），模板的格式契约要是只写在 Mac 侧，
//     就没人能自动证明它没坏；
//  3. 界面上的「用标准模板填入」与回归测试**读同一份常量**，
//     所以「模板内容」与「模板是否有效」永远只有一个答案。
//
//  ## 两张表共同必须遵守的三条（回归锁在 `CatalogChartTemplateTests`）
//
//    · 「列名」**只写数据列** —— 「尺码 / 款式」是行标签列，写进去会被剔除；
//    · 每行 `= ` 右边的**值个数 == 数据列个数**，分隔符一律**半角逗号**；
//    · 行标签**不与任何列名重名**（重名会被门禁判成「行列可能错位」而整份拒绝）。
//
//  ## ⚠️ 价格表**不是**「数量 × 单价」的账单表
//
//  本应用的价格表是**每个款式的价格表**（系列级，整个系列共用一张）：
//  一行 = 一个款式，列 = 该款式的各个价格口径（预约价 / 定金 / 尾款 / 现货价）。
//  所以**没有**「数量」「金额」两列 —— 数量由用户加购时选择，金额由应用按价格口径算，
//  录进表格里只会和真实交易对不上。
//  需要留话时直接**加一列**（`columns` 是自由文本），例如末尾加「备注」，
//  只要每行的值个数跟着一致即可（回归锁里有这一形态）。
//
//  ⚠️ 改这里的任何一行，都要跑 `Packages/SharedCatalog` 的 `swift test`。
//

import Foundation

public enum CatalogChartTemplate {

    /// 尺码表模板（7 个数据列 × 5 行）。
    public enum SizeChart {

        public static let unit = "cm"

        /// 只写数据列：「尺码」是行标签列（渲染时占最左边那一列），不写进列名。
        public static let columnsText = "后衣长, 胸围, 腰围, 肩宽, 袖长, 袖口, 领围"

        /// 每行 `尺码 = 值1, 值2, …`：值个数与数据列一样多（这里都是 7）。
        public static let rowsText = """
        XS = 49, 85, 70, 33, 20, 26, 42
        S = 50, 89, 74, 34, 20.5, 27, 42
        M = 51, 93, 78, 35, 21, 28, 43
        L = 52, 97, 82, 36, 21.5, 29, 44
        XL = 53, 101, 86, 37, 22, 30, 45
        """

        /// 行标签（按原始顺序）—— 颜色 SKU 的可售尺码勾选项从这里派生。
        public static let sizeLabels = ["XS", "S", "M", "L", "XL"]

        /// 首行样例 —— 界面上的「每一行一条：…」直接读它。
        ///
        /// ⭐ 提示与模板**同源**是硬要求：2026-10-01 的报障里，
        /// Mac 价格表的 placeholder 举例 4 列、下面「每一行」提示却写 3 列，
        /// 两句话互相矛盾，用户照哪一句填都可能失败。
        public static var sampleRowText: String { CatalogChartTemplate.firstRow(of: rowsText) }
    }

    /// 预约价格表模板（4 个数据列 × 3 行）。
    ///
    /// 列的选择对齐领域模型（`OpsSeriesEntryDraft` 文件头）：
    ///   · 预约价 + 定金 + 尾款 = 一条 reservation 型销售记录；
    ///   · 现货价 = 一条 stock 型销售记录，与预约价**互相独立**（不覆盖、不二选一）。
    /// 所以这四列就是「一个款式一共要知道的几个价格」，不多不少。
    public enum PriceChart {

        /// ⚠️ 价格表的「单位」是**金额单位**（展示为「单位：元」）。
        /// 尺码表那边的 `cm` 是长度单位，两者不可混用 ——
        /// Mac 价格表卡片原先的 placeholder 写的是「如 cm / inch」，是从尺码表抄过来的。
        public static let unit = "元"

        /// 只写数据列：「款式」是行标签列（渲染时占角落那一列），不写进列名。
        public static let columnsText = "预约价, 定金, 尾款, 现货价"

        /// 每行 `款式 = 值1, 值2, …`：值个数与数据列一样多（这里都是 4）。
        ///
        /// ⚠️ 示例数字满足应用自己的价格口径 **定金 + 尾款 == 预约价**
        /// （91+227=318、80+188=268、87+352=439）——
        /// 用户多半会直接改数字，模板自己先给出自洽的一组，免得照着填出自相矛盾的价格。
        public static let rowsText = """
        大蝴蝶结背心裙 = 318, 91, 227, 368
        蝴蝶结半裙 = 268, 80, 188, 308
        美乐蒂背带 = 439, 87, 352, 489
        """

        /// 行标签（按原始顺序）—— 即每个款式名。
        public static let rowLabels = ["大蝴蝶结背心裙", "蝴蝶结半裙", "美乐蒂背带"]

        /// 首行样例 —— 界面上的「每一行：…」直接读它（与模板同源，见 `SizeChart.sampleRowText`）。
        public static var sampleRowText: String { CatalogChartTemplate.firstRow(of: rowsText) }

        /// 「想加一列备注」的扩展形态：列名是**自由文本**，加在末尾即可。
        /// 只要求每行值个数跟着一致（回归锁里验证它同样能过）。
        public static let extendedColumnsText = columnsText + ", 备注"

        public static let extendedRowsText = """
        大蝴蝶结背心裙 = 318, 91, 227, 368, 含手工发饰
        蝴蝶结半裙 = 268, 80, 188, 308, 预定款
        美乐蒂背带 = 439, 87, 352, 489, 现货充足
        """
    }

    /// 多行文本的首行（去掉空行）。界面提示与模板同源时用它，避免两处各写一份样例。
    public static func firstRow(of text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false)
        where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
}
