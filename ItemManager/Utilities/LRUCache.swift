
import Foundation

class LRUCache<Key: Hashable, Value> {
    private struct CachePayload {
        let key: Key
        let value: Value
    }
    
    private let capacity: Int
    private let list = DoublyLinkedList<CachePayload>()
    private var nodes = [Key: DoublyLinkedList<CachePayload>.Node]()
    
    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }
    
    func setValue(_ value: Value, for key: Key) {
        let payload = CachePayload(key: key, value: value)
        
        if let node = nodes[key] {
            node.payload = payload
            list.moveToHead(node)
        } else {
            let node = list.addHead(payload)
            nodes[key] = node
        }
        
        if list.count > capacity {
            if let node = list.removeLast() {
                nodes[node.payload.key] = nil
            }
        }
    }
    
    func getValue(for key: Key) -> Value? {
        guard let node = nodes[key] else { return nil }
        list.moveToHead(node)
        return node.payload.value
    }
}

// 简单的双向链表实现
private class DoublyLinkedList<T> {
    class Node {
        var payload: T
        var previous: Node?
        var next: Node?
        
        init(payload: T) {
            self.payload = payload
        }
    }
    
    private(set) var count: Int = 0
    private var head: Node?
    private var tail: Node?
    
    func addHead(_ payload: T) -> Node {
        let node = Node(payload: payload)
        if let head = head {
            node.next = head
            head.previous = node
            self.head = node
        } else {
            head = node
            tail = node
        }
        count += 1
        return node
    }
    
    func moveToHead(_ node: Node) {
        guard node !== head else { return }
        
        let previous = node.previous
        let next = node.next
        
        previous?.next = next
        next?.previous = previous
        
        node.next = head
        node.previous = nil
        
        if node === tail {
            tail = previous
        }
        
        if let head = head {
            head.previous = node
        }
        
        head = node
    }
    
    func removeLast() -> Node? {
        guard let tail = tail else { return nil }
        
        let previous = tail.previous
        previous?.next = nil
        self.tail = previous
        
        if count == 1 {
            head = nil
        }
        
        count -= 1
        return tail
    }
}
