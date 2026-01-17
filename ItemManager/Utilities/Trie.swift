
import Foundation

class TrieNode {
    var children: [Character: TrieNode] = [:]
    var isTerminating: Bool = false
    var originalWord: String?
    var frequency: Int = 0 // 用于排序
}

class Trie {
    private let root = TrieNode()
    
    func insert(_ word: String) {
        guard !word.isEmpty else { return }
        
        var currentNode = root
        for char in word.lowercased() {
            if currentNode.children[char] == nil {
                currentNode.children[char] = TrieNode()
            }
            currentNode = currentNode.children[char]!
        }
        
        if !currentNode.isTerminating {
            currentNode.isTerminating = true
            currentNode.originalWord = word
        }
        currentNode.frequency += 1
    }
    
    func search(prefix: String, limit: Int = 8) -> [String] {
        guard !prefix.isEmpty else { return [] }
        
        var currentNode = root
        for char in prefix.lowercased() {
            guard let child = currentNode.children[char] else {
                return []
            }
            currentNode = child
        }
        
        return findWords(node: currentNode, limit: limit)
    }
    
    private func findWords(node: TrieNode, limit: Int) -> [String] {
        var results: [String] = []
        
        if node.isTerminating, let word = node.originalWord {
            results.append(word)
        }
        
        for (_, childNode) in node.children {
            let childResults = findWords(node: childNode, limit: limit)
            results.append(contentsOf: childResults)
        }
        
        // 简单的排序策略：按长度排序
        return results.sorted { $0.count < $1.count }.prefix(limit).map { String($0) }
    }
    
    // 清空
    func clear() {
        root.children.removeAll()
    }
}
