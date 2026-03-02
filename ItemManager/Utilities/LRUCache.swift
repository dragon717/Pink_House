
import Foundation

// 使用字典 + 数组实现 LRU 缓存
// 注意：为了规避 Swift 6.2 编译器在 Release 模式下对泛型类 deinit 的崩溃问题，
// 这个实现使用具体类型而非泛型
protocol LRUCacheKey: Hashable {
    var cacheKey: String { get }
}

protocol LRUCacheValue {
    var cacheValue: Any { get }
}

// 具体类型的缓存实现，避免泛型导致的编译器崩溃
final class LRUCache {
    private var storage: [String: Any] = [:]
    private var accessOrder: [String] = []
    private let capacity: Int
    private let lock = NSLock()
    
    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }
    
    func setValue(_ value: Any, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // 如果 key 已存在，更新值并移动到队尾（最近使用）
        if storage[key] != nil {
            storage[key] = value
            moveToEnd(key: key)
            return
        }
        
        // 如果容量已满，移除最久未使用的（队首）
        if accessOrder.count >= capacity {
            let oldestKey = accessOrder.removeFirst()
            storage.removeValue(forKey: oldestKey)
        }
        
        // 添加新值到队尾
        storage[key] = value
        accessOrder.append(key)
    }
    
    func getValue(for key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let value = storage[key] else { return nil }
        
        // 移动到队尾表示最近使用
        moveToEnd(key: key)
        return value
    }
    
    func removeValue(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        
        storage.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }
    
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        
        storage.removeAll()
        accessOrder.removeAll()
    }
    
    // MARK: - Private
    
    private func moveToEnd(key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}
