//
//  ShopCatalogCloudSyncTests.swift
//  ItemManagerTests
//
//  「店家上新」云同步（消费端）验收：
//    · 校验器三层正反用例（协议版本 / 根清单自洽 / 摘要 / gzip / 结构）
//    · 包缓存安装回读与控制状态（测试隔离红线：双 Storage 重定向）
//    · Store 三层合并（base → remote → overlay / saleEvents 按 id 去重 / 墓碑并集）
//    · 同步服务编排（stub Reader：updated / nothingPublished / 失败保留本地）
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogCloudSyncTests: XCTestCase {

    // MARK: 夹具

    private var releasedAt: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 10))!
    }

    override func setUp() {
        super.setUp()
        // 红线：单测宿主 = 主 App。包缓存（SyncStorage）与控制状态（Storage）
        // 两处都要重定向，缺一个就会污染生产数据。
        ShopCatalogStorage.useTemporaryForTesting()
        ShopCatalogSyncStorage.useTemporaryForTesting()
    }

    override func tearDown() {
        ShopCatalogSyncStorage.restoreDefaultForTesting()
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    // MARK: - 数据包构造（gzip 仿形 + 三层校验所需的全套声明）

    /// 与 Mac 端 `gzip.compress` 同构的压缩包：gzip 头 + raw deflate + 8 字节尾。
    /// 校验器不校验 CRC32/ISIZE（剥离后直接 inflate），测试尾 8 字节用零占位即可。
    private func gzipPack(payload: ShopCatalogPackPayload) throws -> Data {
        let raw = try ShopCatalogJSONCoding.encoder().encode(payload)
        let deflated = try (raw as NSData).compressed(using: .zlib) as Data
        var gz = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xFF])
        gz.append(deflated)
        gz.append(Data(repeating: 0, count: 8))
        return gz
    }

    private func payload(catalog: ShopCatalog) -> ShopCatalogPackPayload {
        ShopCatalogPackPayload(
            schemaVersion: ShopCatalogSyncProtocol.schemaVersion,
            partitionID: ShopCatalogSyncProtocol.shopCatalogPartitionID,
            brandID: ShopCatalogSyncProtocol.shopCatalogBrandID,
            entityType: ShopCatalogSyncProtocol.shopCatalogEntityType,
            partitionRevision: 3,
            coverageStatus: "complete",
            checkedThrough: nil,
            shopCatalog: catalog)
    }

    private func partition(for pack: Data, revision: Int = 3) -> ShopCatalogRootIndex.Partition {
        let hash = ShopCatalogSyncProtocol.sha256Hex(pack)
        return .init(
            partitionID: ShopCatalogSyncProtocol.shopCatalogPartitionID,
            brandID: ShopCatalogSyncProtocol.shopCatalogBrandID,
            entityType: ShopCatalogSyncProtocol.shopCatalogEntityType,
            partitionRevision: revision,
            coverageStatus: "complete",
            checkedThrough: nil,
            packRecordName: ShopCatalogSyncProtocol.packRecordName(payloadHash: hash),
            payloadHash: hash,
            recordCount: 5,
            dependencyPackRecordNames: nil)
    }

    private func rootIndexData(seq: Int, partition: ShopCatalogRootIndex.Partition) throws -> Data {
        let index = ShopCatalogRootIndex(
            schemaVersion: ShopCatalogSyncProtocol.schemaVersion,
            releaseSeq: seq,
            publishedAt: nil,
            revocationEpoch: 0,
            partitions: [partition],
            withdrawals: nil)
        return try ShopCatalogJSONCoding.encoder().encode(index)
    }

    private func header(seq: Int, rootHash: String) -> ShopCatalogReleaseHeader {
        .init(
            releaseSeq: seq,
            schemaVersion: ShopCatalogSyncProtocol.schemaVersion,
            revocationEpoch: 0,
            minimumReaderVersion: ShopCatalogSyncProtocol.readerVersion,
            previousReleaseSeq: seq - 1,
            publishedAt: nil,
            rootIndexHash: rootHash)
    }

    /// 合法全套夹具：返回（发布头 / 根清单 / 压缩包 / 载荷目录）
    private func validRelease(seq: Int, catalog: ShopCatalog) throws
        -> (header: ShopCatalogReleaseHeader, rootData: Data, pack: Data, catalog: ShopCatalog) {
        let pack = try gzipPack(payload: payload(catalog: catalog))
        let rootData = try rootIndexData(seq: seq, partition: partition(for: pack))
        let header = self.header(seq: seq, rootHash: ShopCatalogSyncProtocol.sha256Hex(rootData))
        return (header, rootData, pack, catalog)
    }

    /// 云端远端层：合成种子 + 同 id 改名 + 新增完整子图（店家/系列/商品/规格/事件）
    private func makeRemoteCatalog() throws -> ShopCatalog {
        var remote = ShopCatalogSeedFixture.makeCatalog()
        remote.shops[0].name = "Alice Girl（云端改名）"

        let remoteJSON = #"""
        {"version":1,"shops":[
            {"id":"shop-remote-new","name":"云端新店家","aliases":["RNP"]}],
         "series":[
            {"id":"series-remote-new","shopID":"shop-remote-new","name":"云端新系列","year":2026}],
         "products":[
            {"id":"prod-remote-new","shopID":"shop-remote-new","seriesID":"series-remote-new",
             "name":"云端新品 JSK","category":"JSK","images":[]}],
         "variants":[
            {"id":"var-remote-new-s","productID":"prod-remote-new","color":"云端色","size":"S"}],
         "saleEvents":[
            {"id":"ev-remote-new","productID":"prod-remote-new","type":"reservation","price":328}],
         "sizeCharts":[],"assets":[]}
        """#
        let extra = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: Data(remoteJSON.utf8))
        remote.shops.append(contentsOf: extra.shops)
        remote.series.append(contentsOf: extra.series)
        remote.products.append(contentsOf: extra.products)
        remote.variants.append(contentsOf: extra.variants)
        remote.saleEvents.append(contentsOf: extra.saleEvents)
        return remote
    }

    // MARK: - 校验器 · 正例

    func testValidatorAcceptsValidPack() throws {
        let release = try validRelease(seq: 7, catalog: ShopCatalogSeedFixture.makeCatalog())
        let installed = try ShopCatalogCloudSyncValidator.validatedShopCatalog(
            header: release.header, rootIndexData: release.rootData, packCompressed: release.pack)
        XCTAssertEqual(installed.shops.count, 2)
        XCTAssertEqual(installed.products.count, ShopCatalogSeedFixture.makeCatalog().products.count)
    }

    // MARK: - 校验器 · 反例

    func testValidatorRejectsUnsupportedSchemaVersion() throws {
        let release = try validRelease(seq: 7, catalog: ShopCatalogSeedFixture.makeCatalog())
        var badHeader = release.header
        badHeader.schemaVersion = 99
        XCTAssertThrowsError(try ShopCatalogCloudSyncValidator.validatedShopCatalog(
            header: badHeader, rootIndexData: release.rootData, packCompressed: release.pack)) {
            error in
            if case .unsupportedSchema = error as? ShopCatalogSyncValidationError {} else {
                XCTFail("应为 unsupportedSchema，实际 \(error)")
            }
        }
    }

    func testValidatorRejectsReleaseSeqMismatch() throws {
        let release = try validRelease(seq: 7, catalog: ShopCatalogSeedFixture.makeCatalog())
        let staleHeader = header(seq: 6, rootHash: release.header.rootIndexHash)
        XCTAssertThrowsError(try ShopCatalogCloudSyncValidator.validatedShopCatalog(
            header: staleHeader, rootIndexData: release.rootData, packCompressed: release.pack)) {
            error in
            if case .rootIndexMismatch = error as? ShopCatalogSyncValidationError {} else {
                XCTFail("应为 rootIndexMismatch，实际 \(error)")
            }
        }
    }

    func testValidatorRejectsTamperedPackBytes() throws {
        let release = try validRelease(seq: 7, catalog: ShopCatalogSeedFixture.makeCatalog())
        var tampered = release.pack
        tampered.append(0x00)  // 压缩字节被改动 → SHA-256 与 payloadHash 不一致
        XCTAssertThrowsError(try ShopCatalogCloudSyncValidator.validatedShopCatalog(
            header: release.header, rootIndexData: release.rootData, packCompressed: tampered)) {
            error in
            if case .packMismatch = error as? ShopCatalogSyncValidationError {} else {
                XCTFail("应为 packMismatch，实际 \(error)")
            }
        }
    }

    func testValidatorRejectsNonGzipPack() throws {
        // 用明文 JSON 冒充压缩包：让声明与明文哈希一致，
        // 专门验证 gzip 解析层的拒绝能力（魔数不符 → packMismatch）
        let plain = try ShopCatalogJSONCoding.encoder().encode(payload(catalog: ShopCatalogSeedFixture.makeCatalog()))
        let fakePartition = partition(for: plain)
        let rootData = try rootIndexData(seq: 7, partition: fakePartition)
        let header = self.header(seq: 7, rootHash: ShopCatalogSyncProtocol.sha256Hex(rootData))
        XCTAssertThrowsError(try ShopCatalogCloudSyncValidator.validatedShopCatalog(
            header: header, rootIndexData: rootData, packCompressed: plain)) {
            error in
            if case .packMismatch = error as? ShopCatalogSyncValidationError {} else {
                XCTFail("应为 packMismatch（非 gzip），实际 \(error)")
            }
        }
    }

    func testValidatorRejectsDuplicateIDs() throws {
        let json = #"""
        {"version":1,"shops":[
            {"id":"shop-dup","name":"店家A"},
            {"id":"shop-dup","name":"店家B"}],
         "series":[],"products":[],"variants":[],"sizeCharts":[],"saleEvents":[],"assets":[]}
        """#
        let catalog = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: Data(json.utf8))
        let release = try validRelease(seq: 7, catalog: catalog)
        XCTAssertThrowsError(try ShopCatalogCloudSyncValidator.validatedShopCatalog(
            header: release.header, rootIndexData: release.rootData, packCompressed: release.pack)) {
            error in
            if case .structural(let issues) = error as? ShopCatalogSyncValidationError {
                XCTAssertTrue(issues.contains { $0.contains("shop-dup") }, "问题应点名重复 ID：\(issues)")
            } else {
                XCTFail("应为 structural，实际 \(error)")
            }
        }
    }

    func testValidatorRejectsTombstoneConflict() throws {
        var catalog = ShopCatalogSeedFixture.makeCatalog()
        // 店家还活着却同时声明已删除 = 数据自相矛盾
        catalog.removedShopIDs = ["shop-alice-girl"]
        let release = try validRelease(seq: 7, catalog: catalog)
        XCTAssertThrowsError(try ShopCatalogCloudSyncValidator.validatedShopCatalog(
            header: release.header, rootIndexData: release.rootData, packCompressed: release.pack)) {
            error in
            if case .structural(let issues) = error as? ShopCatalogSyncValidationError {
                XCTAssertTrue(issues.contains { $0.contains("已删除店家") }, "\(issues)")
            } else {
                XCTFail("应为 structural，实际 \(error)")
            }
        }
    }

    func testValidatorRejectsEmptyCoverageWithEntities() throws {
        // 声明 empty 却带完整条目 = 覆盖状态与内容自相矛盾
        var packPayload = payload(catalog: ShopCatalogSeedFixture.makeCatalog())
        packPayload.coverageStatus = "empty"
        let pack = try gzipPack(payload: packPayload)
        var part = partition(for: pack)
        part.coverageStatus = "empty"
        let rootData = try rootIndexData(seq: 7, partition: part)
        let header = self.header(seq: 7, rootHash: ShopCatalogSyncProtocol.sha256Hex(rootData))
        XCTAssertThrowsError(try ShopCatalogCloudSyncValidator.validatedShopCatalog(
            header: header, rootIndexData: rootData, packCompressed: pack)) {
            error in
            if case .structural(let issues) = error as? ShopCatalogSyncValidationError {
                XCTAssertTrue(issues.contains { $0.contains("empty") }, "\(issues)")
            } else {
                XCTFail("应为 structural，实际 \(error)")
            }
        }
    }

    // MARK: - 包缓存（安装回读 / 控制状态 / 清理）

    func testPackCacheInstallReadbackAndControl() throws {
        let pack = Data("pack-bytes-\(releasedAt.timeIntervalSince1970)".utf8)
        let hash = ShopCatalogSyncProtocol.sha256Hex(pack)

        XCTAssertNil(ShopCatalogPackCache.cachedPackData(payloadHash: hash))
        try ShopCatalogPackCache.installPack(pack, payloadHash: hash)
        XCTAssertEqual(ShopCatalogPackCache.cachedPackData(payloadHash: hash), pack)
        XCTAssertGreaterThan(ShopCatalogPackCache.usageBytes(), 0)

        var control = ShopCatalogSyncControl(
            installedReleaseSeq: 7, installedPayloadHash: hash, lastCheckedAt: releasedAt)
        ShopCatalogPackCache.saveControl(control)
        XCTAssertEqual(ShopCatalogPackCache.loadControl(), control)

        // 下载判定：同序号同摘要 → 不下；序号或摘要任一变化 → 下
        XCTAssertFalse(ShopCatalogPackCache.needsDownload(releaseSeq: 7, payloadHash: hash, control: control))
        XCTAssertTrue(ShopCatalogPackCache.needsDownload(releaseSeq: 8, payloadHash: hash, control: control))
        XCTAssertTrue(ShopCatalogPackCache.needsDownload(releaseSeq: 7, payloadHash: String(hash.reversed()), control: control))

        // 清理：包删除 + installedPayloadHash 置空，但 installedReleaseSeq 保留
        let freed = ShopCatalogPackCache.clearDownloadedContent()
        XCTAssertGreaterThan(freed, 0)
        XCTAssertNil(ShopCatalogPackCache.cachedPackData(payloadHash: hash))
        XCTAssertEqual(ShopCatalogPackCache.loadControl().installedReleaseSeq, 7)
        XCTAssertNil(ShopCatalogPackCache.loadControl().installedPayloadHash)
    }

    func testSyncControlDecodeToleratesMissingKeys() throws {
        // 旧版本控制文件缺键 → 按零值兜底，不解码失败（否则每次冷启动都全量重下）
        let legacy = Data(#"{"installedReleaseSeq": 5}"#.utf8)
        try legacy.write(to: ShopCatalogPackCache.controlURL, options: .atomic)
        let control = ShopCatalogPackCache.loadControl()
        XCTAssertEqual(control.installedReleaseSeq, 5)
        XCTAssertNil(control.installedPayloadHash)
        XCTAssertEqual(control.revocationEpoch, 0)
    }

    // MARK: - Store 三层合并（base → remote → overlay）

    func testInstallRemoteCatalogMergesOverBase() throws {
        let store = ShopCatalogSeedFixture.makeStore()
        let baseProductCount = store.catalog?.products.count ?? -1
        let remote = try makeRemoteCatalog()

        store.installRemoteCatalog(remote)

        // 同 id 替换：云端改名生效
        XCTAssertEqual(store.shop(id: "shop-alice-girl")?.name, "Alice Girl（云端改名）")
        // 新增子图整体可见
        XCTAssertEqual(store.shop(id: "shop-remote-new")?.name, "云端新店家")
        XCTAssertEqual(store.product(id: "prod-remote-new")?.name, "云端新品 JSK")
        XCTAssertEqual(store.colors(forProduct: "prod-remote-new"), ["云端色"])
        // 基底实体一个不少
        XCTAssertEqual(store.catalog?.shops.count, 3)
        XCTAssertEqual(store.catalog?.products.count, baseProductCount + 1)
    }

    func testRemoteSaleEventsDedupByIDKeepFirstArrival() throws {
        let store = ShopCatalogSeedFixture.makeStore()
        let baseEventCount = store.catalog?.saleEvents.count ?? -1
        let anchor = try XCTUnwrap(store.saleEvent(id: "ev-ag-jsk-resv-2026"), "夹具锚点事件应存在")

        var remote = try makeRemoteCatalog()
        // 同 id 不同价格的事件：append-only 硬约束 → 不替换、不重复，保留先到者
        remote.saleEvents.append(CatalogSaleEvent(
            id: "ev-ag-jsk-resv-2026", productID: "prod-ag-xueguo-jsk", type: .reservation, price: 999))

        store.installRemoteCatalog(remote)

        let kept = try XCTUnwrap(store.saleEvent(id: "ev-ag-jsk-resv-2026"))
        XCTAssertEqual(kept.price, anchor.price, "同 id 事件保留先到内容，不得被云端覆盖")
        XCTAssertEqual(store.catalog?.saleEvents.count, baseEventCount + 1, "只应多出真正的新事件")
    }

    func testRemoteTombstoneRemovesBaseProductWithVariants() throws {
        let store = ShopCatalogSeedFixture.makeStore()
        var remote = try makeRemoteCatalog()
        remote.removedProductIDs = ["prod-ag-xueguo-jsk"]

        store.installRemoteCatalog(remote)

        XCTAssertNil(store.product(id: "prod-ag-xueguo-jsk"), "墓碑商品应从生效目录排除")
        XCTAssertTrue(store.variants(forProduct: "prod-ag-xueguo-jsk").isEmpty, "规格按商品连坐排除")
        XCTAssertNotNil(store.saleEvent(id: "ev-ag-jsk-resv-2026"), "销售历史永不排除（append-only）")
        XCTAssertNotNil(store.product(id: "prod-ag-xueguo-kc"), "其余商品不受影响")
    }

    func testOverlayWinsOverRemoteAndInstallNilClearsRemote() throws {
        let store = ShopCatalogSeedFixture.makeStore()
        store.installRemoteCatalog(try makeRemoteCatalog())
        XCTAssertEqual(store.shop(id: "shop-alice-girl")?.name, "Alice Girl（云端改名）")

        // 覆盖层是运营「未发布」的最新编辑，必须赢过已发布快照
        let overlayJSON = #"""
        {"version":1,"shops":[{"id":"shop-alice-girl","name":"Alice Girl（本机未发布）"}],
         "series":[],"products":[],"variants":[],"sizeCharts":[],"saleEvents":[],"assets":[]}
        """#
        try Data(overlayJSON.utf8).write(to: ShopCatalogDraftStore.overlayURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: ShopCatalogDraftStore.overlayURL) }
        store.reloadWithOverlay()
        XCTAssertEqual(store.shop(id: "shop-alice-girl")?.name, "Alice Girl（本机未发布）",
                       "覆盖层优先级必须高于远端层")

        // 公共库清空（安装 nil）→ 回退 base + overlay，远端改名痕迹消失
        store.installRemoteCatalog(nil)
        XCTAssertEqual(store.shop(id: "shop-alice-girl")?.name, "Alice Girl（本机未发布）")
        XCTAssertNil(store.shop(id: "shop-remote-new"), "远端层应整体卸载")
    }

    // MARK: - 同步服务编排（stub Reader）

    /// nonisolated：协议是非隔离 Sendable 的，嵌套类型默认会被推导成 MainActor
    private nonisolated struct StubReader: ShopCatalogPublicReading {
        var header: ShopCatalogReleaseHeader?
        var rootData: Data?
        var pack: Data?
        var error: ShopCatalogSyncError?

        func fetchReleaseHeader() async throws -> ShopCatalogReleaseHeader {
            if let error { throw error }
            if let header { return header }
            throw ShopCatalogSyncError.recordMissing(
                recordType: "THRelease", recordName: ShopCatalogSyncProtocol.releaseRecordName)
        }
        func fetchRootIndex() async throws -> Data {
            if let error { throw error }
            return try XCTUnwrap(rootData, "stub 未配置根清单")
        }
        func fetchPack(payloadHash: String) async throws -> Data {
            if let error { throw error }
            return try XCTUnwrap(pack, "stub 未配置数据包")
        }
    }

    func testSyncInstallsRemoteCatalogAndThrottlesNextCheck() async throws {
        let remote = try makeRemoteCatalog()
        let release = try validRelease(seq: 7, catalog: remote)
        let store = ShopCatalogSeedFixture.makeStore()
        let service = ShopCatalogCloudSyncService(
            reader: StubReader(header: release.header, rootData: release.rootData, pack: release.pack),
            store: store)

        await service.syncIfNeeded(force: true)

        XCTAssertEqual(service.state, .updated(releaseSeq: 7, recordCount: 5))
        XCTAssertEqual(store.shop(id: "shop-alice-girl")?.name, "Alice Girl（云端改名）",
                       "同步完成后云端内容应立即生效")
        let control = ShopCatalogPackCache.loadControl()
        XCTAssertEqual(control.installedReleaseSeq, 7)
        XCTAssertEqual(control.installedPayloadHash, ShopCatalogSyncProtocol.sha256Hex(release.pack))
        XCTAssertEqual(ShopCatalogPackCache.cachedPackData(payloadHash: control.installedPayloadHash ?? ""),
                       release.pack, "包文件应原子落盘")

        // 节流窗口内第二次检查：零下载，直接 upToDate
        await service.syncIfNeeded()
        XCTAssertEqual(service.state, .upToDate(releaseSeq: 7))
    }

    func testSyncNothingPublishedIsNormalEmptyState() async {
        let store = ShopCatalogSeedFixture.makeStore()
        let service = ShopCatalogCloudSyncService(
            reader: StubReader(error: ShopCatalogSyncError.recordMissing(
                recordType: "THRelease", recordName: ShopCatalogSyncProtocol.releaseRecordName)),
            store: store)

        await service.syncIfNeeded(force: true)

        XCTAssertEqual(service.state, .nothingPublished, "发布头缺失是正常空态，不算故障")
        XCTAssertFalse(service.state.isFailure)
    }

    func testSyncRejectsTamperedPackAndKeepsLocalData() async throws {
        let release = try validRelease(seq: 7, catalog: ShopCatalogSeedFixture.makeCatalog())
        var tampered = release.pack
        tampered.append(0x00)
        let store = ShopCatalogSeedFixture.makeStore()
        let baseName = store.shop(id: "shop-alice-girl")?.name
        let service = ShopCatalogCloudSyncService(
            reader: StubReader(header: release.header, rootData: release.rootData, pack: tampered),
            store: store)

        await service.syncIfNeeded(force: true)

        guard case .failed(let reason) = service.state else {
            return XCTFail("被篡改的包必须如实报失败，实际 \(service.state)")
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(store.shop(id: "shop-alice-girl")?.name, baseName,
                       "失败必须保留本地数据，绝不把失败当空目录")
        XCTAssertEqual(ShopCatalogPackCache.loadControl().installedReleaseSeq, 0,
                       "安装失败不得推进控制状态")
    }
}
