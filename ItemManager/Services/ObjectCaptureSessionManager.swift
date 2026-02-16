import Foundation
import Combine

#if os(iOS)
import SwiftUI
import RealityKit

@available(iOS 17.0, *)
@MainActor
class ObjectCaptureSessionManager: ObservableObject {

    static let shared = ObjectCaptureSessionManager()

    @Published var session: ObjectCaptureSession?
    @Published var state: ObjectCaptureSession.CaptureState = .initializing
    @Published var isCapturing: Bool = false
    @Published var capturedImageCount: Int = 0
    @Published var userCompletedScanPass: Bool = false

    private var imageSaveDirectory: URL?

    private init() {}

    var isSupported: Bool {
        ObjectCaptureSession.isSupported
    }

    func prepareSession() -> ObjectCaptureSession {
        let newSession = ObjectCaptureSession()
        self.session = newSession
        return newSession
    }

    func startDetecting() {
        session?.startDetecting()
    }

    func startCapturing() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[ObjectCapture] 无法获取文档目录")
            return
        }

        let captureDir = documentsDir.appendingPathComponent("ObjectCapture_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
        imageSaveDirectory = captureDir

        session?.beginNewScanPass()
    }

    func pauseCapturing() {
        session?.pause()
    }

    func resumeCapturing() {
        session?.resume()
    }

    func finishCapturing() -> URL? {
        session?.finish()
        return imageSaveDirectory
    }

    func cancelSession() {
        session?.cancel()
        session = nil
        isCapturing = false
        capturedImageCount = 0
        userCompletedScanPass = false
    }

    func reset() {
        session?.cancel()
        session = nil
        state = .initializing
        isCapturing = false
        capturedImageCount = 0
        userCompletedScanPass = false
        imageSaveDirectory = nil
    }
}
#else

import SwiftUI

@MainActor
class ObjectCaptureSessionManager: ObservableObject {
    static let shared = ObjectCaptureSessionManager()

    @Published var session: Any? = nil
    @Published var state: String = "unsupported"
    @Published var isCapturing: Bool = false
    @Published var capturedImageCount: Int = 0
    @Published var userCompletedScanPass: Bool = false

    var isSupported: Bool { false }

    private init() {}

    func prepareSession() -> Any? { nil }
    func startDetecting() {}
    func startCapturing() {}
    func pauseCapturing() {}
    func resumeCapturing() {}
    func finishCapturing() -> URL? { nil }
    func cancelSession() {}
    func reset() {}
}
#endif
