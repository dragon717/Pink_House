//
//  OpsSnapshotHarnessTests.swift
//  PinkHouseOpsTests
//
//  快照 harness 的**可信度**测试。
//
//  ## 为什么值得测
//
//  harness 造样例数据有二十几个步骤，每一步都可能失败。失败时那一步在快照里
//  就是**空的** —— 而「空」看起来像「这个页面的空态设计本来就是这样」，
//  验收时会被直接放过（实测：系列价格表因列数/值数不齐被录入端挡住，
//  界面上只表现为「价格表：无」，从截图完全看不出是一次失败）。
//
//  所以这里锁两件事：
//    · ⭐ `run(into:)` 跑完整套夹具**一步都不许失败** —— 夹具一坏，测试立刻红，
//      不用等人去盯着截图看（这比红色横幅更早发现问题）；
//    · 横幅本身的不变量：**没有失败就绝不改产物**，有失败就必须改。
//

import XCTest
@testable import PinkHouseOps

final class OpsSnapshotHarnessTests: XCTestCase {

    // MARK: - ⭐ 夹具不许失败

    /// 跑一遍完整 harness，断言造数据每一步都成功、六个分区都出了图。
    ///
    /// 这是本文件最重要的一条：它把「验收者要能看出来」变成「CI 直接跑出来」。
    func testHarnessSeedsEveryStepAndWritesEverySection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinkhouse-snapshot-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        OpsSnapshotHarness.run(into: directory)

        let logURL = directory.appendingPathComponent("harness.log")
        let log = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertFalse(log.contains("SNAPSHOT 造数据失败"),
                       "样例数据有步骤失败，快照不可信。完整日志：\n\(log)")
        XCTAssertFalse(log.contains("SNAPSHOT 渲染失败"), "有分区渲染失败：\n\(log)")
        XCTAssertTrue(log.contains("SNAPSHOT 完成：\(OpsSection.allCases.count)/\(OpsSection.allCases.count) 张"),
                      "没有全部产出：\n\(log)")

        for section in OpsSection.allCases {
            let png = directory.appendingPathComponent("\(section.rawValue).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: png.path),
                          "缺分区快照：\(section.rawValue)")
            XCTAssertGreaterThanOrEqual(try Data(contentsOf: png).count, 1_000,
                                        "\(section.rawValue).png 小得不像一张真截图")
        }
    }

    // MARK: - 横幅的不变量

    /// **没有失败 = 一个字节都不许改。**
    ///
    /// 否则「可信的截图」与「加了横幅的截图」会不一样，两次运行无法逐字节比对 ——
    /// 而逐字节比对正是我们确认「没有回归」的手段。
    func testStampingWithoutFailuresLeavesArtifactUntouched() throws {
        let png = try makeSolidPNG(width: 200, height: 120)
        XCTAssertNil(OpsSnapshotHarness.stampUntrusted(png, failedSteps: []))
    }

    func testStampingKeepsGeometryAndPaintsBanner() throws {
        let png = try makeSolidPNG(width: 200, height: 120)
        let stamped = try XCTUnwrap(OpsSnapshotHarness.stampUntrusted(png, failedSteps: ["系列价格表"]))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: stamped))

        XCTAssertEqual(rep.pixelsWide, 200, "横幅不该改变尺寸")
        XCTAssertEqual(rep.pixelsHigh, 120, "横幅不该改变尺寸")

        // 原图纯白；盖章后必须出现一条明显的红色区域，且**不是**整张变红
        let colors = sampleColumn(rep)
        let reds = colors.filter { $0.redComponent > 0.6 && $0.greenComponent < 0.4 }
        XCTAssertGreaterThan(reds.count, 0, "盖上去了但没找到红色横幅")
        XCTAssertLessThan(reds.count, colors.count, "整张图都被涂红了，横幅画法有问题")
    }

    func testDifferentFailureListsRenderDifferentBanners() throws {
        let png = try makeSolidPNG(width: 320, height: 160)
        let one = try XCTUnwrap(OpsSnapshotHarness.stampUntrusted(png, failedSteps: ["系列价格表"]))
        let two = try XCTUnwrap(OpsSnapshotHarness.stampUntrusted(png, failedSteps: ["系列价格表", "商品图绑定"]))
        XCTAssertNotEqual(one, two, "失败步骤名没被画进横幅里（两次结果一模一样）")
    }

    // MARK: - 工具

    /// 造一张纯白 PNG。
    private func makeSolidPNG(width: Int, height: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// 沿中轴纵向取样，用于判断「哪一段被涂红了」。
    private func sampleColumn(_ rep: NSBitmapImageRep) -> [NSColor] {
        let x = rep.pixelsWide / 2
        return stride(from: 2, to: rep.pixelsHigh - 2, by: 4).compactMap {
            rep.colorAt(x: x, y: $0)?.usingColorSpace(.deviceRGB)
        }
    }
}
