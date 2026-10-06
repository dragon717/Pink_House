//
//  CatalogChartRecognitionCardSnapshotTests.swift
//  ItemManagerTests
//
//  2026-10-01 需求第四条「该识别功能最终需要在手机端以**可视化的板块形式**展示出来，
//  请确保移动端的**显示效果完整、适配良好**」的**视觉取证**。
//
//  ## 为什么用离屏快照，而不是 UI 测试
//
//  承载这个板块的两个入口（批次详情的一站式系列配置 / 补录草稿编辑器）
//  都挂在「运营工具」下面，而该入口自 2026-09-25 起只对
//  `creatorAccess.isWhitelistedCreator` 渲染（当时从 `isCreator` 收紧：本机的
//  「创作者模式」调试开关不再能撬开它，**未登录 iCloud = 不算白名单**）。
//  模拟器里没有 iCloud 登录 ⇒ 整条 UI 路径不可达，与本次改动无关。
//  （`ItemManagerUITests/ShopCatalogChartRecognitionUITests.swift` 因此会在入口处
//   `XCTSkip`，它在有白名单身份的机器/真机上仍可跑。）
//
//  快照法还多一个好处：能把**适配变量**显式钉住 —— 宽度、动态字体 —— 这正是
//  「适配良好」这句话的唯一可验证含义。
//
//  ## ⚠️ 表格区必须单独拍（本文件最容易被误读的一条）
//
//  `ImageRenderer` **不绘制 `ScrollView` 的内容**：整卡快照里表格区是一片**空白**
//  （只保留它占的高度）。实测结果：`01-尺码表-识别成功.png` 里表头与数据行全空，
//  只剩一句「共 3 行」—— 看着像功能坏了，其实是画布的限制。
//  所以表格本体的核对走 `CatalogChartTablePreview`（不带滚动容器的那个 View），
//  线上路径不变（卡片自己仍然用 `ScrollView(.horizontal)` 兜住长表）。
//
//  ## 各条断言分别在证明什么
//
//    · **表宽可预测**（88 + N×76）→ 列宽是固定的，长表交给横向滚动而不是把列压扁；
//    · **长款式名更高**（表格）→ 行标签是**换行显示完整**，不是被截断成「大蝴蝶结…」；
//      同一组断言里还要求**表宽不变** → 列宽没被内容带跑，值列仍对齐；
//    · **宽度被压在给定宽度** → 卡片没有把父容器撑破（`frame(maxWidth: .infinity)` 生效）；
//    · **窄屏更高**（失败卡）→ 引导话术是**换行**而不是被截断（截断时高度不变）；
//    · **大字号更高** → 生效的是语义字号（`.subheadline` / `.footnote` / `.caption`）
//      而不是写死的 pt（写死时高度不变）；
//    · **窄屏行高不变**（表格）→ 再次确认列不被压缩。
//
//  ⚠️ 快照只证明「板块自己画得对」；它进不进得了页面由 `ShopCatalogChartPasteButton`
//     的调用点保证（尺码表 4 处 + 价格表 1 处，见 `RULES.md`）。
//  ⚠️ 判定与文案**不在这里测** —— 那是共享包 `CatalogChartRecognitionTests` 的事，
//     本文件只用现成的 `verdict` / `rejected` 造输入，不自己拼结论。
//

import UIKit
import XCTest
import SwiftUI
@testable import ItemManager

@MainActor
final class CatalogChartRecognitionCardSnapshotTests: XCTestCase {

    /// 落盘目录名（在模拟器容器的 tmp 下，宿主机可读，便于把图取出来看）
    private static let snapshotDirectoryName = "chart-recognition-snapshots"

    /// 常见 iPhone 逻辑宽度（iPhone 17 / 18 这一代）
    private static let regularPhoneWidth: CGFloat = 393
    /// 最窄的在役 iPhone 逻辑宽度（SE 一类）—— 窄屏是「适配良好」最容易露馅的地方
    private static let narrowPhoneWidth: CGFloat = 320

    /// 与 `CatalogChartTablePreview` 里的列宽常量对应（改动那边必须同步改这里）
    private static let labelColumnWidth: CGFloat = 88
    private static let valueColumnWidth: CGFloat = 76

    // MARK: - 造输入（只用共享包的公开构造入口）

    private func sizeSuccess() -> CatalogChartRecognition {
        .verdict(kind: .size,
                 source: .pastedText,
                 columns: ["前裙长", "胸围", "推荐胸围"],
                 rows: [CatalogSizeRow(label: "S", values: ["110", "96", "86-92"]),
                        CatalogSizeRow(label: "M", values: ["114", "102", "92-98"]),
                        CatalogSizeRow(label: "L", values: ["118", "108", "98-104"])])
    }

    private func sizeFailure() -> CatalogChartRecognition {
        .verdict(kind: .size,
                 source: .pastedText,
                 columns: ["前裙长"],
                 rows: [CatalogSizeRow(label: "S", values: ["110"])])
    }

    private func priceSuccess() -> CatalogChartRecognition {
        .verdict(kind: .price,
                 source: .pastedText,
                 columns: ["预约价", "定金", "尾款", "现货价"],
                 rows: [CatalogSizeRow(label: "大蝴蝶结背心裙", values: ["318", "91", "227", "368"]),
                        CatalogSizeRow(label: "蝴蝶结半裙", values: ["268", "80", "188", "308"]),
                        CatalogSizeRow(label: "美乐蒂背带", values: ["439", "87", "352", "489"])])
    }

    private func priceFailure() -> CatalogChartRecognition {
        .verdict(kind: .price,
                 source: .pastedText,
                 columns: ["预约价", "定金"],
                 rows: [CatalogSizeRow(label: "定金", values: ["91", nil])])
    }

    /// 与 `priceSuccess()` **只有行标签长短不同**（列名、数值、行数全一样）。
    /// 用来把「长标签换行」与「被截断」区分开：截断时高度不变，换行时高度变大。
    private func priceShortLabels() -> CatalogChartRecognition {
        .verdict(kind: .price,
                 source: .pastedText,
                 columns: ["预约价", "定金", "尾款", "现货价"],
                 rows: [CatalogSizeRow(label: "背心裙", values: ["318", "91", "227", "368"]),
                        CatalogSizeRow(label: "半裙", values: ["268", "80", "188", "308"]),
                        CatalogSizeRow(label: "背带", values: ["439", "87", "352", "489"])])
    }

    /// 行标签**明显超过** `labelColumnWidth`（88pt ≈ 7 个汉字）的那一档 ——
    /// 第一个标签 10 字（≈120pt）必然要换行。**对照组必须用这个，不能用
    /// `priceSuccess()`**：后者最长 7 字（≈84pt）在 88pt 里放得下、本来就单行，
    /// 拿它比高度会得出「没换行」的假结论（本机实测踩过）。
    private func priceOverlongLabels() -> CatalogChartRecognition {
        .verdict(kind: .price,
                 source: .pastedText,
                 columns: ["预约价", "定金", "尾款", "现货价"],
                 rows: [CatalogSizeRow(label: "大蝴蝶结背心裙加长版", values: ["318", "91", "227", "368"]),
                        CatalogSizeRow(label: "蝴蝶结半裙", values: ["268", "80", "188", "308"]),
                        CatalogSizeRow(label: "美乐蒂背带", values: ["439", "87", "352", "489"])])
    }

    // MARK: - 渲染与留档

    /// 渲染任意视图并留档。
    ///
    /// 口径与既有 `WardrobeStatsMonthLabelTests` 一致：铺白底 + 顶部对齐 + 钉浅色外观，
    /// `scale = 2`，`isOpaque = true`（不铺满会出现黑边且内容垂直居中 —— 那是画布的锅，
    /// 不是布局 bug）。
    @discardableResult
    private func render<V: View>(_ view: V,
                                 named name: String,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) throws -> UIImage {
        let canvas = view
            .background(Color.white)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        renderer.isOpaque = true

        let image = try XCTUnwrap(renderer.uiImage,
                                  "ImageRenderer 未产出图像（\(name)）",
                                  file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 10,
                             "\(name)：高度小得不正常，很可能没渲染出来", file: file, line: line)

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let url = try? writePNG(image, named: name) {
            print("SNAPSHOT 落盘 \(url.path)")
        }
        return image
    }

    /// 按手机宽度渲染一张识别板块卡（宽度被 `frame(width:)` 钉住）。
    @discardableResult
    private func renderBoard(_ recognition: CatalogChartRecognition,
                             width: CGFloat,
                             dynamicType: DynamicTypeSize = .large,
                             named name: String,
                             file: StaticString = #filePath,
                             line: UInt = #line) throws -> UIImage {
        let image = try render(CatalogChartRecognitionCard(recognition: recognition)
            .frame(width: width, alignment: .top)
            .environment(\.dynamicTypeSize, dynamicType),
                               named: name, file: file, line: line)
        // ⚠️ `image.size` 是「点」，不是像素（像素看 `cgImage.width`）
        XCTAssertEqual(image.size.width, width, accuracy: 4,
                       "\(name)：卡片把父容器撑破了，宽度应被压在 \(width)",
                       file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 60,
                             "\(name)：卡片高度小得不正常，很可能没渲染出来",
                             file: file, line: line)
        return image
    }

    private func writePNG(_ image: UIImage, named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.snapshotDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        let data = try XCTUnwrap(image.pngData(), "PNG 编码失败：\(name)")
        try data.write(to: url)
        return url
    }

    // MARK: - ① 表格本体：列宽固定、内容真的画出来了
    //
    // 「整卡快照里表格是空白」是 `ImageRenderer` + `ScrollView` 的已知限制，
    // 所以这一条拍的是不带滚动容器的 `CatalogChartTablePreview`，按**固有尺寸**渲染
    // （`fixedSize`），这样 PNG 里能看到完整的列名与数值，供人工核对对齐。

    func testTablePreviewLaysOutFixedWidthColumnsWithRealContent() throws {
        let size = try render(CatalogChartTablePreview(recognition: sizeSuccess())
            .fixedSize(), named: "11-尺码表-表格本体-固有宽度")
        let price = try render(CatalogChartTablePreview(recognition: priceSuccess())
            .fixedSize(), named: "12-预约价格表-表格本体-固有宽度")

        // 列宽是写死的常量 ⇒ 表宽可预测（62 + N×76）。对不上说明列被压缩或换行了。
        XCTAssertEqual(size.size.width,
                       Self.labelColumnWidth + 3 * Self.valueColumnWidth,
                       accuracy: 2,
                       "尺码表本体宽度应为「行标签列 + 3 个值列」")
        XCTAssertEqual(price.size.width,
                       Self.labelColumnWidth + 4 * Self.valueColumnWidth,
                       accuracy: 2,
                       "价格表本体宽度应为「行标签列 + 4 个值列」")
        // 表头行 + 3 个数据行；少于这个高度说明行没画出来
        XCTAssertGreaterThan(size.size.height, 60, "尺码表本体的数据行很可能没渲染")
        XCTAssertGreaterThan(price.size.height, 60, "价格表本体的数据行很可能没渲染")
    }

    // MARK: - ② 行标签换行显示完整，不截断（价格表的行标签就是款式名）

    /// 这条是**真实缺陷的回归锁**。
    ///
    /// 首版把行标签写成 `.lineLimit(1)` + 62pt，于是「大蝴蝶结背心裙」在快照里
    /// 被截成「大蝴蝶结…」（见 `output/识别结果板块_移动端快照/12-预约价格表-表格本体-固有宽度.png`
    /// 的历史版本）。尺码表的标签是 S/M/L 看不出来，**价格表的行标签就是款式名**，
    /// 被截掉等于把最关键的信息吃了 —— 与「显示效果完整」直接冲突。
    /// 商品详情页 `ShopCatalogProductDetailView.structuredTable` 一直是「固定宽 + 换行」，
    /// 这里对齐同一口径。
    func testLongRowLabelWrapsInsteadOfTruncating() throws {
        let long = try render(CatalogChartTablePreview(recognition: priceOverlongLabels())
            .fixedSize(), named: "15-预约价格表-表格本体-长款式名换行")
        let short = try render(CatalogChartTablePreview(recognition: priceShortLabels())
            .fixedSize(), named: "16-预约价格表-表格本体-短款式名对照")

        // 两组只有标签长短不同：换行 ⇒ 变高；截断 ⇒ 一样高。
        XCTAssertGreaterThan(long.size.height, short.size.height,
                             "长款式名所在的行应变高（换行显示完整）。高度相同 = 标签被截断成「大蝴蝶结…」了")

        // 但**宽度必须一样**：列宽固定，值列才不会因为标签长短而错位。
        XCTAssertEqual(long.size.width, short.size.width, accuracy: 2,
                       "标签长短不该改变表宽 —— 变了说明列宽被内容带跑了，值列会错位")
    }

    // MARK: - ③ 表格在窄屏上不压缩（交给横向滚动，而不是把列挤扁）

    func testTablePreviewKeepsRowHeightOnNarrowPhone() throws {
        let intrinsic = try render(CatalogChartTablePreview(recognition: priceSuccess())
            .fixedSize(), named: "13-预约价格表-表格本体-固有宽度-对照")
        // 窄于内容宽度（62 + 4×76 = 366 > 320）：列宽固定 ⇒ 行高不该变
        let narrow = try render(CatalogChartTablePreview(recognition: priceSuccess())
            .frame(width: Self.narrowPhoneWidth, alignment: .leading),
                                named: "14-预约价格表-表格本体-窄屏320")

        XCTAssertEqual(narrow.size.height, intrinsic.size.height, accuracy: 2,
                       "窄屏上行高变了 —— 说明列被压扁换行，而不是交给外层横向滚动")
    }

    // MARK: - ④ 成功 / 失败两态都要能画出来（两张表各一份）

    func testSuccessAndFailureBoardsRenderForBothChartKinds() throws {
        let sizeSuccess = try renderBoard(sizeSuccess(),
                                          width: Self.regularPhoneWidth,
                                          named: "01-尺码表-识别成功")
        let sizeFailure = try renderBoard(sizeFailure(),
                                          width: Self.regularPhoneWidth,
                                          named: "02-尺码表-识别失败")
        let priceSuccess = try renderBoard(priceSuccess(),
                                           width: Self.regularPhoneWidth,
                                           named: "03-预约价格表-识别成功")
        let priceFailure = try renderBoard(priceFailure(),
                                           width: Self.regularPhoneWidth,
                                           named: "04-预约价格表-识别失败")

        // 成功卡比失败卡高：多出来的就是表格区（表头 + 每个数据行）。
        // ⚠️ 注意这条**不能**读成「表格画出来了」—— `ImageRenderer` 只保留了滚动容器
        //    占的高度、不画内容（见文件头）。表格内容由 ①② 两条负责。
        XCTAssertGreaterThan(sizeSuccess.size.height, sizeFailure.size.height,
                             "尺码表成功卡应包含表格区，因此高于只有结论 + 引导的失败卡")
        XCTAssertGreaterThan(priceSuccess.size.height, priceFailure.size.height,
                             "价格表成功卡应包含表格区，因此高于只有结论 + 引导的失败卡")
    }

    // MARK: - ⑤ 窄屏：引导话术换行，不是被截断

    func testFailureGuidanceWrapsOnNarrowPhoneInsteadOfTruncating() throws {
        let regular = try renderBoard(sizeFailure(),
                                      width: Self.regularPhoneWidth,
                                      named: "05-尺码表-识别失败-常规屏宽")
        let narrow = try renderBoard(sizeFailure(),
                                     width: Self.narrowPhoneWidth,
                                     named: "06-尺码表-识别失败-窄屏320")

        XCTAssertGreaterThan(narrow.size.height, regular.size.height,
                             "窄屏上引导话术应折行 → 卡片变高。若两档高度相同，说明话术被截断了")
    }

    // MARK: - ⑥ 动态字体：语义字号生效，不写死 pt

    func testCardScalesWithDynamicTypeInsteadOfClipping() throws {
        let normal = try renderBoard(priceFailure(),
                                     width: Self.regularPhoneWidth,
                                     dynamicType: .large,
                                     named: "07-预约价格表-识别失败-标准字号")
        let huge = try renderBoard(priceFailure(),
                                   width: Self.regularPhoneWidth,
                                   dynamicType: .accessibility3,
                                   named: "08-预约价格表-识别失败-超大字号")

        XCTAssertGreaterThan(huge.size.height, normal.size.height,
                             "放大系统字号后卡片应变高。高度不变 = 字号被写死成 pt，用户调大字号也看不全")
    }

    // MARK: - ⑦ 成功卡在最窄屏上也不横向溢出

    func testSuccessBoardFitsNarrowestPhoneWidth() throws {
        let regular = try renderBoard(priceSuccess(),
                                      width: Self.regularPhoneWidth,
                                      named: "09-预约价格表-识别成功-常规屏宽")
        let narrow = try renderBoard(priceSuccess(),
                                     width: Self.narrowPhoneWidth,
                                     named: "10-预约价格表-识别成功-窄屏320")

        // 表格区是横向滚动兜底的，所以窄屏上高度不该暴涨（暴涨 = 列被压扁换行）
        XCTAssertLessThan(abs(narrow.size.height - regular.size.height), 40,
                          "窄屏与常规屏高度差过大 —— 表格很可能被压扁换行，而不是交给横向滚动")
    }

    // MARK: - ⑧ 共享文案里的 `**强调**` 必须被解析掉（不许逐字显示星号）

    /// 共享包 `CatalogChartRecognition` 的 `headline` / `detail` / `guidance`
    /// 是**两端同一份文案**。Mac 侧过 `opsMarkdown`，iOS 侧原先直接 `Text(变量)` ——
    /// 而 **`Text(变量)` 与 `Text("a"+"b")` 都不解析 Markdown**，
    /// 一旦共享文案里出现 `**强调**`，iOS 上就会把星号原样画出来。
    ///
    /// ⚠️ 这类缺陷**编译与其余单测全绿都发现不了**，只能像这样把转换后的文本抽出来断言。
    /// 同理：`ItemManager/`（iOS）全仓没有 markdown 渲染门禁，
    /// 所以共享文案的 iOS 侧只能靠这条用例兜着。
    func testSharedCopyMarkdownIsParsedInsteadOfShownAsAsterisks() {
        let rendered = String(CatalogChartRecognitionCard
            .emphasis("先看**行标签列**这一条，其余照填即可").characters)
        XCTAssertEqual(rendered, "先看行标签列这一条，其余照填即可")
        XCTAssertFalse(rendered.contains("*"), "星号必须被解析掉，不能逐字显示")

        // 纯文本（当前共享文案的实际形态）必须逐字不变 —— 别把空白也一起吃掉
        let plain = "预约价格表的列名要有 2 个以上，且至少一行有数字。"
        XCTAssertEqual(String(CatalogChartRecognitionCard.emphasis(plain).characters), plain)

        // 真实的 `guidance` 走一遍：失败态一定有引导话术，过一遍转换必须逐字不变
        let recognition = CatalogChartRecognition.rejected(
            kind: .price, source: .pastedText, reason: "预约价格表没有数据行")
        let guidance = recognition.guidance
        XCTAssertNotNil(guidance, "失败态必须有引导话术（卡片靠它给下一步）")
        XCTAssertEqual(String(CatalogChartRecognitionCard
            .emphasis(guidance ?? "").characters), guidance ?? "")
    }
}
