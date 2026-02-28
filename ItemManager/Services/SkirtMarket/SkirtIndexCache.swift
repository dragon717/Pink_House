//
//  SkirtIndexCache.swift
//  裙子股市 - 裙子索引缓存服务
//
//  预下载Public DB中的裙子索引到内存，实现高效去重
//

import Foundation
import SwiftData

/// 裙子索引条目 - 内存中的轻量级去重索引
struct SkirtIndexEntry: Hashable {
    let platformID: String          // 平台+商品ID
    let semanticHash: String        // 语义哈希（品牌+名称+类型+颜色）
    let cleanedName: String         // 清洗后的名称
    let brand: String?              // 品牌
    let itemType: String?           // 类型
    let color: String?              // 颜色
    let currentPrice: Double        // 当前价格
    let lastUpdated: Date           // 最后更新时间
    let platform: String            // 来源平台
    let mainImageURL: String?       // 主图URL（用于视觉比对）
    let isDeleted: Bool             // 是否已删除
    
    /// 从LolitaItem创建索引条目
    init(from item: LolitaItem) {
        self.platformID = item.platformID
        self.semanticHash = item.semanticHash ?? ""
        self.cleanedName = item.cleanedName ?? item.rawTitle
        self.brand = item.brand
        self.itemType = item.itemType?.rawValue
        self.color = item.color
        self.currentPrice = item.currentPrice
        self.lastUpdated = item.lastUpdated
        self.platform = item.platform.rawValue
        self.mainImageURL = item.mainImageURL
        self.isDeleted = item.isDeleted
    }
}

/// 裙子索引缓存服务
/// 负责预下载Public DB中的索引到内存，提供高效的去重查询
@MainActor
final class SkirtIndexCache {
    static let shared = SkirtIndexCache()
    
    // MARK: - 缓存数据
    
    /// 语义哈希索引: semanticHash -> [SkirtIndexEntry]
    /// 同一语义哈希可能对应多个平台的同一商品
    private var semanticHashIndex: [String: [SkirtIndexEntry]] = [:]
    
    /// PlatformID索引: platformID -> SkirtIndexEntry
    private var platformIDIndex: [String: SkirtIndexEntry] = [:]
    
    /// 品牌索引: brand -> [SkirtIndexEntry]
    private var brandIndex: [String: [SkirtIndexEntry]] = [:]
    
    /// 缓存最后更新时间
    private var lastCacheUpdate: Date?
    
    /// 缓存有效期（5分钟）
    private let cacheValidityInterval: TimeInterval = 5 * 60
    
    /// 是否正在刷新
    private var isRefreshing = false
    
    /// 刷新队列（防止并发刷新）
    private var refreshContinuation: CheckedContinuation<Void, Never>?
    
    private init() {}
    
    // MARK: - 缓存管理
    
    /// 刷新缓存 - 从Public DB加载所有活跃商品的索引
    func refreshCache() async {
        // 检查是否正在刷新
        guard !isRefreshing else {
            // 等待当前刷新完成
            await withCheckedContinuation { continuation in
                self.refreshContinuation = continuation
            }
            return
        }
        
        // 检查缓存是否仍有效
        if let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityInterval {
            print("📦 索引缓存仍有效，跳过刷新")
            return
        }
        
        isRefreshing = true
        defer {
            isRefreshing = false
            // 唤醒等待的continuation
            refreshContinuation?.resume()
            refreshContinuation = nil
        }
        
        print("🔄 开始刷新裙子索引缓存...")
        
        guard let context = SkirtMarketPersistence.shared.mainContext else {
            print("❌ 无法获取上下文")
            return
        }
        
        // 查询所有未删除的商品（只获取必要的字段）
        let descriptor = FetchDescriptor<LolitaItem>(
            predicate: #Predicate { $0.isDeleted == false }
        )
        
        do {
            let items = try context.fetch(descriptor)
            
            // 清空旧缓存
            semanticHashIndex.removeAll(keepingCapacity: true)
            platformIDIndex.removeAll(keepingCapacity: true)
            brandIndex.removeAll(keepingCapacity: true)
            
            // 构建新索引
            for item in items {
                let entry = SkirtIndexEntry(from: item)
                
                // 1. 添加到语义哈希索引
                if !entry.semanticHash.isEmpty {
                    semanticHashIndex[entry.semanticHash, default: []].append(entry)
                }
                
                // 2. 添加到PlatformID索引
                platformIDIndex[entry.platformID] = entry
                
                // 3. 添加到品牌索引
                if let brand = entry.brand {
                    brandIndex[brand, default: []].append(entry)
                }
            }
            
            lastCacheUpdate = Date()
            
            print("✅ 索引缓存刷新完成: \(items.count) 个商品")
            print("   - 语义哈希索引: \(semanticHashIndex.count) 条")
            print("   - PlatformID索引: \(platformIDIndex.count) 条")
            print("   - 品牌索引: \(brandIndex.count) 个品牌")
            
        } catch {
            print("❌ 刷新索引缓存失败: \(error)")
        }
    }
    
    /// 增量更新缓存 - 只更新指定商品
    func updateCache(with item: LolitaItem) {
        let entry = SkirtIndexEntry(from: item)
        
        // 如果已删除，从缓存中移除
        if item.isDeleted {
            removeFromCache(platformID: item.platformID)
            return
        }
        
        // 更新语义哈希索引
        if !entry.semanticHash.isEmpty {
            // 先移除旧的
            if let oldEntry = platformIDIndex[entry.platformID],
               !oldEntry.semanticHash.isEmpty {
                semanticHashIndex[oldEntry.semanticHash]?.removeAll { $0.platformID == entry.platformID }
            }
            // 添加新的
            semanticHashIndex[entry.semanticHash, default: []].append(entry)
        }
        
        // 更新PlatformID索引
        platformIDIndex[entry.platformID] = entry
        
        // 更新品牌索引
        if let brand = entry.brand {
            // 先移除旧的
            brandIndex[brand]?.removeAll { $0.platformID == entry.platformID }
            // 添加新的
            brandIndex[brand, default: []].append(entry)
        }
    }
    
    /// 从缓存中移除指定商品
    func removeFromCache(platformID: String) {
        guard let entry = platformIDIndex[platformID] else { return }
        
        // 从语义哈希索引移除
        if !entry.semanticHash.isEmpty {
            semanticHashIndex[entry.semanticHash]?.removeAll { $0.platformID == platformID }
        }
        
        // 从PlatformID索引移除
        platformIDIndex.removeValue(forKey: platformID)
        
        // 从品牌索引移除
        if let brand = entry.brand {
            brandIndex[brand]?.removeAll { $0.platformID == platformID }
        }
    }
    
    /// 清空缓存
    func clearCache() {
        semanticHashIndex.removeAll()
        platformIDIndex.removeAll()
        brandIndex.removeAll()
        lastCacheUpdate = nil
        print("🧹 索引缓存已清空")
    }
    
    // MARK: - 去重查询
    
    /// 通过语义哈希查找重复商品 - O(1)复杂度
    func findBySemanticHash(_ hash: String) -> [SkirtIndexEntry] {
        return semanticHashIndex[hash] ?? []
    }
    
    /// 通过PlatformID查找商品 - O(1)复杂度
    func findByPlatformID(_ platformID: String) -> SkirtIndexEntry? {
        return platformIDIndex[platformID]
    }
    
    /// 通过品牌查找商品
    func findByBrand(_ brand: String) -> [SkirtIndexEntry] {
        return brandIndex[brand] ?? []
    }
    
    /// 模糊匹配 - 在内存中计算相似度
    func findSimilar(cleanedName: String, threshold: Double = 0.85) -> [SkirtIndexEntry] {
        var results: [SkirtIndexEntry] = []
        
        for (_, entries) in semanticHashIndex {
            for entry in entries {
                let similarity = calculateSimilarity(cleanedName, entry.cleanedName)
                if similarity >= threshold {
                    results.append(entry)
                }
            }
        }
        
        return results
    }
    
    /// 检查是否存在重复 - 快速检查
    func hasDuplicate(semanticHash: String, platformID: String) -> Bool {
        // 1. 检查语义哈希
        if let entries = semanticHashIndex[semanticHash] {
            // 排除自己，检查是否有其他重复
            return entries.contains { $0.platformID != platformID }
        }
        return false
    }
    
    /// 获取所有缓存的商品数量
    var cachedItemCount: Int {
        return platformIDIndex.count
    }
    
    /// 获取缓存统计信息
    var cacheStats: String {
        return """
        索引缓存统计:
        - 商品总数: \(platformIDIndex.count)
        - 语义哈希: \(semanticHashIndex.count)
        - 品牌数: \(brandIndex.count)
        - 最后更新: \(lastCacheUpdate?.formatted() ?? "未更新")
        """
    }
    
    // MARK: - 私有方法
    
    /// 计算文本相似度（简化版）
    private func calculateSimilarity(_ text1: String, _ text2: String) -> Double {
        let s1 = text1.lowercased()
        let s2 = text2.lowercased()
        
        if s1 == s2 { return 1.0 }
        
        // 简单的包含检查
        if s1.contains(s2) || s2.contains(s1) {
            let ratio = Double(min(s1.count, s2.count)) / Double(max(s1.count, s2.count))
            return 0.8 + ratio * 0.2  // 0.8-1.0之间
        }
        
        // 计算共同子串比例
        let common = commonCharacterCount(s1, s2)
        let total = max(s1.count, s2.count)
        return total > 0 ? Double(common) / Double(total) : 0
    }
    
    /// 计算共同字符数
    private func commonCharacterCount(_ s1: String, _ s2: String) -> Int {
        var count = 0
        var charCount1: [Character: Int] = [:]
        var charCount2: [Character: Int] = [:]
        
        for char in s1 {
            charCount1[char, default: 0] += 1
        }
        
        for char in s2 {
            charCount2[char, default: 0] += 1
        }
        
        for (char, count1) in charCount1 {
            let count2 = charCount2[char, default: 0]
            count += min(count1, count2)
        }
        
        return count
    }
}

// MARK: - 使用示例

/*
// 在任务执行前刷新缓存
await SkirtIndexCache.shared.refreshCache()

// 快速检查重复
if SkirtIndexCache.shared.hasDuplicate(semanticHash: newItem.semanticHash ?? "", 
                                        platformID: newItem.platformID) {
    // 发现重复
}

// 查找语义相同的商品
let duplicates = SkirtIndexCache.shared.findBySemanticHash(newItem.semanticHash ?? "")

// 模糊匹配
let similar = SkirtIndexCache.shared.findSimilar(cleanedName: newItem.cleanedName ?? "")

// 增量更新缓存（插入新商品后）
SkirtIndexCache.shared.updateCache(with: newItem)
*/
