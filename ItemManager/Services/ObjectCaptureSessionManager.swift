import Foundation
import Combine
import SwiftUI
#if OBJECT_CAPTURE_ENABLED
import RealityKit
#endif

// iOS 17.x 热修：Object Capture session 类型默认不编译，避免启动时绑定 iOS 18+ RealityKit 符号。
#if os(iOS) && OBJECT_CAPTURE_ENABLED
@available(iOS 18.0, *)
@MainActor
class ObjectCaptureSessionManager: ObservableObject {

    static let shared = ObjectCaptureSessionManager()

    @Published var session: ObjectCaptureSession?
    @Published var state: ObjectCaptureSession.CaptureState = .initializing
    @Published var isCapturing: Bool = false
    @Published var capturedImageCount: Int = 0
    @Published var userCompletedScanPass: Bool = false
    @Published var initializationError: Error?
    @Published var isInitializing: Bool = false
    @Published var numberOfShotsTaken: Int = 0
    @Published var maximumNumberOfInputImages: Int = 0
    @Published var currentOrbit: Int = 1
    @Published var isObjectFlippable: Bool = true

    private var imageSaveDirectory: URL?
    
    // 公共访问器，用于获取图像保存目录
    var currentImageDirectory: URL? {
        imageSaveDirectory
    }
    private var observationTasks: [Task<Void, Never>] = []

    private init() {}

    var isSupported: Bool {
        // 不直接访问 ObjectCaptureSession.isSupported，避免 iOS 17.x 启动时
        // 绑定较新 RealityKit/ObjectCapture 符号导致 dyld 崩溃。本类型整体只在
        // iOS 18+ UI 中使用，实际创建 session 失败会在 prepareSession 中处理。
        true
    }

    /// 准备 Object Capture Session
    /// 根据 Apple 官方文档，调用 start 后 session 会进入 ready 状态
    /// 然后需要调用 startDetecting() 进入 detecting 状态
    func prepareSession() -> ObjectCaptureSession? {
        guard isSupported else {
            print("[ObjectCapture] 设备不支持 Object Capture")
            return nil
        }

        // 清理之前的任务
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()

        isInitializing = true
        initializationError = nil

        // 创建保存目录结构
        // 根据 Apple 官方示例，需要创建 images 和 checkpoints 子目录
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[ObjectCapture] 无法获取文档目录")
            return nil
        }

        let captureDir = documentsDir.appendingPathComponent("ObjectCapture_\(UUID().uuidString)")
        let imagesDir = captureDir.appendingPathComponent("images")
        let checkpointsDir = captureDir.appendingPathComponent("checkpoints")

        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: checkpointsDir, withIntermediateDirectories: true)
            imageSaveDirectory = captureDir
            print("[ObjectCapture] 创建捕获目录: \(captureDir.path)")
        } catch {
            print("[ObjectCapture] 创建目录失败: \(error)")
            return nil
        }

        // 创建 session
        let newSession = ObjectCaptureSession()
        self.session = newSession
        setupStateObservation(for: newSession)

        // 配置并启动 session
        // 根据 Apple 官方示例，需要设置 checkpointDirectory
        var configuration = ObjectCaptureSession.Configuration()
        configuration.isOverCaptureEnabled = true
        configuration.checkpointDirectory = checkpointsDir

        // 检查省电模式，如果开启则降低质量设置
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            print("[ObjectCapture] 省电模式开启，降低扫描质量")
            // 在省电模式下降低帧率或质量
            // 注意：ObjectCaptureSession.Configuration 没有直接的 quality 设置
            // 但可以通过其他方式优化
        }

        newSession.start(imagesDirectory: imagesDir, configuration: configuration)
        print("[ObjectCapture] Session 已启动，等待进入 ready 状态...")

        // 检查启动是否立即失败
        if case let .failed(error) = newSession.state {
            print("[ObjectCapture] 启动失败: \(error)")
            initializationError = error
            isInitializing = false
            return nil
        }

        return newSession
    }

    /// 开始检测物体
    /// 需要在 ready 状态下调用
    func startDetecting() -> Bool {
        guard let session = session else {
            print("[ObjectCapture] 错误: session 未初始化")
            return false
        }

        // 检查当前状态
        if case .ready = session.state {
            let result = session.startDetecting()
            print("[ObjectCapture] startDetecting() 调用结果: \(result)")
            return result
        } else {
            print("[ObjectCapture] 错误: 当前状态为 \(session.state)，无法调用 startDetecting()")
            return false
        }
    }

    /// 开始捕获
    /// 在 detecting 状态下调用，进入 capturing 状态
    func startCapturing() {
        guard let session = session else {
            print("[ObjectCapture] 错误: session 未初始化")
            return
        }

        if case .detecting = session.state {
            session.startCapturing()
            print("[ObjectCapture] 开始捕获")
        } else {
            print("[ObjectCapture] 错误: 当前状态为 \(session.state)，无法调用 startCapturing()")
        }
    }

    private var metricsTimer: Timer?

    private func setupStateObservation(for session: ObjectCaptureSession) {
        // 使用更长的间隔减少 CPU 使用
        let stateTask = Task<Void, Never> { [weak self] in
            for await newState in session.stateUpdates {
                guard let self = self else { break }
                // 如果 session 已被清理，退出循环
                guard self.session != nil else { break }
                // 减少主线程更新频率
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                await MainActor.run {
                    // 再次检查 session 是否有效
                    guard self.session != nil else { return }
                    self.state = newState
                    self.handleStateChange(newState)
                }
            }
        }
        observationTasks.append(stateTask)

        let feedbackTask = Task<Void, Never> { [weak self] in
            for await _ in session.feedbackUpdates {
                guard let self = self else { break }
                // 如果 session 已被清理，退出循环
                guard self.session != nil else { break }
                await MainActor.run {
                    // 再次检查 session 是否有效
                    guard self.session != nil else { return }
                    self.checkCaptureProgress()
                    self.updateSessionMetrics()
                }
            }
        }
        observationTasks.append(feedbackTask)

        // 使用更长的更新间隔
        metricsTimer?.invalidate()
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, let currentSession = self.session else {
                timer.invalidate()
                return
            }
            self.userCompletedScanPass = currentSession.userCompletedScanPass
            self.updateSessionMetrics()
        }
    }

    private func updateSessionMetrics() {
        guard let session = session else { return }
        numberOfShotsTaken = session.numberOfShotsTaken
        maximumNumberOfInputImages = session.maximumNumberOfInputImages
    }

    private func checkCaptureProgress() {
        guard let captureDir = imageSaveDirectory else { return }
        let imagesDir = captureDir.appendingPathComponent("images")
        do {
            let files = try FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)
            let imageFiles = files.filter { ["jpg", "heic", "png"].contains($0.pathExtension.lowercased()) }
            capturedImageCount = imageFiles.count
        } catch {
            // 忽略错误
        }
    }

    private func handleStateChange(_ newState: ObjectCaptureSession.CaptureState) {
        switch newState {
        case .initializing:
            print("[ObjectCapture] 正在初始化...")
        case .ready:
            isInitializing = false
            print("[ObjectCapture] 准备就绪，等待用户开始检测")
        case .detecting:
            isInitializing = false
            print("[ObjectCapture] 正在检测物体...")
        case .capturing:
            isCapturing = true
            print("[ObjectCapture] 正在捕获...")
        case .completed:
            isCapturing = false
            print("[ObjectCapture] 捕获完成")
        case .failed(let error):
            isCapturing = false
            isInitializing = false
            initializationError = error
            print("[ObjectCapture] 错误: \(error.localizedDescription)")
        @unknown default:
            break
        }
    }

    func finishCapturing() -> URL? {
        // 检查当前状态，只有在 capturing 或 detecting 状态下才能调用 finish
        guard let session = session else {
            print("[ObjectCapture] 错误: session 为 nil")
            return nil
        }
        
        switch session.state {
        case .capturing, .detecting:
            session.finish()
            print("[ObjectCapture] 完成捕获")
        case .ready:
            print("[ObjectCapture] 警告: 在 ready 状态下调用 finish，可能没有足够图片")
            session.finish()
        default:
            print("[ObjectCapture] 警告: 当前状态为 \(session.state)，无法调用 finish")
        }
        
        return imageSaveDirectory
    }
    
    /// 等待捕获真正完成并获取最终目录
    func finishCapturingAsync() async -> URL? {
        guard let session = session else {
            print("[ObjectCapture] 错误: session 为 nil")
            return nil
        }
        
        // 调用 finish
        session.finish()
        print("[ObjectCapture] 已调用 finish，等待完成...")
        
        // 等待状态变为 completed 或 failed，最多等待5秒
        for _ in 0..<50 {
            if case .completed = session.state {
                print("[ObjectCapture] 捕获已完成")
                break
            }
            if case .failed = session.state {
                print("[ObjectCapture] 捕获失败")
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        return imageSaveDirectory
    }

    func cancelSession() {
        metricsTimer?.invalidate()
        metricsTimer = nil
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
        session?.cancel()
        session = nil
        isCapturing = false
        capturedImageCount = 0
        userCompletedScanPass = false
        isInitializing = false
        print("[ObjectCapture] 会话已取消")
    }

    func reset() {
        metricsTimer?.invalidate()
        metricsTimer = nil
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
        session?.cancel()
        session = nil
        state = .initializing
        isCapturing = false
        capturedImageCount = 0
        userCompletedScanPass = false
        imageSaveDirectory = nil
        initializationError = nil
        isInitializing = false
        print("[ObjectCapture] 已重置")
    }
}

#elseif os(iOS)

@available(iOS 18.0, *)
@MainActor
class ObjectCaptureSessionManager: ObservableObject {
    static let shared = ObjectCaptureSessionManager()
    @Published var isInitializing: Bool = false
    @Published var initializationError: Error?
    @Published var isCapturing: Bool = false
    @Published var capturedImageCount: Int = 0
    @Published var userCompletedScanPass: Bool = false
    @Published var numberOfShotsTaken: Int = 0
    @Published var maximumNumberOfInputImages: Int = 0
    @Published var currentOrbit: Int = 1
    @Published var isObjectFlippable: Bool = true

    private init() {}

    var isSupported: Bool { false }
    var currentImageDirectory: URL? { nil }

    func reset() {}
    func cancelSession() {}
}

#endif
