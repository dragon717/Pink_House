//
//  BottomDockAvoidanceTests.swift
//  ItemManagerTests
//
//  2026-09-24「界面元素遮挡」全量排查的回归锁。
//
//  背景：底部导航 Dock（`MainTabView.customTabBar`）是叠在 tab 内容**之上**的覆盖层，
//  不是系统 TabBar、也不参与安全区计算。曾经有两份重复实现
//  `legacyCustomTabBarAvoidanceInset(...)` 在 iOS 26+ 直接 `return 0`，
//  于是所有走 `AdaptiveSettingsView` 的设置页与「安财」页在新系统上**完全没有**
//  底部预留，最后一个元素被 Dock 盖住。
//
//  这里锁两件事：
//    1. 预留高度只有一个来源，且恒 > 0 —— 不会再被任何系统版本判断吞掉；
//    2. 那份「iOS 26+ 返回 0」的重复实现不许再出现在源码里，
//       所有页面必须走唯一修饰器 `avoidingBottomDock()`。
//

import XCTest
@testable import ItemManager

final class BottomDockAvoidanceTests: XCTestCase {

    // MARK: - 1. 唯一口径 & 恒为正

    func testDockAvoidanceInsetIsSingleSourceAndAlwaysPositive() {
        // Dock 本体几何：高 56、贴底 2（有安全区时）、与内容留 12 的视觉间隙
        XCTAssertEqual(LegacyCustomTabBarLayout.barHeight, 56, accuracy: 0.001)
        XCTAssertEqual(LegacyCustomTabBarLayout.floatingSurfaceGap, 12, accuracy: 0.001)

        // 恒 > 0：任何系统版本都必须为 Dock 留出空间（回归锁）
        XCTAssertGreaterThan(
            LegacyCustomTabBarLayout.floatingSurfaceBottomInset, 0,
            "底部预留不能为 0：Dock 是本 App 的覆盖层，系统不会替我们留空间"
        )

        // 值只能由三个常量派生，禁止在别处再写一个数字
        XCTAssertEqual(
            LegacyCustomTabBarLayout.floatingSurfaceBottomInset,
            LegacyCustomTabBarLayout.barHeight
                + max(LegacyCustomTabBarLayout.bottomSpacingWithSafeArea,
                      LegacyCustomTabBarLayout.bottomSpacingWithoutSafeArea)
                + LegacyCustomTabBarLayout.floatingSurfaceGap,
            accuracy: 0.001
        )

        // 预留量至少要盖住 Dock 本体，否则最后一个元素仍会露出半截
        XCTAssertGreaterThanOrEqual(
            LegacyCustomTabBarLayout.floatingSurfaceBottomInset,
            LegacyCustomTabBarLayout.barHeight
        )
    }

    // MARK: - 2. 旧实现（iOS 26+ 返回 0）不许复活

    /// 判定只针对**代码**：先把行注释与块注释剥掉再匹配。
    /// 否则「注释里提到过旧名字」会被误判成违规（本套件自己就解释过它）。
    private func strippingComments(_ source: String) -> String {
        var result: [String] = []
        var inBlockComment = false
        for rawLine in source.components(separatedBy: "\n") {
            var line = rawLine
            if inBlockComment {
                guard let end = line.range(of: "*/") else { continue }
                line = String(line[end.upperBound...])
                inBlockComment = false
            }
            if let commentStart = line.range(of: "//") {
                line = String(line[line.startIndex..<commentStart.lowerBound])
            }
            if let blockStart = line.range(of: "/*") {
                inBlockComment = true
                line = String(line[line.startIndex..<blockStart.lowerBound])
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    func testObsoleteVersionGatedAvoidanceDoesNotComeBack() throws {
        let fileManager = FileManager.default
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ItemManagerTests/
            .deletingLastPathComponent()   // 仓库根
        let sourcesRoot = repoRoot.appendingPathComponent("ItemManager", isDirectory: true)

        guard fileManager.fileExists(atPath: sourcesRoot.path) else {
            throw XCTSkip("找不到源码目录 \(sourcesRoot.path)（非本机源码树布局，跳过）")
        }
        guard let enumerator = fileManager.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail("无法遍历源码目录 \(sourcesRoot.path)")
            return
        }

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if strippingComments(text).contains("legacyCustomTabBarAvoidanceInset") {
                offenders.append(url.lastPathComponent)
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            底部避让必须收口到唯一修饰器 `avoidingBottomDock()`（Views/Components/BottomDockAvoidance.swift）。
            发现旧的版本门控实现残留：\(offenders.sorted())
            """
        )
    }

    // MARK: - 3. 全量落点清点（不许被悄悄回退）

    /// 2026-09-24 全量排查后必须带底部避让的页面（tab 根 / tab 内 push、且自身不参与 Dock 避让）。
    /// 判据是**代码里有调用**（注释剥掉后再匹配），不是「文件里提到过这个名字」。
    private static let mustAvoidPages: [String] = [
        // 根因页：走 AdaptiveSettingsView 的全部设置页（旧实现在 iOS 26+ 返回 0）
        "Views/Settings/Components/AdaptiveSettingsComponents.swift",
        // 第二份重复实现所在页（「安财」）
        "Views/Wealth/WealthView.swift",
        // 用户截图 1：商品详情
        "Views/ShopCatalog/ShopCatalogProductDetailView.swift",
        // 用户截图 2：系列商品页 + 实体管理页（同一个文件）
        "Views/ShopCatalog/ShopCatalogOpsManageView.swift",
        // tab 根 / 常驻入口
        "Views/MeView.swift",
        "Views/RecycleBinView.swift",
        "Views/ShopCatalog/ShopCatalogViews.swift",
        "Views/ShopCatalog/ShopCatalogOpsView.swift",
        "Views/WardrobeStatisticsDetailView.swift",
        "Views/FavoriteMenuSettingsView.swift",
        "Views/PrivacySettingsView.swift",
        // 手帐 / 日历 / 其它 push 页
        "Views/Calendar/DreamDressCalendarView.swift",
        "Views/OOTD/BookShelfContentView.swift",
        "Views/OOTD/SpatialBookShelfView.swift",
        "Views/OOTD/BookDetail/BookDetailView.swift",
        "Views/ThemeSkin/ThemeSkinDetailView.swift",
        "Views/DepositPlan/DepositNotificationView.swift",
        "Views/Settings/MagicTasksView.swift",
        "Views/Settings/ModelManagementViews.swift",
    ]

    func testCriticalPagesAdoptDockAvoidance() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ItemManagerTests/
            .deletingLastPathComponent()   // 仓库根
        let sourcesRoot = repoRoot.appendingPathComponent("ItemManager", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourcesRoot.path) else {
            throw XCTSkip("找不到源码目录 \(sourcesRoot.path)（非本机源码树布局，跳过）")
        }

        var missing: [String] = []
        for relative in Self.mustAvoidPages {
            let url = sourcesRoot.appendingPathComponent(relative)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                missing.append("\(relative)（文件读不到）")
                continue
            }
            if !strippingComments(text).contains("avoidingBottomDock()") {
                missing.append(relative)
            }
        }
        XCTAssertTrue(missing.isEmpty, "以下页面缺少底部 Dock 避让：\(missing.sorted())")

        // 落点总数下限：防止「把修饰器删了但单点断言还在」这类收缩。
        // 仅统计**调用**（`.avoidingBottomDock()`），定义处是 `func avoidingBottomDock()`。
        var callSiteCount = 0
        if let enumerator = FileManager.default.enumerator(
            at: sourcesRoot, includingPropertiesForKeys: nil
        ) {
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                callSiteCount += strippingComments(text)
                    .components(separatedBy: ".avoidingBottomDock()").count - 1
            }
        }
        XCTAssertGreaterThanOrEqual(
            callSiteCount, 30,
            "底部避让落点只剩 \(callSiteCount) 处，疑似被批量回退"
        )
    }
}
