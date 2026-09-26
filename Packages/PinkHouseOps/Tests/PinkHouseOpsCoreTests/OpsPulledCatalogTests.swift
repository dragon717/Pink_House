//
//  OpsPulledCatalogTests.swift
//  PinkHouseOpsTests
//
//  「从线上拉回基线」的产物模型与采用判定（方案 §5 / R07）的回归锁。
//
//  ## 为什么这些用例值得存在
//
//  这条通道补的是一个**真缺口**：在此之前 App 只能「导入 JSON」，
//  线上基线的内容全靠人手导出 / 导入 —— 而桥接器因此**从不读**
//  `baseReleaseSeq` / `baseRootIndexHash`，R07 的「发布前检测过期基线」等于没落地。
//
//  通道加进来之后，风险从「做不到」变成了「做错」：
//    · 把「线上是空的」说成「拉回了一份空目录」；
//    · 把「已下发口径」（不含归档条目、图片是 thmedia:）静默当成完整备份；
//    · 在损坏草稿上替换内容（覆盖掉唯一那份坏记录 = R03 最怕的事）。
//  三者都不会崩、都不会报错，只会让运营**信一个错的事实**。所以在这里钉死。
//

import XCTest
@testable import PinkHouseOpsCore
import SharedCatalog

final class OpsPulledCatalogTests: XCTestCase {

    // MARK: - 夹具

    private func makeCatalog(
        releaseSeq: Int = 6,
        rootIndexHash: String? = String(repeating: "a", count: 64),
        payloadHash: String? = String(repeating: "b", count: 64),
        counts: [String: Int] = ["shops": 2, "series": 9, "products": 263],
        environment: String = "development",
        path: String = "/tmp/pull/shop-catalog.json"
    ) -> OpsPulledCatalog {
        OpsPulledCatalog(
            path: path,
            environment: environment,
            releaseSeq: releaseSeq,
            rootIndexHash: rootIndexHash,
            payloadHash: payloadHash,
            itemCounts: counts,
            pulledAt: Date(timeIntervalSince1970: 1_772_000_000))
    }

    private func makeResult(
        catalogPath: String? = "/tmp/pull/shop-catalog.json",
        itemCounts: [String: Int]? = ["products": 3],
        payloadHash: String? = "deadbeef",
        head: ShopCatalogOnlineHead? = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 6,
            rootIndexHash: String(repeating: "a", count: 64))
    ) -> OpsBridgeRunResult {
        var result = OpsBridgeRunResult(
            exitCode: 0,
            events: [],
            nonJSONLines: [],
            executablePath: "/usr/bin/true",
            scriptPath: "/tmp/ops_publish_bridge.py")
        result.onlineHead = head
        result.pulledCatalogPath = catalogPath
        result.pulledCatalogItemCounts = itemCounts
        result.pulledCatalogPayloadHash = payloadHash
        return result
    }

    // MARK: - 模式本身

    /// rawValue 是**带连字符**的：写错的话桥接器的 `--mode` 会被 argparse 直接拒，
    /// 但错误只表现为一句 usage，看不出是我们这边拼错。
    func testPullCatalogRawValueMatchesBridgeCLI() {
        XCTAssertEqual(OpsBridgeMode.pullCatalog.rawValue, "pull-catalog")
    }

    /// ⭐ 只有 `publish` 会写远端。这条锁住的是「界面文案读哪个属性」——
    /// 一旦有人把 `writesRemote` 改成恒真，只读操作会被自己吓成会覆盖线上。
    func testOnlyPublishWritesRemote() {
        XCTAssertTrue(OpsBridgeMode.publish.writesRemote)
        XCTAssertFalse(OpsBridgeMode.baseline.writesRemote)
        XCTAssertFalse(OpsBridgeMode.query.writesRemote)
        XCTAssertFalse(OpsBridgeMode.pullCatalog.writesRemote)
    }

    /// 四种模式的显示名必须互不相同（界面上按钮文案重复 = 点错入口）。
    func testModeDisplayNamesAreDistinct() {
        let names = [OpsBridgeMode.baseline, .publish, .query, .pullCatalog].map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count, "显示名重复：\(names)")
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    // MARK: - 从运行结果取产物

    func testFromResultCarriesHeadCountsAndPayload() {
        let pulled = OpsPulledCatalog.from(
            result: makeResult(), environment: "development")
        XCTAssertNotNil(pulled)
        XCTAssertEqual(pulled?.path, "/tmp/pull/shop-catalog.json")
        XCTAssertEqual(pulled?.environment, "development")
        XCTAssertEqual(pulled?.releaseSeq, 6)
        XCTAssertEqual(pulled?.rootIndexHash, String(repeating: "a", count: 64))
        XCTAssertEqual(pulled?.payloadHash, "deadbeef")
        XCTAssertEqual(pulled?.itemCounts["products"], 3)
    }

    /// ⭐ 没有 `catalog` 事件时必须返回 nil —— **绝不去猜输出目录下的文件名**。
    /// 猜的话，「线上是空的」会被当成「拉回了一份空目录」，运营据此会把
    /// 自己的本地内容当成线上基线（正好是反的）。
    func testFromResultWithoutCatalogEventIsNil() {
        XCTAssertNil(OpsPulledCatalog.from(
            result: makeResult(catalogPath: nil), environment: "development"))
    }

    func testFromResultIgnoresEmptyPath() {
        XCTAssertNil(OpsPulledCatalog.from(
            result: makeResult(catalogPath: ""), environment: "development"))
    }

    /// 线上没有发布头时 `head_payload` 只给 `releaseSeq: 0`：
    /// 产物要如实反映「发布号 0、摘要没读到」，而不是编一个号。
    func testFromResultWithOnlySequenceStillWorks() {
        let head = ShopCatalogOnlineHead(environment: "development", releaseSeq: 0)
        let pulled = OpsPulledCatalog.from(
            result: makeResult(head: head), environment: "development")
        XCTAssertEqual(pulled?.releaseSeq, 0)
        XCTAssertNil(pulled?.rootIndexHash)
    }

    // MARK: - 条数

    /// 撤回清单（`removedXxxIDs`）是「删掉了什么」，**不是「有什么」** ——
    /// 混进总数会让运营以为拉回来的东西更多。
    func testEntityCountExcludesTombstones() {
        let pulled = makeCatalog(counts: [
            "shops": 2, "products": 263,
            "removedProductIDs": 7, "removedShopIDs": 1,
        ])
        XCTAssertEqual(pulled.entityCount, 265)
    }

    /// 顺序固定（写死的展示顺序），空条目不出现。
    func testSortedItemCountsIsOrderedAndSkipsZero() {
        let pulled = makeCatalog(counts: [
            "products": 3, "shops": 1,
            "series": 0, "variants": 4,
            "removedShopIDs": 2,
        ])
        let rows = pulled.sortedItemCounts
        XCTAssertEqual(rows.map(\.field), ["shops", "products", "variants", "removedShopIDs"])
        XCTAssertEqual(rows.map(\.label), ["店家", "商品", "规格", "撤回店家"])
        XCTAssertEqual(rows.map(\.count), [1, 3, 4, 2])
    }

    /// `id` 必须是字段名 —— 它同时是视图 `ForEach` 的键。
    func testItemCountIdentityIsFieldName() {
        let rows = makeCatalog().sortedItemCounts
        XCTAssertEqual(rows.map(\.id), rows.map(\.field))
    }

    func testCountsTextSkipsTombstonesAndIsEmptyForEmptyCatalog() {
        XCTAssertEqual(
            makeCatalog(counts: ["shops": 2, "series": 9, "products": 263,
                                 "removedProductIDs": 7]).countsText,
            "店家 2 / 系列 9 / 商品 263")
        XCTAssertEqual(makeCatalog(counts: [:]).countsText, "（空目录）")
    }

    func testHashTextNeverClaimsHashWhenMissing() {
        XCTAssertEqual(makeCatalog(rootIndexHash: nil).hashText, "摘要未读到")
        XCTAssertEqual(makeCatalog(rootIndexHash: "").hashText, "摘要未读到")
        XCTAssertEqual(makeCatalog(rootIndexHash: String(repeating: "a", count: 64)).hashText,
                       "aaaaaaaaaaaa…")
    }

    func testLabelFallsBackToFieldNameForUnknownField() {
        XCTAssertEqual(OpsPulledCatalog.label(for: "products"), "商品")
        XCTAssertEqual(OpsPulledCatalog.label(for: "somethingNew"), "somethingNew")
    }

    /// 展示表必须覆盖载荷的全部字段口径（漏一个 = 界面上那一类数字永远不显示）。
    func testOrderedFieldsCoverEveryPayloadField() {
        let covered = Set(OpsPulledCatalog.orderedFields.map(\.field))
        XCTAssertEqual(covered, Set(OpsPulledCatalog.entityFields + OpsPulledCatalog.tombstoneFields))
        XCTAssertEqual(OpsPulledCatalog.orderedFields.count,
                       OpsPulledCatalog.entityFields.count + OpsPulledCatalog.tombstoneFields.count)
    }

    // MARK: - 阻断项

    func testBlockersAreEmptyWhenEverythingIsFine() {
        let blockers = OpsPulledCatalogAdoption.blockers(
            pulled: makeCatalog(), isDraftCorrupted: false, isCatalogFileReadable: true)
        XCTAssertTrue(blockers.isEmpty, "\(blockers)")
    }

    /// 判「读不读得到」**不能**只判存在：沙盒下 `fileExists` 会返回 true
    /// 而真读是 `Operation not permitted`。所以这里收的是调用方的真读结论。
    func testBlockersRejectUnreadableCatalogFile() {
        let blockers = OpsPulledCatalogAdoption.blockers(
            pulled: makeCatalog(), isDraftCorrupted: false, isCatalogFileReadable: false)
        XCTAssertEqual(blockers.count, 1)
        XCTAssertTrue(blockers[0].contains("/tmp/pull/shop-catalog.json"), blockers[0])
    }

    /// 损坏草稿上替换 = 覆盖掉唯一那份坏记录（R03 要防的事），必须拒。
    func testBlockersRejectCorruptedDraft() {
        let blockers = OpsPulledCatalogAdoption.blockers(
            pulled: makeCatalog(), isDraftCorrupted: true, isCatalogFileReadable: true)
        XCTAssertEqual(blockers.count, 1)
        XCTAssertTrue(blockers[0].contains("另存为新草稿"), blockers[0])
    }

    func testBothBlockersCanFireTogether() {
        let blockers = OpsPulledCatalogAdoption.blockers(
            pulled: makeCatalog(), isDraftCorrupted: true, isCatalogFileReadable: false)
        XCTAssertEqual(blockers.count, 2)
    }

    // MARK: - 替换前的告知

    /// ⭐ 最关键的一条：**「已下发口径」必须说出来**。
    /// 不说的后果是运营把拉回当成「完整备份」，然后发现归档内容没了、图全缺。
    func testCaveatsAlwaysStateReplacementAndDownstreamScope() {
        let notes = OpsPulledCatalogAdoption.caveats(pulled: makeCatalog()).joined(separator: "\n")
        XCTAssertTrue(notes.contains("替换"), notes)
        XCTAssertTrue(notes.contains("归档"), notes)
        XCTAssertTrue(notes.contains("thmedia:"), notes)
    }

    /// 摘要没读到时**不能**让界面有机会写「摘要一致」。
    func testCaveatsMentionMissingRootIndexHash() {
        let notes = OpsPulledCatalogAdoption.caveats(
            pulled: makeCatalog(rootIndexHash: nil)).joined(separator: "\n")
        XCTAssertTrue(notes.contains("没读到线上根清单摘要"), notes)

        let withHash = OpsPulledCatalogAdoption.caveats(
            pulled: makeCatalog()).joined(separator: "\n")
        XCTAssertFalse(withHash.contains("没读到线上根清单摘要"), withHash)
    }

    func testCaveatsReportCountDeltaWhenLocalDiffers() {
        let notes = OpsPulledCatalogAdoption.caveats(
            pulled: makeCatalog(counts: ["products": 10]),
            currentItemCounts: ["products": 4]).joined(separator: "\n")
        XCTAssertTrue(notes.contains("从 4 变成 10"), notes)
        XCTAssertTrue(notes.contains("净增 6"), notes)
    }

    /// 数量相同时不啰嗦（「从 263 变成 263」是纯噪音）。
    func testCaveatsStayQuietWhenCountsMatch() {
        let notes = OpsPulledCatalogAdoption.caveats(
            pulled: makeCatalog(counts: ["products": 4]),
            currentItemCounts: ["products": 4]).joined(separator: "\n")
        XCTAssertFalse(notes.contains("变成"), notes)
    }

    /// 没有本地内容可比时（还没导入过）不加数量那一句。
    func testCaveatsSkipDeltaWhenNoLocalCounts() {
        let notes = OpsPulledCatalogAdoption.caveats(
            pulled: makeCatalog(), currentItemCounts: nil).joined(separator: "\n")
        XCTAssertFalse(notes.contains("变成"), notes)
        XCTAssertFalse(notes.contains("条数"), notes)
    }

    func testDeltaTextHasDirection() {
        XCTAssertEqual(OpsPulledCatalogAdoption.deltaText(from: 4, to: 4), "条数不变")
        XCTAssertEqual(OpsPulledCatalogAdoption.deltaText(from: 4, to: 10), "净增 6")
        XCTAssertEqual(OpsPulledCatalogAdoption.deltaText(from: 10, to: 4), "净减 6")
    }

    // MARK: - 采用之后的基线

    /// ⭐ **环境必须带上**：拿 Development 的基线去核对 Production 是必然误判，
    /// 而判定器正是靠 `baseline.environment` 才认得出这件事。
    func testBaselineAfterAdoptingCarriesEnvironmentAndSequence() {
        let pulled = makeCatalog(releaseSeq: 6, environment: "development")
        let baseline = OpsPulledCatalogAdoption.baseline(afterAdopting: pulled)
        XCTAssertEqual(baseline.releaseSeq, 6)
        XCTAssertEqual(baseline.rootIndexHash, pulled.rootIndexHash)
        XCTAssertEqual(baseline.environment, "development")
        XCTAssertEqual(baseline.observedAt, pulled.pulledAt)
        XCTAssertTrue(baseline.isKnown)
    }

    /// 采用之后立刻核对：草稿基线 vs 同一个线上头 → **一致**（不是过期、不是未核对）。
    /// 这条断了就意味着「刚拉回就显示基线过期」，运营会以为拉回没用。
    func testHeadAfterAdoptingResolvesToCurrent() {
        let pulled = makeCatalog(releaseSeq: 6, environment: "development")
        let baseline = OpsPulledCatalogAdoption.baseline(afterAdopting: pulled)
        let head = OpsPulledCatalogAdoption.head(afterAdopting: pulled)
        XCTAssertEqual(head.releaseSeq, 6)
        XCTAssertEqual(head.environment, "development")

        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head)
        XCTAssertTrue(verdict.isVerified, "\(verdict.displayName)")
        XCTAssertFalse(verdict.isBlocking)
        if case .current = verdict {} else { XCTFail("期望 .current，实得 \(verdict)") }
    }

    /// 换了环境之后再拿同一个头核对 → 必须判成过期并点名「环境不可比」，
    /// 而不是悄悄按发布号比过去。
    func testHeadFromOtherEnvironmentIsRejectedByResolver() {
        let pulled = makeCatalog(releaseSeq: 6, environment: "production")
        let baseline = OpsPulledCatalogAdoption.baseline(afterAdopting: pulled)
        // 换成 development 的头（发布号恰好相同）
        let devHead = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 6,
            rootIndexHash: pulled.rootIndexHash)
        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: devHead)
        if case .stale(_, let reasons) = verdict {
            XCTAssertTrue(reasons.joined().contains("不可比"), "\(reasons)")
        } else {
            XCTFail("期望 .stale，实得 \(verdict)")
        }
    }

    /// 摘要没读到（`head_payload` 没回吐）时，基线仍然可用 ——
    /// 但只按发布号比，判定器给出的建议里必须说清「只比了发布号」。
    func testBaselineWithoutHashStillVerifiesBySequenceOnly() {
        let pulled = makeCatalog(releaseSeq: 3, rootIndexHash: nil)
        let baseline = OpsPulledCatalogAdoption.baseline(afterAdopting: pulled)
        let head = OpsPulledCatalogAdoption.head(afterAdopting: pulled)
        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head)
        if case .current(let value) = verdict {
            XCTAssertEqual(value?.hasRootIndexHash, false)
        } else {
            XCTFail("期望 .current，实得 \(verdict)")
        }
    }
}
