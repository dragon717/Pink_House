//
//  ShopCatalogBatchDeleteTests.swift
//  ItemManagerTests
//
//  批次列表治理（2026-09-22）：批次删除契约
//    1. 空批次 / 全部已处理（published / archived）的批次可删，且**不动任何草稿**
//    2. 仍有未处理草稿（draft / submitted / reviewed）的批次被拦截，原因明确可读
//    3. 多选删除：部分成功（可删的删掉，被拦截的保留并附原因）
//    4. 删除需要运营白名单
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogBatchDeleteTests: XCTestCase {

    private var draftStore: ShopCatalogDraftStore { ShopCatalogDraftStore.shared }

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    /// 建一个批次，并按给定状态放 N 条草稿进去（直接 upsert 指定 status，
    /// 跳过发布链路——本套件只验证删除语义，不依赖发布校验）
    private func makeBatch(name: String, statuses: [CatalogPublicationStatus]) throws -> CatalogBatchEntrySession {
        let session = CatalogBatchEntrySession()
        var drafts: [CatalogProductDraft] = []
        for (index, status) in statuses.enumerated() {
            var draft = CatalogProductDraft()
            draft.name = "\(name)-单品\(index + 1)"
            draft.price = 100
            draft.status = status
            drafts.append(draft)
        }
        _ = draftStore.createBatch(session, drafts: drafts)
        return session
    }

    // MARK: 1. 可删口径

    func testEmptyBatchIsDeletable() throws {
        let batch = try makeBatch(name: "空批次", statuses: [])
        let result = try draftStore.deleteBatches(ids: [batch.id])
        XCTAssertEqual(result.deletedIDs, [batch.id])
        XCTAssertTrue(result.blocked.isEmpty)
        XCTAssertFalse(draftStore.batches.contains { $0.id == batch.id }, "列表应移除该批次")
    }

    func testBatchWithOnlyProcessedDraftsIsDeletableAndDraftsKept() throws {
        let batch = try makeBatch(name: "已处理批次", statuses: [.published, .archived])
        let draftsBefore = draftStore.drafts
        let batchDraftIDs = Set(draftsBefore.filter { $0.batchID == batch.id }.map(\.id))

        let result = try draftStore.deleteBatches(ids: [batch.id])
        XCTAssertEqual(result.deletedIDs, [batch.id])

        // 硬约束：删除批次只删归组记录，单品草稿一条不动
        XCTAssertEqual(draftStore.drafts.count, draftsBefore.count)
        XCTAssertEqual(Set(draftStore.drafts.map(\.id)), Set(draftsBefore.map(\.id)))
        XCTAssertEqual(Set(draftStore.drafts.filter { $0.batchID == batch.id }.map(\.id)),
                       batchDraftIDs,
                       "草稿的批次引用原样保留（仅归组失效）")
    }

    // MARK: 2. 拦截口径

    func testBatchWithUnprocessedDraftsIsBlockedWithReadableReason() throws {
        let batch = try makeBatch(name: "未处理批次",
                                  statuses: [.draft, .submitted, .reviewed])
        let before = draftStore.batches.count

        let result = try draftStore.deleteBatches(ids: [batch.id])
        XCTAssertTrue(result.deletedIDs.isEmpty, "被拦截时不得删除任何东西")
        XCTAssertEqual(result.blocked.count, 1)
        XCTAssertEqual(result.blocked.first?.batchID, batch.id)
        let reason = try XCTUnwrap(result.blocked.first?.reason)
        XCTAssertTrue(reason.contains("草稿 1 条"), "原因需含草稿数：\(reason)")
        XCTAssertTrue(reason.contains("待审核 1 条"), "原因需含待审核数：\(reason)")
        XCTAssertTrue(reason.contains("待发布 1 条"), "原因需含待发布数：\(reason)")
        XCTAssertTrue(reason.contains("草稿箱"), "原因需给出处理路径：\(reason)")
        XCTAssertEqual(draftStore.batches.count, before, "被拦截批次必须保留")
    }

    // MARK: 3. 多选部分成功

    func testMultiSelectPartialSuccessKeepsBlockedEntries() throws {
        let emptyBatch = try makeBatch(name: "可删批次", statuses: [])
        let blockedBatch = try makeBatch(name: "拦截批次", statuses: [.draft])
        // draftStore.shared 在同一进程内跨用例累积草稿：只能断言前后快照不变，
        // 不能断言全局总数（历史用例/其他套件也会往里面写草稿）
        let draftIDsBefore = Set(draftStore.drafts.map(\.id))

        let result = try draftStore.deleteBatches(ids: [emptyBatch.id, blockedBatch.id])
        XCTAssertEqual(result.deletedIDs, [emptyBatch.id], "可删的正常删除")
        XCTAssertEqual(result.blocked.map(\.batchID), [blockedBatch.id], "被拦截的附原因返回")

        XCTAssertTrue(draftStore.batches.contains { $0.id == blockedBatch.id },
                      "被拦截批次必须保留，供处理后重试")
        XCTAssertFalse(draftStore.batches.contains { $0.id == emptyBatch.id })
        XCTAssertEqual(Set(draftStore.drafts.map(\.id)), draftIDsBefore,
                      "删除批次不得带走任何草稿")
        XCTAssertEqual(draftStore.drafts.filter { $0.batchID == blockedBatch.id }.count, 1,
                      "拦截批次里的草稿原样保留")
    }

    // MARK: 4. 白名单

    func testDeleteBatchesRequiresCreatorAccess() throws {
        CreatorAccess.setTestOverride(.viewer)
        let batch = try makeBatch(name: "白名单批次", statuses: [])
        XCTAssertThrowsError(try draftStore.deleteBatches(ids: [batch.id]))
        XCTAssertTrue(draftStore.batches.contains { $0.id == batch.id },
                      "鉴权失败时条目必须保留")
    }

    // MARK: 5. 拦截判定纯函数

    func testBatchDeleteBlockReasonForEmptyBatchIsNil() {
        var draft = CatalogProductDraft()
        draft.batchID = "batch-x"
        draft.status = .published
        XCTAssertNil(ShopCatalogDraftStore.batchDeleteBlockReason(
            batchID: "batch-x", drafts: [draft]))
        XCTAssertNil(ShopCatalogDraftStore.batchDeleteBlockReason(
            batchID: "batch-none", drafts: [draft]), "无关联草稿的批次可删")
    }
}
