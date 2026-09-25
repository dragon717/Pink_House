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

    /// 本机模型容器：草稿 + 上传任务。`cloudKitDatabase: .none` 是有意的，
    /// 不是忘了配（见文件头说明）。
    private let container: ModelContainer = {
        let schema = Schema([OpsCatalogDraftRecord.self, OpsMediaJobRecord.self])
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
        WindowGroup("Pink House 运营") {
            OpsRootView()
        }
        .modelContainer(container)
        .commands {
            // 运营工具的草稿由侧栏管理，系统「新建文稿」在这里没有意义
            CommandGroup(replacing: .newItem) { }
        }
    }
}

// MARK: - 启动钩子

@MainActor
final class OpsAppDelegate: NSObject, NSApplicationDelegate {

    /// 有快照触发文件就以快照模式跑一遍然后退出；没有则什么都不做。
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let directory = OpsSnapshotHarness.pendingRequest() else { return }
        // 等首帧窗口布局完成再抓（0.9s 是 `render` 内部等待之外的额外余量）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            OpsSnapshotHarness.run(into: directory)
            NSApp.terminate(nil)
        }
    }
}
