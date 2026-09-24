//
//  ShopCatalogDraftBatchFlowTests.swift
//  ItemManagerTests
//
//  草稿箱批量流转契约（2026-09-24：批量提交审核 / 批量审核通过 / 批量发布）：
//    1. 状态校验：仅 `draft` 可批量提交审核、仅 `submitted` 可批量审核通过、
//       仅 `reviewed` 可批量发布 —— 状态不符的逐条记入 skipped（带原因），绝不静默
//    2. 整批单次落盘（先写磁盘再提交内存）：写盘失败 / 坏文件封锁时磁盘与内存都不变，
//       可原样重试，绝不出现「改了一半」的半成品
//    3. 批量发布逐条复用单条 publish（幂等 / 校验器 / 半成功恢复全部继承）；
//       单条失败不回滚已成功的，失败逐条带原因进 failures
//    4. 需要运营白名单
//
//  ⚠️ 测试隔离：先 `ShopCatalogStorage.useTemporaryForTesting()`；
//  `shared` 的 drafts 跨套件累积 —— 断言只看本套件插入的草稿（按 id 收窄）。
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogDraftBatchFlowTests: XCTestCase {

    private var draftStore: ShopCatalogDraftStore!
    private var insertedIDs: [String] = []

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        draftStore = ShopCatalogDraftStore.shared
        draftStore.loadDrafts()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    @discardableResult
    private func insertDraft(name: String,
                             status: CatalogPublicationStatus) throws -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.price = 100
        draft.status = status
        try draftStore.upsert(draft)
        insertedIDs.append(draft.id)
        return draft
    }

    private func draft(named name: String) -> CatalogProductDraft? {
        draftStore.drafts.first { $0.name == name }
    }

    // MARK: 批量提交审核

    func testBatchSubmitOnlyTouchesDrafts() throws {
        _ = try insertDraft(name: "甲-草稿", status: .draft)
        _ = try insertDraft(name: "乙-已提交", status: .submitted)
        _ = try insertDraft(name: "丙-已审核", status: .reviewed)
        let ids = Set(insertedIDs)

        let result = try draftStore.batchAdvance(ids: ids, to: .submitted)

        XCTAssertEqual(result.succeededCount, 1, "仅草稿状态可提交审核")
        XCTAssertEqual(result.skipped.count, 2, "状态不符的逐条跳过")
        XCTAssertTrue(result.skipped.allSatisfy { $0.reason.contains("草稿") || $0.reason.contains("待审核") },
                      "跳过原因要说明当前状态")
        XCTAssertEqual(draft(named: "甲-草稿")?.status, .submitted)
        XCTAssertEqual(draft(named: "乙-已提交")?.status, .submitted, "非目标草稿不动")
        XCTAssertEqual(draft(named: "丙-已审核")?.status, .reviewed, "非目标草稿不动")
    }

    // MARK: 批量审核通过

    func testBatchApproveOnlyFromSubmitted() throws {
        _ = try insertDraft(name: "甲-待审核", status: .submitted)
        _ = try insertDraft(name: "乙-草稿", status: .draft)
        let ids = Set(insertedIDs)

        let result = try draftStore.batchAdvance(ids: ids, to: .reviewed)

        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertEqual(result.skipped.first?.name, "乙-草稿")
        XCTAssertEqual(draft(named: "甲-待审核")?.status, .reviewed)
        XCTAssertEqual(draft(named: "乙-草稿")?.status, .draft)
    }

    // MARK: 提交审核清空驳回原因（与单条 advance 同口径）

    func testBatchSubmitClearsRejectReason() throws {
        var rejected = try insertDraft(name: "被驳回款", status: .draft)
        // 模拟曾被驳回留下的原因
        rejected.rejectReason = "价格对不上"
        try draftStore.upsert(rejected)
        insertedIDs.append(rejected.id)

        _ = try draftStore.batchAdvance(ids: [rejected.id], to: .submitted)

        XCTAssertNil(draft(named: "被驳回款")?.rejectReason, "重新提交即视为已回应驳回意见")
    }

    // MARK: 批量发布

    func testBatchPublishOnlyFromReviewedAndCollectsFailures() throws {
        _ = try insertDraft(name: "甲-待发布", status: .reviewed)
        _ = try insertDraft(name: "乙-已提交", status: .submitted)
        let ids = Set(insertedIDs)

        let result = draftStore.batchPublish(ids: ids, store: ShopCatalogStore.shared)

        XCTAssertEqual(result.skipped.count, 1, "非审核通过状态被跳过")
        XCTAssertEqual(result.skipped.first?.name, "乙-已提交")
        // 「甲-待发布」进入了 publish：字段不全 → 校验失败 → 进 failures（不是 skipped）
        XCTAssertEqual(result.succeededCount + result.failures.count, 1,
                       "reviewed 草稿要么发布成功、要么带着原因失败")
        if let failure = result.failures.first {
            XCTAssertEqual(failure.name, "甲-待发布")
            XCTAssertFalse(failure.reason.isEmpty, "失败必须带原因")
        }
    }

    // MARK: 落盘原子性：坏文件封锁时整批不生效

    func testBatchAdvanceThrowsAndKeepsMemoryWhenWriteBlocked() throws {
        let draft = try insertDraft(name: "封锁款", status: .draft)
        let before = draftStore.drafts

        // 制造坏文件 + 重载 → isBlockedByCorruptFile 封锁写入
        let url = ShopCatalogStorage.directory
            .appendingPathComponent("shop-catalog-drafts.json")
        try Data("{ this is not json ".utf8).write(to: url)
        draftStore.loadDrafts()
        defer { draftStore.clearCorruptFileBlockAndReload() }

        XCTAssertThrowsError(try draftStore.batchAdvance(ids: [draft.id], to: .submitted))
        XCTAssertEqual(draftStore.drafts.count, before.count,
                       "写盘失败时内存不变（先写磁盘再提交内存）")
    }
}
