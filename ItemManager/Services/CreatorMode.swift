import Combine
import Foundation

// MARK: - 创作者模式
//
// 背景：仲夏物语的内容补充入口（顶栏「上传上新」+ `MidsummerContributeView`）
// 原本只对 `NoticeCloudKitService.adminIDs` 白名单里的 iCloud 账户可见，而判定依赖
// `CKContainer.userRecordID()`——模拟器、未登录 iCloud、或换了 Apple ID 的设备都取不到，
// 于是入口**永远不出现**。使用者反馈的「缺少供创作者上传缺失内容的入口」正是此因。
//
// 这里把两件事解耦：
//   · 「界面是否显示入口」——由本开关 + 白名单共同决定
//   · 「CloudKit 是否真的允许写入」——由 Console 的 Security Roles 决定，客户端管不了
//
// 所以本开关**只解界面闸门**，不是安全边界；未获授权的账号仍然提交不上去，
// 但会拿到一条明确的失败提示，而不是「连入口都找不到」。
//
// 默认关闭：避免普通浏览者误入投稿页。

@MainActor
final class CreatorMode: ObservableObject {
  static let shared = CreatorMode()

  /// 存档 key。改名等于丢掉使用者已设定的状态，不要改。
  nonisolated static let storageKey = "creator_mode.enabled.v1"

  /// UI 测试用的重置开关：带上该启动参数即清空存档，保证每个用例从「默认关闭」起步。
  /// 只在 App 启动参数里出现，正常运行不会命中。
  nonisolated static let resetLaunchArgument = "-ui-test-reset-creator-mode"

  /// UI 测试用的开启开关：带上即把存档置为开启（上新工作台等 canContribute
  /// 门控入口在模拟器里取不到 CloudKit 身份，靠它解界面闸门）。
  nonisolated static let enableLaunchArgument = "-ui-test-enable-creator-mode"

  @Published private(set) var isEnabled: Bool

  private let defaults: UserDefaults

  /// 允许注入 `UserDefaults`，便于单测用独立域验证读写。
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if ProcessInfo.processInfo.arguments.contains(Self.resetLaunchArgument) {
      defaults.removeObject(forKey: Self.storageKey)
    }
    if ProcessInfo.processInfo.arguments.contains(Self.enableLaunchArgument) {
      defaults.set(true, forKey: Self.storageKey)
    }
    self.isEnabled = defaults.bool(forKey: Self.storageKey)
  }

  func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else { return }
    isEnabled = enabled
    defaults.set(enabled, forKey: Self.storageKey)
    // 角色判定（`CreatorAccess`）实时读这里的存档值，写接口会立刻跟着变；
    // 同步一次判定依据，让设置页的「当前角色」文案与真实角色一致。
    CreatorAccess.shared.refreshBasis()
  }

  /// 供 `MidsummerStore` 这类不持有本对象引用的类型做**只读**判断。
  nonisolated static func isEnabledInDefaults(_ defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: storageKey)
  }
}
