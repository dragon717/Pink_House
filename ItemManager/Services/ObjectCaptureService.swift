import Foundation
import Combine

#if os(iOS)
import UIKit
#endif

enum ObjectCaptureError: LocalizedError {
    case notSupported
    case insufficientImages
    case processingFailed(String)
    case saveFailed
    case networkError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "此设备不支持 Object Capture"
        case .insufficientImages:
            return "需要至少 20 张图片才能生成模型"
        case .processingFailed(let reason):
            return "模型生成失败: \(reason)"
        case .saveFailed:
            return "保存模型失败"
        case .networkError(let reason):
            return "网络错误: \(reason)"
        case .invalidResponse:
            return "无效的服务器响应"
        }
    }
}

enum ObjectCaptureStage {
    case idle
    case preparing
    case uploading
    case processing
    case downloading
    case completed
    case failed(ObjectCaptureError)
}

@MainActor
class ObjectCaptureService: ObservableObject {
    
    static let shared = ObjectCaptureService()
    
    @Published var stage: ObjectCaptureStage = .idle
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?
    
    private init() {}
    
    var isSupported: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
    
    var canStartNewSession: Bool {
        currentTask == nil
    }
    
    // MARK: - Process Images to 3D Model
    
    #if os(iOS)
    func processImages(_ images: [UIImage]) async throws -> URL {
        guard images.count >= 20 else {
            throw ObjectCaptureError.insufficientImages
        }
        
        await MainActor.run {
            stage = .preparing
            progress = 0.0
            statusMessage = "准备图片数据..."
        }
        
        // 创建临时目录保存图片
        let modelID = UUID()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObjectCapture_\(modelID.uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let imageDir = tempDir.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        
        // 保存图片
        for (index, image) in images.enumerated() {
            let imageURL = imageDir.appendingPathComponent("image_\(index).jpg")
            if let data = image.jpegData(compressionQuality: 0.9) {
                try data.write(to: imageURL)
            }
            
            await MainActor.run {
                progress = Double(index + 1) / Double(images.count) * 0.2
            }
        }
        
        // 上传到服务器处理
        let modelURL = try await uploadAndProcessImages(imageDirectory: imageDir, modelID: modelID)
        
        // 清理临时文件
        try? FileManager.default.removeItem(at: tempDir)
        
        return modelURL
    }
    
    private func uploadAndProcessImages(imageDirectory: URL, modelID: UUID) async throws -> URL {
        await MainActor.run {
            stage = .uploading
            progress = 0.2
            statusMessage = "上传图片到服务器..."
        }
        
        // TODO: 实现实际上传逻辑
        // 这里模拟上传和处理过程
        
        // 模拟上传进度
        for i in 0...5 {
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            await MainActor.run {
                progress = 0.2 + Double(i) / 5.0 * 0.3
            }
        }
        
        await MainActor.run {
            stage = .processing
            progress = 0.5
            statusMessage = "服务器正在生成3D模型..."
        }
        
        // 模拟处理进度
        for i in 0...10 {
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
            await MainActor.run {
                progress = 0.5 + Double(i) / 10.0 * 0.4
            }
        }
        
        await MainActor.run {
            stage = .downloading
            progress = 0.9
            statusMessage = "下载生成的模型..."
        }
        
        // 保存到文档目录
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ObjectCaptureError.saveFailed
        }
        
        let modelDir = documentsDir.appendingPathComponent("Models/\(modelID.uuidString)")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        let modelURL = modelDir.appendingPathComponent("model.usdz")
        
        // TODO: 从服务器下载实际的模型文件
        // 这里创建一个空的占位文件
        try Data().write(to: modelURL)
        
        await MainActor.run {
            stage = .completed
            progress = 1.0
            statusMessage = "模型生成完成"
        }
        
        return modelURL
    }
    
    func processImagesFromDirectory(_ imageDirectory: URL) async throws -> URL {
        // 从目录加载图片
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: imageDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
        
        var images: [UIImage] = []
        for url in fileURLs {
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        
        return try await processImages(images)
    }
    
    func processImagesWithFallback(_ images: [UIImage]) async throws -> URL {
        return try await processImages(images)
    }
    #endif
    
    func reset() {
        currentTask?.cancel()
        currentTask = nil
        stage = .idle
        progress = 0.0
        statusMessage = ""
    }
}

// MARK: - API Models

struct ObjectCaptureRequest: Codable {
    let modelID: String
    let imageCount: Int
    let quality: String
}

struct ObjectCaptureResponse: Codable {
    let modelID: String
    let status: String
    let downloadURL: String?
    let errorMessage: String?
}
