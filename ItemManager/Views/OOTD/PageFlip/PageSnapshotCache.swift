//
//  PageSnapshotCache.swift
//  ItemManager
//
//  书页快照缓存管理器 - 用于翻页动画
//

import SwiftUI
import SwiftData
import Combine

/// 书页快照缓存管理器
/// 临时缓存书页的快照图像，用于翻页动画
actor PageSnapshotCache {
    static let shared = PageSnapshotCache()
    
    /// 缓存项
    private struct CacheItem {
        let image: UIImage
        let timestamp: Date
    }
    
    /// 内存缓存
    private var cache: [UUID: CacheItem] = [:]
    
    /// 缓存有效期（秒）
    private let cacheValidDuration: TimeInterval = 300 // 5分钟
    
    /// 最大缓存数量
    private let maxCacheSize = 10
    
    private init() {}
    
    /// 获取缓存的快照
    func getSnapshot(for outfitId: UUID) -> UIImage? {
        guard let item = cache[outfitId] else { return nil }
        
        // 检查是否过期
        if Date().timeIntervalSince(item.timestamp) > cacheValidDuration {
            cache.removeValue(forKey: outfitId)
            return nil
        }
        
        return item.image
    }
    
    /// 设置缓存快照
    func setSnapshot(_ image: UIImage, for outfitId: UUID) {
        // 如果缓存已满，移除最旧的项
        if cache.count >= maxCacheSize {
            removeOldestCache()
        }
        
        cache[outfitId] = CacheItem(image: image, timestamp: Date())
    }
    
    /// 清除特定书页的快照
    func clearSnapshot(for outfitId: UUID) {
        cache.removeValue(forKey: outfitId)
    }
    
    /// 清除所有缓存
    func clearAll() {
        cache.removeAll()
    }
    
    /// 清理过期缓存
    func cleanExpiredCache() {
        let now = Date()
        cache = cache.filter { _, item in
            now.timeIntervalSince(item.timestamp) <= cacheValidDuration
        }
    }
    
    /// 移除最旧的缓存项
    private func removeOldestCache() {
        guard let oldest = cache.min(by: { $0.value.timestamp < $1.value.timestamp }) else { return }
        cache.removeValue(forKey: oldest.key)
    }
}

// MARK: - 书页快照生成器
struct PageSnapshotGenerator {
    /// 生成书页快照
    static func generateSnapshot(for outfit: Outfit) async -> UIImage? {
        let renderer = ImageRenderer(content: OOTDPreviewView(outfit: outfit))
        renderer.scale = UIScreen.main.scale
        
        return renderer.uiImage
    }
    
    /// 生成带占位符的书页快照（用于加载中）
    static func generatePlaceholderSnapshot(for outfit: Outfit) -> UIImage? {
        let renderer = ImageRenderer(
            content: PagePlaceholderView(outfit: outfit)
        )
        renderer.scale = UIScreen.main.scale
        
        return renderer.uiImage
    }
}

// MARK: - 占位符视图
private struct PagePlaceholderView: View {
    let outfit: Outfit
    
    var body: some View {
        ZStack {
            // 背景
            if outfit.canvasType == OOTDCanvasType.blank {
                Color.white
            } else if outfit.canvasType == OOTDCanvasType.custom {
                Color.gray.opacity(0.2)
            } else {
                OOTDMannequinBackgroundView(
                    mannequinAssetID: outfit.mannequinAssetID,
                    contentMode: .fill,
                    opacity: 0.3
                )
            }
            
            // 加载指示器
            VStack {
                ProgressView()
                    .scaleEffect(1.5)
                Text("加载中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .frame(width: 1080, height: 1440)
    }
}

// MARK: - 翻页动画控制器
@MainActor
class PageFlipController: ObservableObject {
    @Published var isFlipping = false
    @Published var flipProgress: CGFloat = 0
    @Published var flipDirection: PageFlipDirection = .next
    
    // 当前页和目标页的快照
    @Published var currentPageImage: UIImage?
    @Published var targetPageImage: UIImage?
    
    private var animationTask: Task<Void, Never>?
    
    /// 开始翻页动画
    func startFlip(
        from currentOutfit: Outfit,
        to targetOutfit: Outfit,
        direction: PageFlipDirection,
        completion: @escaping () -> Void
    ) {
        guard !isFlipping else { return }
        
        isFlipping = true
        flipDirection = direction
        flipProgress = 0
        
        // 获取或生成快照
        Task {
            // 尝试从缓存获取
            let currentImage = await getOrCreateSnapshot(for: currentOutfit)
            let targetImage = await getOrCreateSnapshot(for: targetOutfit)
            
            await MainActor.run {
                self.currentPageImage = currentImage
                self.targetPageImage = targetImage
            }
            
            // 执行动画
            await performFlipAnimation(completion: completion)
        }
    }
    
    /// 获取或创建快照
    private func getOrCreateSnapshot(for outfit: Outfit) async -> UIImage? {
        // 先检查缓存
        if let cached = await PageSnapshotCache.shared.getSnapshot(for: outfit.id) {
            return cached
        }
        
        // 尝试从 snapshotPath 加载
        if outfit.shouldUseStoredSnapshot,
           let path = outfit.snapshotPath,
           let image = ImageManager.shared.loadImage(fileName: path) {
            // 直接调用 actor 方法
            await PageSnapshotCache.shared.setSnapshot(image, for: outfit.id)
            return image
        }
        
        // 生成新快照
        if let image = await PageSnapshotGenerator.generateSnapshot(for: outfit) {
            // 直接调用 actor 方法
            await PageSnapshotCache.shared.setSnapshot(image, for: outfit.id)
            return image
        }
        
        return nil
    }
    
    /// 执行翻页动画
    private func performFlipAnimation(completion: @escaping () -> Void) async {
        let duration: CGFloat = 0.6
        let steps = 60
        let stepDuration = duration / Double(steps)
        
        for i in 0...steps {
            let progress = CGFloat(i) / CGFloat(steps)
            
            // 使用缓动函数
            let easedProgress = easeInOutCubic(progress)
            
            await MainActor.run {
                self.flipProgress = easedProgress
            }
            
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
        }
        
        await MainActor.run {
            self.isFlipping = false
            self.flipProgress = 0
            completion()
        }
    }
    
    /// 缓动函数
    private func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            let f = 2 * t - 2
            return 1 + f * f * f / 2
        }
    }
    
    /// 取消动画
    func cancelFlip() {
        animationTask?.cancel()
        isFlipping = false
        flipProgress = 0
    }
}
