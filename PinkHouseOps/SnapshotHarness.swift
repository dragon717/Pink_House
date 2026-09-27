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
//  产物落在 `<容器>/Library/Application Support/PinkHouseOps/<子目录名>/`，
//  每个分区一张：`seriesEntry.png` / `catalog.png` / `products.png` /
//  `preview.png`（文件名 = `OpsSection.rawValue`），
//  外加一份 `harness.log`（本次运行的完整日志，造数据失败的唯一出口 —— 见下）。
//
//  ## 三条刻意的设计
//
//    · **不碰真实草稿库**：快照用 `isStoredInMemoryOnly` 的容器 + 现场造数据，
//      既不会把示例数据污染进运营的草稿，也让快照不依赖本机当前状态（可复现）；
//    · **走公开入口造数据**：示例数据全走 `OpsWorkspace` 的公开方法，
//      所以这个 harness 顺带验证了「新建草稿 → 加店家/系列/商品 → 导入图片」这条链路；
//    · **渲染失败要出声**：抓不到位图就打印 `SNAPSHOT 渲染失败` 并**不写文件**，
//      绝不写一张全空 PNG 当成功（那正是本项目反复出事的「假绿」）；
//    · **日志跟着产物走**：所有输出同时写进 `<输出目录>/harness.log`。
//      只打 stdout 等于没打 —— 沙箱 App 经 LaunchServices 启动时 stdout 拿不到
//      （`open --stdout` 不生效、直接 exec 被 SIGTRAP 拒），
//      于是「造数据失败」在现场表现为一张空态截图，事后无法区分失败与空态；
//    · **失败要盖回图上**：造数据失败时，每张 PNG 顶部会被盖一条红色横幅
//      （`stampUntrusted`）。因为截图是会被**单独拿走看**的东西 ——
//      验收动作就是「打开图片看一眼」，没人会同时打开 `harness.log`。
//      没有失败时产物逐字节不变（`stampUntrusted` 返回 nil）。
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
            // 目录都建不出来，日志**无处可写**，这里只能打 stdout（唯一一处例外）
            print("SNAPSHOT 建目录失败：\(error.localizedDescription)")
            return
        }
        logLines.removeAll()
        seedFailures.removeAll()
        // 日志**跟着产物走**，而不是只打 stdout。
        //
        // 为什么必须如此：这个 App 是沙箱应用，由 `open -n` 经 LaunchServices 启动时
        // stdout 根本拿不到（`open --stdout <path>` 实测不生成文件，直接 exec 二进制
        // 会被 SIGTRAP 拒掉，退出码 133）。只打 stdout = 验收时看不到任何造数据失败，
        // 于是失败又退化成「快照上是一张空态，看起来布局就这样」。
        defer { writeLog(into: directory) }
        log("SNAPSHOT 开始，输出目录 \(directory.path)")

        guard let container = makeContainer() else { return }
        let workspace = OpsWorkspace(context: container.mainContext)
        seed(workspace)
        // 样例数据是**一次性的**：跑完把自己的暂存目录也带走。
        // 否则每次跑快照都会在运营本机的 staging 下留一堆没有对应草稿的图，
        // 之后打开会被当成孤儿文件列出来。
        defer { try? FileManager.default.removeItem(at: workspace.stagingDirectory) }

        var written = 0
        // 触发文件内容带 `-dark` 后缀 = 按**深色**外观渲染（验收主题跟随用）；
        // 默认仍钉浅色，保证日常快照可复现（见 render 里的外观注释）。
        let darkAppearance = directory.lastPathComponent.hasSuffix("-dark")
        for section in OpsSection.allCases {
            let view = OpsMainView(workspace: workspace, initialSection: section)
                .modelContainer(container)
                .environment(\.colorScheme, darkAppearance ? .dark : .light)
            guard let rendered = render(view, size: size, dark: darkAppearance) else {
                log("SNAPSHOT 渲染失败：\(section.rawValue)")
                continue
            }
            // 造数据失败 → 把失败**盖回图上**（见 `stampUntrusted`）。
            // 没有失败时 `stampUntrusted` 返回 nil，产物逐字节不变。
            let data = stampUntrusted(rendered, failedSteps: seedFailures) ?? rendered
            let file = directory.appendingPathComponent("\(section.rawValue).png")
            do {
                try data.write(to: file)
                written += 1
                log("SNAPSHOT 已写入 \(file.lastPathComponent)（\(data.count) 字节）")
            } catch {
                log("SNAPSHOT 写文件失败 \(file.path)：\(error.localizedDescription)")
            }
        }
        if seedFailures.isEmpty {
            log("SNAPSHOT 完成：\(written)/\(OpsSection.allCases.count) 张")
        } else {
            log("SNAPSHOT 完成：\(written)/\(OpsSection.allCases.count) 张 —— "
                + "⚠️ 本次有 \(seedFailures.count) 步造数据失败，**快照不可信**"
                + "（每张图上已盖横幅）：" + seedFailures.joined(separator: "、"))
        }
    }

    // MARK: - 容器与示例数据

    /// **内存**容器：快照不该改运营本机的草稿库（同 `PinkHouseOpsApp` 的理由，
    /// 只是这里连落盘都省了，保证可复现）。
    ///
    /// ⚠️ schema 必须与 `PinkHouseOpsApp` 一致。
    private static func makeContainer() -> ModelContainer? {
        do {
            let schema = Schema([
                OpsCatalogDraftRecord.self,
            ])
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(
                    schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        } catch {
            log("SNAPSHOT 建内存容器失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 现场造一份有内容的目录，否则快照全是空态、看不出布局好坏。
    ///
    /// 覆盖到的东西（每一块都对应一个界面分区）：
    ///   · 店家 / 系列（含**发售阶段 + 系列价格表**）；
    ///   · 三个商品：一个配置齐全、一个故意**没有图**（演示门禁阻断）、
    ///     一个**已归档**（演示归档态）；
    ///   · 图片走真实导入入口 → 商品图与价格表原图都不是空的；
    ///   · 规格 / 尺码表 / 销售记录 / 价格修正（商品管理页的每一张卡都有内容）；
    ///   · 一次**已确认发布**（写出基线快照）→ 之后新增一个商品、改一处描述，
    ///     于是商品页的「差异」真的有「新增 / 已修改」可看。
    private static func seed(_ workspace: OpsWorkspace) {
        workspace.createDraft(title: "2026-09-26 上新（快照样例）")
        workspace.addShop(name: "樱花小羊")
        guard let shop = workspace.catalog.shops.first else { return }

        workspace.addSeries(shopID: shop.id, name: "星月夜", year: 2026, month: 9, season: "秋")
        guard let series = workspace.catalog.series.first else { return }

        seedStep("系列发售阶段", workspace.updateSeriesSalePhase(
            id: series.id,
            phase: .reservationActive,
            reservationStartAt: Date().addingTimeInterval(-86_400 * 5),
            reservationEndAt: Date().addingTimeInterval(86_400 * 9),
            balanceDueKind: .approximate,
            balanceDueText: "大货到后 1 个月",
            balanceDueAt: nil,
            balanceDueEndAt: nil))

        seedStep("新增商品 JSK", workspace.addProduct(
            shopID: shop.id, seriesID: series.id, name: "星月夜 JSK 粉色", category: "JSK"))
        seedStep("新增商品 OP", workspace.addProduct(
            shopID: shop.id, seriesID: series.id, name: "星月夜 OP 蓝色", category: "OP"))
        seedStep("新增商品 KC", workspace.addProduct(
            shopID: shop.id, seriesID: series.id, name: "星月夜 KC（已归档）", category: "小物"))
        guard let primary = workspace.catalog.products.first(where: { $0.category == "JSK" }),
              let secondary = workspace.catalog.products.first(where: { $0.category == "OP" }),
              let archived = workspace.catalog.products.first(where: { $0.category == "小物" })
        else { return }

        // 图片走真实导入入口：商品图与系列价格表原图才有内容
        if let urls = makeSampleImages() {
            for url in urls {
                _ = workspace.importSingleImage(from: url)
            }
            let assetIDs = workspace.catalog.assets.map(\.id)
            if !assetIDs.isEmpty {
                seedStep("绑定商品图", workspace.bindImages(
                    Array(assetIDs.prefix(2)), toProduct: primary.id))
            }
            // 系列价格表也要一张原图，否则价格表卡的「原图」是空的。
            // ⚠️ 列数必须与每行的值数一致 —— 录入端会挡（实测：先写成 3 列 2 值，
            // 结果这一项**静默**没建成，快照上只表现为「价格表：无」）。
            seedStep("系列价格表", workspace.updateSeriesPriceChart(
                seriesID: series.id,
                unit: "cm",
                columns: ["胸围", "腰围", "衣长"],
                rows: [
                    CatalogSizeRow(label: "M", values: ["92", "70", "58"]),
                    CatalogSizeRow(label: "L", values: ["98", "76", "60"]),
                ],
                sourceImages: assetIDs.first.map { [$0] } ?? []))
        }

        // 商品管理的每张卡都要有内容，否则看不到布局
        seedStep("规格 粉色/M", workspace.addVariant(
            productID: primary.id, color: "粉色", size: "M",
            imageAssetID: workspace.catalog.assets.first?.id))
        seedStep("规格 粉色/L", workspace.addVariant(
            productID: primary.id, color: "粉色", size: "L", imageAssetID: nil))
        seedStep("尺码表", workspace.setSizeChart(
            productID: primary.id,
            unit: "cm",
            columns: ["胸围", "腰围", "衣长"],
            rows: [
                CatalogSizeRow(label: "M", values: ["92", "70", "58"]),
                CatalogSizeRow(label: "L", values: ["98", "76", "60"]),
            ],
            sourceImage: nil))
        seedStep("销售记录 预约价", workspace.appendSaleEvent(
            productID: primary.id, type: .reservation, price: 680, deposit: 200, balance: 480,
            currency: .cny, startAt: Date().addingTimeInterval(-86_400 * 5), endAt: nil,
            batchLabel: "初贩"))
        seedStep("销售记录 现货价", workspace.appendSaleEvent(
            productID: primary.id, type: .stock, price: 748, deposit: nil, balance: nil,
            currency: .cny, startAt: Date().addingTimeInterval(86_400 * 20), endAt: nil,
            batchLabel: "现货"))
        seedStep("价格修正", workspace.applyPriceCorrection(
            productID: secondary.id, reservationPrice: 720, stockPrice: 790,
            deposit: 220, balance: 500, currency: .cny))
        seedStep("归档商品", workspace.setArchived(true, kind: .product, id: archived.id))

        // 一次**已确认发布**：写出基线快照（之后新增/修改才有差分可看）
        seedStep("保存草稿", workspace.saveDraft())
        let revision = workspace.currentRevision
        seedStep("记录已确认发布", workspace.recordConfirmedPublish(
            releaseSeq: 41,
            rootIndexHash: String(repeating: "9f1c", count: 16),
            environment: "Production",
            revision: revision))
        guard let shop2 = workspace.catalog.shops.first,
              let series2 = workspace.catalog.series.first else { return }
        seedStep("新增商品 发夹", workspace.addProduct(
            shopID: shop2.id, seriesID: series2.id, name: "星月夜 发夹（本次新增）",
            category: "小物"))
        seedStep("改一处描述", workspace.updateProductDetail(
            id: secondary.id,
            description: "深蓝渐变，配套有腰封与蝴蝶结。本次只改了这一句文案。",
            designName: nil))
        seedStep("保存草稿", workspace.saveDraft())
    }

    /// 造数据的每一步都要**出声**，并把失败的步骤记下来。
    ///
    /// 为什么不静默：样例数据造失败时，快照只会变成一张**空态**，
    /// 而空态看起来「布局就是这样」—— 验收会直接放过去。
    /// （实测：系列价格表因为列数/值数不齐被录入端挡住，快照上只表现为
    /// 「价格表：无」，从截图里根本看不出这是一次失败。）
    ///
    /// 但「出声」还不够：截图是**会被单独拿走看**的东西，验收动作就是
    /// 「打开图片看一眼」，没人会同时打开 `harness.log`。所以失败的清单
    /// 会被攒进 `seedFailures`，最终由 `stampUntrusted` **盖回到每一张图上**。
    private static func seedStep(_ label: String, _ result: Bool) {
        guard !result else { return }
        seedFailures.append(label)
        log("SNAPSHOT 造数据失败：\(label)")
    }

    /// 本次运行中造数据失败的步骤名（按发生顺序）。空 = 快照可信。
    private static var seedFailures: [String] = []

    // MARK: - 失败横幅

    /// 在产物上盖一条「本次快照不可信」的横幅。
    ///
    /// 返回 `nil` = **没有失败，不该动产物**（这是刻意的不变量：
    /// 可信的截图必须与不加横幅时逐字节相同，否则横幅本身就成了一种噪声）。
    ///
    /// 为什么必须改图而不是只写日志：见 `seedStep` 的注释 ——
    /// 「一张由失败产生的空态截图」和「一张正常的空态截图」必须能一眼分开。
    static func stampUntrusted(_ png: Data, failedSteps: [String]) -> Data? {
        guard !failedSteps.isEmpty else { return nil }
        guard let source = NSBitmapImageRep(data: png),
              let output = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: source.pixelsWide,
                pixelsHigh: source.pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0)
        else {
            log("SNAPSHOT 盖失败横幅失败：无法建立位图上下文")
            return nil
        }

        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))

        // 条带高度与字号都按图高取比例：publish 那张是 2300 高的加长画布，
        // 写死像素会让它在别的尺寸上不是太大就是看不见。
        let barHeight = max(56, height * 0.05)
        NSColor.systemRed.withAlphaComponent(0.94).setFill()
        NSRect(x: 0, y: height - barHeight, width: width, height: barHeight).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: max(18, height * 0.019)),
            .foregroundColor: NSColor.white,
        ]
        let banner = "本次快照不可信 · 造数据有 \(failedSteps.count) 步失败："
            + failedSteps.joined(separator: "、")
        let textHeight = banner.size(withAttributes: attributes).height
        banner.draw(
            at: NSPoint(x: width * 0.012, y: height - barHeight + (barHeight - textHeight) / 2),
            withAttributes: attributes)

        NSGraphicsContext.restoreGraphicsState()
        return output.representation(using: .png, properties: [:])
    }

    // MARK: - 日志

    /// 本次运行的全部日志行。`run` 起手清空、收尾一次性落盘。
    private static var logLines: [String] = []

    /// 既出声（stdout，终端直跑时看得见）也留痕（`harness.log`，沙箱 GUI 启动时唯一出口）。
    /// harness 里所有输出都该走这里，不要直接 `print`。
    private static func log(_ message: String) {
        print(message)
        logLines.append(message)
    }

    /// 把日志写到产物目录旁边 —— 截图和它的诊断信息必须在一起，
    /// 否则「这张空态是布局还是失败」在事后无从判断。
    private static func writeLog(into directory: URL) {
        guard !logLines.isEmpty else { return }
        let text = logLines.joined(separator: "\n") + "\n"
        try? text.data(using: .utf8)?
            .write(to: directory.appendingPathComponent("harness.log"), options: .atomic)
    }

    /// 造两张真 PNG（不依赖任何既有素材）。
    ///
    /// 底色用**设计系统的两个品牌色**（品牌粉 #C9486F / 流程紫 #7B5BD6，
    /// 与 `OpsFlowPalette.accentPink/primaryPurple` 浅色值同源）：
    /// 旧实现用 `systemPink`/`systemIndigo`，那是系统强调色不是品牌色 ——
    /// 亮红 + 亮蓝落在界面里与主题色直接冲突（深色模式下尤其扎眼，2026-09-27 用户点名）。
    /// 构图保持不变：240×240 圆角色块 + 白色内芯（缩略图里读作「图片占位」）。
    private static func makeSampleImages() -> [URL]? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinkhouse-snapshot-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log("SNAPSHOT 样例图目录创建失败：\(error.localizedDescription)")
            return nil
        }
        var urls: [URL] = []
        let brandColors: [NSColor] = [NSColor(hex: 0xC9_486F), NSColor(hex: 0x7B_5BD6)]
        for (index, color) in brandColors.enumerated() {
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
    private static func render<V: View>(_ view: V, size: NSSize, dark: Bool = false) -> Data? {
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
        // ⭐ 默认钉死 aqua（浅色）外观：快照要求**可复现**，而窗口默认跟随系统外观
        // —— 实测晚上（系统自动切深色后）跑快照，控件按 dark 样式渲染（白字/黑底
        // 输入框），叠在设计系统的浅色产物上就是整页读不了。
        // 主题跟随验收：触发内容带 `-dark` 后缀时按 darkAqua 渲染。
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
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
