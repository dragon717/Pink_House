//
//  OpsSnapshotHarness.swift
//  PinkHouseOps
//
//  离线 UI 快照 harness：把每个分区渲染成 PNG，用于**视觉验收**。
//
//  ## 为什么要在应用内部渲染，而不是用系统截屏
//
//  `screencapture` 需要「屏幕录制」TCC 授权，在受限 shell 里直接
//  `could not create image from display`。把这个能力做进 App 里则完全绕开权限：
//  用 `NSHostingView` 真实布局 + `cacheDisplay` 抓位图，
//  拿到的是 AppKit 真控件渲染结果（不是 SwiftUI 的离屏近似）。
//
//  ## 触发方式：**文件**，不是命令行参数
//
//  实测 `open -n <app> --args --snapshot-dir X` 时 App 里的
//  `CommandLine.arguments` 收不到 X（App 照常进入正常使用流程）。
//  所以改成触发文件，由外部创建、App 读到即跑并删掉：
//
//      CONTAINER=~/Library/Containers/bugod2.ItemManager.Ops/Data/Library/Application\ Support/PinkHouseOps
//      mkdir -p "$CONTAINER"
//      printf 'snapshots' > "$CONTAINER/snapshot.request"     # 内容是子目录名，可省
//      open -n build/sym/Debug/PinkHouseOps.app
//
//  产物落在 `<容器>/Library/Application Support/PinkHouseOps/<子目录名>/`：
//  `overview.png` / `catalog.png` / `media.png` / `validation.png` / `preview.png`。
//
//  ## 三条刻意的设计
//
//    · **不碰真实草稿库**：快照用 `isStoredInMemoryOnly` 的容器 + 现场造数据，
//      既不会把示例数据污染进运营的草稿，也让快照不依赖本机当前状态（可复现）；
//    · **走公开入口造数据**：示例数据全走 `OpsWorkspace` 的公开方法，
//      所以这个 harness 顺带验证了「新建草稿 → 加店家/系列/商品 → 导入图片」这条链路；
//    · **渲染失败要出声**：抓不到位图就打印 `SNAPSHOT 渲染失败` 并**不写文件**，
//      绝不写一张全空 PNG 当成功（那正是本项目反复出事的「假绿」）。
//

import AppKit
import SwiftData
import SwiftUI

@MainActor
enum OpsSnapshotHarness {

    /// 触发文件名（放在应用容器的 `Application Support/PinkHouseOps/` 下）
    static let requestFileName = "snapshot.request"

    /// 默认输出子目录名（触发文件为空时用它）
    static let defaultOutputFolderName = "snapshots"

    /// 应用容器内的数据根目录。与 `OpsWorkspace.rootDirectory` 同一算法，
    /// 刻意不共享代码：这个 harness 要在 workspace 之前跑，不该依赖它。
    static func rootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PinkHouseOps", isDirectory: true)
    }

    /// 有触发文件就返回输出目录并**消费掉触发文件**（避免下次启动又跑）。
    static func pendingRequest() -> URL? {
        let root = rootDirectory()
        let marker = root.appendingPathComponent(requestFileName)
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let requested = (try? String(contentsOf: marker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try? FileManager.default.removeItem(at: marker)
        let folder = (requested?.isEmpty == false) ? requested! : defaultOutputFolderName
        return root.appendingPathComponent(folder, isDirectory: true)
    }

    /// 把全部分区渲染到 `directory`。
    static func run(into directory: URL, size: NSSize = NSSize(width: 1280, height: 860)) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("SNAPSHOT 建目录失败：\(error.localizedDescription)")
            return
        }
        print("SNAPSHOT 开始，输出目录 \(directory.path)")

        guard let container = makeContainer() else { return }
        let workspace = OpsWorkspace(context: container.mainContext)
        seed(workspace)
        // 样例数据是**一次性的**：跑完把自己的暂存目录也带走。
        // 否则每次跑快照都会在运营本机的 staging 下留一堆没有对应草稿的图，
        // 之后打开「图片与上传任务」会被当成孤儿文件列出来。
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }

        var written = 0
        for section in OpsSection.allCases {
            let view = OpsMainView(workspace: workspace, initialSection: section)
                .modelContainer(container)
            guard let data = render(view, size: size) else {
                print("SNAPSHOT 渲染失败：\(section.rawValue)")
                continue
            }
            let file = directory.appendingPathComponent("\(section.rawValue).png")
            do {
                try data.write(to: file)
                written += 1
                print("SNAPSHOT 已写入 \(file.lastPathComponent)（\(data.count) 字节）")
            } catch {
                print("SNAPSHOT 写文件失败 \(file.path)：\(error.localizedDescription)")
            }
        }
        print("SNAPSHOT 完成：\(written)/\(OpsSection.allCases.count) 张")
    }

    // MARK: - 容器与示例数据

    /// **内存**容器：快照不该改运营本机的草稿库（同 `PinkHouseOpsApp` 的理由，
    /// 只是这里连落盘都省了，保证可复现）。
    private static func makeContainer() -> ModelContainer? {
        do {
            let schema = Schema([OpsCatalogDraftRecord.self, OpsMediaJobRecord.self])
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(
                    schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        } catch {
            print("SNAPSHOT 建内存容器失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 现场造一份有内容的目录，否则快照全是空态、看不出布局好坏。
    private static func seed(_ workspace: OpsWorkspace) {
        workspace.createDraft(title: "2026-09-26 上新（快照样例）")
        workspace.addShop(name: "樱花小羊")
        guard let shop = workspace.catalog.shops.first else { return }

        workspace.addSeries(shopID: shop.id, name: "星月夜", year: 2026, month: 9)
        guard let series = workspace.catalog.series.first else { return }

        workspace.addProduct(
            shopID: shop.id, seriesID: series.id, name: "星月夜 JSK 粉色", category: "JSK")
        guard let product = workspace.catalog.products.first else { return }

        // 图片走真实导入入口：这样「图片与上传任务」页与门禁页才不是空的
        // （门禁要能看出「哪几个引用解不出图」）。
        if let urls = makeSampleImages() {
            workspace.importImages(from: urls)
            let assetIDs = workspace.catalog.assets.map(\.id)
            if !assetIDs.isEmpty {
                workspace.bindImages(Array(assetIDs.prefix(2)), toProduct: product.id)
            }
        }
    }

    /// 造两张真 PNG（不依赖任何既有素材）。
    private static func makeSampleImages() -> [URL]? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinkhouse-snapshot-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("SNAPSHOT 样例图目录创建失败：\(error.localizedDescription)")
            return nil
        }
        var urls: [URL] = []
        for (index, color) in [NSColor.systemPink, NSColor.systemIndigo].enumerated() {
            let size = NSSize(width: 240, height: 240)
            let image = NSImage(size: size)
            image.lockFocus()
            color.setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor.white.setFill()
            NSRect(x: 40, y: 40, width: 160, height: 160).fill()
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let url = directory.appendingPathComponent("sample-\(index + 1).png")
            try? png.write(to: url)
            urls.append(url)
        }
        return urls.isEmpty ? nil : urls
    }

    // MARK: - 离屏渲染

    /// 真实布局 + 抓位图。
    ///
    /// 用 `NSWindow` 而不是纯 `NSHostingView`：`List` / `Table` / `TextField`
    /// 这些 AppKit 支撑的控件需要真的进窗口才会完成布局与绘制。
    private static func render<V: View>(_ view: V, size: NSSize) -> Data? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hosting.frame,
            // 必须 `.borderless`：带标题栏时宿主视图顶部会被标题栏占掉约 28pt，
            // 而 `cacheDisplay` 抓的是视图自身 bounds —— 结果是每张快照
            // **顶部被裁一条**（侧栏第一行、三栏表头正好落在那条里），
            // 看起来像布局 bug，其实是抓图的锅。
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()

        // SwiftUI 的首帧布局 + `.task` 里的异步工作跑完再抓，否则可能抓到半成品
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        hosting.layoutSubtreeIfNeeded()

        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return nil
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
