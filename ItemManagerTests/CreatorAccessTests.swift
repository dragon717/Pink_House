import UIKit
import XCTest
@testable import ItemManager

// MARK: - 创作者角色与权限单测
//
// 覆盖「角色判定矩阵」（纯函数 `CreatorAccess.resolveRole`）：
//   白名单命中 / 明确排除 / 取不到身份 × 本机开关，谁该是创作者。
//
// 服务层拦截用例（2026-09-24 仲夏物语模块移除时一并下线）：
//   `requireCreator` 的同步校验仍由店家上新运营链路（`ShopCatalogOps`）消费。
//
// 角色注入走 `CreatorAccess.setTestOverride`，不碰真实白名单判定与本机存档。

@MainActor
final class CreatorAccessTests: XCTestCase {

  override func setUp() {
    super.setUp()
    CreatorAccess.setTestOverride(nil)
  }

  override func tearDown() {
    CreatorAccess.setTestOverride(nil)
    CreatorAccess.shared.apply(gate: .unresolved(reason: "单测结束"))
    super.tearDown()
  }

  // MARK: 角色判定矩阵

  func testWhitelistHitIsCreatorEvenWithoutLocalSwitch() {
    let resolved = CreatorAccess.resolveRole(gate: .allowed, localSwitchEnabled: false)
    XCTAssertEqual(resolved.role, .creator)
    XCTAssertEqual(resolved.basis, .whitelist)
  }

  /// 明确不在白名单：本机开关**撬不开**——否则等于人人可自提权。
  func testDeniedStaysViewerEvenWithLocalSwitchOn() {
    let resolved = CreatorAccess.resolveRole(gate: .denied, localSwitchEnabled: true)
    XCTAssertEqual(resolved.role, .viewer)
    XCTAssertEqual(resolved.basis, .whitelistRejected)
  }

  func testUnresolvedFallsBackToLocalSwitch() {
    XCTAssertEqual(
      CreatorAccess.resolveRole(gate: .unresolved(reason: "模拟器"), localSwitchEnabled: true).role,
      .creator, "取不到身份时由本机开关放行（内容维护者在模拟器上的通路）")
    XCTAssertEqual(
      CreatorAccess.resolveRole(gate: .unresolved(reason: "模拟器"), localSwitchEnabled: false).role,
      .viewer, "取不到身份 + 开关关闭 = 普通用户（保守优先）")
  }

  // MARK: 白名单灰度判定（用户 2026-09-19 新版分类与款式表单）

  /// 新版表单布局只认**运营白名单命中**：本机开关（模拟器通路）不放行，
  /// 明确排除与未判定一律不算白名单创作者。
  func testWhitelistedCreatorGateRequiresExplicitAllow() {
    XCTAssertTrue(CreatorAccess.isWhitelistedGate(.allowed), "白名单命中 = 灰度放行")
    XCTAssertFalse(
      CreatorAccess.isWhitelistedGate(.denied),
      "明确不在白名单：本机开关也撬不开灰度能力")
    XCTAssertFalse(
      CreatorAccess.isWhitelistedGate(.unresolved(reason: "模拟器")),
      "未判定（含本机创作者模式开启）不算白名单命中——灰度只认运营名单")
  }

  /// 本机开关真的写进 UserDefaults 时，服务层同步校验也要立刻认。
  func testLocalSwitchIsReadLiveByServiceLayer() {
    let key = CreatorMode.storageKey
    let previous = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.set(true, forKey: key)
    defer {
      if let previous {
        UserDefaults.standard.set(previous, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }

    CreatorAccess.shared.apply(gate: .unresolved(reason: "未登录 iCloud"))
    XCTAssertTrue(CreatorAccess.shared.isCreator)
    XCTAssertNoThrow(try CreatorAccess.requireCreator(.priceEdit))
  }

  func testDeniedGateLocksLocalSwitchOutOfServiceLayer() {
    CreatorAccess.shared.apply(gate: .denied)
    XCTAssertFalse(CreatorAccess.shared.isCreator)
    XCTAssertThrowsError(try CreatorAccess.requireCreator(.priceEdit)) { error in
      guard let denied = error as? CreatorAccessDenied else {
        return XCTFail("应抛 CreatorAccessDenied，实际是 \(error)")
      }
      XCTAssertEqual(denied.operation, .priceEdit)
      XCTAssertTrue(
        denied.errorDescription?.contains("修改价格") ?? false,
        "提示要能说清是哪一步被拦：\(denied.errorDescription ?? "")")
    }
  }
}
