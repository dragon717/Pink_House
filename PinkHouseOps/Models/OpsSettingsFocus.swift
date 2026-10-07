//
//  OpsSettingsFocus.swift
//  PinkHouseOps
//
//  主窗口 → 设置窗口的「跨场景指令」。
//
//  ## 为什么需要它
//
//  新版 SwiftUI **只认 `SettingsLink`** 打开 Settings 场景——
//  `NSApp.sendAction(Selector(("showSettingsWindow:")))` 会被无视，
//  控制台刷 "Please use SettingsLink for opening the Settings scene."
//  （2026-10-07 实测：侧栏「设置」按钮点了没反应，就是它）。
//  但 `SettingsLink` 只能「打开窗口」，没有「导航到某个分区」的 API。
//
//  「云端更新失败 → 一键数据修复」需要跨场景传一个指令：
//  toast 里的 `SettingsLink` 负责开窗口，这个单例负责把
//  「打开后自动弹清理确认框」带到设置场景（`OpsSettingsView` onReceive 消费）。
//

// MemberImportVisibility：`@Published` / `$property` 投影来自 Combine，
// 不显式 import 会报 "cannot find 'Combine' in scope" 一类的错。
import Combine

@MainActor
final class OpsSettingsFocus: ObservableObject {
    static let shared = OpsSettingsFocus()

    /// true = 设置窗口打开后应自动弹出「清理悬空销售记录」的二级确认框。
    /// 设置场景消费后立即置回 false（一次性指令，不残留状态）。
    @Published var repairPromptRequested = false

    private init() {}
}
