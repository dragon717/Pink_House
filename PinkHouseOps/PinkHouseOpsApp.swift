//
//  PinkHouseOpsApp.swift
//  PinkHouseOps
//
//  Mac 原生运营工具入口（计划 §6 P1）。
//
//  ## 这个 App 是干什么的 / 不干什么
//
//  干：导入目录 JSON 与商品图 → 规范化图片并算出 mediaKey → 本地编辑（店家/系列/商品）
//      → 离线跑发布前门禁 → 导出「待发布整包」交给受控发布流水线。
//
//  不干：**不直接写 CloudKit 公共库**。发布通道是现有 Python 发布器
//      （`tools/time_hall/publication/`，ECDSA server-to-server key），
//      私钥不进 App、不进日志（计划 §5 选定的最短上线路径）。
//
//  ## SwiftData 容器
//
//  只存本机草稿与上传任务。**显式关掉 CloudKit 自动同步**：Apple 没给 SwiftData
//  配置 public database 自动同步的选项，而且运营草稿本来就不该进任何云端库。
//

import AppKit
import SwiftData
import SwiftUI

@main
struct PinkHouseOpsApp: App {

    /// 视觉验收用的快照钩子（见 `OpsSnapshotHarness`）。
    ///
    /// 挂在 `applicationDidFinishLaunching` 而不是 SwiftUI `.task`：
    /// 快照必须在**窗口真的出现之后**抓，否则抓到的是未布局的宿主视图；
    /// delegate 回调的时序比 `.task` 更可控。
    @NSApplicationDelegateAdaptor(OpsAppDelegate.self) private var delegate

    /// 本机模型容器：只存本机草稿（上传任务/发布台账已随「素材库 / 发布中心」
    /// 分区移除）。`cloudKitDatabase: .none` 是有意的，不是忘了配（见文件头说明）。
    private let container: ModelContainer = {
        let schema = Schema([
            OpsCatalogDraftRecord.self,
            // 系列发布的草稿箱（2026-10-07 需求：整系列一次发布 + 失败留痕可重试）
            OpsSeriesPublishJob.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // 容器都建不起来就没有可用的运营工具了，直接崩比让人对着空界面猜要好
            fatalError("无法创建本地草稿库：\(error)")
        }
    }()

    var body: some Scene {
        WindowGroup("少女心愿运营") {
            OpsRootView()
        }
        .modelContainer(container)
        .commands {
            // 运营工具的草稿由侧栏管理，系统「新建文稿」在这里没有意义
            CommandGroup(replacing: .newItem) { }
        }
        Settings {
            // 环境选择 / 仓库授权 / 凭证 / 日志入口都在这里（Cmd+,）。
            // 「云端同步」面板的分步卡片已删（2026-10-07）：发布是一键的，配置是静态的。
            OpsSettingsView()
        }
    }
}

// MARK: - 启动钩子

@MainActor
final class OpsAppDelegate: NSObject, NSApplicationDelegate {

    /// 有触发文件就跑对应的 harness 然后退出；没有则什么都不做。
    ///
    /// 三个 harness 都是**文件触发 + 跑完自杀**，各自用**不同的触发文件名**，
    /// 所以任意时刻最多只有一个生效（谁先命中谁跑，跑完 `terminate`）。
    ///
    /// 顺序上快照排前面是**刻意保持既有的验收脚本行为逐字不变**：
    /// 快照是视觉验收的入口，探针是沙盒取证的新入口，不该互相影响。
    ///
    /// ⚠️ 发布演练（`publish-probe.request`）**必须有自己的触发文件**，
    /// 不能并进只读探针 —— 理由见 `BridgeProbeHarness` 文件头。
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = OpsSnapshotHarness.pendingRequest() {
            // 等首帧窗口布局完成再抓（0.9s 是 `render` 内部等待之外的额外余量）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                OpsSnapshotHarness.run(into: directory)
                NSApp.terminate(nil)
            }
            return
        }
        if let directory = OpsBridgeProbeHarness.pendingPublishRequest() {
            // 发布演练：会真跑 `build_release.py`，比只读探针慢得多，
            // 所以它排在只读探针**前面**判断 —— 两个触发文件同时存在时，
            // 先跑「更重、更需要人盯着」的那一个。
            Task {
                await OpsBridgeProbeHarness.runPublish(into: directory)
                NSApp.terminate(nil)
            }
            return
        }
        if let directory = OpsBridgeProbeHarness.pendingRequest() {
            // 探针不渲染任何 UI，但仍是**异步**的：桥接调用要等子进程，
            // 在 applicationDidFinishLaunching 里同步等会拖住 AppKit 的启动序列。
            Task {
                await OpsBridgeProbeHarness.run(into: directory)
                NSApp.terminate(nil)
            }
        }
    }
}
