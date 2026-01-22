//
//  SeriesAnalyzer.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/18/26.
//

import Foundation

struct SeriesInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let styleCount: Int
    let itemCount: Int
    let totalBalance: Decimal
    let totalDeposit: Decimal
}

struct SeriesInput: Sendable {
    let id: UUID
    let name: String
    let balance: Decimal
    let deposit: Decimal
    let stock: Int
}

class SeriesAnalyzer {
    static let shared = SeriesAnalyzer()
    
    // Simplified strategy: Prefix based (First 2-4 characters)
    // As requested: "不用 关键字原则了，直接用前缀（前2-4字 同前缀）即为一个系列，那也就不用屏蔽字了"
    func analyzeSeries(from clothings: [Clothing]) async -> [SeriesInfo] {
        // Convert to Sendable structs to safely pass to detached task
        let inputs = clothings.map { 
            SeriesInput(id: $0.id, name: $0.name, balance: $0.balance, deposit: $0.deposit, stock: $0.stock) 
        }
        
        return await Task.detached(priority: .userInitiated) {
            // We need to calculate stats based on ALL items, not deduplicated ones.
            // But for Style Count, we need to know unique styles.
            
            var candidateStyleKeys: [String: Set<String>] = [:] // Series -> Set of "Name|Price" keys
            var candidateItemCounts: [String: Int] = [:] // Series -> Total Stock
            var candidateBalances: [String: Decimal] = [:]
            var candidateDeposits: [String: Decimal] = [:]
            var candidateClothingIDs: [String: Set<UUID>] = [:]
            
            // 1. Generate candidates from each clothing name
            for clothing in inputs {
                let name = clothing.name
                let candidates = self.generateCandidates(from: name)
                
                // Style Key: Name + Price info (ignoring stock)
                let styleKey = "\(clothing.name)|\(clothing.deposit)|\(clothing.balance)"
                
                for candidate in candidates {
                    candidateStyleKeys[candidate, default: []].insert(styleKey)
                    
                    let stock = clothing.stock
                    candidateItemCounts[candidate, default: 0] += stock
                    
                    candidateBalances[candidate, default: 0] += (clothing.balance * Decimal(stock))
                    candidateDeposits[candidate, default: 0] += (clothing.deposit * Decimal(stock))
                    candidateClothingIDs[candidate, default: []].insert(clothing.id)
                }
            }
            
            // 2. Filter and Refine
            var seriesList: [SeriesInfo] = []
            
            // Get all valid candidates (style count >= 2)
            // Use Style Count to determine if it's a series? Or Item Count?
            // Usually a series implies multiple styles.
            let validCandidates = candidateStyleKeys.keys.filter { key in
                return (candidateStyleKeys[key]?.count ?? 0) >= 2
            }
            
            // Sort by length descending to handle subsumption (prefer longer names first)
            let sortedCandidates = validCandidates.sorted { $0.count > $1.count }
            
            for candidate in sortedCandidates {
                let styleCount = candidateStyleKeys[candidate]?.count ?? 0
                let itemCount = candidateItemCounts[candidate] ?? 0
                let ids = candidateClothingIDs[candidate]!
                
                // Redundancy Check:
                // If this candidate is a prefix of an already added series,
                // AND it covers the exact same set of items, then it's redundant.
                var isRedundant = false
                for existing in seriesList {
                    if existing.name.localizedCaseInsensitiveContains(candidate) {
                        if let existingIDs = candidateClothingIDs[existing.name], existingIDs == ids {
                            isRedundant = true
                            break
                        }
                    }
                }
                
                if !isRedundant {
                    seriesList.append(SeriesInfo(
                        name: candidate, 
                        styleCount: styleCount,
                        itemCount: itemCount,
                        totalBalance: candidateBalances[candidate] ?? 0,
                        totalDeposit: candidateDeposits[candidate] ?? 0
                    ))
                }
            }
            
            // Sort by total balance descending (priority for deposit plan), then by style count
            return seriesList.sorted {
                if $0.totalBalance != $1.totalBalance {
                    return $0.totalBalance > $1.totalBalance
                }
                return $0.styleCount > $1.styleCount
            }
        }.value
    }
    
    func generateCandidates(from text: String) -> Set<String> {
        var candidates: Set<String> = []
        
        // Sanitize text: remove special characters (brackets, etc.)
        // As requested: "如 【chi】 和 chi 和 [chi] 都算成一个系列， 系列名是 chi （去掉特殊符号）"
        let sanitized = sanitize(text)
        
        // Take first 2, 3, 4 characters as candidates
        let chars = Array(sanitized)
        let lengths = [2, 3, 4]
        
        for len in lengths {
            if chars.count >= len {
                let prefix = String(chars.prefix(len)).trimmingCharacters(in: .whitespacesAndNewlines)
                // Relaxed check: we use the sanitized prefix even if trimming changed its length slightly,
                // as long as it's not empty.
                if !prefix.isEmpty {
                   candidates.insert(prefix)
                }
            }
        }
        
        return candidates
    }
    
    private func sanitize(_ text: String) -> String {
        // Remove brackets and common special symbols that might wrap the series name
        // Keep alphanumeric, spaces, and basic punctuation that might be part of name (like dash?)
        // Actually, user wants to remove "special symbols".
        // Let's remove brackets: []【】(){}<>《》
        let charactersToRemove = CharacterSet(charactersIn: "[]【】(){}<>《》")
        return text.components(separatedBy: charactersToRemove).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    var isNumber: Bool {
        return Double(self) != nil
    }
}
