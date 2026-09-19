import Combine
import Foundation

// MARK: - 创作者角色与权限中心
//
// 背景：仲夏物语的创作者能力（上架管理 / 改价 / 换图 / 云端发布）此前散落在
// 三处各自判定——`CreatorMode`（本机开关）、`NoticeCloudKitService.CreatorGate`
// （运营白名单三态）、`MidsummerStore.canEnterCreatorView`（界面门控），
// 于是出现两种漏洞：
//   · 系列详情「上新管理」等入口**完全没有门控**，普通用户也能进；
//   · 服务层（本地存档 / CloudKit 发布）**没有任何校验**，绕过界面直接调用即可写入。
//
// 本文件把「谁是创作者」收敛成**一个真值**，并要求两条链路都来问它：
//   1. 界面：`CreatorAccess.shared.isCreator` —— 决定入口 / 按钮是否渲染；
//   2. 服务：`CreatorAccess.requireCreator(_:)` —— 写接口第一行就校验，
//      无论调用方是界面、快捷指令还是将来的深链，越过前端也写不进去。
//
// 角色判定（保守优先，取不到身份一律按普通用户处理）：
//   · 白名单命中 `.allowed`  → 创作者（硬判定，本机开关不影响）
//   · 白名单明确排除 `.denied` → 普通用户（硬判定，**本机开关撬不开**）
//   · 取不到 iCloud 身份 `.unresolved` → 由本机「创作者模式」开关决定
//     （模拟器 / 未登录 iCloud 的内容维护场景，见 `CreatorMode` 顶部说明）
//
// ⚠️ 客户端只是**预校验**，不是安全边界：真正的写权限在 CloudKit Console 的
// Security Roles（见 docs/MIDSUMMER_TALE_CLOUDKIT_SETUP.md §2）。这里挡住的是
// 「普通用户在 App 内就能改公共内容」这条路径，挡不住拿到凭据直连 CloudKit 的人。

/// 角色：普通用户 / 创作者。
nonisolated enum CreatorRole: String, Sendable, CaseIterable {
  /// 普通用户：浏览、入库、购买等既有能力不变，无任何编辑能力。
  case viewer
  /// 创作者：上架管理 / 改价 / 换图 / 云端发布。
  case creator

  var labelZH: String {
    switch self {
    case .viewer: return "普通用户"
    case .creator: return "创作者"
    }
  }
}

/// 需要权限校验的操作。用途有俩：错误文案可定位到具体动作；日志与提示能说清「哪一项被拦下」。
nonisolated enum CreatorOperation: String, Sendable, CaseIterable {
  case listingPublish
  case listingStatus
  case listingDelete
  case listingEdit
  case priceEdit
  case imageReplace
  case seriesCreate
  case seriesDelete
  case cloudPublish

  var labelZH: String {
    switch self {
    case .listingPublish: return "发布新商品"
    case .listingStatus: return "上架 / 下架"
    case .listingDelete: return "删除商品"
    case .listingEdit: return "编辑商品"
    case .priceEdit: return "修改价格"
    case .imageReplace: return "更换商品图"
    case .seriesCreate: return "新建系列"
    case .seriesDelete: return "删除系列"
    case .cloudPublish: return "发布到云端公共库"
    }
  }
}

/// 角色判定的依据（设置页与调试展示用）。
nonisolated enum CreatorBasis: String, Sendable {
  /// CloudKit 白名单命中。
  case whitelist
  /// 白名单明确排除：本机开关也无法放行。
  case whitelistRejected
  /// 取不到 iCloud 身份，但本机「创作者模式」开关已开（模拟器 / 未登录 iCloud）。
  case localSwitch
  /// 取不到身份且本机开关关闭（默认态）。
  case unresolvedIdentity
  /// 单测注入的角色。
  case testOverride

  var labelZH: String {
    switch self {
    case .whitelist: return "运营白名单"
    case .whitelistRejected: return "不在运营白名单"
    case .localSwitch: return "本机创作者模式（未取到 iCloud 身份）"
    case .unresolvedIdentity: return "未取到 iCloud 身份"
    case .testOverride: return "单测注入"
    }
  }
}

/// 权限拒绝：写接口统一抛它，界面转成一句人话提示。
nonisolated struct CreatorAccessDenied: LocalizedError, Sendable {
  let operation: CreatorOperation
  let basis: CreatorBasis

  /// 面向使用者的主提示。
  var errorDescription: String? {
    "当前账号不是创作者，无法进行「\(operation.labelZH)」。"
  }

  /// 补充一句「为什么」以及能做什么，避免使用者卡在无从下手。
  var recoverySuggestion: String? {
    switch basis {
    case .whitelistRejected:
      return "本机的 iCloud 账户不在运营白名单里，这个开关也打不开编辑能力；需要权限请联系运营加白名单。"
    case .unresolvedIdentity, .localSwitch:
      return "未取到 iCloud 身份（模拟器 / 未登录 iCloud）。如需在本机维护内容，请到「设置 → 创作者模式」开启。"
    case .whitelist, .testOverride:
      return "请重新进入页面后再试。"
    }
  }
}

extension Error {
  /// 写操作失败时给使用者看的一句话。
  ///
  /// 权限拒绝要说清「哪一项被拦 + 为什么 + 怎么办」，其它错误沿用系统描述。
  var userMessage: String {
    guard let denied = self as? CreatorAccessDenied else { return localizedDescription }
    return [denied.errorDescription, denied.recoverySuggestion]
      .compactMap { $0 }
      .joined(separator: " ")
  }
}

/// 白名单判定结果的进程内快照。
///
/// 判定是 `async` 的（要问 CloudKit 要 `userRecordID`），而服务层的写接口是同步的，
/// 因此把最近一次判定结果存在这里，供同步校验读取。用 `NSLock` 保护，
/// 任何隔离域都能安全调用。
final class CreatorGateSnapshot: @unchecked Sendable {
  static let shared = CreatorGateSnapshot()

  private let lock = NSLock()
  private var gate: NoticeCloudKitService.CreatorGate = .unresolved(reason: "尚未判定")
  private var override: CreatorRole?

  private init() {}

  func update(gate: NoticeCloudKitService.CreatorGate) {
    lock.lock()
    self.gate = gate
    lock.unlock()
  }

  func currentGate() -> NoticeCloudKitService.CreatorGate {
    lock.lock()
    defer { lock.unlock() }
    return gate
  }

  /// 单测注入：非 nil 时角色判定直接取它，不再看白名单与本机开关。
  func setOverride(_ role: CreatorRole?) {
    lock.lock()
    self.override = role
    lock.unlock()
  }

  func currentOverride() -> CreatorRole? {
    lock.lock()
    defer { lock.unlock() }
    return override
  }
}

/// 角色与权限的唯一真值：界面读 `isCreator`，服务层调 `requireCreator(_:)`。
@MainActor
final class CreatorAccess: ObservableObject {
  static let shared = CreatorAccess()

  /// 最近一次 CloudKit 白名单判定结果（三态）。
  @Published private(set) var gate: NoticeCloudKitService.CreatorGate = .unresolved(
    reason: "尚未判定")
  /// 判定依据：白名单命中 / 明确排除 / 本机开关 / 取不到身份。
  @Published private(set) var basis: CreatorBasis = .unresolvedIdentity

  private init() {}

  // MARK: 角色

  var isCreator: Bool { role == .creator }

  /// 运营白名单命中的创作者（用户 2026-09-19 分级灰度）。
  ///
  /// 与 `isCreator` 的差别：本机「创作者模式」开关（模拟器 / 未登录 iCloud）
  /// **不**放行这一条——新版「分类与款式」表单布局是白名单灰度能力，
  /// 只有 CloudKit 白名单明确命中（`gate == .allowed`）才启用；
  /// 其余创作者（含本机开关创作者）与普通用户沿用旧布局 / 看不到入口。
  var isWhitelistedCreator: Bool {
    Self.isWhitelistedGate(gate)
  }

  /// 白名单命中的纯判定（脱离实例可测）。
  nonisolated static func isWhitelistedGate(_ gate: NoticeCloudKitService.CreatorGate) -> Bool {
    if case .allowed = gate { return true }
    return false
  }

  var role: CreatorRole {
    Self.resolveRole(gate: gate).role
  }

  /// 设置页用的说明文案：当前是什么角色、凭什么判定。
  var statusText: String {
    "\(role.labelZH) · \(basis.labelZH)"
  }

  /// 非创作者看到只读提示时的通用引导（页面级拒绝共用）。
  ///
  /// 复用 `CreatorAccessDenied` 的 `recoverySuggestion`，避免「列表页一句话、
  /// 面板里另一句话」的文案漂移；前半句固定安抚——浏览与入库能力不受影响。
  var deniedGuidance: String {
    let how = CreatorAccessDenied(operation: .listingPublish, basis: basis).recoverySuggestion
    return "当前账号可以照常浏览商品与价格。" + (how ?? "")
  }

  // MARK: 判定刷新

  /// 问一次 CloudKit 白名单，刷新角色。
  ///
  /// App 启动与云端刷新各调一次；判定不到（断网 / 未登录 iCloud）时保守回落为
  /// 「取不到身份」，由本机开关决定是否放行。
  func refresh() async {
    apply(gate: await MidsummerCloudService.shared.creatorGate())
  }

  /// 本机「创作者模式」开关变更后调用：角色是实时读 UserDefaults 的，
  /// 这里只需把判定依据（`basis`）刷新成最新，设置页文案才不会停在旧值。
  func refreshBasis() {
    basis = Self.resolveRole(gate: gate).basis
  }

  /// 写入判定结果（刷新与单测共用），同步更新快照供服务层读取。
  func apply(gate: NoticeCloudKitService.CreatorGate) {
    self.gate = gate
    basis = Self.resolveRole(gate: gate).basis
    CreatorGateSnapshot.shared.update(gate: gate)
  }

  // MARK: 同步校验（服务层入口）

  /// 非创作者时抛 `CreatorAccessDenied`，写接口在改动数据**之前**调用。
  nonisolated static func requireCreator(_ operation: CreatorOperation) throws {
    let resolved = resolveNow()
    guard resolved.role == .creator else {
      throw CreatorAccessDenied(operation: operation, basis: resolved.basis)
    }
  }

  /// 同步判断当前是否创作者（界面在无法拿到 `shared` 的地方用它）。
  nonisolated static func isCreatorNow() -> Bool {
    resolveNow().role == .creator
  }

  /// 同步解析角色：单测注入 > 白名单三态 > 本机开关。
  nonisolated static func resolveNow() -> (role: CreatorRole, basis: CreatorBasis) {
    if let override = CreatorGateSnapshot.shared.currentOverride() {
      return (override, .testOverride)
    }
    return resolveRole(gate: CreatorGateSnapshot.shared.currentGate())
  }

  /// 三态 → 角色。抽成纯函数，单测可脱离 CloudKit 直接验证判定矩阵。
  nonisolated static func resolveRole(
    gate: NoticeCloudKitService.CreatorGate,
    localSwitchEnabled: Bool = CreatorMode.isEnabledInDefaults()
  ) -> (role: CreatorRole, basis: CreatorBasis) {
    switch gate {
    case .allowed:
      return (.creator, .whitelist)
    case .denied:
      // 明确不在白名单：本机开关一律不放行，否则等于谁都能自己提权。
      return (.viewer, .whitelistRejected)
    case .unresolved:
      return localSwitchEnabled ? (.creator, .localSwitch) : (.viewer, .unresolvedIdentity)
    }
  }

  // MARK: 单测钩子

  /// 单测注入角色；传 nil 恢复真实判定。
  ///
  /// 只走快照（同步校验那条路），不动 `@Published`，因为单测里的服务层调用
  /// 全部走 `requireCreator` / `resolveNow`。
  static func setTestOverride(_ role: CreatorRole?) {
    CreatorGateSnapshot.shared.setOverride(role)
  }
}
