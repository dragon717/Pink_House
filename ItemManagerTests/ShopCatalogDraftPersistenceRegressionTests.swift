//
//  ShopCatalogDraftPersistenceRegressionTests.swift
//  ItemManagerTests
//
//  第三版收口 R01 回归（方案 §9 T01 / T02）：
//    T01 带 createdAt / startAt / endAt 的草稿保存后冷启动 → 内容、状态、驳回原因保留
//    T02 草稿文件损坏 / 旧日期格式 / 写盘失败 → 可诊断、原文件保留、不静默成功
//
//  事故形态：`persist()` 用 `.iso8601` 编码，`loadDrafts()` 用默认 `JSONDecoder()`
//  （`secondsSince1970`）解码 —— 方向不一致，带日期的草稿重启后整体消失，
//  且失败被 `?? []` 兜成空草稿箱，下一次保存还会用空库覆盖掉还能抢救的旧文件。
//
//  ⚠️ 测试隔离（2026-09-21 事故）：必须先 `ShopCatalogStorage.useTemporaryForTesting()`，
//  否则 `FileManager.default` 指向宿主 App 真实沙盒，会删到用户数据。
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogDraftPersistenceRegressionTests: XCTestCase {

    private var draftStore: ShopCatalogDraftStore!

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        draftStore = ShopCatalogDraftStore.shared
        // 单例的 drafts 会跨套件累积（历史坑）：切到本套件的临时目录后必须重新加载，
        // 否则 `drafts[0]` 可能是别的套件留下的草稿（状态机与断言都会串）
        draftStore.loadDrafts()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    private var draftsURL: URL {
        ShopCatalogStorage.directory.appendingPathComponent("shop-catalog-drafts.json")
    }

    private func makeDraft(name: String) -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.saleKind = .reservation
        draft.price = 428
        draft.stockPrice = 498
        draft.deposit = 128
        draft.balance = 300
        draft.startAt = Date(timeIntervalSince1970: 1_754_000_000)
        draft.endAt = Date(timeIntervalSince1970: 1_756_000_000)
        return draft
    }

    // MARK: T01 冷启动保留

    func testDraftWithDatesSurvivesColdStart() throws {
        var draft = makeDraft(name: "冷启动款")
        draft.newShopName = "冷启动店家"
        draft.newSeriesName = "冷启动系列"
        try draftStore.upsert(draft)
        try draftStore.advance(draft, to: .submitted)
        let submitted = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.review(submitted, approve: false, reason: "价格需要复核")

        let reviewed = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        let savedStatus = reviewed.status
        let savedReason = reviewed.rejectReason
        XCTAssertEqual(savedStatus, .draft)
        XCTAssertEqual(savedReason, "价格需要复核")

        // 冷启动：丢弃内存，从磁盘重新加载（模拟 App 重启）
        draftStore.loadDrafts()

        let restored = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id },
                                     "带日期的草稿必须在重启后仍然可见")
        XCTAssertEqual(restored.name, "冷启动款")
        XCTAssertEqual(restored.status, .draft, "审核状态必须保留")
        XCTAssertEqual(restored.rejectReason, "价格需要复核", "驳回原因必须保留")
        XCTAssertEqual(restored.price, 428)
        XCTAssertEqual(restored.stockPrice, 498)
        XCTAssertEqual(restored.startAt?.timeIntervalSince1970, 1_754_000_000,
                       "startAt 必须原样恢复（旧口径会整体丢草稿）")
        XCTAssertEqual(restored.endAt?.timeIntervalSince1970, 1_756_000_000)
        XCTAssertEqual(restored.createdAt.timeIntervalSince1970,
                       draft.createdAt.timeIntervalSince1970, accuracy: 1)
    }

    /// 编解码必须**同源**：编码器写出来的文件，解码器一定要能读回来。
    func testEncoderOutputIsDecodableByOurDecoder() throws {
        let draft = makeDraft(name: "编解码同源款")
        let data = try ShopCatalogJSONCoding.encoder().encode([draft])
        let decoded = try ShopCatalogJSONCoding.decoder().decode([CatalogProductDraft].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].startAt?.timeIntervalSince1970, 1_754_000_000)
    }

    // MARK: T02 历史日期格式兼容

    /// 历史文件格式样本：用**真实编码器**产出完整草稿 JSON，再把日期改写成旧口径。
    ///
    /// 不能用「只有几个字段的手写 JSON」当样本：合成 Decodable 对有默认值的
    /// 非 Optional 字段仍然走 `decode`（缺键即抛错），那样测出来的「兼容失败」
    /// 其实测的是样本本身不完整，而不是日期口径。
    private func writeLegacyDraft(id: String, name: String,
                                  mutate: (inout [String: Any]) -> Void) throws {
        var draft = makeDraft(name: name)
        draft.id = id
        var json = try JSONSerialization.jsonObject(
            with: ShopCatalogJSONCoding.encoder().encode([draft])) as? [[String: Any]]
        XCTAssertNotNil(json)
        var first = json![0]
        first["id"] = id
        mutate(&first)
        json![0] = first
        let data = try JSONSerialization.data(withJSONObject: json!)
        try data.write(to: draftsURL)
    }

    func testLegacySecondsTimestampDraftStillLoads() throws {
        // 旧口径（默认 JSONDecoder = secondsSince1970）落盘的数值时间戳必须还能读回来
        try writeLegacyDraft(id: "legacy-1", name: "历史时间戳草稿") { item in
            item["createdAt"] = 1_754_000_000
            item["startAt"] = 1_754_000_000
        }
        draftStore.loadDrafts()
        let restored = try XCTUnwrap(draftStore.drafts.first { $0.id == "legacy-1" },
                                     "秒级时间戳的存量草稿必须能读回")
        XCTAssertEqual(restored.startAt?.timeIntervalSince1970, 1_754_000_000)
        XCTAssertNil(draftStore.lastLoadIssue, "历史格式不是错误，应正常载入")
    }

    func testMillisecondsTimestampDraftStillLoads() throws {
        try writeLegacyDraft(id: "legacy-2", name: "毫秒时间戳草稿") { item in
            item["createdAt"] = 1_754_000_000_000
        }
        draftStore.loadDrafts()
        let restored = try XCTUnwrap(draftStore.drafts.first { $0.id == "legacy-2" })
        XCTAssertEqual(restored.createdAt.timeIntervalSince1970, 1_754_000_000, accuracy: 1)
    }

    func testPlainDateStringDraftStillLoads() throws {
        // 迁移产物与手工编辑常见：createdAt 写成 "2026-09-22"
        try writeLegacyDraft(id: "legacy-3", name: "纯日期草稿") { item in
            item["createdAt"] = "2026-09-22"
        }
        draftStore.loadDrafts()
        let restored = try XCTUnwrap(draftStore.drafts.first { $0.id == "legacy-3" })
        XCTAssertEqual(restored.name, "纯日期草稿")
        XCTAssertNil(draftStore.lastLoadIssue)
    }

    // MARK: T02 坏文件保护

    func testCorruptDraftFileIsPreservedAndBlocksOverwrite() throws {
        let good = makeDraft(name: "损坏前已存在的草稿")
        try draftStore.upsert(good)
        let originalData = try Data(contentsOf: draftsURL)

        // 人为写坏文件
        try "{{{ not json".data(using: .utf8)!.write(to: draftsURL)
        draftStore.loadDrafts()

        XCTAssertTrue(draftStore.isBlockedByCorruptFile, "解析失败必须进入待处理状态")
        XCTAssertNotNil(draftStore.lastLoadIssue, "必须给出可诊断的原因")
        XCTAssertNotNil(draftStore.corruptFileBackupURL, "必须备份坏文件供人工抢救")
        XCTAssertTrue(FileManager.default.fileExists(atPath: draftStore.corruptFileBackupURL!.path))

        // 关键：不得把空库写回、覆盖掉还能抢救的旧文件
        XCTAssertThrowsError(try draftStore.upsert(makeDraft(name: "不该写进去的草稿"))) { error in
            XCTAssertTrue(error is ShopCatalogDraftFileError,
                          "写入必须被拒绝并给出明确错误，实际：\(error)")
        }
        let after = try Data(contentsOf: draftsURL)
        XCTAssertEqual(after, "{{{ not json".data(using: .utf8)!,
                       "坏文件必须原样保留，不能被空库覆盖")

        // 人工处理完坏文件后可恢复
        try originalData.write(to: draftsURL)
        draftStore.clearCorruptFileBlockAndReload()
        XCTAssertFalse(draftStore.isBlockedByCorruptFile)
        XCTAssertNotNil(draftStore.drafts.first { $0.id == good.id }, "恢复后应读回原草稿")
    }

    func testMissingDraftFileIsNotAnError() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: draftsURL.path))
        draftStore.loadDrafts()
        XCTAssertNil(draftStore.lastLoadIssue, "首次启动的文件不存在是合法的空草稿箱")
        XCTAssertFalse(draftStore.isBlockedByCorruptFile)
    }

    // MARK: 写盘失败可见

    func testWriteFailureLeavesMemoryAndDiskUnchanged() throws {
        let draft = makeDraft(name: "写盘失败款")
        try draftStore.upsert(draft)
        let before = draftStore.drafts

        // 把草稿文件换成一个目录 → 写入必然失败
        try FileManager.default.removeItem(at: draftsURL)
        try FileManager.default.createDirectory(at: draftsURL, withIntermediateDirectories: true)

        var updated = draft
        updated.name = "写盘失败款-改名"
        XCTAssertThrowsError(try draftStore.upsert(updated))
        XCTAssertEqual(draftStore.drafts.count, before.count, "写盘失败时内存也不变，可原样重试")
        XCTAssertEqual(draftStore.drafts.first?.name, "写盘失败款")

        // 绑定式写入（Binding set 不能抛错）把错误暴露出来供 UI 提示
        draftStore.upsertReportingError(updated)
        XCTAssertNotNil(draftStore.lastPersistenceError, "失败必须可见，不能静默成功")
    }
}
