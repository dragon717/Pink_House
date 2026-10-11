import XCTest
import UIKit
import SwiftUI
@testable import ItemManager

/// 显式选择的 Development 真机验收。普通 test 默认跳过；不替换用户覆盖层。
/// 先运行创建用例，由 Mac 独立回读，再运行删除/冷缓存用例。
@MainActor
final class ShopCatalogStageCLiveTests: XCTestCase {
    private let prefix = "stage-c-20261009"

    private func requireLiveDevelopment() async throws {
        #if !DEBUG
        throw XCTSkip("阶段 C 只能运行 Debug / Development")
        #endif
        try XCTSkipIf(ProcessInfo.processInfo.environment["PINK_HOUSE_STAGE_C_LIVE"] != "1",
                      "真实联网写入须显式选择阶段 C 验收")
        guard await NoticeCloudKitService.shared.creatorGate() == .allowed else {
            XCTFail("当前测试设备账号未命中既有运营名单；没有上传，也不自动扩大权限")
            throw ShopCatalogOpsUploadError.blocked("当前设备不是已有运营账号")
        }
        try await ShopCatalogOpsPublicCloudWriter().ensureWritableAccount()
    }

    private func isolateStorage() {
        ShopCatalogStorage.useTemporaryForTesting()
        ShopCatalogSyncStorage.useTemporaryForTesting()
    }

    private func restoreStorage() {
        ShopCatalogSyncStorage.restoreDefaultForTesting()
        ShopCatalogStorage.restoreDefaultForTesting()
    }

    private func readCatalog(_ reader: ShopCatalogPublicCloudReader) async throws
        -> (ShopCatalogReleaseHeader, ShopCatalog, String) {
        let head = try await reader.fetchReleaseHeader()
        let rootData = try await reader.fetchRootIndex()
        let root = try ShopCatalogJSONCoding.decoder().decode(ShopCatalogRootIndex.self, from: rootData)
        let partition = try XCTUnwrap(root.shopCatalogPartition)
        let pack = try await reader.fetchPack(payloadHash: partition.payloadHash)
        let catalog = try ShopCatalogCloudSyncValidator.validatedShopCatalog(
            header: head, rootIndexData: rootData, packCompressed: pack)
        return (head, catalog, partition.payloadHash)
    }

    private func remember(_ header: ShopCatalogReleaseHeader) throws {
        try ShopCatalogPackCache.savePublicationBaseline(ShopCatalogBaseline(
            releaseSeq: header.releaseSeq, rootIndexHash: header.rootIndexHash,
            environment: "development", observedAt: Date()))
    }

    private func attachReport(_ values: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "stage-c-live-report.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[StageC] " + String(decoding: data, as: UTF8.self))
    }

    private func attachRenderedGallery(_ hashes: [String]) async throws {
        let host = UIHostingController(rootView:
            VStack(spacing: 8) {
                Text("阶段 C：空缓存重新取回的图片")
                HStack {
                    ForEach(hashes, id: \.self) { hash in
                        ShopCatalogAssetImage(reference: "thmedia:" + hash, contentMode: .fit)
                            .frame(width: 60, height: 64)
                    }
                }
            }.frame(width: 360, height: 140).background(Color.white))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 140))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(1))
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "stage-c-empty-cache-gallery.png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCreateAndPublishOnDevelopment() async throws {
        try await requireLiveDevelopment()
        isolateStorage()
        defer { restoreStorage() }
        let reader = ShopCatalogPublicCloudReader()
        let (before, existing, _) = try await readCatalog(reader)
        let expectedSeq = Int(ProcessInfo.processInfo.environment["PINK_HOUSE_STAGE_C_EXPECTED_SEQ"] ?? "")
        let expectedHash = ProcessInfo.processInfo.environment["PINK_HOUSE_STAGE_C_EXPECTED_ROOT_HASH"]
        guard expectedSeq == before.releaseSeq, expectedHash == before.rootIndexHash else {
            throw ShopCatalogOpsUploadError.conflict("手机读取结果与电脑刚核对的试用区不一致；未上传")
        }
        guard !existing.shops.contains(where: { $0.id == prefix + "-shop" }) else {
            throw ShopCatalogOpsUploadError.conflict("验收店家已存在，停止重复创建；先核对已有运行记录")
        }
        var catalog = existing
        var refs: [String] = []
        var hashes: [String] = []
        for index in 0..<5 {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
            let image = renderer.image { context in
                UIColor(hue: CGFloat(index) / 5, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
                ("C\(index + 1)" as NSString).draw(at: CGPoint(x: 12, y: 18),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.white])
            }
            let data = try XCTUnwrap(image.pngData())
            let file = "\(prefix)-\(index).png"
            try data.write(to: ShopCatalogImageStore.directory.appendingPathComponent(file))
            refs.append("local:" + file)
            hashes.append(ShopCatalogSyncProtocol.sha256Hex(data))
        }
        catalog.shops.append(CatalogShop(id: prefix + "-shop", name: "阶段C手机验收店家",
                                        logo: refs[0], cover: refs[0], description: "专用验收资料"))
        catalog.series.append(CatalogSeries(id: prefix + "-series", shopID: prefix + "-shop",
                                            name: "阶段C手机验收系列", cover: refs[1]))
        let assetIDs = (2..<5).map { prefix + "-asset-\($0)" }
        catalog.products.append(CatalogProduct(id: prefix + "-product", shopID: prefix + "-shop",
            seriesID: prefix + "-series", name: "阶段C手机验收商品（非售卖）", category: "其他", images: assetIDs))
        for index in 2..<5 {
            catalog.assets.append(CatalogAsset(id: prefix + "-asset-\(index)", type: .productImage,
                                                originalURL: refs[index]))
        }
        try remember(before)
        let publisher = ShopCatalogOpsPublisher(uploadStore: ShopCatalogOpsUploadStore(inMemory: true))
        let result = await publisher.publish(catalog: catalog)
        XCTAssertTrue(publisher.lastStagingIssues.isEmpty)
        guard case .published(let seq, let count) = result else {
            XCTFail(result.summary); throw ShopCatalogOpsUploadError.failed(result.summary)
        }
        XCTAssertEqual(seq, before.releaseSeq + 1)
        XCTAssertEqual(count, 5)
        let (after, remote, payloadHash) = try await readCatalog(reader)
        XCTAssertEqual(after.releaseSeq, seq)
        XCTAssertTrue(remote.products.contains { $0.id == prefix + "-product" })
        XCTAssertTrue(existing.shops.allSatisfy { old in remote.shops.contains { $0.id == old.id } })
        for hash in hashes {
            let bytes = try await reader.fetchMedia(contentHash: hash)
            XCTAssertEqual(ShopCatalogSyncProtocol.sha256Hex(bytes), hash)
            XCTAssertNotNil(UIImage(data: bytes))
        }
        try attachReport(["phase": "create", "environment": "development", "beforeSeq": before.releaseSeq,
            "afterSeq": seq, "rootIndexHash": after.rootIndexHash, "payloadHash": payloadHash,
            "fixturePrefix": prefix, "mediaHashes": hashes, "mediaCount": count,
            "uploaded": publisher.lastMediaStats?.uploaded ?? -1,
            "skipped": publisher.lastMediaStats?.skipped ?? -1,
            "failed": publisher.lastMediaStats?.failed ?? -1,
            "readBackVerified": true, "existingCatalogPreserved": true, "userOverlayReplaced": false])
    }

    func testDeleteAndReadFromEmptyCacheOnDevelopment() async throws {
        try await requireLiveDevelopment()
        isolateStorage()
        defer { restoreStorage() }
        let reader = ShopCatalogPublicCloudReader()
        let (before, existing, historicalHash) = try await readCatalog(reader)
        let expectedSeq = Int(ProcessInfo.processInfo.environment["PINK_HOUSE_STAGE_C_EXPECTED_SEQ"] ?? "")
        let expectedHash = ProcessInfo.processInfo.environment["PINK_HOUSE_STAGE_C_EXPECTED_ROOT_HASH"]
        guard expectedSeq == before.releaseSeq, expectedHash == before.rootIndexHash else {
            throw ShopCatalogOpsUploadError.conflict("手机读取结果与电脑刚核对的试用区不一致；未删除")
        }
        let product = try XCTUnwrap(existing.products.first { $0.id == prefix + "-product" })
        let shop = try XCTUnwrap(existing.shops.first { $0.id == prefix + "-shop" })
        let series = try XCTUnwrap(existing.series.first { $0.id == prefix + "-series" })
        let assets = existing.assets.filter { product.images.contains($0.id) }
        let references = [shop.logo, series.cover].compactMap { $0 } + assets.map(\.originalURL)
        let hashes = references.compactMap {
            ShopCatalogSyncProtocol.resolvedMediaKey(nil, fallbackReferences: [$0])
        }
        XCTAssertEqual(Set(hashes).count, 5)
        var catalog = existing
        catalog.products.removeAll { $0.id == product.id }
        catalog.assets.removeAll { product.images.contains($0.id) }
        catalog.removedProductIDs.append(product.id)
        try remember(before)
        let publisher = ShopCatalogOpsPublisher(uploadStore: ShopCatalogOpsUploadStore(inMemory: true))
        let result = await publisher.publish(catalog: catalog)
        guard case .published(let seq, _) = result else {
            XCTFail(result.summary); throw ShopCatalogOpsUploadError.failed(result.summary)
        }
        XCTAssertEqual(seq, before.releaseSeq + 1)
        XCTAssertTrue(ShopCatalogStorage.isTestOverridden && ShopCatalogSyncStorage.isTestOverridden)
        _ = ShopCatalogPackCache.clearDownloadedContent()
        _ = ShopCatalogPackCache.clearDownloadedMedia()
        let store = ShopCatalogStore(baseCatalog: ShopCatalog())
        let consumer = ShopCatalogCloudSyncService(reader: reader, store: store)
        await consumer.syncIfNeeded(force: true)
        let installed = try XCTUnwrap(store.catalog)
        XCTAssertFalse(consumer.state.isFailure)
        XCTAssertFalse(installed.products.contains { $0.id == product.id })
        XCTAssertTrue(installed.removedProductIDs.contains(product.id))
        XCTAssertEqual(installed.shops.first { $0.id == shop.id }?.name, shop.name)
        XCTAssertEqual(installed.series.first { $0.id == series.id }?.name, series.name)
        let mediaStore = ShopCatalogMediaStore(reader: reader)
        for hash in hashes {
            XCTAssertNil(ShopCatalogPackCache.cachedMediaURL(contentHash: hash))
            let resolved = await mediaStore.resolvedURL(mediaKey: hash)
            let url = try XCTUnwrap(resolved)
            let data = try Data(contentsOf: url)
            XCTAssertEqual(ShopCatalogSyncProtocol.sha256Hex(data), hash)
            XCTAssertNotNil(UIImage(data: data))
        }
        try await attachRenderedGallery(hashes)
        let history = try await reader.fetchPack(payloadHash: historicalHash)
        XCTAssertEqual(ShopCatalogSyncProtocol.sha256Hex(history), historicalHash)
        let reloadedStore = ShopCatalogStore(baseCatalog: ShopCatalog())
        let coldConsumer = ShopCatalogCloudSyncService(reader: reader, store: reloadedStore)
        await coldConsumer.syncIfNeeded(force: true)
        XCTAssertFalse(coldConsumer.state.isFailure)
        XCTAssertFalse(reloadedStore.catalog?.products.contains { $0.id == product.id } ?? true)
        try attachReport(["phase": "delete-and-empty-cache", "environment": "development",
            "beforeSeq": before.releaseSeq, "afterSeq": seq, "fixturePrefix": prefix,
            "removedProductID": product.id, "mediaHashes": hashes, "fiveCachedImagesHashMatch": true,
            "decodedImages": 5, "deletedProductAbsent": true, "historicalPackRetained": true,
            "coldStartRestored": true, "cacheClearedOnlyInIsolatedTestStorage": true,
            "userOverlayReplaced": false])
    }
}
