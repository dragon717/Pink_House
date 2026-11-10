#if targetEnvironment(simulator)
import UIKit
import XCTest
@testable import ItemManager

@MainActor
final class ReleaseAppIconTests: XCTestCase {
    /// Give each change a separate foreground launch so the system icon confirmation
    /// from a previous selection has the same dismissal boundary as a user visit.
    func testMemberSelection() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Pink House Store ") == true)
        let request = URL.documentsDirectory.appendingPathComponent("ReleaseTestIcon.txt")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: request.path))
        let requestedID = try String(contentsOf: request, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let manager = VIPAppIconManager.shared
        let alternateNames = manager.availableIcons.compactMap(\.alternateIconName)
        XCTAssertEqual(Set(alternateNames).count, 5)
        for option in manager.availableIcons {
            XCTAssertNotNil(UIImage(named: option.previewAssetName))
        }

        try await Task.sleep(for: .seconds(3))
        manager.refreshCurrentIcon()
        XCTAssertTrue(manager.supportsAlternateIcons)
        let requested = try XCTUnwrap(manager.availableIcons.first { $0.id == requestedID })
        let member = VIPManager.shared
        let originalMembership = member.isVIP
        defer { member.isVIP = originalMembership }
        member.isVIP = false
        let locked = await manager.applyIcon(requested)
        XCTAssertFalse(locked.success)

        member.isVIP = true
        let result = await manager.applyIcon(requested)
        try await Task.sleep(for: .seconds(1))
        manager.refreshCurrentIcon()
        XCTAssertTrue(result.success, result.message)
        XCTAssertEqual(UIApplication.shared.alternateIconName, requested.alternateIconName)
        XCTAssertEqual(manager.currentIconID, requested.id)
    }
}
#endif
