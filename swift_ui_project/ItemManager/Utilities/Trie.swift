
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
    
    func search(prefix: String, limit: Int = 20) -> [String] {
        guard !prefix.isEmpty else { return [] }
        
        var currentNode = root
        for char in prefix.lowercased() {
            guard let child = currentNode.children[char] else {
                return []
            }
            currentNode = child
        }
        
        // 收集所有匹配项，不限制递归深度，只在最后限制数量
        let allMatches = findAllWords(node: currentNode)
        
        // 排序并截取
        return allMatches.sorted { $0.count < $1.count }.prefix(limit).map { String($0) }
    }
    
    private func findAllWords(node: TrieNode) -> [String] {
        var results: [String] = []
        
        if node.isTerminating, let word = node.originalWord {
            results.append(word)
        }
        
        for (_, childNode) in node.children {
            results.append(contentsOf: findAllWords(node: childNode))
        }
        
        return results
    }
    
    // 清空
    func clear() {
        root.children.removeAll()
    }
}
