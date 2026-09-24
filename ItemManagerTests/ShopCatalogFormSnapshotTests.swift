//
//  ShopCatalogFormSnapshotTests.swift
//  ItemManagerTests
//
//  2026-09-24「离开页面再回来，之前填的内容全部消失」的**根源修复**验收。
//
//  ## 病灶（两层，缺一不可）
//
//  ① **呈现结构**：`.sheet` 挂在 `ForEach` 的**行视图**上（批次行 / 草稿行 / 系列行）。
//     `Form` 的行是惰性、可复用的，行身份一变或列表重新布局（切后台、跳系统相册、
//     切到其他应用再回来都会触发）行视图连同它承载的 sheet 内容视图一起被重建。
//  ② **状态只活在 `@State` 里**：上一轮已发现「这三个场景会重新触发 `onAppear`」，
//     于是加了 `loaded` 一次性回填守卫 —— 但 `loaded` **自己也是 `@State`**，
//     视图一重建就归零，守卫直接失效，表单被存储值重新回填（用户看到的就是「被重置」）。
//
//  ## 本套件钉什么
//
//  第 ② 层的兜底：快照落盘 / 作用域隔离 / 坏文件容错 / 恢复判定 / 防抖 / 提交清理，
//  以及三个页面载荷（含**封面图**与每个颜色的**配色图**）的编解码完整性。
//  第 ① 层是结构性改动，靠 XCUITest 三场景验收（`ShopCatalogFormStateUITests`）。
//
//  ⚠️ 测试隔离：一律先 `ShopCatalogStorage.useTemporaryForTesting()`，
//  快照文件落在独立临时目录，`tearDown` 里整目录删除 —— 绝不触碰生产路径。
//

import XCTest
@testable import ItemManager

// MARK: - 测试用载荷

private struct SnapshotPayload: Codable, Equatable {
    var id: String
    var text: String
    var cover: String
}

// MARK: - 存储层

final class ShopCatalogFormSnapshotStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
    }

    override func tearDown() {
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    private func payload(_ id: String = "a", text: String = "填了一半", cover: String = "local:c.jpg") -> SnapshotPayload {
        SnapshotPayload(id: id, text: text, cover: cover)
    }

    func testSaveThenLoadReturnsSameValue() {
        let scope = "scope-roundtrip"
        ShopCatalogFormSnapshotStore.save(payload(), scope: scope)
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope), payload())
    }

    /// 没写过就是 nil —— 绝不能把「没有快照」当成「有一个空快照」，
    /// 否则每次进页面都会恢复出一个空表单，把默认回填覆盖掉。
    func testLoadWithoutFileIsNil() {
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: "never-written"))
    }

    func testClearRemovesOnlyThatScope() {
        ShopCatalogFormSnapshotStore.save(payload("a"), scope: "keep-me")
        ShopCatalogFormSnapshotStore.save(payload("b"), scope: "drop-me")
        ShopCatalogFormSnapshotStore.clear(scope: "drop-me")
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: "drop-me"))
        XCTAssertNotNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: "keep-me"))
    }

    /// 作用域必须逐个实体隔离：把 A 批次填的店家和系列恢复进 B 批次是灾难级串页。
    func testScopesAreIsolated() {
        ShopCatalogFormSnapshotStore.save(payload(text: "批次A"), scope: "batch-config-A")
        ShopCatalogFormSnapshotStore.save(payload(text: "批次B"), scope: "batch-config-B")
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: "batch-config-A")?.text, "批次A")
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: "batch-config-B")?.text, "批次B")
    }

    /// 作用域里出现路径分隔符时：① 不许写到目录外；② 不许和「被擦成同样字符」的另一个
    /// 作用域撞成同一个文件（哈希后缀保证这一点）。
    func testScopeWithPathSeparatorStaysInsideDirectoryAndDoesNotCollide() {
        let directory = ShopCatalogStorage.directory.appendingPathComponent("form-snapshots", isDirectory: true)
        let a = ShopCatalogFormSnapshotStore.fileURL(scope: "draft/form/1")
        let b = ShopCatalogFormSnapshotStore.fileURL(scope: "draft_form_1")
        XCTAssertEqual(a.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(b.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertNotEqual(a, b)

        ShopCatalogFormSnapshotStore.save(payload(text: "斜杠"), scope: "draft/form/1")
        ShopCatalogFormSnapshotStore.save(payload(text: "下划线"), scope: "draft_form_1")
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: "draft/form/1")?.text, "斜杠")
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: "draft_form_1")?.text, "下划线")
    }

    /// 坏文件（手改 / 半截写入）→ 当作「没有快照」，**不许抛错也不许崩**。
    /// 快照只是兜底，它坏了绝不能让用户连页面都进不去。
    func testCorruptFileLoadsAsNilWithoutThrowing() throws {
        let scope = "scope-corrupt"
        let url = ShopCatalogFormSnapshotStore.fileURL(scope: scope)
        try Data("这不是 JSON".utf8).write(to: url)
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope))
        // 坏文件仍可被覆盖：下一次正常落盘即可自愈
        ShopCatalogFormSnapshotStore.save(payload(text: "自愈"), scope: scope)
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope)?.text, "自愈")
    }

    func testClearAllRemovesEveryScope() {
        ShopCatalogFormSnapshotStore.save(payload(), scope: "a")
        ShopCatalogFormSnapshotStore.save(payload(), scope: "b")
        ShopCatalogFormSnapshotStore.clearAll()
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: "a"))
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: "b"))
    }

    /// 快照落在 `ShopCatalogStorage.directory` 下 —— 测试注入的临时目录生效，
    /// 生产沙盒不会被任何一条用例写到。
    func testSnapshotDirectoryFollowsStorageOverride() {
        XCTAssertTrue(ShopCatalogStorage.isTestOverridden)
        let url = ShopCatalogFormSnapshotStore.fileURL(scope: "x")
        XCTAssertTrue(url.path.hasPrefix(ShopCatalogStorage.directory.standardizedFileURL.path))
    }
}

// MARK: - 页面侧管家

@MainActor
final class ShopCatalogFormSnapshotKeeperTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
    }

    override func tearDown() {
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    private func scope() -> String { "keeper-\(UUID().uuidString)" }

    private func defaults() -> SnapshotPayload {
        SnapshotPayload(id: "x", text: "", cover: "")
    }

    // MARK: 恢复

    func testRestoreAppliesStoredSnapshotAndFlagsIt() {
        let scope = scope()
        let stored = SnapshotPayload(id: "x", text: "用户填了一半", cover: "local:cover.jpg")
        ShopCatalogFormSnapshotStore.save(stored, scope: scope)

        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        var applied: SnapshotPayload?
        keeper.restoreOrDiscard(defaults: defaults()) { applied = $0 }

        XCTAssertEqual(applied, stored)
        XCTAssertTrue(keeper.didRestore)
    }

    func testRestoreWithoutSnapshotDoesNothing() {
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope())
        var applied: SnapshotPayload?
        keeper.restoreOrDiscard(defaults: defaults()) { applied = $0 }
        XCTAssertNil(applied)
        XCTAssertFalse(keeper.didRestore)
    }

    /// 快照与默认态逐字段相同 = 上次其实没改什么 → 直接清掉。
    /// 否则每次进页面都会弹一条「已恢复未保存的编辑」，把用户训练成忽略提示。
    func testRestoreDiscardsSnapshotEqualToDefaults() {
        let scope = scope()
        ShopCatalogFormSnapshotStore.save(defaults(), scope: scope)

        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        var applied: SnapshotPayload?
        keeper.restoreOrDiscard(defaults: defaults()) { applied = $0 }

        XCTAssertNil(applied)
        XCTAssertFalse(keeper.didRestore)
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope))
    }

    func testRestoreIsSkippedWhenScopeIsEmpty() {
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: "")
        var applied: SnapshotPayload?
        keeper.restoreOrDiscard(defaults: defaults()) { applied = $0 }
        XCTAssertNil(applied)
        XCTAssertFalse(keeper.didRestore)
    }

    func testDiscardClearsSnapshotAndFlag() {
        let scope = scope()
        ShopCatalogFormSnapshotStore.save(SnapshotPayload(id: "x", text: "改了", cover: ""), scope: scope)
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        keeper.restoreOrDiscard(defaults: defaults()) { _ in }
        XCTAssertTrue(keeper.didRestore)

        keeper.discard()
        XCTAssertFalse(keeper.didRestore)
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope))
    }

    func testMarkRestoreAcknowledgedKeepsSnapshotFile() {
        let scope = scope()
        ShopCatalogFormSnapshotStore.save(SnapshotPayload(id: "x", text: "改了", cover: ""), scope: scope)
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        keeper.restoreOrDiscard(defaults: defaults()) { _ in }
        keeper.markRestoreAcknowledged()
        XCTAssertFalse(keeper.didRestore)
        // 「知道了」只是收起提示条，内容仍是未保存的编辑 → 快照要留着
        XCTAssertNotNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope))
    }

    // MARK: 落盘

    func testFlushWritesUncommittedSnapshot() {
        let scope = scope()
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        let current = SnapshotPayload(id: "x", text: "未保存", cover: "local:c.jpg")
        keeper.flush(current)
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope), current)
    }

    /// 提交之后关页（onDisappear 会再 flush 一次）**不能**把刚保存的内容又写成
    /// 「未保存的编辑」—— 否则下次进页面会恢复出旧值，用户以为保存没生效。
    func testFlushAfterCommitClearsInsteadOfWriting() {
        let scope = scope()
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        let committed = SnapshotPayload(id: "x", text: "已保存", cover: "")
        keeper.commit(committed)
        keeper.flush(committed)
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope))
    }

    func testFlushAfterCommitWritesAgainWhenContentChanged() {
        let scope = scope()
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        keeper.commit(SnapshotPayload(id: "x", text: "已保存", cover: ""))
        let later = SnapshotPayload(id: "x", text: "保存后又改了", cover: "local:new.jpg")
        keeper.flush(later)
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope), later)
    }

    func testFlushIsSkippedWhenScopeIsEmpty() {
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: "")
        keeper.flush(SnapshotPayload(id: "x", text: "t", cover: ""))
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: ""))
    }

    /// 防抖：`schedule` 之后立刻读**不该**有文件（还没到 0.5s），
    /// 等过防抖窗口才落盘。这层「改一下就存一下」是跳系统相册那条路的唯一兜底
    /// —— 相册返回不会走 `onDisappear`。
    func testScheduleWritesOnlyAfterDebounceWindow() async throws {
        let scope = scope()
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        let current = SnapshotPayload(id: "x", text: "打字中", cover: "")
        keeper.schedule(current)
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope),
                     "防抖窗口内不应落盘")

        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope), current)
    }

    /// 连续变更只留最后一次（防抖），不是每次都写一遍。
    func testScheduleKeepsOnlyLatestChange() async throws {
        let scope = scope()
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        keeper.schedule(SnapshotPayload(id: "x", text: "1", cover: ""))
        keeper.schedule(SnapshotPayload(id: "x", text: "12", cover: ""))
        keeper.schedule(SnapshotPayload(id: "x", text: "123", cover: "local:last.jpg"))
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope)?.text, "123")
    }

    /// 已提交的内容再 schedule 也不会写回（避免「保存后又被恢复出来」）。
    func testScheduleDoesNotWriteCommittedContent() async throws {
        let scope = scope()
        var keeper = ShopCatalogFormSnapshotKeeper<SnapshotPayload>(scope: scope)
        let committed = SnapshotPayload(id: "x", text: "已保存", cover: "")
        keeper.commit(committed)
        keeper.schedule(committed)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertNil(ShopCatalogFormSnapshotStore.load(SnapshotPayload.self, scope: scope))
    }
}

// MARK: - 页面载荷的编解码完整性

/// 快照载荷必须**无损**：用户明确要求「所有已填写的表单字段和已选封面图都能完整保留」，
/// 少一个字段就是少一处会丢的内容。这里逐页钉住。
@MainActor
final class ShopCatalogFormSnapshotPayloadTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
    }

    override func tearDown() {
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T,
                                                   file: StaticString = #filePath,
                                                   line: UInt = #line) -> T {
        guard let data = try? ShopCatalogJSONCoding.encoder().encode(value),
              let decoded = try? ShopCatalogJSONCoding.decoder().decode(T.self, from: data) else {
            XCTFail("快照编解码失败：\(T.self)", file: file, line: line)
            return value
        }
        XCTAssertEqual(decoded, value, "快照往返后字段不一致：\(T.self)", file: file, line: line)
        return decoded
    }

    private func series(id: String = "series-1") -> CatalogSeries {
        CatalogSeries(id: id, shopID: "shop-1", name: "天空音乐会")
    }

    /// ⚠️ 日期一律用整秒：`ShopCatalogJSONCoding` 走 ISO8601，小数秒会被截掉，
    /// 用 `Date()` 造数据会让相等断言在编解码后必然失败（不是缺陷，是口径）。
    private func wholeSecondForm() -> ShopCatalogSeriesConfigForm {
        var form = ShopCatalogSeriesConfigForm(series: series(), now: epoch)
        form.salePhase = .reservationActive
        form.reservationHasStart = true
        form.reservationStartAt = epoch
        form.reservationEndAt = epoch.addingTimeInterval(86_400 * 30)
        form.balanceDueKind = .exact
        form.balanceDueText = ""
        form.balanceDueEndText = ""
        form.balanceDueAt = epoch.addingTimeInterval(86_400 * 31)
        form.balanceDueHasEnd = true
        form.balanceDueEndAt = epoch.addingTimeInterval(86_400 * 61)
        form.cover = "local:cover-abc.jpg"
        form.descriptionText = "一条系列简介"
        form.priceChartImageText = "local:chart-1.jpg\nlocal:chart-2.jpg"
        form.priceChartColumnsText = "款式,预约价,定金"
        form.priceChartRowsText = "大蝴蝶结背心裙:318,91"
        form.priceChartUnitText = "元"
        return form
    }

    /// 需求点名要保住的「已选封面图」：封面引用必须原样过一遍编解码。
    func testConfigFormKeepsCoverAndEveryField() {
        let form = wholeSecondForm()
        let decoded = roundTrip(form)
        XCTAssertEqual(decoded.cover, "local:cover-abc.jpg")
        XCTAssertEqual(decoded.descriptionText, "一条系列简介")
        XCTAssertEqual(decoded.priceChartImageText, "local:chart-1.jpg\nlocal:chart-2.jpg")
        XCTAssertEqual(decoded.salePhase, .reservationActive)
        XCTAssertTrue(decoded.reservationHasStart)
        XCTAssertEqual(decoded.reservationStartAt, epoch)
        XCTAssertEqual(decoded.balanceDueKind, .exact)
        XCTAssertTrue(decoded.balanceDueHasEnd)
        XCTAssertEqual(decoded.balanceDueEndAt, epoch.addingTimeInterval(86_400 * 61))
    }

    func testBatchConfigSnapshotKeepsIdentityAndCover() {
        let snapshot = ShopCatalogBatchConfigSnapshot(
            batchID: "batch-9",
            shopID: "shop-1",
            newShopName: "",
            newShopAliases: "别名一,别名二",
            seriesID: "series-1",
            newSeriesName: "",
            newSeriesYearMonthText: "2026-10",
            newSeriesSeason: "冬",
            configFormSeriesID: "series-1",
            config: wholeSecondForm())

        let scope = "batch-config-batch-9"
        ShopCatalogFormSnapshotStore.save(snapshot, scope: scope)
        let loaded = ShopCatalogFormSnapshotStore.load(ShopCatalogBatchConfigSnapshot.self, scope: scope)

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded?.batchID, "batch-9")
        XCTAssertEqual(loaded?.newSeriesYearMonthText, "2026-10")
        XCTAssertEqual(loaded?.config.cover, "local:cover-abc.jpg")
    }

    /// 补录编辑器的颜色行：**每个颜色已选的配色图**（含多张）必须一起保住。
    func testDraftFormSnapshotKeepsEveryColorImage() {
        let rows = [
            ShopCatalogDraftStyleForm.ColorRow(id: "row-1",
                                               draftID: "draft-1",
                                               colorName: "生成色",
                                               imageRefs: ["local:a.jpg", "local:b.jpg"],
                                               sizes: ["S", "M"],
                                               isSettled: false),
            ShopCatalogDraftStyleForm.ColorRow(id: "row-2",
                                               draftID: nil,
                                               colorName: "粉紫色",
                                               imageRefs: ["local:c.jpg"],
                                               sizes: ["M"],
                                               isSettled: false),
            ShopCatalogDraftStyleForm.ColorRow(id: "row-3",
                                               draftID: "draft-3",
                                               colorName: "黑色",
                                               imageRefs: [],
                                               sizes: [],
                                               isSettled: true),
        ]
        let snapshot = ShopCatalogDraftFormSnapshot(
            sourceDraftID: "draft-1",
            designNameText: "一字领 OP",
            categoryText: "连衣裙",
            fabricText: "100% 聚酯纤维",
            styleDescriptionText: "款式描述",
            chartColumnsText: "尺码,胸围",
            chartRowsText: "S:80",
            chartUnit: "cm",
            chartImageText: "local:chart.jpg",
            newSeriesYearMonthText: "2026-10",
            reservationPriceText: "318",
            stockPriceText: "398",
            depositText: "91",
            currency: .cny,
            colors: rows)

        let scope = "draft-form-draft-1"
        ShopCatalogFormSnapshotStore.save(snapshot, scope: scope)
        let loaded = ShopCatalogFormSnapshotStore.load(ShopCatalogDraftFormSnapshot.self, scope: scope)

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded?.colors.count, 3)
        XCTAssertEqual(loaded?.colors.first?.imageRefs, ["local:a.jpg", "local:b.jpg"])
        XCTAssertEqual(loaded?.colors[1].imageRefs, ["local:c.jpg"])
        XCTAssertEqual(loaded?.colors[2].isSettled, true)
        XCTAssertEqual(loaded?.colors[1].draftID, nil)
        XCTAssertEqual(loaded?.reservationPriceText, "318")
        XCTAssertEqual(loaded?.currency, .cny)
    }

    /// 颜色行的列表身份（`id`）也必须原样回来：它是「新加的空行在保存前也有稳定身份」
    /// 的锚点，丢了会导致恢复后列表整片重建、输入框失焦。
    func testColorRowRoundTripsIdentity() {
        let row = ShopCatalogDraftStyleForm.ColorRow(id: "new-fixed-id",
                                                    draftID: nil,
                                                    colorName: "生成色",
                                                    imageRefs: ["local:a.jpg"],
                                                    sizes: ["S"],
                                                    isSettled: false)
        let decoded = roundTrip(row)
        XCTAssertEqual(decoded.id, "new-fixed-id")
        XCTAssertTrue(decoded.isNew)
    }

    func testSeriesEditSnapshotKeepsNameYearMonthAndCover() {
        let snapshot = ShopCatalogSeriesEditSnapshot(seriesID: "series-1",
                                                    name: "天空音乐会",
                                                    yearMonthText: "2026-10",
                                                    season: "冬",
                                                    config: wholeSecondForm())
        let scope = "series-edit-series-1"
        ShopCatalogFormSnapshotStore.save(snapshot, scope: scope)
        let loaded = ShopCatalogFormSnapshotStore.load(ShopCatalogSeriesEditSnapshot.self, scope: scope)

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded?.seriesID, "series-1")
        XCTAssertEqual(loaded?.yearMonthText, "2026-10")
        XCTAssertEqual(loaded?.config.cover, "local:cover-abc.jpg")
    }

    /// 未填写的可选字段（`nil`）也要能原样往返 —— 恢复出「未声明」而不是被塞进默认值。
    func testNilOptionalFieldsStayNil() {
        var form = ShopCatalogSeriesConfigForm(series: series(), now: epoch)
        form.salePhase = nil
        form.balanceDueKind = nil
        form.reservationHasStart = false
        form.balanceDueHasEnd = false
        form.cover = ""
        let decoded = roundTrip(form)
        XCTAssertNil(decoded.salePhase)
        XCTAssertNil(decoded.balanceDueKind)
        XCTAssertFalse(decoded.reservationHasStart)
        XCTAssertFalse(decoded.balanceDueHasEnd)
        XCTAssertEqual(decoded.cover, "")
    }
}
