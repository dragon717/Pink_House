//
//  SpatialAssetManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI
import RealityKit
import Combine

// MARK: - Shadow Types for iOS 26+ Simulation
// 即使在 iOS 26+ 环境下，部分 VisionOS 专属 API 可能仍被标记为 unavailable。
// 此处我们在 iOS 平台提供 Shadow Definition 以启用功能演示。
// 如果未来 SDK 完全支持，可移除此部分。

#if os(iOS)
public enum SpatialViewingMode {
    case spatial3D
    case spatialStereo
}

public struct ImagePresentationComponent: Component {
    public struct Spatial3DImage {
        let url: URL
        
        // Mock Parameters for Enhanced 3D Effect
        // 模拟官方 API 的视差范围配置
        public var disparityRange: ClosedRange<Float> = -1.0...1.0
        // 模拟点云补全开关
        public var pointCloudInfillingEnabled: Bool = true
        
        public init(contentsOf url: URL) { self.url = url }
        
        // 模拟 AI 生成过程
        public func generate() async throws {
            print("[Spatial3DImage] 开始 AI 生成空间数据...")
            print("[Spatial3DImage] 配置: DisparityRange=\(disparityRange), Infilling=\(pointCloudInfillingEnabled)")
            let startTime = Date()
            
            // 模拟 1 秒的生成耗时
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            let duration = Date().timeIntervalSince(startTime)
            print("[Spatial3DImage] AI 生成完成，耗时: \(String(format: "%.2f", duration))秒")
        }
    }
    
    public var desiredViewingMode: SpatialViewingMode = .spatial3D
    
    // 为了模拟效果，我们需要保存图像引用
    public let spatial3DImage: Spatial3DImage
    
    public init(spatial3DImage: Spatial3DImage) {
        self.spatial3DImage = spatial3DImage
    }
}
#endif

// MARK: - SpatialAssetManager
@MainActor
class SpatialAssetManager: ObservableObject {
    static let shared = SpatialAssetManager()
    
    // 发布已准备好的资源
    @Published var spatialImage: ImagePresentationComponent.Spatial3DImage?
    @Published var isReady = false
    @Published var isLoading = false
    
    private var preloadTask: Task<Void, Never>?
    
    // 预加载特定资源
    func preload(imageName: String, extension: String) {
        // 如果已经加载或正在加载，忽略
        guard !isReady && !isLoading else { return }
        
        print("[SpatialAssetManager] 触发预加载: \(imageName)")
        isLoading = true
        
        // 使用 detached 任务避免阻塞 MainActor
        preloadTask = Task.detached(priority: .userInitiated) {
            // 1. 获取文件 URL (处理 Asset Catalog 情况)
            // prepareAssetFile 包含耗时的 I/O 和图片编码
            guard let fileURL = await self.prepareAssetFile(name: imageName, ext: `extension`) else {
                await MainActor.run {
                    print("[SpatialAssetManager] 错误：无法准备资源文件")
                    self.isLoading = false
                }
                return
            }
            
            // 2. 检查缓存 (模拟)
            let hasCached = await self.checkCache(for: imageName)
            
            do {
                // 3. 创建并生成
                // 注意：在真实 iOS 26 API 中，Spatial3DImage 的初始化可能是轻量的，
                // 但 generate() 是耗时的。如果 generate 内部阻塞，也应确保它不在 Main 运行。
                // 我们的 Mock generate 只是 sleep，是异步非阻塞的。
                let image = ImagePresentationComponent.Spatial3DImage(contentsOf: fileURL)
                
                if hasCached {
                    await MainActor.run {
                        print("[SpatialAssetManager] 命中本地缓存，跳过 AI 生成耗时")
                    }
                } else {
                    try await image.generate()
                    await self.markCached(for: imageName)
                }
                
                // 4. 完成 - 回到主线程更新 UI
                await MainActor.run {
                    self.spatialImage = image
                    self.isReady = true
                    self.isLoading = false
                    print("[SpatialAssetManager] 资源准备就绪")
                }
                
            } catch {
                await MainActor.run {
                    print("[SpatialAssetManager] 生成失败: \(error)")
                    self.isLoading = false
                }
            }
        }
    }
    
    func clearCache(for name: String) {
        UserDefaults.standard.removeObject(forKey: "spatial_cache_\(name)")
        isReady = false
        spatialImage = nil
    }
    
    /// 清理所有小世界空间照片缓存
    /// 当 App 版本更新或从备份恢复且版本不一致时调用
    func clearAllCache() {
        print("[SpatialAssetManager] 执行全量缓存清理...")
        
        // 1. 清理 UserDefaults 标记
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        
        for (key, _) in dictionary {
            if key.hasPrefix("spatial_cache_") {
                defaults.removeObject(forKey: key)
                print("[SpatialAssetManager] 移除缓存记录: \(key)")
            }
        }
        
        // 2. 重置内存状态
        isReady = false
        spatialImage = nil
        
        // 3. (可选) 清理临时文件
        // 由于文件名不可知，且临时目录由系统管理，我们主要依赖移除 UserDefaults 标记来强制重新生成。
        // 如果需要更彻底的清理，可以尝试清空临时目录中我们自己生成的文件，但需要小心误删。
        // 目前策略：依赖覆盖写入。
    }
    
    func rebuild(imageName: String, extension: String) {
        clearCache(for: imageName)
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("\(imageName).\(`extension`)" )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        preload(imageName: imageName, extension: `extension`)
    }
    
    // 准备资源文件：如果 Bundle 里找不到文件（可能在 Asset Catalog），则尝试导出到临时文件
    // 声明为 nonisolated 以允许在后台线程运行
    nonisolated private func prepareAssetFile(name: String, ext: String) async -> URL? {
        // 1. 尝试直接从 Bundle 获取
        if let bundleURL = Bundle.main.url(forResource: name, withExtension: ext) {
            return bundleURL
        }
        
        // 2. 尝试从 Asset Catalog 读取并写入临时文件
        print("[SpatialAssetManager] Bundle 中未找到文件，尝试从 Assets 读取...")
        
        // UIImage(named:) 必须在主线程调用
        let image = await MainActor.run { UIImage(named: name) }
        guard let image = image else {
            print("[SpatialAssetManager] Assets 中也找不到图片: \(name)")
            return nil
        }
        
        // 构造临时路径
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("\(name).\(ext)")
        
        // 如果文件已存在，直接返回 (简单的文件缓存)
        // 注意：在开发阶段(DEBUG)，为了支持热替换图片，我们跳过此缓存检查，总是重新写入
        #if !DEBUG // 仅在调试模式下适当不启用缓存检查, 换了图片用-否
        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("[SpatialAssetManager] 使用已存在的临时文件: \(fileURL.path)")
            return fileURL
        }
        #endif
        
        // 耗时操作：图片编码和写入 (在后台线程运行)
        print("[SpatialAssetManager] 开始后台编码图片...")
        var data: Data?
        if ext.lowercased() == "png" {
            data = image.pngData()
        } else if ext.lowercased() == "jpg" || ext.lowercased() == "jpeg" {
            data = image.jpegData(compressionQuality: 1.0)
        }
        
        guard let imageData = data else { return nil }
        
        do {
            try imageData.write(to: fileURL)
            print("[SpatialAssetManager] 已导出图片到: \(fileURL.path)")
            return fileURL
        } catch {
            print("[SpatialAssetManager] 写入临时文件失败: \(error)")
            return nil
        }
    }
    
    // MARK: - Simple Mock Cache Logic
    nonisolated private func checkCache(for name: String) async -> Bool {
        return UserDefaults.standard.bool(forKey: "spatial_cache_\(name)")
    }
    
    nonisolated private func markCached(for name: String) async {
        UserDefaults.standard.set(true, forKey: "spatial_cache_\(name)")
    }
}
