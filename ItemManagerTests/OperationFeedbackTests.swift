import XCTest
import UIKit
import SwiftUI
@testable import ItemManager

final class OperationFeedbackTests: XCTestCase {
    @MainActor
    func testFeedbackHostAppearsAboveSheetWithoutCapturingBackgroundTouches() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let center = OperationFeedbackCenter()
        let coordinator = OperationFeedbackSceneInstaller.Coordinator(center: center)
        let content = UIViewController()
        content.view.backgroundColor = .systemBackground
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = content
        window.isHidden = false
        defer {
            coordinator.window?.isHidden = true
            coordinator.window = nil
            window.isHidden = true
        }
        let sheet = UIViewController()
        sheet.view.backgroundColor = .systemIndigo
        sheet.modalPresentationStyle = .pageSheet
        content.present(sheet, animated: false)
        coordinator.attach(to: scene, isEnabled: true)
        center.show("添加成功，已加入少女衣橱", kind: .success, fishCoins: 50, duration: 30)
        let overlay = try XCTUnwrap(coordinator.window)
        for _ in 0..<30 where overlay.cardFrame.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        // 等 sheet 与辅助窗口完成首轮合成，允许模拟器截取实际画面核对透明区域。
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertFalse(overlay.cardFrame.isEmpty, "消息必须实际渲染到 scene 宿主")
        XCTAssertLessThan(overlay.cardFrame.height, overlay.bounds.height / 2,
                          "短反馈卡片不能占据整屏或阻挡页面的主要操作")
        XCTAssertNotNil(content.presentedViewController)
        XCTAssertGreaterThan(overlay.windowLevel, window.windowLevel)
        XCTAssertFalse(overlay.isKeyWindow)
        let belowCard = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.maxY - 20)
        XCTAssertNil(overlay.hitTest(belowCard, with: nil), "卡片以外的操作必须透传")
        XCTAssertNotNil(overlay.hitTest(CGPoint(x: overlay.cardFrame.midX, y: overlay.cardFrame.midY), with: nil))
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            overlay.drawHierarchy(in: overlay.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "添加成功与鱼币-覆盖Sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
        // 宿主被暂停时不消费队列，恢复后仍显示同一条消息。
        let id = center.current?.id
        coordinator.attach(to: scene, isEnabled: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(center.current?.id, id)
        coordinator.attach(to: scene, isEnabled: true)
    }

    @MainActor
    func testQueuePreservesSuccessAcrossOtherMessagesAndStaleDismissal() async {
        let center = OperationFeedbackCenter()
        center.show("first")
        let first = center.current!.id
        center.show("second", kind: .success)
        XCTAssertEqual(center.messages.count, 2)
        XCTAssertEqual(center.current?.text, "first")
        center.dismiss(id: first)
        XCTAssertEqual(center.current?.text, "second")
        center.dismiss(id: first)
        XCTAssertEqual(center.current?.text, "second")
    }

    @MainActor
    func testCombinedBatchSuccessUsesActualAmountAndDeduplicatesRewards() async throws {
        let name = "OperationFeedbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var status = PetStatus()
        status.dailyFishCoinEarned = PetStatus.dailyFishCoinLimit - 75
        defaults.set(try JSONEncoder().encode(status), forKey: "PetStatus_Data")
        let manager = RewardManager(defaults: defaults)
        let center = OperationFeedbackCenter()
        let rewards: [OperationFeedbackCenter.RewardRequest] = [
            .init(type: .addClothing, operationID: "a"),
            .init(type: .addClothing, operationID: "b")]
        center.succeeded("添加成功，2 条记录", rewards: rewards, rewardManager: manager)
        XCTAssertEqual(center.messages.count, 1)
        XCTAssertEqual(center.current?.kind, .success)
        XCTAssertEqual(center.current?.fishCoins, 75)
        XCTAssertNotNil(center.current?.detail)
        center.succeeded("再次显示", rewards: rewards, rewardManager: manager)
        XCTAssertEqual(center.messages.last?.fishCoins, 0)
        let saved = try JSONDecoder().decode(PetStatus.self, from: defaults.data(forKey: "PetStatus_Data")!)
        XCTAssertEqual(saved.fishCoin, 1075)
    }

    @MainActor
    func testSuccessfulOperationRemainsSuccessfulWhenWalletUnavailable() async {
        let name = "OperationFeedbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = OperationFeedbackCenter()
        center.succeeded("保存成功", rewards: [.init(type: .addClothing, operationID: "new")],
                         rewardManager: RewardManager(defaults: defaults))
        XCTAssertEqual(center.current?.kind, .success)
        XCTAssertEqual(center.current?.fishCoins, 0)
        XCTAssertNotNil(center.current?.detail)
    }
}
