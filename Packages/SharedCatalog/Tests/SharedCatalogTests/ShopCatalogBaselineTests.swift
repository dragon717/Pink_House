//
//  ShopCatalogBaselineTests.swift
//  SharedCatalogTests
//
//  发布基线与「基线过期」判定（方案 R07 / T13）。
//
//  ## 这份测试要防的是什么
//
//  两个运营从同一基线改**不同**商品，A 先发、B 后发。Mac 草稿是**完整目录**，
//  于是 B 的整包会把 A 的改动整体抹掉，而线上看不出来（B 的目录本身合法完整）。
//
//  所以判定必须做到三件事，缺一不可：
//    1. 「没读到线上」≠「线上没问题」—— 前者是 `unverified`，界面不得显示「已核对」；
//    2. 「线上确实还没发过」≠「没读到」—— 前者是 `releaseSeq = 0` 的正常首次发布；
//    3. 「线上已经前进」必须**阻断**，而不是提示一句就放过。
//
//  另外锁一条容易写反的：拿 Development 的基线去核对 Production 的发布头，
//  结论是「不可比」（过期的一种），**不能**碰巧比出相等就说一致。
//

import XCTest

@testable import SharedCatalog

final class ShopCatalogBaselineTests: XCTestCase {

    private let hashCurrent = String(repeating: "ab", count: 32)
    private let hashNewer = String(repeating: "cd", count: 32)

    // MARK: 未核对

    func testMissingOnlineHeadIsUnverifiedNotCurrent() {
        let baseline = ShopCatalogBaseline(releaseSeq: 3, rootIndexHash: hashCurrent)
        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: nil)

        guard case .unverified = verdict else {
            return XCTFail("没读到线上发布头必须是 unverified，实际 \(verdict)")
        }
        XCTAssertFalse(verdict.isVerified, "没读到线上时不得声称已核对")
        XCTAssertFalse(verdict.isBlocking, "未核对不阻断提交，但必须由运营显式确认")
    }

    func testEmptyBaselineWithExistingOnlineIsUnverified() {
        // 草稿没记基线、线上已经有版本 → 无法判断它基于哪一版
        let verdict = ShopCatalogBaselineResolver.verdict(
            baseline: ShopCatalogBaseline(),
            head: ShopCatalogOnlineHead(environment: "development", releaseSeq: 7, rootIndexHash: hashCurrent))

        guard case .unverified = verdict else {
            return XCTFail("空基线 + 线上有内容必须是 unverified，实际 \(verdict)")
        }
    }

    // MARK: 首次发布

    func testEmptyBaselineWithEmptyOnlineIsCurrent() {
        let head = ShopCatalogOnlineHead(environment: "development", releaseSeq: 0, rootIndexHash: "")
        XCTAssertTrue(head.isFirstRelease)

        let verdict = ShopCatalogBaselineResolver.verdict(baseline: ShopCatalogBaseline(), head: head)
        guard case .current = verdict else {
            return XCTFail("线上确实还没有内容时应视为首次发布，实际 \(verdict)")
        }
        XCTAssertTrue(verdict.isVerified)
        XCTAssertFalse(verdict.isBlocking)
    }

    // MARK: 一致

    func testMatchingBaselineIsCurrent() {
        let baseline = ShopCatalogBaseline(
            releaseSeq: 4, rootIndexHash: hashCurrent, environment: "development")
        let head = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 4, rootIndexHash: hashCurrent)

        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head)
        guard case .current = verdict else { return XCTFail("相同发布号与摘要应判一致，实际 \(verdict)") }
        XCTAssertTrue(verdict.isVerified)
    }

    func testBaselineWithoutHashComparesBySequenceOnly() {
        // 旧草稿形态：只有发布号，没有摘要
        let baseline = ShopCatalogBaseline(releaseSeq: 4, environment: "development")
        let head = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 4, rootIndexHash: hashNewer)

        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head)
        guard case .current = verdict else {
            return XCTFail("摘要缺失时只比发布号，实际 \(verdict)")
        }
    }

    // MARK: 过期（阻断）

    func testOnlineAheadIsStaleAndBlocking() {
        let baseline = ShopCatalogBaseline(
            releaseSeq: 4, rootIndexHash: hashCurrent, environment: "development")
        let head = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 5, rootIndexHash: hashNewer)

        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head)
        guard case .stale(let online, let reasons) = verdict else {
            return XCTFail("线上已前进必须判过期，实际 \(verdict)")
        }
        XCTAssertEqual(online.releaseSeq, 5)
        XCTAssertTrue(verdict.isBlocking, "基线过期必须阻断，不能只提示")
        XCTAssertTrue(reasons.contains { $0.contains("5") }, "原因里要说清线上是多少：\(reasons)")
    }

    func testSameSequenceButDifferentRootHashIsStale() {
        // 发布号被回收 / 被别处改写：摘要对不上就不能当一致
        let baseline = ShopCatalogBaseline(
            releaseSeq: 5, rootIndexHash: hashCurrent, environment: "development")
        let head = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 5, rootIndexHash: hashNewer)

        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head)
        XCTAssertTrue(verdict.isBlocking, "同号不同摘要必须阻断：\(verdict)")
    }

    func testDifferentEnvironmentIsStaleWithExplicitReason() {
        let baseline = ShopCatalogBaseline(
            releaseSeq: 9, rootIndexHash: hashCurrent, environment: "production")
        let head = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 1, rootIndexHash: hashNewer)

        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head)
        guard case .stale(_, let reasons) = verdict else {
            return XCTFail("跨环境比较必须判不可比，实际 \(verdict)")
        }
        XCTAssertTrue(
            reasons.contains { $0.contains("production") && $0.contains("development") },
            "原因里要点明两个环境：\(reasons)")
    }

    func testBaselineNewerThanOnlineIsStale() {
        let baseline = ShopCatalogBaseline(
            releaseSeq: 12, rootIndexHash: hashCurrent, environment: "development")
        let head = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 3, rootIndexHash: hashNewer)

        XCTAssertTrue(
            ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head).isBlocking,
            "本地基线比线上新也要阻断（可能读错环境或基线被污染）")
    }

    // MARK: 文案

    func testDisplayTextNeverClaimsVerifiedWhenEmpty() {
        XCTAssertTrue(ShopCatalogBaseline().displayText.contains("未知"))
        XCTAssertFalse(ShopCatalogBaseline().isKnown)
        XCTAssertTrue(ShopCatalogBaseline(releaseSeq: 0).isKnown, "0 是有效发布号，不是「未知」")
    }

    // MARK: 线上摘要未读到（不能把「读不到」当成「不一致」）

    func testMissingOnlineHashComparesBySequenceOnly() {
        // 受控发布器读发布头时不一定回吐 rootIndexHash → 只能比发布号。
        // 若把它算成「摘要变了」，每一次正常发布都会被误判成基线过期。
        let baseline = ShopCatalogBaseline(
            releaseSeq: 4, rootIndexHash: hashCurrent, environment: "development")
        let head = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 4, rootIndexHash: nil)

        XCTAssertFalse(head.hasRootIndexHash)
        let verdict = ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head)
        guard case .current = verdict else {
            return XCTFail("线上摘要未读到时只能比发布号，不得判过期，实际 \(verdict)")
        }
        XCTAssertTrue(verdict.isVerified, "发布号确实比到了")
        XCTAssertFalse(verdict.isBlocking)
        // 但文案里**不许**声称摘要一致
        XCTAssertTrue(verdict.guidance.contains("只比了发布号"), "实际文案：\(verdict.guidance)")
    }

    func testMissingOnlineHashStillDetectsSequenceAhead() {
        // 「摘要读不到」不能变成放过线上前进的理由
        let baseline = ShopCatalogBaseline(
            releaseSeq: 4, rootIndexHash: hashCurrent, environment: "development")
        let head = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 9, rootIndexHash: nil)

        XCTAssertTrue(
            ShopCatalogBaselineResolver.verdict(baseline: baseline, head: head).isBlocking,
            "发布号已经前进就必须阻断，与摘要读没读到无关")
    }

    func testStaleReasonOmitsHashClaimWhenOnlineHashMissing() {
        let baseline = ShopCatalogBaseline(
            releaseSeq: 4, rootIndexHash: hashCurrent, environment: "development")
        let head = ShopCatalogOnlineHead(
            environment: "development", releaseSeq: 6, rootIndexHash: nil)

        guard case .stale(_, let reasons) = ShopCatalogBaselineResolver.verdict(
            baseline: baseline, head: head) else {
            return XCTFail("线上已前进应判过期")
        }
        XCTAssertFalse(
            reasons.contains { $0.contains("摘要") },
            "线上摘要没读到就不能声称摘要变化：\(reasons)")
    }
}
