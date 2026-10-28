//
//  ShopCatalogOpsUploadTests.swift
//  ItemManagerTests
//
//  两份方案的实施回归：
//    · 《公共数据库字段配置实施方案》§2.2 —— `CatalogAsset.mediaKey` 的兼容解码与解析口径；
//    · 《iOS 运营上传实施方案》§3–§4 —— 暂存 / 媒体上传 / 发布头条件更新 / 失败分类。
//
//  ## 测试隔离（红线）
//
//  宿主是主 App，`FileManager.default` 就是用户真实沙盒。
//  需要真文件的用例一律先 `ShopCatalogStorage.useTemporaryForTesting()`，
//  结束 `restoreDefaultForTesting()`；任务表用 `ShopCatalogOpsUploadStore(inMemory: true)`。
//

import XCTest
import UIKit
@testable import ItemManager

// MARK: - 方案一 §2.2：mediaKey

final class ShopCatalogAssetMediaKeyTests: XCTestCase {

    private func decode(_ json: String) throws -> CatalogAsset {
        try ShopCatalogJSONCoding.decoder().decode(CatalogAsset.self, from: Data(json.utf8))
    }

    func testLegacyJSONWithoutMediaKeyStillDecodes() throws {
        let asset = try decode("""
        {"id":"a1","type":"productImage","originalURL":"local:img-1.jpg","width":1200,"height":1600}
        """)
        XCTAssertNil(asset.mediaKey, "旧包没有 mediaKey 必须照常解码（可选、非必填）")
        XCTAssertEqual(asset.originalURL, "local:img-1.jpg")
    }

    func testMediaKeyDecodesWhenPresent() throws {
        let hash = String(repeating: "a", count: 64)
        let asset = try decode("""
        {"id":"a1","type":"productImage","mediaKey":"\(hash)","originalURL":"thmedia:\(hash)"}
        """)
        XCTAssertEqual(asset.mediaKey, hash)
    }

    func testMediaKeyRoundTripsThroughEncoder() throws {
        let hash = String(repeating: "b", count: 64)
        var asset = CatalogAsset(id: "a1", type: .productImage, originalURL: "https://example.com/a.jpg")
        asset.mediaKey = hash
        let data = try ShopCatalogJSONCoding.encoder().encode(asset)
        let back = try ShopCatalogJSONCoding.decoder().decode(CatalogAsset.self, from: data)
        XCTAssertEqual(back.mediaKey, hash)
    }

    func testResolvedMediaKeyPrefersCanonicalField() {
        let canonical = String(repeating: "c", count: 64)
        let legacy = String(repeating: "d", count: 64)
        XCTAssertEqual(
            ShopCatalogSyncProtocol.resolvedMediaKey(
                canonical, fallbackReferences: ["thmedia:\(legacy)"]),
            canonical)
    }

    func testResolvedMediaKeyFallsBackToLegacyReference() {
        let legacy = String(repeating: "d", count: 64)
        XCTAssertEqual(
            ShopCatalogSyncProtocol.resolvedMediaKey(
                nil, fallbackReferences: ["thmedia:\(legacy)"]),
            legacy)
        XCTAssertEqual(
            ShopCatalogSyncProtocol.resolvedMediaKey(
                "", fallbackReferences: [nil, "local:img-1.jpg", "thmedia:\(legacy)"]),
            legacy)
    }

    func testResolvedMediaKeyRejectsMalformedValues() {
        XCTAssertNil(ShopCatalogSyncProtocol.resolvedMediaKey("not-a-hash", fallbackReferences: []))
        XCTAssertNil(ShopCatalogSyncProtocol.resolvedMediaKey(nil, fallbackReferences: ["local:x.jpg"]))
        XCTAssertNil(ShopCatalogSyncProtocol.resolvedMediaKey(
            "c", fallbackReferences: ["thmedia:short"]))
    }
}

// MARK: - gzip 压缩（iOS 发布 THDataPack 的前置能力）

final class ShopCatalogGzipTests: XCTestCase {

    func testCompressedBytesLookLikeGzip() throws {
        let raw = Data(repeating: 0x41, count: 4096)
        let compressed = try ShopCatalogCloudSyncValidator.compress(raw)
        XCTAssertEqual(Array(compressed.prefix(3)), [0x1F, 0x8B, 0x08],
                       "必须是 gzip（RFC 1952）魔数，消费端按它硬校验")
    }

    func testRoundTripThroughValidatorDecompressor() throws {
        // 用一条真实的压缩包走「压缩 → 被校验器解压」闭环，验证两端封装一致
        let catalog = ShopCatalog(shops: [CatalogShop(id: "shop-1", name: "测试店家")])
        let payload = ShopCatalogPackPayload(
            schemaVersion: ShopCatalogSyncProtocol.schemaVersion,
            partitionID: ShopCatalogSyncProtocol.shopCatalogPartitionID,
            brandID: ShopCatalogSyncProtocol.shopCatalogBrandID,
            entityType: ShopCatalogSyncProtocol.shopCatalogEntityType,
            partitionRevision: 1,
            coverageStatus: ShopCatalogRootIndex.Partition.Coverage.complete,
            checkedThrough: nil,
            shopCatalog: catalog)

        let raw = try ShopCatalogJSONCoding.encoder().encode(payload)
        let compressed = try ShopCatalogCloudSyncValidator.compress(raw)
        let restored = ShopCatalogCloudSyncValidator.catalog(fromVerifiedPack: compressed)

        XCTAssertNotNil(restored, "自压缩的数据包必须能被消费端解压")
        XCTAssertEqual(restored?.shops.first?.name, "测试店家")
    }

    func testCompressionIsDeterministic() throws {
        let raw = Data(repeating: 0x7A, count: 1024)
        let first = try ShopCatalogCloudSyncValidator.compress(raw)
        let second = try ShopCatalogCloudSyncValidator.compress(raw)
        XCTAssertEqual(first, second,
                       "mtime 固定为 0：同内容必须同字节，否则内容寻址的包会每次发布都多一个")
        XCTAssertEqual(ShopCatalogSyncProtocol.sha256Hex(first),
                       ShopCatalogSyncProtocol.sha256Hex(second))
    }
}

// MARK: - 方案二 §3.1 / §3.3：暂存与改写

@MainActor
final class ShopCatalogOpsMediaStagingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
    }

    override func tearDown() {
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    /// 使用可完整解码的图片；超限场景额外填充字节。
    @discardableResult
    private func writeJPEG(name: String, bytes: Int = 512) throws -> String {
        var data = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 12, height: 9)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 9))
        }.jpegData(compressionQuality: 0.85))
        data.append(Data(repeating: 0x11, count: max(0, bytes - data.count)))
        let url = ShopCatalogImageStore.directory.appendingPathComponent(name)
        try data.write(to: url)
        return "local:\(name)"
    }

    private func catalog(with references: [String]) -> ShopCatalog {
        ShopCatalog(
            sizeCharts: [
                CatalogSizeChart(id: "chart-1", productID: "p-1", sourceImage: references.first)
            ],
            assets: references.enumerated().map { index, ref in
                CatalogAsset(id: "asset-\(index)", type: .productImage, originalURL: ref)
            })
    }

    func testPlanDeduplicatesSameContentAndCollectsOwners() throws {
        let reference = try writeJPEG(name: "img-dup.jpg")
        let plan = try ShopCatalogOpsMediaStaging.plan(for: catalog(with: [reference, reference]))
        XCTAssertEqual(plan.count, 1, "同内容摘要只产生一条待上传媒体")
        XCTAssertGreaterThanOrEqual(plan[0].owners.count, 2, "多处引用都要记下来")
        XCTAssertEqual(plan[0].mimeType, "image/jpeg")
        XCTAssertEqual(plan[0].mediaKey.count, 64)
    }

    func testPlanIgnoresBundleAndHTTPReferences() throws {
        let plan = try ShopCatalogOpsMediaStaging.plan(
            for: catalog(with: ["bundle:seed.jpg", "https://example.com/a.jpg"]))
        XCTAssertTrue(plan.isEmpty, "bundle: / http(s) 不由本机上传")
    }

    func testPlanThrowsWhenFileMissing() {
        XCTAssertThrowsError(
            try ShopCatalogOpsMediaStaging.plan(for: catalog(with: ["local:img-missing.jpg"]))
        ) { error in
            guard case ShopCatalogOpsMediaStagingError.fileMissing = error else {
                return XCTFail("缺图必须硬报错，实际 \(error)")
            }
        }
    }

    func testPlanThrowsOnUnsupportedType() throws {
        let url = ShopCatalogImageStore.directory.appendingPathComponent("img-raw.bin")
        try Data(repeating: 0x00, count: 64).write(to: url)
        XCTAssertThrowsError(
            try ShopCatalogOpsMediaStaging.plan(for: catalog(with: ["local:img-raw.bin"]))
        ) { error in
            guard case ShopCatalogOpsMediaStagingError.unsupportedMimeType = error else {
                return XCTFail("非图片类型必须在暂存阶段就被拦下，实际 \(error)")
            }
        }
    }

    func testPlanThrowsWhenOverByteLimit() throws {
        let reference = try writeJPEG(
            name: "img-huge.jpg", bytes: ShopCatalogUploadPolicy.maxMediaBytes + 16)
        XCTAssertThrowsError(try ShopCatalogOpsMediaStaging.plan(for: catalog(with: [reference]))) {
            guard case ShopCatalogOpsMediaStagingError.tooLarge = $0 else {
                return XCTFail("超出上限必须拒绝，实际 \($0)")
            }
        }
    }

    /// 2026-09-29 回归锁：缺图必须**一次列全**（原先抛第一条就停，
    /// 线上 174 张缺图只报得出 1 张，运营无从下手）。
    func testDiagnoseCollectsEveryMissingFileOnceAndAggregatesOwners() throws {
        let catalog = ShopCatalog(
            sizeCharts: [
                CatalogSizeChart(id: "chart-1", productID: "p-1", sourceImage: "local:missing-a.jpg"),
                CatalogSizeChart(id: "chart-2", productID: "p-2", sourceImage: "local:missing-b.jpg"),
            ],
            assets: [
                CatalogAsset(id: "asset-1", type: .productImage, originalURL: "local:missing-c.jpg"),
                CatalogAsset(id: "asset-2", type: .productImage, originalURL: "local:missing-c.jpg"),
            ])

        let diagnosis = ShopCatalogOpsMediaStaging.diagnose(for: catalog)

        XCTAssertTrue(diagnosis.isBlocked)
        XCTAssertTrue(diagnosis.staged.isEmpty)
        XCTAssertEqual(diagnosis.issues.count, 3, "按文件去重：3 个不同的缺图文件")
        XCTAssertEqual(diagnosis.missingFileCount, 3)

        let repeated = try XCTUnwrap(diagnosis.issues.first { $0.reference == "local:missing-c.jpg" })
        XCTAssertEqual(repeated.owners.count, 2, "同一个文件的每一处引用都要记下来")
        XCTAssertEqual(repeated.fileName, "missing-c.jpg")

        XCTAssertTrue(diagnosis.summary.contains("3 个图片文件"), diagnosis.summary)
        XCTAssertTrue(diagnosis.summary.contains("线上仍是旧版本"),
                      "失败必须说清「线上没被改动」，否则运营会以为发了一半")
        XCTAssertTrue(repeated.displayText.contains("图片资源 asset-1"), repeated.displayText)
    }

    /// `plan` 保持「快速失败」语义不变（既有调用方的回归锁）。
    func testPlanStillThrowsFirstIssueForFastFailCallers() {
        let catalog = ShopCatalog(
            assets: [
                CatalogAsset(id: "a", type: .productImage, originalURL: "local:missing-1.jpg"),
                CatalogAsset(id: "b", type: .productImage, originalURL: "local:missing-2.jpg"),
            ])
        XCTAssertThrowsError(try ShopCatalogOpsMediaStaging.plan(for: catalog)) { error in
            guard case ShopCatalogOpsMediaStagingError.fileMissing = error else {
                return XCTFail("plan 仍按旧语义抛第一条，实际 \(error)")
            }
        }
    }

    /// 图片齐全时 `diagnose` 必须放行，且不产生任何问题条目。
    func testDiagnosePassesWhenAllFilesArePresent() throws {
        let reference = try writeJPEG(name: "img-ok.jpg")
        let diagnosis = ShopCatalogOpsMediaStaging.diagnose(for: catalog(with: [reference]))
        XCTAssertFalse(diagnosis.isBlocked)
        XCTAssertTrue(diagnosis.issues.isEmpty)
        XCTAssertEqual(diagnosis.staged.count, 1)
        XCTAssertTrue(diagnosis.summary.contains("图片齐了"), diagnosis.summary)
    }

    func testRewriteSetsCanonicalMediaKeyAndThmediaReference() throws {
        let reference = try writeJPEG(name: "img-rewrite.jpg")
        var original = catalog(with: [reference])
        original.products = [CatalogProduct(id: "p", shopID: "s", seriesID: "series", name: "帽子",
            category: "小物", images: ["asset-0", reference])]
        original.variants = [CatalogProductVariant(id: "v", productID: "p", imageAssetID: reference)]
        let plan = try ShopCatalogOpsMediaStaging.plan(for: original)
        let digest = plan[0].mediaKey

        let rewritten = ShopCatalogOpsMediaStaging.rewrite(
            original, mediaKeys: [reference: digest])

        XCTAssertEqual(rewritten.assets[0].mediaKey, digest, "原图摘要要写进 canonical mediaKey")
        XCTAssertEqual(rewritten.assets[0].originalURL, "thmedia:\(digest)")
        XCTAssertEqual(rewritten.sizeCharts[0].sourceImage, "thmedia:\(digest)")
        XCTAssertEqual(rewritten.products[0].images, ["asset-0", "thmedia:\(digest)"])
        XCTAssertEqual(rewritten.variants[0].imageAssetID, "thmedia:\(digest)")
        XCTAssertEqual(original.assets[0].mediaKey, nil, "改写不得改动入参（暂存阶段目录原封不动）")
    }

    func testRewriteLeavesNonLocalReferencesAlone() {
        let original = ShopCatalog(
            shops: [CatalogShop(id: "shop-1", name: "店家", logo: "bundle:logo.png")],
            series: [CatalogSeries(id: "series-1", shopID: "shop-1", name: "系列",
                                   cover: "https://example.com/c.jpg")])
        let rewritten = ShopCatalogOpsMediaStaging.rewrite(original, mediaKeys: ["local:x": "hash"])
        XCTAssertEqual(rewritten.shops[0].logo, "bundle:logo.png")
        XCTAssertEqual(rewritten.series[0].cover, "https://example.com/c.jpg")
    }

    func testRecognizableButBrokenImageCannotBeUploaded() throws {
        let url = ShopCatalogImageStore.directory.appendingPathComponent("broken.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]).write(to: url)
        let diagnosis = ShopCatalogOpsMediaStaging.diagnose(for: catalog(with: ["local:broken.jpg"]))
        XCTAssertTrue(diagnosis.isBlocked)
        XCTAssertTrue(diagnosis.staged.isEmpty)
        guard case .invalidImage = diagnosis.issues.first?.reason else {
            return XCTFail("格式头合法的坏图也必须在上传前被拦下")
        }
    }
}

// MARK: - 方案二 §4：任务状态机

/// `ShopCatalogOpsUploadStore` 是 `@MainActor`（它持有 SwiftData 容器），
/// 本类里的容器/暂存表用例必须在主 actor 上跑。
@MainActor
final class ShopCatalogUploadJobTests: XCTestCase {

    private func makeJob() -> ShopCatalogUploadJob {
        ShopCatalogUploadJob(
            jobID: String(repeating: "e", count: 64),
            mediaKey: String(repeating: "e", count: 64),
            filePath: "/tmp/not-used.jpg",
            mimeType: "image/jpeg",
            byteCount: 512)
    }

    func testRetryableFailureSchedulesExponentialBackoff() throws {
        let job = makeJob()
        let now = Date()
        job.markFailure(.retryable, reason: "网络超时", now: now)
        XCTAssertEqual(job.status, .retryable)
        XCTAssertEqual(job.attemptCount, 1)
        let scheduled = try XCTUnwrap(job.nextRetryAt, "可重试失败必须排下次重试时间")
        XCTAssertEqual(scheduled.timeIntervalSince(now),
                       ShopCatalogUploadPolicy.retryDelay(attempt: 1), accuracy: 1)
    }

    func testBlockedFailureNeverSchedulesRetry() {
        let job = makeJob()
        job.markFailure(.blocked, reason: "没有 iCloud 账号")
        XCTAssertNil(job.nextRetryAt, "阻塞类不自动重试（方案 §4）")
        XCTAssertFalse(job.status.allowsManualRetry, "先解决账号/权限，不给「重试」按钮")
    }

    func testConflictRequiresOperatorConfirmation() {
        let job = makeJob()
        job.markFailure(.conflict, reason: "changeTag 冲突")
        XCTAssertNil(job.nextRetryAt)
        XCTAssertTrue(job.status.isTerminalFailure)
        XCTAssertFalse(job.status.allowsManualRetry)
    }

    func testRetryableDowngradesToFailedAtAttemptLimit() {
        let job = makeJob()
        for _ in 0..<ShopCatalogUploadPolicy.maxAttempts {
            job.markFailure(.retryable, reason: "网络超时")
        }
        XCTAssertEqual(job.status, .failed, "重试到上限就停，不能无限打网络")
        XCTAssertNil(job.nextRetryAt)
    }

    func testSuccessClearsErrorAndRetryClock() {
        let job = makeJob()
        job.markFailure(.retryable, reason: "网络超时")
        job.markSuccess(.mediaVerified)
        XCTAssertEqual(job.status, .mediaVerified)
        XCTAssertNil(job.lastError)
        XCTAssertNil(job.nextRetryAt)
    }

    func testInMemoryStoreUpsertsWithoutOverwritingProgressedJob() {
        let store = ShopCatalogOpsUploadStore(inMemory: true)
        let key = String(repeating: "f", count: 64)
        store.stage(mediaKey: key, productID: "p-1", assetID: "asset-1",
                    filePath: "/tmp/a.jpg", mimeType: "image/jpeg", byteCount: 10)
        store.update(mediaKey: key) { $0.markSuccess(.mediaVerified) }

        store.stage(mediaKey: key, productID: "p-2", assetID: "asset-2",
                    filePath: "/tmp/a.jpg", mimeType: "image/jpeg", byteCount: 10)
        XCTAssertEqual(store.job(mediaKey: key)?.status, .mediaVerified,
                       "重新暂存不得把已传完的任务打回 staged")
        XCTAssertEqual(store.job(mediaKey: key)?.productID, "p-1", "只补空字段")
    }

    func testPruneOnlyRemovesVerifiedStagedFiles() throws {
        let store = ShopCatalogOpsUploadStore(inMemory: true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prune-\(UUID().uuidString).jpg")
        try Data(repeating: 0x01, count: 32).write(to: url)

        let key = String(repeating: "a", count: 64)
        store.stage(mediaKey: key, productID: "", assetID: "",
                    filePath: url.path, mimeType: "image/jpeg", byteCount: 32)
        store.pruneVerifiedStagedFiles()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "没校验通过的暂存文件不能删（方案 §4 尾注）")

        store.update(mediaKey: key) { $0.markSuccess(.mediaVerified) }
        store.pruneVerifiedStagedFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

// MARK: - 方案二 §3.4：负载与根清单

final class ShopCatalogOpsPublishScopeTests: XCTestCase {

    func testPublicationTitleIdentifiesBrandSeriesAndChangedProduct() {
        var catalog = ShopCatalog(
            shops: [CatalogShop(id: "s", name: "1304")],
            series: [CatalogSeries(id: "se", shopID: "s", name: "PAD")])
        let baseline = catalog
        catalog.products = [CatalogProduct(id: "p", shopID: "s", seriesID: "se", name: "粉色 OP", category: "OP")]
        XCTAssertEqual(ShopCatalogOpsPublisher.publicationTitle(catalog: catalog, baseline: baseline),
                       "1304 · PAD · 粉色 OP")
        XCTAssertTrue(ShopCatalogOpsPublisher.publicationTitle(catalog: ShopCatalog(), baseline: nil).contains("商品 0"))
    }

    func testPayloadCarriesAgreedPartitionContract() {
        let catalog = ShopCatalog(shops: [CatalogShop(id: "shop-1", name: "店家")])
        let payload = ShopCatalogOpsPublisher.makePayload(catalog: catalog)
        XCTAssertEqual(payload.shopCatalog.shops.count, 1, "载荷键是 shopCatalog")
        XCTAssertEqual(payload.brandID, ShopCatalogSyncProtocol.shopCatalogBrandID)
        XCTAssertEqual(payload.entityType, ShopCatalogSyncProtocol.shopCatalogEntityType)
        XCTAssertEqual(payload.partitionID, ShopCatalogSyncProtocol.shopCatalogPartitionID)
        XCTAssertEqual(payload.coverageStatus, ShopCatalogRootIndex.Partition.Coverage.complete)
        XCTAssertFalse(payload.checkedThrough?.isEmpty ?? true,
                       "Mac 公共协议要求完整分片声明检查时间")
    }

    func testEmptyCatalogDeclaresEmptyCoverage() {
        let payload = ShopCatalogOpsPublisher.makePayload(catalog: ShopCatalog())
        XCTAssertEqual(payload.coverageStatus, ShopCatalogRootIndex.Partition.Coverage.empty,
                       "空目录必须声明 empty，不能报 complete（客户端结构校验会拒）")
        XCTAssertFalse(payload.checkedThrough?.isEmpty ?? true)
    }

    func testRootIndexMatchesProtocolContract() throws {
        let payloadHash = String(repeating: "9", count: 64)
        let data = try ShopCatalogOpsPublisher.makeRootIndexData(
            releaseSeq: 7, revocationEpoch: 0, payloadHash: payloadHash,
            compressedByteCount: 1234, recordCount: 3)
        let rootIndex = try ShopCatalogJSONCoding.decoder().decode(
            ShopCatalogRootIndex.self, from: data)

        XCTAssertEqual(rootIndex.releaseSeq, 7)
        XCTAssertEqual(rootIndex.schemaVersion, ShopCatalogSyncProtocol.schemaVersion)
        let partition = try XCTUnwrap(rootIndex.shopCatalogPartition)
        XCTAssertEqual(partition.recordCount, 3)
        XCTAssertFalse(partition.checkedThrough?.isEmpty ?? true)
        XCTAssertEqual(partition.packRecordName,
                       ShopCatalogSyncProtocol.packRecordName(payloadHash: payloadHash))
        // 契约校验（消费端与 Mac 端共用同一口径）
        XCTAssertNoThrow(try ShopCatalogCloudSyncValidator.checkPartitionContract(partition))
    }

    func testEntityCountMatchesStructuralValidatorScope() {
        let catalog = ShopCatalog(
            shops: [CatalogShop(id: "s", name: "s")],
            series: [CatalogSeries(id: "se", shopID: "s", name: "se")],
            products: [CatalogProduct(id: "p", shopID: "s", seriesID: "se",
                                      name: "p", category: "其他")],
            assets: [CatalogAsset(id: "a", type: .productImage, originalURL: "bundle:x.jpg")])
        XCTAssertEqual(ShopCatalogOpsPublisher.entityCount(of: catalog), 4)
    }
}

// MARK: - 方案二 §3–§4：全流程（内存替身）

/// 内存版公共库：写通道与只读通道共享同一份存储
private final class FakeCloudBackend {
    var media: [String: Data] = [:]
    var mediaMime: [String: String] = [:]
    var packs: [String: Data] = [:]
    var release: ShopCatalogReleaseHeader?
    var rootIndex: Data?
    /// 构造冲突：saveRelease 一律报 changeTag 冲突
    var conflictOnReleaseSave = false
    /// 构造「Asset 上传成功但回读拿不到」
    var hideMediaOnRead = false
    var hideRootOnRead = false
}

private final class FakeWriter: ShopCatalogOpsCloudWriting {
    let backend: FakeCloudBackend
    private(set) var savedMediaCount = 0
    private(set) var savedReleaseCount = 0
    private(set) var savedPackCount = 0

    init(backend: FakeCloudBackend) { self.backend = backend }

    func ensureWritableAccount() async throws {}

    func fetchMediaMetadata(mediaKey: String) async throws -> ShopCatalogOpsRemoteMediaMeta? {
        guard let data = backend.media[mediaKey] else { return nil }
        return ShopCatalogOpsRemoteMediaMeta(
            sha256: ShopCatalogSyncProtocol.sha256Hex(data), byteCount: data.count)
    }

    func saveMedia(mediaKey: String, mimeType: String, sha256: String, byteCount: Int,
                   fileURL: URL) async throws {
        let data = try Data(contentsOf: fileURL)
        backend.media[mediaKey] = data
        backend.mediaMime[mediaKey] = mimeType
        savedMediaCount += 1
    }

    func fetchMediaBytes(mediaKey: String) async throws -> Data {
        guard let data = backend.media[mediaKey] else {
            throw ShopCatalogOpsUploadError.retryable("媒体暂时读不到")
        }
        return data
    }

    func fetchPackMetadata(payloadHash: String) async throws -> ShopCatalogOpsRemotePackMeta? {
        guard let data = backend.packs[payloadHash] else { return nil }
        return ShopCatalogOpsRemotePackMeta(
            sha256: ShopCatalogSyncProtocol.sha256Hex(data), byteCount: data.count)
    }

    func savePack(payloadHash: String, partitionID: String, releaseSeq: Int, sha256: String,
                  byteCount: Int, fileURL: URL) async throws {
        backend.packs[payloadHash] = try Data(contentsOf: fileURL)
        savedPackCount += 1
    }

    func fetchRelease() async throws -> ShopCatalogOpsReleaseSnapshot? {
        guard let header = backend.release else { return nil }
        return ShopCatalogOpsReleaseSnapshot(header: header, systemFields: Data())
    }

    func saveRelease(systemFields: Data?, update: ShopCatalogOpsReleaseUpdate) async throws {
        if backend.conflictOnReleaseSave {
            throw ShopCatalogOpsUploadError.conflict("changeTag 冲突")
        }
        backend.rootIndex = update.rootIndexData
        backend.release = ShopCatalogReleaseHeader(
            releaseSeq: update.releaseSeq,
            schemaVersion: update.schemaVersion,
            revocationEpoch: update.revocationEpoch,
            minimumReaderVersion: update.minimumReaderVersion,
            previousReleaseSeq: update.previousReleaseSeq,
            publishedAt: update.publishedAt,
            rootIndexHash: update.rootIndexHash)
        savedReleaseCount += 1
    }
}

private final class FakeReader: ShopCatalogPublicReading {
    let backend: FakeCloudBackend
    init(backend: FakeCloudBackend) { self.backend = backend }

    func fetchReleaseHeader() async throws -> ShopCatalogReleaseHeader {
        guard let header = backend.release else {
            throw ShopCatalogSyncError.recordMissing(
                recordType: "THRelease",
                recordName: ShopCatalogSyncProtocol.releaseRecordName)
        }
        return header
    }

    func fetchRootIndex() async throws -> Data {
        guard !backend.hideRootOnRead, let data = backend.rootIndex else {
            throw ShopCatalogSyncError.recordMissing(recordType: "THRelease", recordName: "root")
        }
        return data
    }

    func fetchPack(payloadHash: String) async throws -> Data {
        guard let data = backend.packs[payloadHash] else {
            throw ShopCatalogSyncError.recordMissing(recordType: "THDataPack", recordName: payloadHash)
        }
        return data
    }

    func fetchMedia(contentHash: String) async throws -> Data {
        guard !backend.hideMediaOnRead, let data = backend.media[contentHash] else {
            throw ShopCatalogSyncError.recordMissing(recordType: "THMedia", recordName: contentHash)
        }
        return data
    }
}

@MainActor
final class ShopCatalogOpsPublisherTests: XCTestCase {

    private var backend: FakeCloudBackend!
    private var writer: FakeWriter!
    private var publisher: ShopCatalogOpsPublisher!
    private var uploadStore: ShopCatalogOpsUploadStore!

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        try! ShopCatalogPackCache.savePublicationBaseline(ShopCatalogBaseline(
            releaseSeq: 0, environment: ShopCatalogOpsPublisher.environmentName))
        backend = FakeCloudBackend()
        writer = FakeWriter(backend: backend)
        uploadStore = ShopCatalogOpsUploadStore(inMemory: true)
        publisher = ShopCatalogOpsPublisher(
            writer: writer, reader: FakeReader(backend: backend), uploadStore: uploadStore)
    }

    override func tearDown() {
        ShopCatalogStorage.restoreDefaultForTesting()
        backend = nil
        writer = nil
        publisher = nil
        uploadStore = nil
        super.tearDown()
    }

    private func makeLocalImageCatalog(name: String) throws -> (ShopCatalog, String) {
        var data = Data([0xFF, 0xD8, 0xFF, 0xE0])
        data.append(Data(repeating: 0x22, count: 600))
        try data.write(to: ShopCatalogImageStore.directory.appendingPathComponent(name))
        let reference = "local:\(name)"
        // 目录自身必须是**引用完整**的：回读验证会跑客户端的结构校验，
        // 悬空引用会让「已发布未验证」这类断言因为别的原因通过，测试就假绿了。
        let catalog = ShopCatalog(
            shops: [CatalogShop(id: "shop-1", name: "店家")],
            series: [CatalogSeries(id: "series-1", shopID: "shop-1", name: "系列")],
            products: [CatalogProduct(id: "p-1", shopID: "shop-1", seriesID: "series-1",
                                      name: "商品", category: "其他")],
            assets: [CatalogAsset(id: "asset-1", type: .productImage, originalURL: reference)])
        return (catalog, reference)
    }

    func testUnknownBaselineBlocksBeforeAnyCloudWrite() async throws {
        try ShopCatalogPackCache.clearPublicationBaseline()
        backend.release = ShopCatalogReleaseHeader(
            releaseSeq: 1, schemaVersion: 1, revocationEpoch: 0,
            minimumReaderVersion: 1, previousReleaseSeq: 0,
            publishedAt: nil, rootIndexHash: String(repeating: "a", count: 64))
        let (catalog, _) = try makeLocalImageCatalog(name: "unknown-baseline.jpg")
        let result = await publisher.publish(catalog: catalog)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.summary.contains("先取回"))
        XCTAssertEqual(writer.savedMediaCount, 0)
        XCTAssertEqual(writer.savedPackCount, 0)
        XCTAssertEqual(writer.savedReleaseCount, 0)
    }

    func testSyncKeepsLocalAndRemoteAdditionsAndPublishesTogether() async throws {
        let remote = ShopCatalog(shops: [CatalogShop(id: "remote", name: "线上店家")])
        let initial = await publisher.publish(catalog: remote)
        XCTAssertTrue(initial.isSuccess)
        let local = ShopCatalog(shops: [CatalogShop(id: "local", name: "本机新店家")])
        try ShopCatalogDraftStore.replaceOverlay(with: local)
        let store = ShopCatalogStore(baseCatalog: ShopCatalog())
        store.reloadWithOverlay()
        switch await publisher.synchronizeAndPublish(store: store) {
        case .finished(let result): XCTAssertTrue(result.isSuccess, result.summary)
        case .conflicts: XCTFail("互不重叠的新增不应冲突")
        }
        XCTAssertEqual(Set(store.catalog?.shops.map(\.id) ?? []), ["remote", "local"])
        XCTAssertEqual(writer.savedReleaseCount, 2)
    }

    func testSyncConflictRequiresChoiceAndPreservesUnrelatedLocalAddition() async throws {
        let original = ShopCatalog(shops: [CatalogShop(id: "s", name: "原名")])
        _ = await publisher.publish(catalog: original)
        var remote = original
        remote.shops[0].name = "远端修改"
        _ = await publisher.publish(catalog: remote)
        // 两边共同起点仍是原名，不是新拉下来的线上版本。
        try ShopCatalogPackCache.savePublicationBaseline(ShopCatalogBaseline(
            releaseSeq: 1, rootIndexHash: "old", environment: ShopCatalogOpsPublisher.environmentName), catalog: original)
        var local = original
        local.shops[0].name = "本机修改"
        local.shops.append(CatalogShop(id: "new", name: "本机新增"))
        try ShopCatalogDraftStore.replaceOverlay(with: local)
        let store = ShopCatalogStore(baseCatalog: ShopCatalog())
        store.reloadWithOverlay()
        let before = writer.savedReleaseCount
        guard case .conflicts(let fields, let token) = await publisher.synchronizeAndPublish(store: store) else {
            return XCTFail("必须先报告冲突")
        }
        XCTAssertEqual(fields, ["shops.s.name"])
        XCTAssertEqual(writer.savedReleaseCount, before)
        XCTAssertEqual(ShopCatalogDraftStore.loadOverlay()?.shops, local.shops)
        // 确认后本机又修改，旧选择不能自动应用到新的内容。
        local.shops[0].name = "再次修改"
        try ShopCatalogDraftStore.replaceOverlay(with: local)
        store.reloadWithOverlay()
        guard case .conflicts(_, let freshToken) = await publisher.synchronizeAndPublish(
            store: store, resolution: .init(token: token, preferLocal: true)) else {
            return XCTFail("过期选择必须重新核对")
        }
        guard case .finished(let result) = await publisher.synchronizeAndPublish(
            store: store, resolution: .init(token: freshToken, preferLocal: false)) else {
            return XCTFail("明确选择后应继续上传")
        }
        XCTAssertTrue(result.isSuccess, result.summary)
        XCTAssertEqual(store.catalog?.shops.first { $0.id == "s" }?.name, "远端修改")
        XCTAssertNotNil(store.catalog?.shops.first { $0.id == "new" })
    }

    func testFailedRemoteReadDoesNotWriteLocalCatalogOrPublish() async throws {
        let remote = ShopCatalog(shops: [CatalogShop(id: "remote", name: "线上")])
        _ = await publisher.publish(catalog: remote)
        let local = ShopCatalog(shops: [CatalogShop(id: "local", name: "新增")])
        try ShopCatalogDraftStore.replaceOverlay(with: local)
        let store = ShopCatalogStore(baseCatalog: ShopCatalog())
        store.reloadWithOverlay()
        backend.hideRootOnRead = true
        guard case .finished(let result) = await publisher.synchronizeAndPublish(store: store) else {
            return XCTFail("读取失败须显示原因")
        }
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(ShopCatalogDraftStore.loadOverlay()?.shops, local.shops)
        XCTAssertEqual(writer.savedReleaseCount, 1)
    }

    func testSyncWithoutChangesDoesNotRepublish() async throws {
        let remote = ShopCatalog(shops: [CatalogShop(id: "s", name: "店家")])
        _ = await publisher.publish(catalog: remote)
        let store = ShopCatalogStore(baseCatalog: ShopCatalog())
        store.installRemoteCatalog(remote)
        guard case .finished(.upToDate(let seq)) = await publisher.synchronizeAndPublish(store: store) else {
            return XCTFail("没有修改应直接完成同步")
        }
        XCTAssertEqual(seq, 1)
        XCTAssertEqual(writer.savedReleaseCount, 1)
        XCTAssertTrue(ShopCatalogDraftStore.loadOverlay()?.shops.isEmpty == true)
    }

    func testDeletedHistoryStaysLocalAndPublicPackRemainsReadableByExistingClients() async throws {
        var catalog = ShopCatalog(shops: [CatalogShop(id: "s", name: "店家")])
        catalog.saleEvents = [CatalogSaleEvent(id: "history", productID: "deleted", type: .stock, price: 888)]
        catalog.removedProductIDs = ["deleted"]
        try ShopCatalogDraftStore.replaceOverlay(with: catalog)
        let store = ShopCatalogStore(baseCatalog: ShopCatalog())
        store.reloadWithOverlay()
        guard case .finished(let result) = await publisher.synchronizeAndPublish(store: store) else {
            return XCTFail("明确删除的历史不应阻塞发布")
        }
        XCTAssertTrue(result.isSuccess, result.summary)
        XCTAssertEqual(store.catalog?.saleEvents, catalog.saleEvents)
        let hash = try XCTUnwrap(backend.packs.keys.first)
        let publicCatalog = try XCTUnwrap(ShopCatalogCloudSyncValidator.catalog(fromVerifiedPack: backend.packs[hash]!))
        XCTAssertTrue(publicCatalog.saleEvents.isEmpty)
        guard case .finished(.upToDate) = await publisher.synchronizeAndPublish(store: store) else {
            return XCTFail("保留本机历史不会制造重复上传")
        }
        XCTAssertEqual(store.catalog?.saleEvents, catalog.saleEvents)
        XCTAssertEqual(writer.savedReleaseCount, 1)
    }

    func testRootUpdatePreservesOtherPartitionsAndWithdrawalMetadata() throws {
        let previous = Data("""
        {"schemaVersion":1,"releaseSeq":4,"revocationEpoch":2,"partitions":[
          {"partitionID":"other","payloadHash":"unchanged","custom":"retain"}
        ],"brands":[{"brandID":"other"}],"withdrawals":[{"id":"removed"}],"custom":"keep"}
        """.utf8)
        let result = try ShopCatalogOpsPublisher.makeRootIndexData(
            releaseSeq: 5, revocationEpoch: 2, payloadHash: String(repeating: "a", count: 64),
            compressedByteCount: 100, recordCount: 3, previousRootData: previous)
        let object = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        XCTAssertEqual(object["custom"] as? String, "keep")
        let partitions = object["partitions"] as! [[String: Any]]
        XCTAssertEqual(partitions.count, 2)
        XCTAssertEqual(partitions[0]["payloadHash"] as? String, "unchanged")
        XCTAssertEqual((object["withdrawals"] as! [[String: String]])[0]["id"], "removed")
    }

    func testOrphanEventWithoutProductBlocksBeforeAnyCloudWrite() async {
        let catalog = ShopCatalog(saleEvents: [CatalogSaleEvent(
            id: "event", productID: "lost-product", type: .stock, price: 888)])
        let result = await publisher.publish(catalog: catalog)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.summary.contains("恢复缺失商品"))
        XCTAssertEqual(writer.savedMediaCount, 0)
        XCTAssertEqual(writer.savedPackCount, 0)
        XCTAssertEqual(writer.savedReleaseCount, 0)
    }

    func testConfirmedEmptyCloudAllowsFirstPublicationWithoutOldBaseline() async throws {
        try ShopCatalogPackCache.clearPublicationBaseline()
        let (catalog, _) = try makeLocalImageCatalog(name: "confirmed-empty.jpg")
        let result = await publisher.publish(catalog: catalog)
        XCTAssertTrue(result.isSuccess, result.summary)
        XCTAssertEqual(writer.savedReleaseCount, 1)

        let releaseJob = uploadStore.jobs.first { $0.stage == .release }
        XCTAssertEqual(releaseJob?.catalogSummary, "店家 · 系列 · 商品")
        XCTAssertEqual(ShopCatalogPackCache.loadPublicationBaseline()?.releaseSeq, 1)
    }

    func testStaleBaselineBlocksBeforeAnyCloudWrite() async throws {
        backend.release = ShopCatalogReleaseHeader(
            releaseSeq: 1, schemaVersion: 1, revocationEpoch: 0,
            minimumReaderVersion: 1, previousReleaseSeq: 0,
            publishedAt: nil, rootIndexHash: String(repeating: "a", count: 64))
        let (catalog, _) = try makeLocalImageCatalog(name: "stale-baseline.jpg")
        let result = await publisher.publish(catalog: catalog)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.summary.contains("线上内容已更新"))
        XCTAssertEqual(writer.savedMediaCount, 0)
        XCTAssertEqual(writer.savedPackCount, 0)
        XCTAssertEqual(writer.savedReleaseCount, 0)
    }

    func testPublishHappyPathSwitchesReleaseAndVerifies() async throws {
        let (catalog, reference) = try makeLocalImageCatalog(name: "img-happy.jpg")
        let result = await publisher.publish(catalog: catalog)

        guard case .published(let releaseSeq, let mediaCount) = result else {
            return XCTFail("期望发布成功，实际 \(result.summary)")
        }
        XCTAssertEqual(releaseSeq, 1, "首次发布序号从 1 开始")
        XCTAssertEqual(mediaCount, 1)
        XCTAssertEqual(writer.savedMediaCount, 1)
        XCTAssertEqual(writer.savedPackCount, 1)
        XCTAssertEqual(writer.savedReleaseCount, 1)

        // 包里必须已经换成 thmedia: 引用 + canonical mediaKey（方案 §3.3）
        let payloadHash = try XCTUnwrap(backend.packs.keys.first)
        let payload = try ShopCatalogCloudSyncValidator
            .catalog(fromVerifiedPack: try XCTUnwrap(backend.packs[payloadHash]))
        let asset = try XCTUnwrap(payload?.assets.first)
        XCTAssertEqual(asset.mediaKey, asset.originalURL.replacingOccurrences(of: "thmedia:", with: ""))
        XCTAssertTrue(asset.originalURL.hasPrefix("thmedia:"))
        XCTAssertNotEqual(asset.originalURL, reference, "新发布目录不得再依赖 local:")
    }

    func testPublishIsIdempotentOnSecondRun() async throws {
        let (catalog, _) = try makeLocalImageCatalog(name: "img-idempotent.jpg")
        _ = await publisher.publish(catalog: catalog)
        let mediaAfterFirst = writer.savedMediaCount
        let packAfterFirst = writer.savedPackCount

        _ = await publisher.publish(catalog: catalog)
        XCTAssertEqual(writer.savedMediaCount, mediaAfterFirst, "同一 hash 的图片不得重复上传")
        XCTAssertEqual(writer.savedPackCount, packAfterFirst, "同一 payloadHash 的数据包不得重复上传")
    }

    func testMissingImageBlocksBeforeReleaseSwitch() async throws {
        // 目录引用一张本机没有的图 → 暂存阶段就失败
        let catalog = ShopCatalog(
            assets: [CatalogAsset(id: "asset-x", type: .productImage,
                                  originalURL: "local:img-never-exists.jpg")])
        let result = await publisher.publish(catalog: catalog)

        guard case .notPublished = result else {
            return XCTFail("缺图必须挡在发布头之前，实际 \(result.summary)")
        }
        XCTAssertEqual(writer.savedReleaseCount, 0, "发布头绝不能切换（方案 §3.4 末段）")
        XCTAssertNil(backend.release)
    }

    /// 2026-09-29 回归锁：缺图要**一次列全**并暴露给界面，不能只说第一条。
    /// （现场症状：点了「上传并发布到公共库」毫无反应，因为异常被吞、任务一条不落。）
    func testMissingImagesAreListedAllAtOnceInsteadOfSilently() async throws {
        let catalog = ShopCatalog(
            assets: [
                CatalogAsset(id: "a", type: .productImage, originalURL: "local:gone-1.jpg"),
                CatalogAsset(id: "b", type: .productImage, originalURL: "local:gone-2.jpg"),
            ])
        let result = await publisher.publish(catalog: catalog)

        guard case .notPublished(let reason) = result else {
            return XCTFail("缺图必须挡在发布头之前，实际 \(result.summary)")
        }
        XCTAssertEqual(publisher.lastStagingIssues.count, 2,
                       "两条缺图都要列出来（原先只报得出第一条）")
        XCTAssertTrue(reason.contains("2 个图片文件"), reason)
        XCTAssertTrue(reason.contains("线上仍是旧版本"), reason)
        XCTAssertEqual(uploadStore.jobs.count, 0,
                       "卡在暂存阶段：一条任务都不该建（这也是界面看不到任务表的原因）")
        XCTAssertEqual(writer.savedReleaseCount, 0)
    }

    func testReleaseConflictIsReportedWithoutForcingOverwrite() async throws {
        let (catalog, _) = try makeLocalImageCatalog(name: "img-conflict.jpg")
        backend.conflictOnReleaseSave = true
        let result = await publisher.publish(catalog: catalog)

        guard case .notPublished(let reason) = result else {
            return XCTFail("冲突只能如实回报，不能强制覆盖，实际 \(result.summary)")
        }
        XCTAssertTrue(reason.contains("冲突"), reason)
        XCTAssertEqual(writer.savedReleaseCount, 0)
        XCTAssertEqual(uploadStore.jobs.first { $0.stage == .release }?.status, .conflict)
    }

    func testReadBackFailureAfterSwitchIsMarkedUnverified() async throws {
        let (catalog, _) = try makeLocalImageCatalog(name: "img-unverified.jpg")
        backend.hideRootOnRead = true
        let result = await publisher.publish(catalog: catalog)

        guard case .publishedButUnverified(let releaseSeq, _) = result else {
            return XCTFail("发布头已切换但回读失败必须标「未验证」，实际 \(result.summary)")
        }
        XCTAssertEqual(releaseSeq, 1)
        XCTAssertEqual(uploadStore.jobs.first { $0.stage == .release }?.status,
                       .publishedButUnverified)
    }

    func testNewImageUnavailableToPublicReaderBlocksReleaseSwitch() async throws {
        let (catalog, _) = try makeLocalImageCatalog(name: "img-public-unavailable.jpg")
        backend.hideMediaOnRead = true
        let result = await publisher.publish(catalog: catalog)
        guard case .notPublished = result else {
            return XCTFail("普通读取拿不到新图片时不能发布，实际 \(result.summary)")
        }
        XCTAssertEqual(writer.savedMediaCount, 1)
        XCTAssertEqual(writer.savedPackCount, 0)
        XCTAssertEqual(writer.savedReleaseCount, 0)
    }

    func testExistingShopLogoIsVerifiedThroughPublicReader() async throws {
        let bytes = Data("existing-shop-logo".utf8)
        let hash = ShopCatalogSyncProtocol.sha256Hex(bytes)
        backend.media[hash] = bytes
        backend.hideMediaOnRead = true
        let catalog = ShopCatalog(shops: [CatalogShop(id: "shop", name: "店家", logo: "thmedia:" + hash)])
        let result = await publisher.publish(catalog: catalog)
        guard case .publishedButUnverified = result else {
            return XCTFail("已有店家图标也必须回读，实际 \(result.summary)")
        }
        XCTAssertEqual(writer.savedMediaCount, 0)
        XCTAssertEqual(writer.savedReleaseCount, 1)
    }
}

// MARK: - 方案二 §5：图片链路失败必须可重试

/// 媒体下载**永远失败**的只读替身，用来数「到底有没有真的去打网络」。
///
/// 走失败路径时 `ShopCatalogMediaStore.download` 在 catch 里直接返回 nil，
/// **不会碰缓存目录**，所以本组用例零落盘、不需要 `useTemporaryForTesting()`。
private actor FailingMediaReader: ShopCatalogPublicReading {
    private(set) var mediaRequestCount = 0

    func fetchReleaseHeader() async throws -> ShopCatalogReleaseHeader {
        throw ShopCatalogSyncError.recordMissing(recordType: "THRelease", recordName: "-")
    }
    func fetchRootIndex() async throws -> Data { Data() }
    func fetchPack(payloadHash: String) async throws -> Data { Data() }
    func fetchMedia(contentHash: String) async throws -> Data {
        mediaRequestCount += 1
        throw ShopCatalogSyncError.recordMissing(recordType: "THMedia", recordName: contentHash)
    }
}

@MainActor
final class ShopCatalogMediaRetryTests: XCTestCase {

    /// 用一个几乎不可能与真实缓存撞车的合成摘要，避免读到宿主里已有的缓存
    private let syntheticKey = String(repeating: "a", count: 64)

    func testFailedDownloadIsRememberedAndRetryReallyRefetches() async {
        let reader = FailingMediaReader()
        let store = ShopCatalogMediaStore(reader: reader)

        let first = await store.resolvedURL(mediaKey: syntheticKey)
        XCTAssertNil(first, "下载失败必须返回 nil，视图才会显示「加载失败 + 重试」占位")
        let afterFirst = await reader.mediaRequestCount
        XCTAssertEqual(afterFirst, 1, "首次应当真的发起一次请求")

        let second = await store.resolvedURL(mediaKey: syntheticKey)
        XCTAssertNil(second)
        let afterSecond = await reader.mediaRequestCount
        XCTAssertEqual(afterSecond, 1, "本次会话内已失败的摘要不再重复打网络（列表滚动会反复命中）")

        store.clearSessionFailure(mediaKey: syntheticKey)
        let third = await store.resolvedURL(mediaKey: syntheticKey)
        XCTAssertNil(third)
        let afterThird = await reader.mediaRequestCount
        XCTAssertEqual(afterThird, 2,
                       "点按重试必须真的重新发起请求 —— 只把视图的 remoteMediaFailed 置回 false 是无效的，"
                       + "store 的会话失败记忆会把它直接挡回来（表现为「点了没反应」）")
    }

    func testClearingOneKeyDoesNotReviveOtherFailures() async {
        let reader = FailingMediaReader()
        let store = ShopCatalogMediaStore(reader: reader)
        let otherKey = String(repeating: "b", count: 64)

        _ = await store.resolvedURL(mediaKey: syntheticKey)
        _ = await store.resolvedURL(mediaKey: otherKey)
        let before = await reader.mediaRequestCount
        XCTAssertEqual(before, 2)

        store.clearSessionFailure(mediaKey: syntheticKey)

        _ = await store.resolvedURL(mediaKey: otherKey)
        let after = await reader.mediaRequestCount
        XCTAssertEqual(after, 2, "重试入口只清自己那一张，不能顺手把别人的失败记忆也清掉")
    }

    func testNilMediaKeyNeverTouchesNetwork() async {
        let reader = FailingMediaReader()
        let store = ShopCatalogMediaStore(reader: reader)

        let url = await store.resolvedURL(mediaKey: nil)
        XCTAssertNil(url)
        let count = await reader.mediaRequestCount
        XCTAssertEqual(count, 0, "没有媒体键就不是远端媒体，不该产生任何网络请求")
    }
}
