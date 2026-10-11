import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsSyncMediaRecoveryTests: XCTestCase {
    private let localHash = String(repeating: "a", count: 64)
    private let remoteHash = String(repeating: "b", count: 64)

    private func catalog(_ hash: String) -> ShopCatalog {
        var shop = CatalogShop(id: hash, name: "店家")
        shop.logo = "thmedia:" + hash
        return ShopCatalog(shops: [shop])
    }

    @MainActor
    func testProductionDownloadsLocalReferencesAndRecoversOnlyMissingOnesFromDevelopment() async {
        var available: Set<String> = []
        var calls: [(String, [String])] = []
        let result = await OpsSyncMediaRecovery.download(local: catalog(localHash), remote: catalog(remoteHash),
            environment: "production", available: { available }, fetch: { hashes, environment in
                calls.append((environment, hashes))
                return .init(directory: "fixture", environment: environment,
                    files: [.init(contentHash: environment == "production" ? self.remoteHash : self.localHash, fileName: "fixture.png")],
                    missing: environment == "production" ? [self.localHash] : [])
            }, receive: { available.formUnion($0.files.map(\.contentHash)) })
        XCTAssertEqual(calls.map(\.0), ["production", "development"])
        XCTAssertEqual(calls.map(\.1), [[localHash, remoteHash], [localHash]])
        XCTAssertEqual(result.requested, [localHash, remoteHash])
        XCTAssertTrue(result.unresolved.isEmpty)

        var repeatedCalls = 0
        let repeated = await OpsSyncMediaRecovery.download(local: catalog(localHash), remote: catalog(remoteHash),
            environment: "production", available: { available }, fetch: { _, _ in repeatedCalls += 1; return nil }, receive: { _ in })
        XCTAssertTrue(repeated.requested.isEmpty)
        XCTAssertEqual(repeatedCalls, 0)
    }

    @MainActor
    func testNetworkCorruptionAndUnknownResultsCannotTriggerOtherEnvironmentLookup() async {
        for status in ["network", "corrupt", "pending"] {
            var calls = 0
            let result = await OpsSyncMediaRecovery.download(local: catalog(localHash), remote: ShopCatalog(),
                environment: "production", available: { [] }, fetch: { _, environment in
                    calls += 1
                    if status == "network" { return nil }
                    return .init(directory: "fixture", environment: environment,
                        corrupt: status == "corrupt" ? [self.localHash] : [],
                        pending: status == "pending" ? [self.localHash] : [])
                }, receive: { _ in })
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(result.unresolved, [localHash])
        }
    }

    @MainActor
    func testProductionPublishedImageCannotBeSilentlyRecoveredFromAnotherEnvironment() async {
        var calls = 0
        let result = await OpsSyncMediaRecovery.download(local: catalog(remoteHash), remote: catalog(remoteHash),
            environment: "production", available: { [] }, fetch: { _, environment in
                calls += 1
                return .init(directory: "fixture", environment: environment, missing: [self.remoteHash])
            }, receive: { _ in })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(result.unresolved, [remoteHash])
    }

    @MainActor
    func testUnverifiedOrWrongEnvironmentFilesRemainBlocked() async {
        for sourceEnvironment in ["development", "production"] {
            let result = await OpsSyncMediaRecovery.download(local: catalog(localHash), remote: ShopCatalog(),
                environment: "production", available: { [] }, fetch: { _, environment in
                    if environment == "production" {
                        return .init(directory: "fixture", environment: environment, missing: [self.localHash])
                    }
                    return .init(directory: "fixture", environment: sourceEnvironment,
                        files: [.init(contentHash: self.localHash, fileName: "corrupt.png")])
                }, receive: { _ in /* staging 没有接纳字节，不能凭 manifest 声称补齐。 */ })
            XCTAssertEqual(result.unresolved, [localHash])
            XCTAssertEqual(result.downloads.count, sourceEnvironment == "development" ? 2 : 1)
        }
    }

    @MainActor
    func testDevelopmentNeverLooksUpProductionAndKeepsUnresolvedImages() async {
        var calls: [String] = []
        let result = await OpsSyncMediaRecovery.download(local: catalog(localHash), remote: ShopCatalog(),
            environment: "development", available: { [] }, fetch: { _, environment in
                calls.append(environment)
                return .init(directory: "fixture", environment: environment, missing: [self.localHash])
            }, receive: { _ in })
        XCTAssertEqual(calls, ["development"])
        XCTAssertEqual(result.unresolved, [localHash])
    }
}
