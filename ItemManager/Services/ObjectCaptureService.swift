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

@available(iOS 17.0, *)
@MainActor
class ObjectCaptureService: ObservableObject {
    
    static let shared = ObjectCaptureService()
    
    @Published var stage: ObjectCaptureStage = .idle
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var estimatedRemainingTime: TimeInterval?
    
    private var photogrammetrySession: PhotogrammetrySession?
    private var currentTask: Task<Void, Never>?
    
    private init() {}
    
    var isSupported: Bool {
        PhotogrammetrySession.isSupported
    }
    
    var canStartNewSession: Bool {
        PhotogrammetrySession.isSupported && currentTask == nil
    }
    
    func processImages(_ images: [UIImage], detail: PhotogrammetrySession.Request.Detail = .reduced) async throws -> URL {
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
    
    func processImagesFromDirectory(_ imageDirectory: URL, detail: PhotogrammetrySession.Request.Detail = .reduced) async throws -> URL {
        let modelID = UUID()
        return try await performPhotogrammetry(
            imageDirectory: imageDirectory,
            modelID: modelID,
            detail: detail
        )
    }
    
    func processImagesWithFallback(_ images: [UIImage]) async throws -> URL {
        return try await processImages(images, detail: .reduced)
    }
    
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
        photogrammetrySession?.cancel()
        currentTask = nil
        photogrammetrySession = nil
        stage = .idle
        progress = 0.0
        statusMessage = ""
    }
    
    func reset() {
        cancelProcessing()
        stage = .idle
        progress = 0.0
        statusMessage = ""
        estimatedRemainingTime = nil
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

@available(iOS 17.0, *)
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
