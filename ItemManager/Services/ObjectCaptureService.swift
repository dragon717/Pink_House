import Foundation
import Combine

#if os(iOS)
import UIKit
import RealityKit
#endif

enum ObjectCaptureError: LocalizedError {
    case notSupported
    case insufficientImages
    case processingFailed(String)
    case saveFailed
    case invalidInput
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "此设备不支持 Object Capture"
        case .insufficientImages:
            return "需要至少 10 张图片才能生成模型"
        case .processingFailed(let reason):
            return "模型生成失败: \(reason)"
        case .saveFailed:
            return "保存模型失败"
        case .invalidInput:
            return "无效的输入数据"
        case .cancelled:
            return "处理已取消"
        }
    }
}

enum ObjectCaptureStage {
    case idle
    case preparing
    case processing
    case completed
    case failed(ObjectCaptureError)
}

#if os(iOS)

@MainActor
class ObjectCaptureService: ObservableObject {
    
    static let shared = ObjectCaptureService()
    
    @Published var stage: ObjectCaptureStage = .idle
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var estimatedRemainingTime: TimeInterval?
    
    private var photogrammetrySession: Any?
    private var currentTask: Task<Void, Never>?
    
    // MARK: - 暂停/恢复状态
    private var isPaused: Bool = false
    private var pendingContinuation: CheckedContinuation<URL, Error>?
    private var pendingOutputURL: URL?
    private var savedStage: ObjectCaptureStage?
    private var savedProgress: Double = 0.0
    private var savedStatusMessage: String = ""
    
    private init() {}

    private static var canUseOnDevicePhotogrammetry: Bool {
        guard #available(iOS 18.0, *) else { return false }
#if targetEnvironment(simulator)
        return false
#else
        return true
#endif
    }
    
    var isSupported: Bool {
        Self.canUseOnDevicePhotogrammetry
    }
    
    var canStartNewSession: Bool {
        Self.canUseOnDevicePhotogrammetry && currentTask == nil
    }
    
    func processImages(_ images: [UIImage]) async throws -> URL {
        guard #available(iOS 18.0, *), Self.canUseOnDevicePhotogrammetry else {
            throw ObjectCaptureError.notSupported
        }
        return try await processImagesForObjectCapture(images, detail: .reduced)
    }

    @available(iOS 18.0, *)
    private func processImagesForObjectCapture(_ images: [UIImage], detail: PhotogrammetrySession.Request.Detail) async throws -> URL {
        guard images.count >= 10 else {
            throw ObjectCaptureError.insufficientImages
        }
        
        // 限制图片数量，减少内存使用
        let maxImages = min(images.count, 100) // 最多使用100张图片
        let processedImages = Array(images.prefix(maxImages))
        
        await MainActor.run {
            stage = .preparing
            progress = 0.0
            statusMessage = "准备图片数据..."
        }
        
        let modelID = UUID()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObjectCapture_\(modelID.uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let imageDir = tempDir.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        
        // 使用 autoreleasepool 减少内存峰值
        for (index, image) in processedImages.enumerated() {
            autoreleasepool {
                let imageURL = imageDir.appendingPathComponent("image_\(index).jpg")
                // 降低压缩质量以减少内存使用
                if let data = image.jpegData(compressionQuality: 0.7) {
                    try? data.write(to: imageURL)
                }
            }
            
            // 每处理10张图片暂停一下，让系统回收内存
            if index % 10 == 0 {
                await Task.yield()
            }
            
            await MainActor.run {
                progress = Double(index + 1) / Double(processedImages.count) * 0.1
            }
        }
        
        let modelURL = try await performPhotogrammetry(
            imageDirectory: imageDir,
            modelID: modelID,
            detail: detail
        )
        
        // 立即清理临时文件
        try? FileManager.default.removeItem(at: tempDir)
        
        return modelURL
    }
    
    func processImagesFromDirectory(_ imageDirectory: URL) async throws -> URL {
        guard #available(iOS 18.0, *), Self.canUseOnDevicePhotogrammetry else {
            throw ObjectCaptureError.notSupported
        }
        return try await processImagesFromDirectoryForObjectCapture(imageDirectory, detail: .reduced)
    }

    @available(iOS 18.0, *)
    private func processImagesFromDirectoryForObjectCapture(_ imageDirectory: URL, detail: PhotogrammetrySession.Request.Detail) async throws -> URL {
        let modelID = UUID()
        
        // ObjectCaptureSession 创建的目录结构是:
        // ObjectCapture_UUID/
        //   ├── images/          <-- 图片在这里
        //   └── checkpoints/
        // PhotogrammetrySession 需要传入 images 子目录
        
        let imagesDir = imageDirectory.appendingPathComponent("images")
        
        // 详细检查输入目录
        print("[ObjectCaptureService] 开始处理目录: \(imageDirectory.path)")
        print("[ObjectCaptureService] 图片目录: \(imagesDir.path)")
        
        // 检查 images 目录是否存在
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: imagesDir.path, isDirectory: &isDirectory)
        
        guard exists && isDirectory.boolValue else {
            print("[ObjectCaptureService] 错误: images 目录不存在")
            throw ObjectCaptureError.invalidInput
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            let imageFiles = files.filter { ["jpg", "jpeg", "heic", "png"].contains($0.pathExtension.lowercased()) }
            print("[ObjectCaptureService] 找到 \(imageFiles.count) 张图片")
            
            guard imageFiles.count >= 10 else {
                print("[ObjectCaptureService] 错误: 图片数量不足 (\(imageFiles.count)/10)")
                throw ObjectCaptureError.insufficientImages
            }
            
            for (index, file) in imageFiles.enumerated() {
                let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                let size = attrs?[.size] as? Int64 ?? 0
                print("[ObjectCaptureService] 图片 \(index + 1): \(file.lastPathComponent), 大小: \(size) bytes")
            }
        } catch {
            print("[ObjectCaptureService] 读取目录失败: \(error)")
            throw ObjectCaptureError.invalidInput
        }
        
        // 传入 images 子目录给 PhotogrammetrySession
        return try await performPhotogrammetry(
            imageDirectory: imagesDir,
            modelID: modelID,
            detail: detail
        )
    }
    
    func processImagesWithFallback(_ images: [UIImage]) async throws -> URL {
        return try await processImages(images)
    }
    
    @available(iOS 18.0, *)
    private func performPhotogrammetry(
        imageDirectory: URL,
        modelID: UUID,
        detail: PhotogrammetrySession.Request.Detail
    ) async throws -> URL {
        
        await MainActor.run {
            stage = .processing
            progress = 0.0
            statusMessage = "正在初始化 3D 重建...\n这可能需要几分钟时间"
        }
        
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ObjectCaptureError.saveFailed
        }
        
        let modelDir = documentsDir.appendingPathComponent("Models/\(modelID.uuidString)")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        let outputURL = modelDir.appendingPathComponent("model.usdz")
        
        var configuration = PhotogrammetrySession.Configuration()
        configuration.isObjectMaskingEnabled = true
        
        let session = try PhotogrammetrySession(
            input: imageDirectory,
            configuration: configuration
        )
        self.photogrammetrySession = session
        
        let request = PhotogrammetrySession.Request.modelFile(
            url: outputURL,
            detail: detail
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            currentTask = Task {
                do {
                    try session.process(requests: [request])
                    
                    var hasReceivedProgress = false
                    
                    for try await output in session.outputs {
                        if Task.isCancelled {
                            continuation.resume(throwing: ObjectCaptureError.cancelled)
                            return
                        }
                        
                        // 检测是否开始收到进度
                        if case .requestProgress = output {
                            hasReceivedProgress = true
                        }
                        
                        await self.handleOutput(output, continuation: continuation, outputURL: outputURL)
                    }
                } catch {
                    await MainActor.run {
                        self.stage = .failed(.processingFailed(error.localizedDescription))
                    }
                    continuation.resume(throwing: ObjectCaptureError.processingFailed(error.localizedDescription))
                }
            }
        }
    }
    
    @available(iOS 18.0, *)
    private func handleOutput(
        _ output: PhotogrammetrySession.Output,
        continuation: CheckedContinuation<URL, Error>,
        outputURL: URL
    ) async {
        switch output {
        case .requestProgress(let request, let fractionComplete):
            if case .modelFile = request {
                let percent = Int(fractionComplete * 100)
                await MainActor.run {
                    self.progress = 0.1 + fractionComplete * 0.9
                    // 只在有阶段描述时才更新，否则保持阶段描述
                    if self.statusMessage.contains("%") || self.statusMessage.isEmpty {
                        self.statusMessage = "🔄 处理中... \(percent)%"
                    }
                }
            }
            
        case .requestProgressInfo(let request, let progressInfo):
            if case .modelFile = request {
                await MainActor.run {
                    self.estimatedRemainingTime = progressInfo.estimatedRemainingTime
                    if let stageDescription = progressInfo.processingStage?.processingStageString {
                        self.statusMessage = stageDescription
                    }
                }
            }
            
        case .requestComplete(let request, _):
            if case .modelFile = request {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    await MainActor.run {
                        self.stage = .completed
                        self.progress = 1.0
                        self.statusMessage = "✅ 模型生成完成！"
                    }
                    continuation.resume(returning: outputURL)
                } else {
                    await MainActor.run {
                        self.stage = .failed(.saveFailed)
                    }
                    continuation.resume(throwing: ObjectCaptureError.saveFailed)
                }
            }
            
        case .requestError(_, let error):
            await MainActor.run {
                self.stage = .failed(.processingFailed(error.localizedDescription))
            }
            continuation.resume(throwing: ObjectCaptureError.processingFailed(error.localizedDescription))
            
        case .processingCancelled:
            await MainActor.run {
                self.stage = .failed(.cancelled)
            }
            continuation.resume(throwing: ObjectCaptureError.cancelled)
            
        case .inputComplete:
            await MainActor.run {
                self.progress = 0.1
                self.statusMessage = "📂 输入处理完成\n🚀 开始 3D 重建..."
            }
            
        case .invalidSample(let id, let reason):
            print("[ObjectCapture] 无效样本 \(id): \(reason)")
            await MainActor.run {
                self.statusMessage = "⚠️ 部分图片质量不佳\n继续处理其他图片..."
            }
            
        case .skippedSample(let id):
            print("[ObjectCapture] 跳过样本 \(id)")
            
        case .automaticDownsampling:
            await MainActor.run {
                self.statusMessage = "📉 自动优化图片质量..."
            }
            
        @unknown default:
            break
        }
    }
    
    func cancelProcessing() {
        currentTask?.cancel()
        if #available(iOS 18.0, *),
           let session = photogrammetrySession as? PhotogrammetrySession {
            session.cancel()
        }
        currentTask = nil
        photogrammetrySession = nil
        stage = .idle
        progress = 0.0
        statusMessage = ""
        isPaused = false
        pendingContinuation = nil
        pendingOutputURL = nil
    }
    
    func reset() {
        cancelProcessing()
        stage = .idle
        progress = 0.0
        statusMessage = ""
        estimatedRemainingTime = nil
        isPaused = false
        pendingContinuation = nil
        pendingOutputURL = nil
    }
    
    // MARK: - 暂停/恢复功能

    /// 暂停当前处理（当离开页面时调用）
    /// 注意：PhotogrammetrySession 不支持真正的暂停，这里只是保存状态并取消当前任务
    func pauseProcessing() {
        guard case .processing = stage, !isPaused else { return }

        isPaused = true
        savedStage = stage
        savedProgress = progress
        savedStatusMessage = statusMessage

        // 注意：PhotogrammetrySession 没有 pause 方法，只能取消
        // 但取消后无法恢复，所以这里我们只是标记状态，不真正取消
        // 让处理在后台继续运行

        print("[ObjectCaptureService] 建模处理标记为后台运行（页面离开）")
    }

    /// 恢复处理（当回到页面时调用）
    /// 实际上处理一直在后台运行，这里只是恢复UI状态显示
    func resumeProcessing() {
        guard isPaused else { return }

        isPaused = false

        print("[ObjectCaptureService] 建模处理恢复前台显示")
    }

    /// 检查是否处于暂停状态
    var isProcessingPaused: Bool {
        isPaused
    }

    /// 获取保存的状态（用于恢复UI显示）
    var pausedState: (stage: ObjectCaptureStage, progress: Double, statusMessage: String)? {
        guard isPaused, let savedStage = savedStage else { return nil }
        return (savedStage, savedProgress, savedStatusMessage)
    }

    /// 检查处理是否仍在进行中（用于页面恢复时检查）
    var isProcessing: Bool {
        if case .processing = stage { return true }
        if case .preparing = stage { return true }
        return false
    }
    
    // MARK: - 磁盘空间管理
    
    /// 清理旧的模型文件，保留最近 N 个
    func cleanupOldModels(keepRecent: Int = 10) {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let modelsDir = documentsDir.appendingPathComponent("Models")
        
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.creationDateKey])
            
            // 按创建日期排序
            let sortedContents = contents.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2 // 最新的在前
            }
            
            // 删除旧的模型
            if sortedContents.count > keepRecent {
                let oldModels = sortedContents.suffix(from: keepRecent)
                for modelURL in oldModels {
                    try? fileManager.removeItem(at: modelURL)
                    print("[ObjectCaptureService] 清理旧模型: \(modelURL.lastPathComponent)")
                }
            }
            
            // 清理临时文件
            cleanupTempFiles()
            
        } catch {
            print("[ObjectCaptureService] 清理旧模型失败: \(error)")
        }
    }
    
    /// 清理临时文件
    private func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            let objectCaptureDirs = contents.filter { $0.lastPathComponent.hasPrefix("ObjectCapture_") }
            
            for dir in objectCaptureDirs {
                try? FileManager.default.removeItem(at: dir)
            }
            
            if !objectCaptureDirs.isEmpty {
                print("[ObjectCaptureService] 清理 \(objectCaptureDirs.count) 个临时目录")
            }
        } catch {
            print("[ObjectCaptureService] 清理临时文件失败: \(error)")
        }
    }
    
    /// 获取模型目录总大小（MB）
    func getModelsDirectorySize() -> Double {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return 0 }
        
        let modelsDir = documentsDir.appendingPathComponent("Models")
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil)
            var totalSize: Int64 = 0
            
            for url in contents {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
            
            return Double(totalSize) / 1024 / 1024 // 转换为 MB
        } catch {
            return 0
        }
    }
}

@available(iOS 18.0, *)
extension PhotogrammetrySession.Output.ProcessingStage {
    var processingStageString: String {
        switch self {
        case .preProcessing:
            return "🔄 预处理中...\n请保持耐心，即将开始重建"
        case .imageAlignment:
            return "📸 图像对齐中...\n分析照片之间的关联"
        case .pointCloudGeneration:
            return "☁️ 生成点云中...\n构建 3D 空间结构"
        case .meshGeneration:
            return "🕸️ 生成网格中...\n创建模型表面"
        case .textureMapping:
            return "🎨 纹理映射中...\n添加颜色和细节"
        case .optimization:
            return "✨ 优化模型中...\n即将完成"
        @unknown default:
            return "🔄 处理中..."
        }
    }
}

#else

@MainActor
class ObjectCaptureService: ObservableObject {
    static let shared = ObjectCaptureService()
    
    @Published var stage: ObjectCaptureStage = .idle
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var estimatedRemainingTime: TimeInterval?
    
    var isSupported: Bool { false }
    var canStartNewSession: Bool { false }
    
    private init() {}
    
    func processImages(_ images: [Any]) async throws -> URL {
        throw ObjectCaptureError.notSupported
    }
    
    func processImagesFromDirectory(_ imageDirectory: URL) async throws -> URL {
        throw ObjectCaptureError.notSupported
    }
    
    func processImagesWithFallback(_ images: [Any]) async throws -> URL {
        throw ObjectCaptureError.notSupported
    }
    
    func cancelProcessing() {}
    func reset() {}
}

#endif
