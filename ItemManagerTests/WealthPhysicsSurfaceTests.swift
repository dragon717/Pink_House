import XCTest
import SwiftUI
import SpriteKit
@testable import ItemManager

@MainActor
final class WealthPhysicsSurfaceTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDownWithError() throws {
        windows.forEach { $0.isHidden = true; $0.rootViewController = nil }
        windows = []
    }

    func testSceneIsCreatedOnlyAfterValidLayoutAndRetainedAcrossUpdates() throws {
        var creations = 0
        let host = WealthPhysicsHost<ProbeScene> { size in
            creations += 1
            return ProbeScene(size: size)
        }
        host.update(isActive: true) { _, _ in }
        XCTAssertNil(host.hostedScene)
        let window = mount(host, size: CGSize(width: 320, height: 400))
        let scene = try XCTUnwrap(host.hostedScene)
        XCTAssertTrue(host.scene === scene)
        for index in 1...20 {
            host.update(isActive: index.isMultiple(of: 2)) { _, _ in }
            host.layoutIfNeeded()
            XCTAssertTrue(host.hostedScene === scene)
            XCTAssertTrue(host.scene === scene)
        }
        XCTAssertEqual(creations, 1)
        XCTAssertFalse(host.isPaused)
        XCTAssertFalse(scene.isPaused)
        window.isHidden = true
        host.removeFromSuperview()
        XCTAssertTrue(host.isPaused)
        XCTAssertTrue(scene.isPaused)
    }

    func testFirstPausedFrameIsTransparentAndCanResumeWithoutRecreatingScene() throws {
        let host = WealthPhysicsHost<ProbeScene> { ProbeScene(size: $0) }
        host.update(isActive: false) { _, _ in }
        _ = mount(host)
        let scene = try XCTUnwrap(host.hostedScene)
        XCTAssertTrue(host.allowsTransparency)
        XCTAssertFalse(host.isOpaque)
        XCTAssertEqual(host.backgroundColor?.cgColor.alpha, 0)
        XCTAssertEqual(host.layer.backgroundColor?.alpha, 0)
        XCTAssertEqual(scene.backgroundColor.cgColor.alpha, 0)
        XCTAssertTrue(host.isPaused)
        XCTAssertTrue(scene.isPaused)
        XCTAssertEqual(scene.resumeCount, 0)

        host.update(isActive: true) { _, _ in }
        XCTAssertTrue(host.scene === scene)
        XCTAssertFalse(host.isPaused)
        XCTAssertFalse(scene.isPaused)
        XCTAssertEqual(scene.resumeCount, 1)
        host.update(isActive: true) { _, _ in }
        XCTAssertEqual(scene.resumeCount, 1, "普通 SwiftUI 重绘不能重复启动传感器")
    }

    func testDetachAndReturnResumeSameSceneAndTearDownReleasesIt() throws {
        let host = WealthPhysicsHost<ProbeScene> { ProbeScene(size: $0) }
        host.update(isActive: true) { _, _ in }
        let window = mount(host)
        let scene = try XCTUnwrap(host.hostedScene)
        host.removeFromSuperview()
        XCTAssertTrue(scene.isPaused)
        window.rootViewController?.view.addSubview(host)
        host.layoutIfNeeded()
        XCTAssertTrue(host.scene === scene)
        XCTAssertFalse(scene.isPaused)
        host.tearDown()
        XCTAssertTrue(scene.isPaused)
        XCTAssertNil(host.scene)
        XCTAssertNil(host.hostedScene)
    }

    func testSizeAndConfigurationAlwaysReachThePresentedScene() throws {
        let host = WealthPhysicsHost<ProbeScene> { ProbeScene(size: $0) }
        host.update(isActive: true) { scene, size in scene.userData = ["width": size.width] }
        _ = mount(host)
        let scene = try XCTUnwrap(host.hostedScene)
        host.frame.size = CGSize(width: 600, height: 240)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        XCTAssertEqual(scene.size, host.bounds.size)
        XCTAssertEqual(scene.userData?["width"] as? CGFloat, 600)
        XCTAssertTrue(host.scene === scene)
    }

    func testGoldAndSilverPopulate253BeansAndFollowChangedAmount() {
        let gold = GoldScene(size: CGSize(width: 320, height: 400))
        let silver = SilverScene(size: gold.size)
        gold.updateBoundary(CGRect(origin: .zero, size: gold.size))
        silver.updateBoundary(CGRect(origin: .zero, size: silver.size))
        gold.updateBeans(totalWeight: 253.99, beanWeight: 1)
        silver.updateBeans(totalWeight: 12699.5, beanWeight: 50)
        for frame in 0..<6 { gold.update(Double(frame)); silver.update(Double(frame)) }
        XCTAssertEqual(gold.children.count, 253)
        XCTAssertEqual(silver.children.count, 253)
        gold.pauseSimulation()
        gold.updateBeans(totalWeight: 1, beanWeight: 1)
        gold.update(7)
        XCTAssertEqual(gold.children.count, 253)
        gold.resumeSimulation()
        for frame in 8..<11 { gold.update(Double(frame)) }
        XCTAssertEqual(gold.children.count, 1)
        gold.pauseSimulation()
        silver.pauseSimulation()
    }

    func testVirtualCoinsKeepWalletConversionAndResizeTheirBoundary() throws {
        let scene = VirtualCoinScene(size: CGSize(width: 320, height: 400))
        scene.updateMeowCoins(count: 3)
        scene.updateFishCoins(count: 2500)
        scene.updateBoneCoins(count: 4999)
        scene.update(0)
        XCTAssertEqual(scene.children.count, 9)
        let originalBoundary = scene.physicsBody
        scene.size = CGSize(width: 600, height: 240)
        let body = try XCTUnwrap(scene.physicsBody)
        XCTAssertEqual(body.categoryBitMask, VirtualCoinPhysicsCategory.wall)
        XCTAssertFalse(body === originalBoundary, "旋转/布局改变后必须重建边界")
        scene.updateMeowCoins(count: -10)
        scene.updateFishCoins(count: 0)
        scene.updateBoneCoins(count: 0)
        scene.update(1)
        XCTAssertEqual(scene.children.count, 0)
        scene.pauseSimulation()
    }

    func testInvalidAmountsCannotOverflowOrLeavePreviousBeansVisible() {
        for weight in [Double.nan, .infinity, -.infinity, -1, 0] {
            XCTAssertEqual(WealthVisualCount.beans(totalWeight: weight, beanWeight: 1, limit: 5000), 0)
        }
        for unit in [Double.nan, .infinity, 0, -1] {
            XCTAssertEqual(WealthVisualCount.beans(totalWeight: 253, beanWeight: unit, limit: 5000), 0)
        }
        XCTAssertEqual(WealthVisualCount.beans(totalWeight: .greatestFiniteMagnitude, beanWeight: .leastNonzeroMagnitude, limit: 5000), 5000)
        XCTAssertEqual(WealthVisualCount.beans(totalWeight: 0.99, beanWeight: 1, limit: 5000), 0)
        let scene = GoldScene(size: CGSize(width: 320, height: 400))
        scene.updateBeans(totalWeight: 10, beanWeight: 1)
        scene.update(0)
        XCTAssertEqual(scene.children.count, 10)
        scene.updateBeans(totalWeight: .nan, beanWeight: 1)
        scene.update(1)
        XCTAssertTrue(scene.children.isEmpty)
    }

    func testCustomBackgroundAndDefaultBoundaryStayInsideViewport() {
        let size = CGSize(width: 320, height: 600)
        let fitted = WealthContainerLayout(size: size, customImageSize: CGSize(width: 1000, height: 500))
        XCTAssertEqual(fitted.frame, CGRect(x: 0, y: 220, width: 320, height: 160))
        XCTAssertEqual(fitted.physicsBoundary(in: size), fitted.frame)
        XCTAssertEqual(WealthContainerLayout(size: size, customImageSize: nil).frame, CGRect(origin: .zero, size: size))
        XCTAssertEqual(WealthContainerLayout(size: size, customImageSize: .zero).frame, CGRect(origin: .zero, size: size))
    }

    private func mount<Scene: SKScene & WealthPhysicsScene>(_ host: WealthPhysicsHost<Scene>, size: CGSize = CGSize(width: 320, height: 400)) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIViewController()
        window.rootViewController = controller
        host.frame = CGRect(origin: .zero, size: size)
        controller.view.addSubview(host)
        window.isHidden = false
        host.setNeedsLayout()
        host.layoutIfNeeded()
        windows.append(window)
        return window
    }

    private final class ProbeScene: SKScene, WealthPhysicsScene {
        var resumeCount = 0
        func pauseSimulation() { isPaused = true }
        func resumeSimulation() { resumeCount += 1; isPaused = false }
    }
}
