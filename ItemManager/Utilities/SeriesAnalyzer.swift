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
    let count: Int
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
            // Deduplicate inputs: Keep only unique combinations of name, deposit, balance, and stock
            var seenKeys: Set<String> = []
            var uniqueInputs: [SeriesInput] = []
            
            for input in inputs {
                // Create a unique key for the clothing
                // Using a combination of name and financial/stock details
                let key = "\(input.name)|\(input.deposit)|\(input.balance)|\(input.stock)"
                
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    uniqueInputs.append(input)
                }
            }
            
            var candidateCounts: [String: Int] = [:]
            var candidateBalances: [String: Decimal] = [:]
            var candidateDeposits: [String: Decimal] = [:]
            var candidateClothingIDs: [String: Set<UUID>] = [:]
            
            // 1. Generate candidates from each clothing name
            for clothing in uniqueInputs {
                let name = clothing.name
                let candidates = self.generateCandidates(from: name)
                
                for candidate in candidates {
                    candidateCounts[candidate, default: 0] += 1
                    let stock = Decimal(clothing.stock)
                    candidateBalances[candidate, default: 0] += (clothing.balance * stock)
                    candidateDeposits[candidate, default: 0] += (clothing.deposit * stock)
                    candidateClothingIDs[candidate, default: []].insert(clothing.id)
                }
            }
            
            // 2. Filter and Refine
            var seriesList: [SeriesInfo] = []
            
            // Get all valid candidates (count >= 2)
            let validCandidates = candidateCounts.keys.filter { count in
                return (candidateCounts[count] ?? 0) >= 2
            }
            
            // Sort by length descending to handle subsumption (prefer longer names first)
            let sortedCandidates = validCandidates.sorted { $0.count > $1.count }
            
            for candidate in sortedCandidates {
                let count = candidateCounts[candidate]!
                let ids = candidateClothingIDs[candidate]!
                
                // Redundancy Check:
                // If this candidate is a prefix of an already added series,
                // AND it covers the exact same set of items, then it's redundant.
                // e.g. "Pink House" (10 items) vs "Pink" (10 items) -> Keep "Pink House", skip "Pink"
                var isRedundant = false
                for existing in seriesList {
                    // Check if existing series name starts with this candidate (since we are using prefixes)
                    // Or more generally, if existing name contains this candidate
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
                        count: count, 
                        totalBalance: candidateBalances[candidate] ?? 0,
                        totalDeposit: candidateDeposits[candidate] ?? 0
                    ))
                }
            }
            
            // Sort by total balance descending (priority for deposit plan), then by count
            return seriesList.sorted {
                if $0.totalBalance != $1.totalBalance {
                    return $0.totalBalance > $1.totalBalance
                }
                return $0.count > $1.count
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
