import XCTest
import SwiftData
import SharedCatalog
import PinkHouseOpsCore
import AppKit
import SwiftUI
@testable import PinkHouseOps

@MainActor
final class OpsCatalogEditorPersistenceTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
    }

    private func suppressNetwork(_ workspace: OpsWorkspace) {
        workspace.catalogEditSyncQueue = OpsCatalogEditSyncQueue(
            pending: { nil }, isBusy: { false }, publish: { _ in .failed("test") }, finished: { _, _ in })
    }

    private func completedSeriesInput() -> OpsSeriesEntryDraft {
        OpsSeriesEntryDraft(createsNewShop: true, newShopName: "上一份店家",
            newSeriesName: "上一份系列", newSeriesYearText: "2026", newSeriesMonthText: "9",
            typeEntries: [OpsSeriesTypeEntry(category: "JSK", designName: "上一份款式",
                stockPriceText: "100", colors: [OpsSeriesColorSKU(name: "白色")])])
    }

    private func assertBlankSeries(_ entry: OpsSeriesEntryDraft, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(entry.shopID, "", file: file, line: line)
        XCTAssertFalse(entry.createsNewShop, file: file, line: line)
        XCTAssertEqual(entry.newShopName, "", file: file, line: line)
        XCTAssertNil(entry.shopLogoReference, file: file, line: line)
        XCTAssertEqual(entry.seriesID, "", file: file, line: line)
        XCTAssertEqual(entry.newSeriesName, "", file: file, line: line)
        XCTAssertEqual(entry.newSeriesYearText, "", file: file, line: line)
        XCTAssertEqual(entry.newSeriesMonthText, "", file: file, line: line)
        XCTAssertNil(entry.coverAssetID, file: file, line: line)
        XCTAssertFalse(entry.declaresPhase, file: file, line: line)
        XCTAssertFalse(entry.hasBalanceStart, file: file, line: line)
        XCTAssertFalse(entry.declaresPriceChart, file: file, line: line)
        XCTAssertTrue(entry.priceChartImageAssetIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(entry.typeEntries.isEmpty, file: file, line: line)
    }

    func testExplicitSeriesSaveClearsFormDurablyAndKeepsCatalog() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        let resetID = workspace.seriesEntryResetID
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        assertBlankSeries(workspace.seriesEntry)
        XCTAssertNotEqual(workspace.seriesEntryResetID, resetID, "界面需要返回第一步")
        let job = try XCTUnwrap(workspace.seriesPublishJobs().first)
        XCTAssertEqual(job.status, .pending)
        XCTAssertEqual(job.attempts, 0)
        XCTAssertEqual(job.draftID, workspace.draft?.id)
        XCTAssertEqual(job.environment, OpsCloudSyncModel.shared.targetEnvironment.rawValue)
        XCTAssertEqual(job.seriesID, workspace.catalog.series.first?.id)
        XCTAssertEqual(job.items.map(\.name), ["JSK·上一份款式"])
        XCTAssertTrue(job.items.allSatisfy(\.ok))
        let snapshot = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: XCTUnwrap(job.catalogSnapshotJSON))
        XCTAssertEqual(snapshot.products.count, 1)
        let restored = OpsWorkspace(context: ModelContext(store))
        assertBlankSeries(restored.seriesEntry)
        XCTAssertEqual(restored.seriesPublishJobs().first?.id, job.id)
        XCTAssertEqual(restored.seriesPublishJobs().first?.status, .pending)
        XCTAssertEqual(restored.catalog.shops.first?.name, "上一份店家")
        XCTAssertEqual(restored.catalog.series.first?.name, "上一份系列")
        XCTAssertEqual(restored.catalog.products.first?.name, "上一份款式")
        XCTAssertEqual(restored.priceArchive(forProduct: restored.catalog.products[0].id)?.currentStockPrice, 100)
    }

    func testInvalidSeriesSaveRetainsInputAndStep() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        workspace.seriesEntry = completedSeriesInput()
        workspace.seriesEntry.typeEntries[0].designName = ""
        let input = workspace.seriesEntry
        let resetID = workspace.seriesEntryResetID
        XCTAssertFalse(workspace.saveSeriesEntryToDraft().allOK)
        XCTAssertEqual(workspace.seriesEntry, input)
        XCTAssertEqual(workspace.seriesEntryResetID, resetID)
        XCTAssertTrue(workspace.seriesPublishJobs().isEmpty)
    }

    func testBlankFormDiskFailureRetainsCompletedInputAndPersistedJSON() throws {
        let store = try container()
        var saveCalls = 0
        let workspace = OpsWorkspace(context: store.mainContext, saveCatalogContext: {
            saveCalls += 1
            if saveCalls == 2 { throw NSError(domain: "test.blankFormDisk", code: 1) }
            try $0.save()
        })
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        let resetID = workspace.seriesEntryResetID
        XCTAssertFalse(workspace.saveSeriesEntryToDraft().allOK)
        XCTAssertEqual(workspace.seriesEntry.newSeriesName, "上一份系列")
        XCTAssertEqual(workspace.seriesEntryResetID, resetID)
        XCTAssertTrue(workspace.lastError?.contains("空白表单保存失败") == true)
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(restored.seriesEntry.newSeriesName, "上一份系列")
        XCTAssertEqual(restored.catalog.products.count, 1)
        XCTAssertTrue(workspace.seriesPublishJobs().isEmpty, "草稿箱落盘失败不能留下虚假待发布记录")
        XCTAssertTrue(restored.seriesPublishJobs().isEmpty)
    }

    func testConfirmedSeriesPublicationClearsDurably() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        let result = await workspace.publishSeries(cloud: .shared, publishNow: { current in
            XCTAssertEqual(current.seriesEntry.newSeriesName, "上一份系列", "上传开始前不能清空")
            return .confirmed(releaseSeq: 42)
        })
        XCTAssertEqual(result, .published(releaseSeq: 42))
        assertBlankSeries(workspace.seriesEntry)
        XCTAssertTrue(workspace.seriesPublishJobs().isEmpty)
        XCTAssertTrue(workspace.statusMessage?.contains("上一份系列") == true)
        let restored = OpsWorkspace(context: ModelContext(store))
        assertBlankSeries(restored.seriesEntry)
        XCTAssertEqual(restored.catalog.products.count, 1)
    }

    func testUnconfirmedSeriesPublicationRetainsFormAndJob() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        let resetID = workspace.seriesEntryResetID
        let result = await workspace.publishSeries(cloud: .shared, publishNow: { _ in .failed("结果待确认") })
        XCTAssertEqual(result, .failed(reason: "结果待确认", itemFailures: []))
        XCTAssertEqual(workspace.seriesEntry.newSeriesName, "上一份系列")
        XCTAssertEqual(workspace.seriesEntryResetID, resetID)
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(restored.seriesEntry.newSeriesName, "上一份系列")
        XCTAssertEqual(restored.seriesPublishJobs().count, 1)
    }

    func testPublicationDoesNotClearNewInputEnteredInBackground() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        let resetID = workspace.seriesEntryResetID
        let result = await workspace.publishSeries(cloud: .shared, publishNow: { current in
            current.seriesEntry.newSeriesName = "发布期间的新输入"
            current.persistSeriesEntryState()
            return .confirmed(releaseSeq: 43)
        })
        XCTAssertEqual(result, .published(releaseSeq: 43))
        XCTAssertEqual(workspace.seriesEntry.newSeriesName, "发布期间的新输入")
        XCTAssertEqual(workspace.seriesEntryResetID, resetID)
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(restored.seriesEntry.newSeriesName, "发布期间的新输入")
    }

    func testPublicationDoesNotClearAnotherDraftOpenedInBackground() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        let result = await workspace.publishSeries(cloud: .shared, publishNow: { current in
            _ = current.createDraft(title: "下一份草稿")
            current.seriesEntry.newSeriesName = "下一份系列"
            current.persistSeriesEntryState()
            return .confirmed(releaseSeq: 44)
        })
        XCTAssertEqual(result, .published(releaseSeq: 44))
        XCTAssertEqual(workspace.draft?.title, "下一份草稿")
        XCTAssertEqual(workspace.seriesEntry.newSeriesName, "下一份系列")
    }

    func testTwoSeriesDraftsStayInQueueAfterFormsClear() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        workspace.seriesEntry = completedSeriesInput()
        workspace.seriesEntry.newShopName = "下一份店家"
        workspace.seriesEntry.newSeriesName = "下一份系列"
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        assertBlankSeries(workspace.seriesEntry)
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(Set(restored.seriesPublishJobs().map(\.seriesName)), ["上一份系列", "下一份系列"])
        XCTAssertTrue(restored.seriesPublishJobs().allSatisfy { $0.status == .pending })
        XCTAssertEqual(restored.catalog.products.count, 2)
    }

    func testResavingSameSeriesReusesQueuedRecord() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.commitSeriesEntry().allOK)
        let committed = workspace.seriesEntry
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        let job = try XCTUnwrap(workspace.seriesPublishJobs().first)
        let id = job.id
        let firstSubmission = job.submissionID
        workspace.seriesEntry = committed
        workspace.seriesEntry.typeEntries[0].stockPriceText = "200"
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        XCTAssertEqual(workspace.seriesPublishJobs().count, 1)
        XCTAssertEqual(job.id, id)
        XCTAssertNotEqual(job.submissionID, firstSubmission)
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(restored.seriesPublishJobs().first?.id, id)
        XCTAssertEqual(restored.catalog.products.count, 1)
        XCTAssertEqual(restored.priceArchive(forProduct: restored.catalog.products[0].id)?.currentStockPrice, 200)
    }

    func testQueuedSeriesPublishesAfterFormResetAndPreservesNextInput() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        let job = try XCTUnwrap(workspace.seriesPublishJobs().first)
        let product = try XCTUnwrap(workspace.catalog.products.first)
        XCTAssertTrue(workspace.applyPriceCorrection(productID: product.id, reservationPrice: nil,
            stockPrice: 220, deposit: nil, balance: nil, currency: .cny))
        XCTAssertTrue(workspace.saveDraft())
        workspace.seriesEntry = OpsSeriesEntryDraft(createsNewShop: true, newShopName: "正在填写的店家",
            newSeriesName: "正在填写的系列")
        let input = workspace.seriesEntry
        let result = await workspace.retrySeriesPublish(job: job, cloud: .shared, publishNow: { current in
            XCTAssertEqual(current.seriesEntry, input, "草稿箱发布不能提交下一份向导")
            XCTAssertEqual(current.catalog.products.count, 1)
            guard let data = job.catalogSnapshotJSON,
                  let latest = try? ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: data) else {
                XCTFail("必须保留可解码的最新目录快照")
                return .failed("缺少目录快照")
            }
            XCTAssertEqual(latest.products.first?.priceCorrection?.stockPrice, 220)
            return .confirmed(releaseSeq: 50)
        })
        XCTAssertEqual(result, .published(releaseSeq: 50))
        XCTAssertTrue(workspace.seriesPublishJobs().isEmpty)
        XCTAssertEqual(workspace.seriesEntry, input)
    }

    func testQueuedSeriesFailureRetainsSameRecordAndCanRetry() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        let job = try XCTUnwrap(workspace.seriesPublishJobs().first)
        let id = job.id
        let failed = await workspace.retrySeriesPublish(job: job, cloud: .shared, publishNow: { _ in .failed("网络中断") })
        XCTAssertEqual(failed, .failed(reason: "网络中断", itemFailures: []))
        XCTAssertEqual(job.status, .failed)
        XCTAssertEqual(job.attempts, 1)
        let restored = OpsWorkspace(context: ModelContext(store))
        suppressNetwork(restored)
        let retryJob = try XCTUnwrap(restored.seriesPublishJobs().first)
        XCTAssertEqual(retryJob.id, id)
        let result = await restored.retrySeriesPublish(job: retryJob, cloud: .shared, publishNow: { _ in .confirmed(releaseSeq: 51) })
        XCTAssertEqual(result, .published(releaseSeq: 51))
        XCTAssertTrue(restored.seriesPublishJobs().isEmpty)
        assertBlankSeries(restored.seriesEntry)
    }

    func testQueuedPublishRefusesAnotherDraftAndOpeningOwnerPreservesCurrentInput() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        let job = try XCTUnwrap(workspace.seriesPublishJobs().first)
        let ownerID = workspace.draft?.id
        let other = workspace.createDraft(title: "另一个草稿")
        workspace.seriesEntry.newSeriesName = "另一个草稿中的输入"
        let result = await workspace.retrySeriesPublish(job: job, cloud: .shared, publishNow: { _ in
            XCTFail("不能用另一份目录发布此系列")
            return .confirmed(releaseSeq: 52)
        })
        guard case .failed = result else { return XCTFail("应阻止错草稿发布") }
        XCTAssertEqual(job.status, .pending)
        XCTAssertTrue(workspace.openSeriesPublishDraft(job: job))
        XCTAssertEqual(workspace.draft?.id, ownerID)
        assertBlankSeries(workspace.seriesEntry)
        XCTAssertTrue(workspace.adoptDraft(id: other.id))
        XCTAssertEqual(workspace.seriesEntry.newSeriesName, "另一个草稿中的输入")
    }

    func testQueuedPublishStateDiskFailureNeverStartsNetworking() async throws {
        let store = try container()
        var fails = false
        let workspace = OpsWorkspace(context: store.mainContext, saveCatalogContext: {
            if fails { throw NSError(domain: "test.queue.state", code: 1) }
            try $0.save()
        })
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        let job = try XCTUnwrap(workspace.seriesPublishJobs().first)
        let snapshot = job.catalogSnapshotJSON
        fails = true
        let result = await workspace.retrySeriesPublish(job: job, cloud: .shared, publishNow: { _ in
            XCTFail("发布状态落盘失败时不能联网")
            return .confirmed(releaseSeq: 53)
        })
        guard case .failed = result else { return XCTFail("应报告状态保存失败") }
        XCTAssertEqual(job.status, .pending)
        XCTAssertEqual(job.attempts, 0)
        XCTAssertEqual(job.catalogSnapshotJSON, snapshot)
    }

    func testOldPublishCompletionCannotRemoveResubmittedQueueRecord() async throws {
        for confirmed in [true, false] {
            let store = try container()
            let workspace = OpsWorkspace(context: store.mainContext)
            suppressNetwork(workspace)
            workspace.seriesEntry = completedSeriesInput()
            XCTAssertTrue(workspace.commitSeriesEntry().allOK)
            let committed = workspace.seriesEntry
            XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
            let job = try XCTUnwrap(workspace.seriesPublishJobs().first)
            let oldSubmission = job.submissionID
            _ = await workspace.retrySeriesPublish(job: job, cloud: .shared, publishNow: { current in
                current.seriesEntry = committed
                current.seriesEntry.typeEntries[0].stockPriceText = "300"
                XCTAssertTrue(current.saveSeriesEntryToDraft().allOK)
                return confirmed ? .confirmed(releaseSeq: 54) : .failed("旧请求失败")
            })
            let remaining = try XCTUnwrap(workspace.seriesPublishJobs().first)
            XCTAssertEqual(remaining.id, job.id)
            XCTAssertNotEqual(remaining.submissionID, oldSubmission)
            XCTAssertEqual(remaining.status, .pending)
            XCTAssertNil(remaining.lastError)
            let restored = OpsWorkspace(context: ModelContext(store))
            XCTAssertEqual(restored.seriesPublishJobs().first?.status, .pending)
        }
    }

    func testSQLiteReopenPreservesPendingSeriesAndBlankForm() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("series.store"), cloudKitDatabase: .none)
        var ownerID: String?
        var jobID = ""
        do {
            let store = try ModelContainer(for: schema, configurations: [config])
            let workspace = OpsWorkspace(context: store.mainContext)
            suppressNetwork(workspace)
            workspace.seriesEntry = completedSeriesInput()
            XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
            ownerID = workspace.draft?.id
            jobID = try XCTUnwrap(workspace.seriesPublishJobs().first?.id)
        }
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let restored = OpsWorkspace(context: reopened.mainContext)
        suppressNetwork(restored)
        assertBlankSeries(restored.seriesEntry)
        let job = try XCTUnwrap(restored.seriesPublishJobs().first)
        XCTAssertEqual(job.id, jobID)
        XCTAssertEqual(job.draftID, ownerID)
        XCTAssertEqual(job.status, .pending)
        XCTAssertEqual(job.seriesName, "上一份系列")
    }

    func testExistingQueuedRecordRollsBackWhenResaveFails() throws {
        let store = try container()
        var calls = 0
        var failAt: Int?
        let workspace = OpsWorkspace(context: store.mainContext, saveCatalogContext: {
            calls += 1
            if calls == failAt { throw NSError(domain: "test.queue.resave", code: 1) }
            try $0.save()
        })
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.commitSeriesEntry().allOK)
        let committed = workspace.seriesEntry
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        let job = try XCTUnwrap(workspace.seriesPublishJobs().first)
        let before = (job.submissionID, job.catalogSnapshotJSON, job.itemsJSON, job.updatedAt)
        workspace.seriesEntry = committed
        workspace.seriesEntry.typeEntries[0].stockPriceText = "250"
        failAt = calls + 2 // 目录先保存成功，草稿箱和空白表单事务失败。
        XCTAssertFalse(workspace.saveSeriesEntryToDraft().allOK)
        XCTAssertEqual(job.status, .pending)
        XCTAssertEqual(job.submissionID, before.0)
        XCTAssertEqual(job.catalogSnapshotJSON, before.1)
        XCTAssertEqual(job.itemsJSON, before.2)
        XCTAssertEqual(job.updatedAt, before.3)
        XCTAssertEqual(workspace.seriesEntry.typeEntries[0].stockPriceText, "250")
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(restored.seriesPublishJobs().count, 1)
        XCTAssertEqual(restored.seriesPublishJobs().first?.submissionID, before.0)
    }

    func testLegacyQueuedRecordWithoutNewMetadataStillPublishes() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        let job = try XCTUnwrap(workspace.seriesPublishJobs().first)
        job.draftID = nil
        job.submissionID = nil
        job.environment = nil
        try store.mainContext.save()
        let result = await workspace.retrySeriesPublish(job: job, cloud: .shared, publishNow: { _ in .confirmed(releaseSeq: 55) })
        XCTAssertEqual(result, .published(releaseSeq: 55))
        XCTAssertTrue(workspace.seriesPublishJobs().isEmpty)
    }

    private func batchFixture(_ workspace: OpsWorkspace, count: Int = 3) throws -> [OpsSeriesPublishJob] {
        suppressNetwork(workspace)
        for index in 1...count {
            workspace.seriesEntry = completedSeriesInput()
            workspace.seriesEntry.newSeriesName = "批量系列\(index)"
            XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        }
        return workspace.seriesPublishJobs().sorted { $0.seriesName < $1.seriesName }
    }

    func testBatchPublishesSelectionOnceAndKeepsUnselectedRecordAndNextInput() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        let jobs = try batchFixture(workspace)
        workspace.seriesEntry.newSeriesName = "下一份正在录入"
        workspace.persistSeriesEntryState()
        let resetID = workspace.seriesEntryResetID
        var uploads = 0
        let result = await workspace.publishSelectedSeries(jobs: [jobs[0], jobs[1], jobs[0]], cloud: .shared, publishNow: { current in
            uploads += 1
            XCTAssertEqual(jobs[0].status, .publishing)
            XCTAssertEqual(jobs[1].status, .publishing)
            XCTAssertEqual(jobs[2].status, .pending)
            XCTAssertEqual(jobs[0].attempts, 1)
            let persisted = OpsWorkspace(context: ModelContext(store))
            XCTAssertEqual(persisted.seriesPublishJobs().filter { $0.status == .publishing }.count, 2)
            XCTAssertEqual(current.catalog.products.count, 3)
            return .confirmed(releaseSeq: 81)
        })
        XCTAssertEqual(result, .published(releaseSeq: 81))
        XCTAssertEqual(uploads, 1, "合并成一个目录发布，不能每个系列重复上传整包")
        XCTAssertEqual(workspace.seriesPublishJobs().map(\.id), [jobs[2].id])
        XCTAssertEqual(workspace.seriesEntry.newSeriesName, "下一份正在录入")
        XCTAssertEqual(workspace.seriesEntryResetID, resetID)
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(restored.seriesPublishJobs().map(\.id), [jobs[2].id])
        XCTAssertEqual(restored.seriesEntry.newSeriesName, "下一份正在录入")
        XCTAssertEqual(restored.catalog.products.count, 3)
    }

    func testBatchFailureKeepsEverySelectedRecordAndRetriesTogetherAfterReopen() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        let jobs = try batchFixture(workspace, count: 2)
        let ids = Set(jobs.map(\.id))
        let result = await workspace.publishSelectedSeries(jobs: jobs, cloud: .shared, publishNow: { _ in .failed("网络中断，结果未确认") })
        XCTAssertEqual(result, .failed(reason: "网络中断，结果未确认", itemFailures: []))
        let reopened = OpsWorkspace(context: ModelContext(store))
        suppressNetwork(reopened)
        let retained = reopened.seriesPublishJobs()
        XCTAssertEqual(Set(retained.map(\.id)), ids)
        XCTAssertTrue(retained.allSatisfy { $0.status == .failed && $0.attempts == 1 && $0.lastError == "网络中断，结果未确认" })
        var uploads = 0
        let retry = await reopened.publishSelectedSeries(jobs: retained, cloud: .shared, publishNow: { _ in
            uploads += 1
            XCTAssertTrue(retained.allSatisfy { $0.status == .publishing && $0.attempts == 2 })
            return .confirmed(releaseSeq: 82)
        })
        XCTAssertEqual(retry, .published(releaseSeq: 82))
        XCTAssertEqual(uploads, 1)
        XCTAssertTrue(OpsWorkspace(context: ModelContext(store)).seriesPublishJobs().isEmpty)
    }

    func testBatchRejectsWholeSelectionBeforeUploadingIfOneRecordIsUnavailable() async throws {
        for condition in ["otherDraft", "environment", "partial", "failedItem", "emptyItems", "missingSeries", "publishing", "published"] {
            let store = try container()
            let workspace = OpsWorkspace(context: store.mainContext)
            let jobs = try batchFixture(workspace, count: 2)
            switch condition {
            case "otherDraft": jobs[1].draftID = "different-draft"
            case "environment": jobs[1].environment = "different-environment"
            case "partial": jobs[1].status = .partialFailed
            case "failedItem": jobs[1].items = [.init(id: "invalid", name: "款式", ok: false, message: "缺少名称")]
            case "emptyItems": jobs[1].items = []
            case "missingSeries": jobs[1].seriesID = "missing"
            case "publishing": jobs[1].status = .publishing
            default: jobs[1].status = .published
            }
            XCTAssertNil(workspace.seriesBatchPublishBlockReason(job: jobs[0], cloud: .shared))
            XCTAssertNotNil(workspace.seriesBatchPublishBlockReason(job: jobs[1], cloud: .shared))
            var uploaded = false
            let result = await workspace.publishSelectedSeries(jobs: jobs, cloud: .shared, publishNow: { _ in
                uploaded = true
                return .confirmed(releaseSeq: 99)
            })
            guard case .failed = result else { return XCTFail("不允许只发布选择中能通过的半组：\(condition)") }
            XCTAssertFalse(uploaded)
            XCTAssertEqual(jobs[0].status, .pending)
            XCTAssertEqual(jobs[0].attempts, 0)
        }
    }

    func testEmptySelectionAndBusyCloudNeverUpload() async throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        let jobs = try batchFixture(workspace, count: 2)
        var uploaded = false
        let callback: (OpsWorkspace) async -> OpsPublishInvocationResult = { _ in uploaded = true; return .confirmed(releaseSeq: 99) }
        let empty = await workspace.publishSelectedSeries(jobs: [], cloud: .shared, publishNow: callback)
        XCTAssertEqual(empty, .failed(reason: "请先勾选要发布的系列。", itemFailures: []))
        let cloud = OpsCloudSyncModel.shared
        let previous = cloud.isSyncing
        defer { cloud.isSyncing = previous }
        cloud.isSyncing = true
        let busy = await workspace.publishSelectedSeries(jobs: jobs, cloud: cloud, publishNow: callback)
        guard case .failed = busy else { return XCTFail("已有同步时不允许发起另一组发布") }
        XCTAssertFalse(uploaded)
        XCTAssertTrue(jobs.allSatisfy { $0.status == .pending && $0.attempts == 0 })
    }

    func testBatchStateSaveFailureRollsBackWholeGroupWithoutNetworking() async throws {
        let store = try container()
        var failSave = false
        let workspace = OpsWorkspace(context: store.mainContext, saveCatalogContext: {
            if failSave { throw NSError(domain: "test.batch.state", code: 1) }
            try $0.save()
        })
        let jobs = try batchFixture(workspace, count: 2)
        let snapshots = jobs.map(\.catalogSnapshotJSON)
        failSave = true
        var uploaded = false
        let result = await workspace.publishSelectedSeries(jobs: jobs, cloud: .shared, publishNow: { _ in
            uploaded = true
            return .confirmed(releaseSeq: 99)
        })
        guard case .failed(let reason, _) = result else { return XCTFail("保存失败不能宣称发布") }
        XCTAssertTrue(reason.contains("尚未上传"))
        XCTAssertFalse(uploaded)
        XCTAssertEqual(jobs.map(\.catalogSnapshotJSON), snapshots)
        XCTAssertTrue(jobs.allSatisfy { $0.status == .pending && $0.attempts == 0 })
        let persisted = OpsWorkspace(context: ModelContext(store)).seriesPublishJobs()
        XCTAssertEqual(persisted.count, 2)
        XCTAssertTrue(persisted.allSatisfy { $0.status == .pending && $0.attempts == 0 })
    }

    func testBatchOldReceiptCannotRemoveOrFailNewerSubmission() async throws {
        for confirms in [true, false] {
            let store = try container()
            let workspace = OpsWorkspace(context: store.mainContext)
            suppressNetwork(workspace)
            workspace.seriesEntry = completedSeriesInput()
            XCTAssertTrue(workspace.commitSeriesEntry().allOK)
            let original = workspace.seriesEntry
            XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
            let first = try XCTUnwrap(workspace.seriesPublishJobs().first)
            workspace.seriesEntry = completedSeriesInput()
            workspace.seriesEntry.newSeriesName = "第二份系列"
            XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
            let second = try XCTUnwrap(workspace.seriesPublishJobs().first { $0.id != first.id })
            let oldSubmission = first.submissionID
            _ = await workspace.publishSelectedSeries(jobs: [first, second], cloud: .shared, publishNow: { current in
                current.seriesEntry = original
                current.seriesEntry.typeEntries[0].stockPriceText = "300"
                XCTAssertTrue(current.saveSeriesEntryToDraft().allOK)
                current.seriesEntry.newSeriesName = "仍在录入"
                current.persistSeriesEntryState()
                return confirms ? .confirmed(releaseSeq: 83) : .failed("旧批次失败")
            })
            let restored = OpsWorkspace(context: ModelContext(store))
            let newer = try XCTUnwrap(restored.seriesPublishJobs().first { $0.id == first.id })
            XCTAssertNotEqual(newer.submissionID, oldSubmission)
            XCTAssertEqual(newer.status, .pending)
            XCTAssertNil(newer.lastError)
            XCTAssertEqual(restored.seriesEntry.newSeriesName, "仍在录入")
            XCTAssertEqual(restored.seriesPublishJobs().count, confirms ? 1 : 2)
            if !confirms { XCTAssertEqual(restored.seriesPublishJobs().first { $0.id == second.id }?.status, .failed) }
        }
    }

    func testBatchConfirmedButLocalSaveFailsDoesNotOfferRepublish() async throws {
        for failsAt in [2, 3] { // 发布回执保存 / 已确认记录清理
            let store = try container()
            var postSetupSaves = 0
            var testing = false
            let workspace = OpsWorkspace(context: store.mainContext, saveCatalogContext: {
                if testing {
                    postSetupSaves += 1
                    if postSetupSaves == failsAt { throw NSError(domain: "test.batch.receipt", code: failsAt) }
                }
                try $0.save()
            })
            let jobs = try batchFixture(workspace, count: 2)
            testing = true
            let result = await workspace.publishSelectedSeries(jobs: jobs, cloud: .shared, publishNow: { current in
                current.seriesEntry.newSeriesName = "上传期间保存的新输入"
                current.persistSeriesEntryState()
                return .confirmed(releaseSeq: 84)
            })
            XCTAssertEqual(result, .published(releaseSeq: 84), "云端已经成功，本机清理失败不能宣称上传失败")
            XCTAssertNotNil(workspace.lastError)
            XCTAssertEqual(workspace.seriesPublishJobs().count, 2)
            XCTAssertTrue(workspace.seriesPublishJobs().allSatisfy { $0.status == .published && $0.releaseSeq == 84 })
            let persisted = OpsWorkspace(context: ModelContext(store)).seriesPublishJobs()
            XCTAssertEqual(persisted.count, 2)
            XCTAssertTrue(persisted.allSatisfy { workspace.seriesBatchPublishBlockReason(job: $0, cloud: .shared) != nil })
            if failsAt == 3 { XCTAssertTrue(persisted.allSatisfy { $0.status == .published && $0.releaseSeq == 84 }) }
            XCTAssertEqual(workspace.seriesEntry.newSeriesName, "上传期间保存的新输入")
            XCTAssertEqual(OpsWorkspace(context: ModelContext(store)).seriesEntry.newSeriesName, "上传期间保存的新输入")
        }
    }

    func testSeriesCoverSurvivesCommitReopenAndExportWithImageBytes() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try writeImage(into: directory, name: "系列封面 原图.png")
        let assetID = try XCTUnwrap(workspace.importSingleImage(from: original))
        workspace.seriesEntry = completedSeriesInput()
        workspace.seriesEntry.coverAssetID = assetID
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        try FileManager.default.removeItem(at: original)
        let reopened = OpsWorkspace(context: ModelContext(store))
        let series = try XCTUnwrap(reopened.catalog.series.first)
        XCTAssertEqual(series.cover, assetID)
        let imageURL = try XCTUnwrap(reopened.stagedImageURL(forReference: series.cover))
        XCTAssertNotNil(NSImage(contentsOf: imageURL))
        let entries = try ShopCatalogExportArchive.completeHandoffEntries(for: reopened.catalog, imageDirectory: reopened.stagingDirectory)
        let bytes = try Data(contentsOf: imageURL)
        XCTAssertTrue(entries.contains { $0.name.hasPrefix("images/") && $0.data == bytes })
        let json = try XCTUnwrap(entries.first { $0.name == "shop-catalog.json" })
        let exported = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: json.data)
        XCTAssertEqual(exported.series.first?.cover, assetID)
        XCTAssertEqual(ShopCatalogImageSource.resolve(assetID, asset: { id in exported.assets.first { $0.id == id } }).references,
                       [reopened.asset(for: assetID)!.originalURL])
    }

    func testMacSeriesCoverResolvesDirectAndCanonicalReferencesAndPreviewFallback() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try XCTUnwrap(workspace.importSingleImage(from: writeImage(into: directory, name: "下载封面.png")))
        let asset = try XCTUnwrap(workspace.asset(for: id))
        let local = try XCTUnwrap(workspace.stagedFileURL(forReference: asset.originalURL))
        XCTAssertEqual(workspace.stagedImageURL(forReference: asset.originalURL), local)
        let hash = try XCTUnwrap(asset.mediaKey)
        XCTAssertEqual(workspace.stagedImageURL(forReference: "thmedia:" + hash), local)
        let index = try XCTUnwrap(workspace.catalog.assets.firstIndex { $0.id == id })
        workspace.catalog.assets[index].originalURL = "local:missing-original.png"
        workspace.catalog.assets[index].previewURL = asset.originalURL
        XCTAssertEqual(workspace.stagedImageURL(forReference: id), local)
        workspace.catalog.assets[index].originalURL = ""
        workspace.catalog.assets[index].previewURL = nil
        workspace.catalog.assets[index].thumbnailURL = nil
        XCTAssertEqual(workspace.stagedImageURL(forReference: id), local, "只有 canonical 媒体键仍应能读取已下载图片")
        XCTAssertNil(workspace.stagedImageURL(forReference: nil))
        XCTAssertNil(workspace.stagedImageURL(forReference: "unknown-asset"))
    }

    func testDuplicateStylePreservesAllInputAndPersistsIndependentIdentities() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        var original = OpsSeriesTypeEntry(category: "OP", designName: "纯色 OP",
            usesSizeChart: true, chartUnit: "cm", chartColumnsText: "胸围,裙长",
            chartRowsText: "XS = 80, 90\nS = 84, 92", chartSourceImageAssetID: "chart-image",
            reservationPriceText: "570.00", depositText: "100.00", balanceText: "470.00",
            stockPriceText: "699.00", currencyRawValue: CatalogCurrency.jpy.rawValue,
            colors: [.init(name: "奶白", imageAssetID: "white-image", selectedSizes: ["S"]),
                     .init(name: "黑色", imageAssetID: "black-image", selectedSizes: [])],
            committedProductID: "already-committed-product", lastCommitOK: true)
        workspace.seriesEntry = completedSeriesInput()
        workspace.seriesEntry.typeEntries = [original, OpsSeriesTypeEntry(category: "KC", designName: "其它条目")]
        let catalog = workspace.catalog
        let copyID = try XCTUnwrap(workspace.duplicateSeriesTypeEntry(id: original.id))
        XCTAssertEqual(workspace.seriesEntry.typeEntries.map(\.id), [original.id, copyID, workspace.seriesEntry.typeEntries[2].id])
        let copy = workspace.seriesEntry.typeEntries[1]
        XCTAssertNil(copy.committedProductID)
        XCTAssertNil(copy.lastCommitOK)
        XCTAssertTrue(Set(copy.colors.map(\.id)).isDisjoint(with: original.colors.map(\.id)))
        original.id = copy.id
        for index in original.colors.indices { original.colors[index].id = copy.colors[index].id }
        original.committedProductID = nil
        original.lastCommitOK = nil
        XCTAssertEqual(copy, original, "除内部身份与提交状态外，原文必须逐字段保持，名称不追加副本后缀，尾款不重算")
        XCTAssertEqual(workspace.catalog, catalog, "复制表单不能立即新增商品或发布")
        let reopened = OpsWorkspace(context: ModelContext(store))
        // 既有 JSON 日期精度为秒；比较重新解码后的完整草稿，避免默认日期的亚秒误差。
        let expected = try ShopCatalogJSONCoding.decoder().decode(OpsSeriesEntryDraft.self,
            from: ShopCatalogJSONCoding.encoder().encode(workspace.seriesEntry))
        XCTAssertEqual(reopened.seriesEntry, expected)
        workspace.seriesEntry.typeEntries[1].designName = "改过的副本"
        workspace.seriesEntry.typeEntries[1].colors[0].name = "副本配色"
        workspace.seriesEntry.typeEntries[1].depositText = "150"
        XCTAssertEqual(workspace.seriesEntry.typeEntries[0].designName, "纯色 OP")
        XCTAssertEqual(workspace.seriesEntry.typeEntries[0].colors[0].name, "奶白")
        XCTAssertEqual(workspace.seriesEntry.typeEntries[0].balanceText, "470.00")
    }

    func testCopyOfCommittedStyleCreatesNewProductAndKeepsOriginal() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.commitSeriesEntry().allOK)
        let original = workspace.seriesEntry.typeEntries[0]
        let productID = try XCTUnwrap(original.committedProductID)
        let copyID = try XCTUnwrap(workspace.duplicateSeriesTypeEntry(id: original.id))
        let copyIndex = try XCTUnwrap(workspace.seriesEntry.typeEntries.firstIndex { $0.id == copyID })
        workspace.seriesEntry.typeEntries[copyIndex].designName = "修改副本款式"
        workspace.seriesEntry.typeEntries[copyIndex].stockPriceText = "200"
        XCTAssertTrue(workspace.commitSeriesEntry().allOK)
        let newProductID = try XCTUnwrap(workspace.seriesEntry.typeEntries[copyIndex].committedProductID)
        XCTAssertNotEqual(newProductID, productID)
        XCTAssertEqual(workspace.catalog.products.count, 2)
        XCTAssertEqual(workspace.catalog.products.first { $0.id == productID }?.name, original.designName)
        XCTAssertEqual(workspace.priceArchive(forProduct: productID)?.currentStockPrice, 100)
        XCTAssertEqual(workspace.priceArchive(forProduct: newProductID)?.currentStockPrice, 200)
        XCTAssertEqual(workspace.variants(forProduct: productID).map(\.color), ["白色"])
        XCTAssertEqual(workspace.variants(forProduct: newProductID).map(\.color), ["白色"])
    }

    func testCopySaveFailureDoesNotInsertOrAlterOriginal() throws {
        let store = try container()
        var fails = false
        let workspace = OpsWorkspace(context: store.mainContext, saveCatalogContext: {
            if fails { throw NSError(domain: "test.copyStyle.disk", code: 1) }
            try $0.save()
        })
        suppressNetwork(workspace)
        workspace.seriesEntry = completedSeriesInput()
        workspace.persistSeriesEntryState()
        let original = workspace.seriesEntry
        let json = workspace.draft?.seriesEntryJSON
        fails = true
        XCTAssertNil(workspace.duplicateSeriesTypeEntry(id: original.typeEntries[0].id))
        XCTAssertEqual(workspace.seriesEntry, original)
        XCTAssertEqual(workspace.draft?.seriesEntryJSON, json)
        let expected = try ShopCatalogJSONCoding.decoder().decode(OpsSeriesEntryDraft.self, from: XCTUnwrap(json))
        XCTAssertEqual(OpsWorkspace(context: ModelContext(store)).seriesEntry, expected)
        XCTAssertTrue(workspace.lastError?.contains("复制款式保存失败") == true)
    }

    func testCopyKeepsIncompleteTextAndCanRepeatWithoutIDCollisions() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry.typeEntries = [OpsSeriesTypeEntry(category: "自定义", designName: "",
            chartRowsText: "尚未填写完的表格", reservationPriceText: "57.", depositText: "未知", balanceText: "旧尾款")]
        let id = workspace.seriesEntry.typeEntries[0].id
        XCTAssertNotNil(workspace.duplicateSeriesTypeEntry(id: id))
        XCTAssertNotNil(workspace.duplicateSeriesTypeEntry(id: id))
        XCTAssertEqual(workspace.seriesEntry.typeEntries.count, 3)
        XCTAssertEqual(Set(workspace.seriesEntry.typeEntries.map(\.id)).count, 3)
        XCTAssertTrue(workspace.seriesEntry.typeEntries.allSatisfy { $0.reservationPriceText == "57." && $0.balanceText == "旧尾款" })
        let before = workspace.seriesEntry
        XCTAssertNil(workspace.duplicateSeriesTypeEntry(id: "unknown"))
        XCTAssertEqual(workspace.seriesEntry, before)
    }

    private func writeImage(into directory: URL, name: String, rgb: (UInt8, UInt8, UInt8) = (205, 90, 135)) throws -> URL {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 64, bitsPerPixel: 32))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for y in 0..<16 { for x in 0..<16 {
            let offset = y * bitmap.bytesPerRow + x * 4
            pixels[offset] = rgb.0
            pixels[offset + 1] = rgb.1
            pixels[offset + 2] = rgb.2
            pixels[offset + 3] = 255
        } }
        let url = directory.appendingPathComponent(name)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    func testBatchUploadHistorySurvivesWithoutConfirmingAssignmentsAndDeduplicates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }
        let pink = try writeImage(into: directory, name: "微信图片 粉色.png")
        let blue = try writeImage(into: directory, name: "微信图片 蓝色.png", rgb: (45, 120, 220))
        let duplicate = directory.appendingPathComponent("粉色再次上传.png")
        try FileManager.default.copyItem(at: pink, to: duplicate)
        let invalid = directory.appendingPathComponent("损坏图片.png")
        try Data("invalid".utf8).write(to: invalid)
        let entry = OpsSeriesTypeEntry(category: "JSK", designName: "未确定配图", colors: [OpsSeriesColorSKU(name: "粉色")])
        workspace.seriesEntry.typeEntries = [entry]
        workspace.persistSeriesEntryState()
        let result = await workspace.importColorImages(from: [pink, blue, duplicate, invalid])
        XCTAssertEqual(result.assetIDs.count, 2)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(workspace.imageUploadHistory.count, 2)
        XCTAssertEqual(Set(workspace.imageUploadHistory.map(\.name)), ["粉色再次上传.png", "微信图片 蓝色.png"])
        try FileManager.default.removeItem(at: directory)
        let restored = OpsWorkspace(context: ModelContext(store))
        suppressNetwork(restored)
        let items = restored.imageLibraryItems(uploadsOnly: true, search: "")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.name)), ["粉色再次上传.png", "微信图片 蓝色.png"])
        XCTAssertTrue(items.allSatisfy { $0.fileURL.flatMap { NSImage(contentsOf: $0) } != nil })
        XCTAssertEqual(restored.imageLibraryItems(uploadsOnly: true, search: "蓝色").count, 1)
        XCTAssertNil(restored.seriesEntry.typeEntries.first?.colors.first?.imageAssetID, "取消配图不能影响已上传历史")
    }

    func testImageHistorySurvivesSeriesResetAndCatalogReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }
        let image = try writeImage(into: directory, name: "系列封面 原图.png")
        let id = try XCTUnwrap(workspace.importSingleImage(from: image))
        workspace.seriesEntry = completedSeriesInput()
        XCTAssertTrue(workspace.saveSeriesEntryToDraft().allOK)
        assertBlankSeries(workspace.seriesEntry)
        XCTAssertEqual(workspace.imageUploadHistory.first?.id, id)
        // 目录合并或清理未引用资源时，历史的完整资源快照仍独立保留。
        workspace.catalog.assets = []
        workspace.markDirty()
        XCTAssertTrue(workspace.saveDraft())
        let restored = OpsWorkspace(context: ModelContext(store))
        suppressNetwork(restored)
        XCTAssertTrue(restored.catalog.assets.isEmpty)
        let item = try XCTUnwrap(restored.imageUploadHistory.first)
        XCTAssertEqual(item.name, "系列封面 原图.png")
        XCTAssertNotNil(item.fileURL)
        XCTAssertEqual(restored.useImageLibraryItem(item), id)
        XCTAssertNotNil(restored.asset(for: id))
    }

    func testImageHistoryCanBeUsedInNewDraftWithoutCopyingEveryImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        let originalStaging = workspace.stagingDirectory
        defer { try? FileManager.default.removeItem(at: originalStaging) }
        let pink = try writeImage(into: directory, name: "以前上传的粉色.png")
        let blue = try writeImage(into: directory, name: "以前上传的蓝色.png", rgb: (45, 120, 220))
        let imported = await workspace.importColorImages(from: [pink, blue])
        XCTAssertEqual(imported.assetIDs.count, 2)
        let pinkItem = try XCTUnwrap(workspace.imageUploadHistory.first { $0.name.contains("粉色") })
        let originalBytes = try Data(contentsOf: XCTUnwrap(pinkItem.fileURL))
        _ = workspace.createDraft(title: "下一个系列的草稿")
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }
        XCTAssertEqual(workspace.imageUploadHistory.count, 2)
        XCTAssertTrue(workspace.catalog.assets.isEmpty, "仅查看素材库不能把其它草稿资源都写进当前目录")
        let entry = OpsSeriesTypeEntry(category: "JSK", designName: "新款", colors: [OpsSeriesColorSKU(name: "粉色")])
        workspace.seriesEntry.typeEntries = [entry]
        let id = try XCTUnwrap(workspace.useImageLibraryItem(pinkItem))
        let currentURL = try XCTUnwrap(workspace.stagedFileURL(forReference: workspace.asset(for: id)?.originalURL))
        XCTAssertNotEqual(currentURL, pinkItem.fileURL)
        XCTAssertEqual(try Data(contentsOf: currentURL), originalBytes, "历史素材复用不能再次编码损失画质")
        XCTAssertEqual(workspace.catalog.assets.count, 1)
        XCTAssertTrue(workspace.applyColorImages(entryID: entry.id, colorIDs: [entry.colors[0].id],
            assignments: [entry.colors[0].id: id]))
        let restored = OpsWorkspace(context: ModelContext(store))
        suppressNetwork(restored)
        XCTAssertEqual(restored.imageUploadHistory.count, 2, "同一张历史素材跨草稿复用仍去重")
        XCTAssertEqual(restored.seriesEntry.typeEntries.first?.colors.first?.imageAssetID, id)
    }

    func testLegacyLocalImagesAppearWhenHistoryMetadataIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }
        let id = try XCTUnwrap(workspace.importSingleImage(from: writeImage(into: directory, name: "旧版本上传.png")))
        workspace.draft?.uploadedImageHistoryJSON = nil
        try store.mainContext.save()
        let restored = OpsWorkspace(context: ModelContext(store))
        let item = try XCTUnwrap(restored.imageLibraryItems(uploadsOnly: true, search: "").first)
        XCTAssertEqual(item.id, id)
        XCTAssertNotNil(item.fileURL)
    }

    func testHistoryDiskFailurePreservesPreviouslySavedHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try container()
        var fails = false
        let workspace = OpsWorkspace(context: store.mainContext, saveCatalogContext: {
            if fails { throw NSError(domain: "test.imageHistory.disk", code: 1) }
            try $0.save()
        })
        suppressNetwork(workspace)
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }
        _ = try XCTUnwrap(workspace.importSingleImage(from: writeImage(into: directory, name: "已保存历史.png")))
        let previousJSON = workspace.draft?.uploadedImageHistoryJSON
        fails = true
        let next = try writeImage(into: directory, name: "保存失败的图片.png", rgb: (45, 120, 220))
        let result = await workspace.importColorImages(from: [next])
        XCTAssertFalse(result.failures.isEmpty)
        XCTAssertEqual(workspace.draft?.uploadedImageHistoryJSON, previousJSON)
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(restored.imageUploadHistory.count, 1)
        XCTAssertEqual(restored.imageUploadHistory.first?.name, "已保存历史.png")
    }

    func testSQLiteReopenPreservesUploadedImagesAndOriginalChineseNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("images.store"), cloudKitDatabase: .none)
        var staging: URL?
        defer { if let staging { try? FileManager.default.removeItem(at: staging) } }
        let source = try writeImage(into: directory, name: "微信图片_深色 中文.png")
        var id = ""
        do {
            let store = try ModelContainer(for: schema, configurations: [config])
            let workspace = OpsWorkspace(context: store.mainContext)
            suppressNetwork(workspace)
            staging = workspace.stagingDirectory
            id = try XCTUnwrap(workspace.importSingleImage(from: source))
        }
        try FileManager.default.removeItem(at: source)
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let restored = OpsWorkspace(context: reopened.mainContext)
        suppressNetwork(restored)
        let item = try XCTUnwrap(restored.imageUploadHistory.first)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.name, "微信图片_深色 中文.png")
        XCTAssertNotNil(item.fileURL.flatMap { NSImage(contentsOf: $0) })
    }

    func testLongSeriesCommitErrorsKeepBannerWithinWindow() throws {
        _ = NSApplication.shared
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = OpsSeriesEntryDraft(createsNewShop: true, newShopName: "店家",
            newSeriesName: "系列", typeEntries: [OpsSeriesTypeEntry(category: "JSK", designName: "问题款式",
                stockPriceText: "100", colors: (1...80).map {
                    OpsSeriesColorSKU(name: "配色\($0)", imageAssetID: "missing-image-\($0)")
                })])
        let report = workspace.commitSeriesEntry()
        XCTAssertFalse(report.allOK)
        XCTAssertTrue(report.draftSaved)
        let error = try XCTUnwrap(workspace.lastError)
        XCTAssertTrue(error.contains("配色80"), "完整错误不能被截断或丢弃")
        let hosting = NSHostingView(rootView: OpsStatusBanner(workspace: workspace).frame(width: 850))
        XCTAssertLessThan(hosting.fittingSize.height, 140, "提示条不能撑出窗口，导致整个主界面白屏")
        XCTAssertEqual(workspace.seriesEntry.typeEntries.first?.colors.count, 80, "失败后保留输入")
    }

    func testProductTablesSupplementPersistsWithoutChangingOtherProducts() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        let shop = try XCTUnwrap(workspace.addShopReturningID(name: "店家"))
        let series = try XCTUnwrap(workspace.addSeriesReturningID(shopID: shop, name: "系列", year: nil, month: nil, season: nil))
        let product = try XCTUnwrap(workspace.addProductReturningID(shopID: shop, seriesID: series, name: "款式", category: "JSK"))
        let other = try XCTUnwrap(workspace.addProductReturningID(shopID: shop, seriesID: series, name: "另一款式", category: "OP"))
        let images = ["thmedia:" + String(repeating: "a", count: 64), "thmedia:" + String(repeating: "b", count: 64)]
        XCTAssertTrue(workspace.updateSeriesPriceChart(seriesID: series, unit: "元", columns: [], rows: [], sourceImages: images))
        XCTAssertTrue(workspace.setSizeChart(productID: product, unit: "cm", columns: ["胸围"],
            rows: [.init(label: "S", values: ["88"])], sourceImage: images[0]))
        XCTAssertTrue(workspace.setSizeChart(productID: product, unit: "cm", columns: ["胸围"],
            rows: [.init(label: "S", values: ["90"])], sourceImage: images[0]), "补录结构化数据应保留已发布原图")
        XCTAssertTrue(workspace.applyPriceCorrection(productID: product, reservationPrice: 570, stockPrice: nil,
            deposit: 100, balance: 470, currency: .cny))
        XCTAssertTrue(workspace.saveCatalogEditorChanges())
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(restored.catalog.series.first { $0.id == series }?.priceChart?.sourceImages, images)
        XCTAssertEqual(restored.sizeChart(forProduct: product)?.rows.first?.values, ["90"])
        XCTAssertEqual(restored.sizeChart(forProduct: product)?.sourceImage, images[0])
        XCTAssertEqual(restored.priceArchive(forProduct: product)?.currentBalance, 470)
        XCTAssertNil(restored.sizeChart(forProduct: other))
        XCTAssertNil(restored.catalog.products.first { $0.id == other }?.priceCorrection)
        XCTAssertNotNil(restored.draft?.catalogSyncRequestID)
    }

    func testSeriesPublishCommitFailureRetainsJobAndInputWithoutNetworking() async throws {
        _ = NSApplication.shared
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        workspace.seriesEntry = OpsSeriesEntryDraft(createsNewShop: true, newShopName: "发布店家",
            newSeriesName: "发布系列", typeEntries: [OpsSeriesTypeEntry(category: "JSK", designName: "问题款式",
                stockPriceText: "100", colors: (1...80).map {
                    OpsSeriesColorSKU(name: "配色\($0)", imageAssetID: "missing-image-\($0)")
                })])
        // 商品写入失败会在网络发布前返回；因此此夹具不读取任何云端凭证。
        let result = await workspace.publishSeries(cloud: .shared)
        guard case .failed(let reason, let items) = result else { return XCTFail("不能报告已发布") }
        XCTAssertTrue(reason.contains("配色80"))
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(workspace.seriesPublishJobs().count, 1)
        XCTAssertEqual(workspace.seriesEntry.typeEntries.first?.colors.count, 80)
        let hosting = NSHostingView(rootView: OpsStatusBanner(workspace: workspace).frame(width: 850))
        XCTAssertLessThan(hosting.fittingSize.height, 140)
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(restored.seriesPublishJobs().count, 1)
        XCTAssertEqual(restored.seriesEntry.typeEntries.first?.colors.count, 80)
    }

    func testUndeclaredDatesReallySaveAndReload() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        let shopID = try XCTUnwrap(workspace.addShopReturningID(name: "店家"))
        let id = try XCTUnwrap(workspace.addSeriesReturningID(shopID: shopID, name: "系列", year: 2026, month: 9, season: nil))
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(workspace.updateSeriesSalePhase(id: id, phase: nil,
            reservationStartAt: nil, reservationEndAt: nil, balanceDueKind: .exact,
            balanceDueText: nil, balanceDueAt: start, balanceDueEndAt: end))
        XCTAssertTrue(workspace.saveCatalogEditorChanges())
        XCTAssertFalse(workspace.hasUnsavedChanges)
        let restored = OpsWorkspace(context: ModelContext(store))
        let series = try XCTUnwrap(restored.catalog.series.first { $0.id == id })
        XCTAssertNil(series.salePhase)
        XCTAssertEqual(series.balanceDueAt, start)
        XCTAssertEqual(series.balanceDueEndAt, end)
        XCTAssertEqual(restored.draft?.catalogSyncRevision, workspace.currentRevision)
        XCTAssertNotNil(restored.draft?.catalogSyncRequestID)
    }

    func testDiskFailureDoesNotClaimSavedOrQueuePublish() throws {
        let store = try container()
        var fails = false
        let workspace = OpsWorkspace(context: store.mainContext, saveCatalogContext: {
            if fails { throw NSError(domain: "test.disk", code: 1) }
            try $0.save()
        })
        suppressNetwork(workspace)
        let id = try XCTUnwrap(workspace.addShopReturningID(name: "原店家"))
        XCTAssertTrue(workspace.saveDraft())
        let previousJSON = workspace.draft?.catalogJSON
        let previousRevision = workspace.savedRevision
        fails = true
        XCTAssertTrue(workspace.updateShop(id: id, name: "新店家", aliases: []))
        XCTAssertFalse(workspace.saveCatalogEditorChanges())
        XCTAssertEqual(workspace.savedRevision, previousRevision)
        XCTAssertEqual(workspace.draft?.catalogJSON, previousJSON)
        XCTAssertTrue(workspace.hasUnsavedChanges)
        XCTAssertNil(workspace.draft?.catalogSyncRequestID)
        XCTAssertEqual(workspace.catalog.shops.first { $0.id == id }?.name, "新店家")
        fails = false
        XCTAssertTrue(workspace.saveCatalogEditorChanges())
        XCTAssertEqual(workspace.savedRevision, workspace.currentRevision)
    }

    func testShopLogoSaveReplaceClearAndInvalidReference() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        let first = "thmedia:" + String(repeating: "a", count: 64)
        let next = "thmedia:" + String(repeating: "b", count: 64)
        let id = try XCTUnwrap(workspace.addShopReturningID(name: "店家", logo: first))
        XCTAssertTrue(workspace.saveCatalogEditorChanges())
        XCTAssertTrue(workspace.updateShopLogo(id: id, reference: next))
        XCTAssertTrue(workspace.saveCatalogEditorChanges())
        let restored = OpsWorkspace(context: ModelContext(store))
        suppressNetwork(restored)
        XCTAssertEqual(restored.catalog.shops.first { $0.id == id }?.logo, next)
        XCTAssertFalse(restored.updateShopLogo(id: id, reference: "missing-asset"))
        XCTAssertEqual(restored.catalog.shops.first { $0.id == id }?.logo, next)
        XCTAssertTrue(restored.updateShopLogo(id: id, reference: nil))
        XCTAssertTrue(restored.saveCatalogEditorChanges())
        let cleared = OpsWorkspace(context: ModelContext(store))
        XCTAssertNil(cleared.catalog.shops.first { $0.id == id }?.logo)
    }

    func testNewShopWizardLogoSurvivesRestoreAndCommits() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        let logo = "thmedia:" + String(repeating: "c", count: 64)
        workspace.seriesEntry = OpsSeriesEntryDraft(createsNewShop: true,
            newShopName: "新店家", managesShopLogo: true, shopLogoReference: logo,
            newSeriesName: "新系列", typeEntries: [OpsSeriesTypeEntry(
                category: "JSK", designName: "新款", stockPriceText: "100",
                colors: [OpsSeriesColorSKU(name: "白色")])])
        workspace.persistSeriesEntryState()
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertTrue(restored.seriesEntry.createsNewShop)
        XCTAssertEqual(restored.seriesEntry.shopLogoReference, logo)
        let report = restored.commitSeriesEntry()
        XCTAssertTrue(report.blockedByValidation.isEmpty, "\(report.blockedByValidation)")
        let shopID = try XCTUnwrap(report.shopID)
        XCTAssertEqual(restored.catalog.shops.first { $0.id == shopID }?.logo, logo)
        let saved = OpsWorkspace(context: ModelContext(store))
        XCTAssertEqual(saved.catalog.shops.first { $0.id == shopID }?.logo, logo)
    }

    func testOldWizardJSONDefaultsToPreservingExistingLogo() throws {
        let draft = try JSONDecoder().decode(OpsSeriesEntryDraft.self, from: Data("{}".utf8))
        XCTAssertFalse(draft.managesShopLogo)
        XCTAssertNil(draft.shopLogoReference)
    }

    func testUploadedLogoBytesSurviveSourceRemovalAndExport() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }
        let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16,
            pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 64, bitsPerPixel: 32))
        for x in 0..<16 { for y in 0..<16 { image.setColor(NSColor(calibratedRed: 0.8, green: 0.3, blue: 0.5, alpha: 1), atX: x, y: y) } }
        let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("logo-\(UUID().uuidString).png")
        try png.write(to: source)
        let assetID = try XCTUnwrap(workspace.importSingleImage(from: source))
        try FileManager.default.removeItem(at: source)
        let id = try XCTUnwrap(workspace.addShopReturningID(name: "上传店家", logo: assetID))
        XCTAssertTrue(workspace.saveCatalogEditorChanges())
        let restored = OpsWorkspace(context: ModelContext(store))
        let asset = try XCTUnwrap(restored.asset(for: assetID))
        XCTAssertEqual(restored.catalog.shops.first { $0.id == id }?.logo, asset.originalURL)
        let staged = try XCTUnwrap(restored.stagedFileURL(forReference: asset.originalURL))
        XCTAssertGreaterThan(try Data(contentsOf: staged).count, 0)
        let references = ShopCatalogMediaReferences.publisherRewritten(in: restored.catalog)
        XCTAssertTrue(references.contains { $0.field == "shops.logo" && $0.reference == asset.originalURL })
        let archive = try ShopCatalogExportArchive.completeHandoffEntries(
            for: restored.catalog, imageDirectory: restored.stagingDirectory)
        XCTAssertTrue(archive.contains { $0.name == "images/" + staged.lastPathComponent })
    }

    func testConfirmedPublishAcknowledgesOnlyCoveredSaveAndSameEnvironment() throws {
        let store = try container()
        let workspace = OpsWorkspace(context: store.mainContext)
        suppressNetwork(workspace)
        let id = try XCTUnwrap(workspace.addShopReturningID(name: "原店家"))
        XCTAssertTrue(workspace.saveCatalogEditorChanges())
        let frozenRevision = workspace.currentRevision
        let frozenCatalog = workspace.catalog
        let environment = try XCTUnwrap(workspace.draft?.catalogSyncEnvironment)
        XCTAssertTrue(workspace.updateShop(id: id, name: "再修改店家", aliases: []))
        XCTAssertTrue(workspace.saveCatalogEditorChanges())
        let pending = workspace.draft?.catalogSyncRequestID
        XCTAssertTrue(workspace.recordConfirmedPublish(releaseSeq: 10, rootIndexHash: nil,
            environment: environment, revision: frozenRevision, publishedCatalog: frozenCatalog))
        XCTAssertEqual(workspace.draft?.catalogSyncRequestID, pending)
        XCTAssertTrue(workspace.recordConfirmedPublish(releaseSeq: 11, rootIndexHash: nil,
            environment: environment == "production" ? "development" : "production", revision: workspace.currentRevision, publishedCatalog: workspace.catalog))
        XCTAssertEqual(workspace.draft?.catalogSyncRequestID, pending)
        XCTAssertTrue(workspace.recordConfirmedPublish(releaseSeq: 12, rootIndexHash: nil,
            environment: environment, revision: workspace.currentRevision, publishedCatalog: workspace.catalog))
        XCTAssertNil(workspace.draft?.catalogSyncRequestID)
        XCTAssertNil(workspace.draft?.catalogSyncError)
        let restored = OpsWorkspace(context: ModelContext(store))
        XCTAssertNil(restored.draft?.catalogSyncRequestID)
        XCTAssertEqual(restored.draft?.lastPublishedReleaseSeq, 12)
    }

    func testSQLiteReopenPreservesSavedLogoAndPendingIntent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        let configuration = ModelConfiguration(schema: schema,
            url: directory.appendingPathComponent("draft.store"), cloudKitDatabase: .none)
        var shopID = ""
        let logo = "thmedia:" + String(repeating: "d", count: 64)
        do {
            let store = try ModelContainer(for: schema, configurations: [configuration])
            let workspace = OpsWorkspace(context: store.mainContext)
            suppressNetwork(workspace)
            shopID = try XCTUnwrap(workspace.addShopReturningID(name: "磁盘店家", logo: logo))
            XCTAssertTrue(workspace.saveCatalogEditorChanges())
            // 模拟上次进程在网络请求后退出；新进程不能盲目重发。
            workspace.draft?.catalogSyncAttemptedID = workspace.draft?.catalogSyncRequestID
            try store.mainContext.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let restored = OpsWorkspace(context: reopened.mainContext)
        suppressNetwork(restored)
        XCTAssertEqual(restored.catalog.shops.first { $0.id == shopID }?.logo, logo)
        XCTAssertNotNil(restored.draft?.catalogSyncRequestID)
        XCTAssertEqual(restored.draft?.catalogSyncRequestID, restored.draft?.catalogSyncAttemptedID)
        restored.resumeCatalogEditorSync()
        XCTAssertTrue(restored.catalogEditSyncMessage?.contains("上次同步未确认完成") == true)
    }

    func testReceiptDiskFailureRetainsPendingIntentAndPreviousBaseline() throws {
        let store = try container()
        var fails = false
        let workspace = OpsWorkspace(context: store.mainContext, saveCatalogContext: {
            if fails { throw NSError(domain: "test.receipt", code: 1) }
            try $0.save()
        })
        suppressNetwork(workspace)
        _ = try XCTUnwrap(workspace.addShopReturningID(name: "店家"))
        XCTAssertTrue(workspace.saveCatalogEditorChanges())
        let id = workspace.draft?.catalogSyncRequestID
        let environment = try XCTUnwrap(workspace.draft?.catalogSyncEnvironment)
        fails = true
        XCTAssertFalse(workspace.recordConfirmedPublish(releaseSeq: 10, rootIndexHash: nil,
            environment: environment, revision: workspace.currentRevision, publishedCatalog: workspace.catalog))
        XCTAssertEqual(workspace.draft?.catalogSyncRequestID, id)
        XCTAssertNil(workspace.draft?.lastPublishedRevision)
        XCTAssertNil(workspace.baselineCatalog)
        fails = false
        XCTAssertTrue(workspace.recordConfirmedPublish(releaseSeq: 10, rootIndexHash: nil,
            environment: environment, revision: workspace.currentRevision, publishedCatalog: workspace.catalog))
        XCTAssertNil(workspace.draft?.catalogSyncRequestID)
    }
}
