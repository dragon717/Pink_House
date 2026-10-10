import XCTest
@testable import PinkHouseOpsCore

final class OpsDownloadedMediaRecoveryTests: XCTestCase {
    func testRecoversOldInterruptedJobWithoutManifestOnlyInRequestedEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for environment in ["development", "production"] {
            let job = root.appendingPathComponent("fetch-" + environment)
            let images = job.appendingPathComponent("images")
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            let request = ["targetEnvironment": environment, "outputDirectory": images.path]
            try JSONSerialization.data(withJSONObject: request).write(to: job.appendingPathComponent("request.json"))
        }
        let recovered = OpsDownloadedMediaRecovery.directories(in: root, environment: "development")
        XCTAssertEqual(recovered.count, 1)
        XCTAssertTrue(recovered[0].path.contains("fetch-development"))
    }

    func testRejectsUnrelatedJobsAndOutputsOutsideDownloadJob() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["publish-seq9", "fetch-old"] {
            let job = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
            let request = ["targetEnvironment": "development", "outputDirectory": root.path]
            try JSONSerialization.data(withJSONObject: request).write(to: job.appendingPathComponent("request.json"))
        }
        XCTAssertTrue(OpsDownloadedMediaRecovery.directories(in: root, environment: "development").isEmpty)
    }
}
