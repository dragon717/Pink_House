//
//  ShopCatalogStrictPolicyTests.swift
//  SharedCatalogTests
//
//  严格发布策略的作用域与边界（方案 R08 / T10）。
//
//  ## 这份测试要防的是什么
//
//  1. **一刀切阻断**：把悬空引用 / 裸名字对所有内容都判红，会把已经在线上跑了
//     几个月的存量目录整体标红。存量必须继续走兼容口径 —— 所以严格策略
//     **只作用于本次新增 / 修改过的实体**，这条要用「作用域外不阻断」的负面断言锁死。
//  2. **假绿**：一个长得像 64 位 hex 的字符串**不证明远端真有那份字节**。
//     本机离线判不出来，所以严格模式下这类引用是**告警 + 明确文案**，
//     而不是本机假装通过、也不是假装阻断。真正的核对在发布器第 5 步。
//

import XCTest

@testable import SharedCatalog

final class ShopCatalogStrictPolicyTests: XCTestCase {

    private let mediaHash = String(repeating: "5c", count: 32)
    private let otherHash = String(repeating: "9d", count: 32)
    private let stagedFile = "img-0001.png"

    // MARK: 作用域内：无法解析的引用必须阻断

    func testStrictBlocksBareNameOnTouchedProduct() {
        let catalog = makeCatalog(productImageReference: "cat_jsk_blue.png")
        let review = review(catalog, strict: .strict, scope: ["p-1"])

        XCTAssertTrue(review.isBlocked, "本次新写进去的裸名字必须阻断")
        XCTAssertEqual(review.strictAudit.blockedReferenceCount, 1)
        XCTAssertTrue(review.blockingIssues.contains { $0.contains("严格策略") })
    }

    func testStrictBlocksDanglingAssetIDOnTouchedProduct() {
        let catalog = makeCatalog(productImageReference: "asset:img-not-exist")
        let review = review(catalog, strict: .strict, scope: ["p-1"])

        XCTAssertTrue(review.isBlocked)
        XCTAssertTrue(review.blockingIssues.contains { $0.contains("不存在的图片资源") })
    }

    func testStrictBlocksExternalURLOnTouchedProduct() {
        let catalog = makeCatalog(productImageReference: "https://example.com/a.jpg")
        let review = review(catalog, strict: .strict, scope: ["p-1"])

        XCTAssertTrue(review.isBlocked, "新内容里塞外链必须阻断：撤回与换图都不受控")
        XCTAssertFalse(review.warnings.contains { $0.contains("外部图片地址") })
    }

    // MARK: 作用域外：兼容口径不变（不能一刀切）

    func testStrictLeavesUntouchedEntitiesOnCompatibilityRules() {
        let catalog = makeCatalog(productImageReference: "cat_jsk_blue.png")
        let review = review(catalog, strict: .strict, scope: ["some-other-product"])

        XCTAssertFalse(review.isBlocked, "没动过的商品继续走兼容口径，不得被严格策略标红")
        XCTAssertEqual(review.strictAudit.blockedReferenceCount, 0)
        XCTAssertTrue(
            review.warnings.contains { $0.contains("裸名字") },
            "兼容口径下它仍然要出现在告警里（不能静默）")
        XCTAssertEqual(review.strictAudit.scopeEntityCount, 1)
    }

    func testCompatibilityPolicyIgnoresScopeEntirely() {
        let catalog = makeCatalog(productImageReference: "cat_jsk_blue.png")
        let review = review(catalog, strict: .compatibility, scope: ["p-1"])

        XCTAssertFalse(review.isBlocked)
        XCTAssertEqual(review.strictAudit.blockedReferenceCount, 0)
        XCTAssertEqual(review.strictAudit.scopeEntityCount, 0, "兼容策略不声称有作用对象")
    }

    // MARK: 远端键：未经回读确认只告警，不假装阻断

    func testStrictWarnsUnverifiedRemoteMediaKeyOnTouchedProduct() {
        let catalog = makeCatalog(productImageReference: "thmedia:\(mediaHash)")
        let review = review(catalog, strict: .strict, scope: ["p-1"])

        XCTAssertFalse(review.isBlocked, "本机离线判不出远端有没有那份字节，不能假装阻断")
        XCTAssertEqual(review.strictAudit.unverifiedMediaKeys, [mediaHash])
        XCTAssertTrue(review.warnings.contains { $0.contains("尚未") || $0.contains("回读核对") })
    }

    func testStrictDoesNotWarnWhenKeyWasVerifiedInTargetEnvironment() {
        let catalog = makeCatalog(productImageReference: "thmedia:\(mediaHash)")
        let review = ShopCatalogPublicationGate.review(
            catalog,
            stagedFileNames: [],
            strict: .strict,
            strictScope: ["p-1"],
            verifiedRemoteMediaKeys: [mediaHash],
            targetEnvironmentName: "Development")

        XCTAssertTrue(review.strictAudit.unverifiedMediaKeys.isEmpty)
        XCTAssertFalse(review.warnings.contains { $0.contains("回读核对") })
    }

    func testStrictWarnsForCanonicalMediaKeyFieldToo() {
        let catalog = makeCatalog(productImageReference: mediaHash)
        let review = review(catalog, strict: .strict, scope: ["p-1"])

        XCTAssertEqual(review.strictAudit.unverifiedMediaKeys, [mediaHash])
    }

    // MARK: 本来就没问题的引用

    func testStagedLocalFileIsAlwaysFine() {
        let catalog = makeCatalog(productImageReference: "local:\(stagedFile)")
        let review = review(catalog, strict: .strict, scope: ["p-1"], stagedFileNames: [stagedFile])

        XCTAssertFalse(review.isBlocked)
        XCTAssertEqual(review.requiredStagedFileNames, [stagedFile])
    }

    func testMissingLocalFileBlocksInBothPolicies() {
        for policy in [ShopCatalogStrictPolicy.compatibility, .strict] {
            let catalog = makeCatalog(productImageReference: "local:\(stagedFile)")
            let review = review(catalog, strict: policy, scope: ["p-1"], stagedFileNames: [])

            XCTAssertTrue(review.isBlocked, "缺图在两种策略下都必须阻断（\(policy.rawValue)）")
            XCTAssertTrue(review.blockingIssues.contains { $0.contains("在本机找不到文件") })
        }
    }

    func testBundledReferenceIsFineInStrictMode() {
        let catalog = makeCatalog(productImageReference: "bundle:cat_jsk_blue.png")
        let review = review(catalog, strict: .strict, scope: ["p-1"])
        XCTAssertFalse(review.isBlocked)
    }

    // MARK: 审计文案

    func testScopeTextExplainsEmptyScope() {
        let audit = ShopCatalogStrictAudit(policy: .strict, scopeEntityCount: 0)
        XCTAssertTrue(audit.scopeText.contains("没有额外收紧对象"))
    }

    // MARK: 夹具

    private func review(
        _ catalog: ShopCatalog,
        strict: ShopCatalogStrictPolicy,
        scope: Set<String>,
        stagedFileNames: Set<String> = []
    ) -> ShopCatalogPublicationReview {
        ShopCatalogPublicationGate.review(
            catalog,
            stagedFileNames: stagedFileNames,
            strict: strict,
            strictScope: scope,
            targetEnvironmentName: "Development")
    }

    /// 只造「一个商品 + 一个图片资源」，把噪声压到最低：
    /// 商品图引用由参数指定，asset 三个 URL 字段填另一个合法的远端键，
    /// 这样断言只会命中被测的那条引用。
    private func makeCatalog(productImageReference: String) -> ShopCatalog {
        var catalog = ShopCatalog()
        catalog.shops = [CatalogShop(id: "shop-1", name: "樱花小羊")]
        catalog.series = [CatalogSeries(id: "series-1", shopID: "shop-1", name: "星月夜")]
        catalog.assets = [CatalogAsset(
            id: "img-1",
            type: .productImage,
            thumbnailURL: "thmedia:\(otherHash)",
            previewURL: "thmedia:\(otherHash)",
            originalURL: "thmedia:\(otherHash)",
            mediaKey: otherHash)]
        catalog.products = [CatalogProduct(
            id: "p-1",
            shopID: "shop-1",
            seriesID: "series-1",
            name: "星月夜 JSK",
            category: "JSK",
            images: [productImageReference])]
        return catalog
    }
}
