//
//  ShopCatalogDraftDeletionTests.swift
//  ItemManagerTests
//
//  草稿箱删除（2026-09-23：单条按钮 + 多选批量 + 二次确认）契约：
//    1. 判定口径：勾选的 id 里**真实存在**的按草稿箱顺序进入 targetIDs，
//       已不存在的进 staleIDs（不算删除数）；`preview` 与执行同源，
//       「弹窗说删几条」与「实际删几条」恒等
//    2. 只动目标草稿：其余草稿一条不动，**批次归组记录也不动**
//       （与「删批次不动草稿」互为镜像）
//    3. 全状态可删（含已发布 / 已归档这份发布回执）：无硬拦截 ——
//       批次删除的拦截文案本身就让运营「在草稿箱中删除这些草稿」，若这里再拦一道，
//       那条指引就成了死路
//    4. 整批只写一次盘；写盘失败 / 坏文件封锁时内存与磁盘都不变，可原样重试
//    5. 需要运营白名单
//
//  ⚠️ 测试隔离（2026-09-21 事故）：先 `ShopCatalogStorage.useTemporaryForTesting()`，
//  否则 `FileManager.default` 指向宿主 App 真实沙盒、会删到用户数据。
//  另：`ShopCatalogDraftStore.shared` 的 drafts 跨套件累积 ——
//  断言一律用**前后快照 / 按 id 收窄 / 差值**，禁止断言全局总数。
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogDraftDeletionTests: XCTestCase {

    private var draftStore: ShopCatalogDraftStore!

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        draftStore = ShopCatalogDraftStore.shared
        // 切到本套件的全新临时目录后必须重新加载，否则内存里还是别的套件留下的草稿
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

    @discardableResult
    private func insertDraft(name: String,
                             status: CatalogPublicationStatus = .draft,
                             batchID: String? = nil) throws -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.price = 100
        draft.status = status
        draft.batchID = batchID
        try draftStore.upsert(draft)
        return draft
    }

    private func idSet(_ drafts: [CatalogProductDraft]) -> Set<String> {
        Set(drafts.map(\.id))
    }

    // MARK: 1. 判定口径：预检与执行同源

    func testPlanKeepsDraftBoxOrderAndCountsByStatus() throws {
        let a = try insertDraft(name: "A", status: .draft)
        let b = try insertDraft(name: "B", status: .submitted)
        let c = try insertDraft(name: "C", status: .published)

        // 勾选顺序故意与草稿箱顺序相反
        let plan = ShopCatalogDraftDeletion.plan(ids: [c.id, a.id], drafts: draftStore.drafts)

        XCTAssertEqual(plan.targetIDs, [a.id, c.id],
                       "targetIDs 应与草稿箱展示顺序一致，而不是勾选顺序")
        XCTAssertEqual(plan.countsByStatus[.draft], 1)
        XCTAssertEqual(plan.countsByStatus[.published], 1)
        XCTAssertNil(plan.countsByStatus[.submitted], "没勾中的状态不该出现在构成里")
        XCTAssertEqual(plan.inFlightCount, 1, "A 是草稿 → 仍在流转")
        XCTAssertEqual(plan.settledCount, 1, "C 已发布 → 已出终态")
        XCTAssertEqual(plan.targetCount, 2)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.staleIDs.isEmpty)
        XCTAssertFalse(b.id.isEmpty)
    }

    func testPlanRegistersStaleIDsWithoutCountingThem() throws {
        let a = try insertDraft(name: "A")

        let plan = ShopCatalogDraftDeletion.plan(ids: [a.id, "ghost-id"], drafts: draftStore.drafts)

        XCTAssertEqual(plan.targetIDs, [a.id])
        XCTAssertEqual(plan.staleIDs, ["ghost-id"], "已不存在的 id 只登记，不计入删除数")
        XCTAssertEqual(plan.targetCount, 1, "少报会让用户以为没删干净")
    }

    func testPlanIsEmptyForEmptySelectionOrOnlyStaleIDs() throws {
        try insertDraft(name: "A")

        XCTAssertTrue(ShopCatalogDraftDeletion.plan(ids: [], drafts: draftStore.drafts).isEmpty)

        let onlyStale = ShopCatalogDraftDeletion.plan(ids: ["ghost"], drafts: draftStore.drafts)
        XCTAssertTrue(onlyStale.isEmpty)
        XCTAssertEqual(onlyStale.staleIDs, ["ghost"])
        XCTAssertEqual(onlyStale.targetCount, 0)
    }

    func testPreviewAndExecutionAgreeOnCount() throws {
        let a = try insertDraft(name: "A")
        let b = try insertDraft(name: "B", status: .reviewed)
        let before = draftStore.drafts

        let preview = draftStore.previewDraftDeletion(ids: [a.id, b.id, "ghost"])
        let executed = try draftStore.deleteDrafts(ids: [a.id, b.id, "ghost"])

        XCTAssertEqual(preview, executed, "预检与执行必须同源：同输入必得同结果")
        XCTAssertEqual(executed.targetCount, 2)
        XCTAssertEqual(before.count - draftStore.drafts.count, 2,
                       "删除数 = 前后草稿数之差（不依赖全局总数断言）")
    }

    // MARK: 2. 只动目标草稿

    func testDeleteRemovesOnlySelectedDrafts() throws {
        let keep = try insertDraft(name: "保留")
        let doomed = try insertDraft(name: "删除")
        let before = idSet(draftStore.drafts)

        let plan = try draftStore.deleteDrafts(ids: [doomed.id])

        XCTAssertEqual(plan.targetIDs, [doomed.id])
        XCTAssertTrue(draftStore.drafts.contains { $0.id == keep.id }, "未勾选的草稿一条不动")
        XCTAssertFalse(draftStore.drafts.contains { $0.id == doomed.id })
        XCTAssertEqual(idSet(draftStore.drafts), before.subtracting([doomed.id]),
                       "结果集必须恰好等于「原集合 − 删除集」")
    }

    func testDeletingDraftDoesNotTouchBatchRecord() throws {
        let session = CatalogBatchEntrySession()
        var first = CatalogProductDraft()
        first.name = "批次内-1"
        first.price = 100
        first.batchID = session.id
        var second = CatalogProductDraft()
        second.name = "批次内-2"
        second.price = 100
        second.batchID = session.id
        _ = try draftStore.createBatch(session, drafts: [first, second])

        let batchesBefore = draftStore.batches
        _ = try draftStore.deleteDrafts(ids: [first.id])

        XCTAssertTrue(draftStore.batches.contains { $0.id == session.id },
                      "删草稿不得连带删批次归组记录（与「删批次不动草稿」互为镜像）")
        XCTAssertEqual(draftStore.batches.map(\.id), batchesBefore.map(\.id))
        XCTAssertTrue(draftStore.drafts.contains { $0.id == second.id }, "同批次其他草稿不受影响")
    }

    // MARK: 3. 全状态可删（无硬拦截）

    func testDeletingDraftsCoversEveryStatusWithoutBlocking() throws {
        var targets: [CatalogProductDraft] = []
        for status in CatalogPublicationStatus.allCases {
            targets.append(try insertDraft(name: "状态-\(status.rawValue)", status: status))
        }
        let before = idSet(draftStore.drafts)
        let targetIDs = idSet(targets)

        let plan = try draftStore.deleteDrafts(ids: targetIDs)

        XCTAssertEqual(plan.targetCount, CatalogPublicationStatus.allCases.count,
                       "全状态可删：草稿箱里再设一道拦截会让批次删除的指引变成死路")
        XCTAssertEqual(plan.settledCount, 2, "已发布 / 已归档各 1 条（发布回执，删了不动线上数据）")
        XCTAssertEqual(plan.inFlightCount, 3, "草稿 / 待审核 / 待发布各 1 条")
        XCTAssertTrue(plan.staleIDs.isEmpty)
        XCTAssertEqual(idSet(draftStore.drafts), before.subtracting(targetIDs))
    }

    func testDeletingSameIDsTwiceReportsNothingToDelete() throws {
        let a = try insertDraft(name: "A")
        _ = try draftStore.deleteDrafts(ids: [a.id])

        let second = try draftStore.deleteDrafts(ids: [a.id])

        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(second.staleIDs, [a.id], "第二次只登记为 stale，不谎报删除数")
        XCTAssertEqual(second.targetCount, 0)
    }

    // MARK: 4. 一次写盘 / 失败不变

    func testWriteFailureLeavesDraftsUnchanged() throws {
        let a = try insertDraft(name: "A")
        let b = try insertDraft(name: "B")
        let before = draftStore.drafts

        // 把草稿文件换成一个目录 → 写盘必然失败
        try FileManager.default.removeItem(at: draftsURL)
        try FileManager.default.createDirectory(at: draftsURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try draftStore.deleteDrafts(ids: [a.id, b.id])) { error in
            XCTAssertTrue(error is ShopCatalogDraftFileError, "必须是可诊断的写盘错误，实际：\(error)")
        }
        XCTAssertEqual(draftStore.drafts, before,
                       "写盘失败时内存必须原样保留（一条都没删），可原样重试")
    }

    func testDeletionIsBlockedWhenDraftFileIsCorrupt() throws {
        let a = try insertDraft(name: "A")
        let corrupt = Data("{{{ not json".utf8)
        try corrupt.write(to: draftsURL)
        draftStore.loadDrafts()
        XCTAssertTrue(draftStore.isBlockedByCorruptFile, "坏文件必须进入待处理状态")

        let before = draftStore.drafts
        XCTAssertThrowsError(try draftStore.deleteDrafts(ids: [a.id])) { error in
            XCTAssertTrue(error is ShopCatalogDraftFileError)
        }
        XCTAssertEqual(draftStore.drafts, before)
        XCTAssertEqual(try Data(contentsOf: draftsURL), corrupt,
                       "坏文件必须原样保留，绝不能被删除操作覆盖掉")
    }

    // MARK: 5. 运营白名单

    func testDeletionRequiresCreatorWhitelist() throws {
        let a = try insertDraft(name: "A")
        let before = draftStore.drafts

        CreatorAccess.setTestOverride(.viewer)

        XCTAssertThrowsError(try draftStore.deleteDrafts(ids: [a.id])) { error in
            XCTAssertTrue(error is CreatorAccessDenied, "普通用户不得删除草稿，实际：\(error)")
        }
        XCTAssertEqual(draftStore.drafts, before, "无权限时不得改动任何草稿")
    }
}
