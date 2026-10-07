//
//  OpsWorkspaceHolder.swift
//  PinkHouseOps
//
//  主窗口那份 `OpsWorkspace` 的**共享引用**。
//
//  ## 为什么需要它
//
//  设置是独立的 `Settings` 场景，拿不到主窗口的环境对象。而另建一份
//  `OpsWorkspace` 是**最坏的选择**：两个实例各持一份目录与版本状态，
//  正是本项目反复吃亏的「两处真相」—— 设置里导入完了，主窗口显示的还是旧内容。
//
//  所以走同一个手法（与 `OpsCloudSyncModel.shared` 一致）：主窗口建好后把它
//  交给这里，需要的地方读这一份。
//
//  ## 为什么是 weak
//
//  设置窗口不该**延长**工作区的生命周期：主窗口关了，工作区就该释放，
//  设置页此时显示「请先打开主窗口」而不是拿着一份悬空的对象继续写。
//

import Foundation
// MemberImportVisibility：`ObservableObject` 与 `objectWillChange` 由 Combine 提供。
import Combine

@MainActor
final class OpsWorkspaceHolder: ObservableObject {
    static let shared = OpsWorkspaceHolder()

    /// ⚠️ 为什么不用 `@Published weak`：Swift 不允许「带属性包装器的属性再声明 weak」。
    /// 所以手动发 `objectWillChange` —— 既要 weak（不延长工作区生命周期），
    /// 又要让设置页在它被赋值那一刻刷新（否则第一次打开设置会看到「请先打开主窗口」）。
    private weak var stored: OpsWorkspace?

    var workspace: OpsWorkspace? {
        get { stored }
        set {
            objectWillChange.send()
            stored = newValue
        }
    }

    private init() {}
}
