import Combine
import SwiftUI

// MARK: - 双视角：用户视图 / 创作者视图（用户 2026-09-17）
//
// 同一个品牌页两套读法，但**共用一套组件与布局骨架**：差异只在视图状态
// （`MidsummerViewModeStore.mode`）控制的交互与可编辑性上，不复制第二份 UI：
//   · 用户视图（viewer）：浏览优先，卡片化 + 留白 + 只读详情；
//   · 创作者视图（creator）：编辑优先，顶栏上传入口、卡片点开直接进入编辑态。
//
// 切换入口只对运营白名单可见（`MidsummerStore.canEnterCreatorView`）——
// 普通用户看不到切换控件，也看不到上传入口。

nonisolated enum MidsummerViewMode: String, CaseIterable, Sendable {
  /// 用户视图：浏览与交互，只读。
  case viewer
  /// 创作者视图：新增与编辑效率优先。
  case creator

  var labelZH: String {
    switch self {
    case .viewer: return "用户视图"
    case .creator: return "创作者视图"
    }
  }

  /// 分段控件上的短文案（顶栏空间有限）。
  var shortLabel: String {
    switch self {
    case .viewer: return "用户"
    case .creator: return "创作者"
    }
  }

  var iconSystemName: String {
    switch self {
    case .viewer: return "eyes"
    case .creator: return "square.and.pencil"
    }
  }

  var accessibilityIdentifier: String {
    switch self {
    case .viewer: return "midsummer-view-mode-viewer"
    case .creator: return "midsummer-view-mode-creator"
    }
  }
}

/// 页面级视图状态：放在环境里向下传递，卡片 / 详情 / 规格面板读同一份真值。
///
/// 显式实现 `objectWillChange` 而不靠 `@Published` 合成：加了 `@MainActor`
/// 后 Swift 6 严格并发下合成的 publisher 会变成 main-actor 隔离，
/// 报「type does not conform to protocol 'ObservableObject'」；显式一份最稳。
final class MidsummerViewModeStore: ObservableObject {
  let objectWillChange = ObservableObjectPublisher()

  private(set) var mode: MidsummerViewMode = .viewer {
    willSet { objectWillChange.send() }
  }

  var isCreator: Bool { mode == .creator }

  func setMode(_ mode: MidsummerViewMode) {
    objectWillChange.send()
    self.mode = mode
  }
}
