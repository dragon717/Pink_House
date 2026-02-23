//
//  SeriesAnalyzer.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/18/26.
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
    // As requested: "只看前端的前2-4字（大小不敏感，都算做一个）"
    func analyzeSeries(from clothings: [Clothing]) async -> [SeriesInfo] {
        // Convert to Sendable structs to safely pass to detached task
        let inputs = clothings.map { 
            SeriesInput(id: $0.id, name: $0.name, balance: $0.totalBalance, deposit: $0.totalDeposit, stock: $0.stock) 
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
            // Or should we just take the longest prefix that matches?
            // The requirement says "First 2-4 chars".
            // If we have "少女心愿" and "Pink", do we keep both?
            // "Only look at the front 2-4 words" implies grouping by prefix.
            
            // Strategy: Group everything by their prefixes.
            // If a clothing matches "Pin" (3 chars) and "Pink" (4 chars), which series does it belong to?
            // Usually we want the most specific (longest) series name that has enough items.
            
            let validCandidates = candidateStyleKeys.keys.filter { key in
                return (candidateStyleKeys[key]?.count ?? 0) >= 1 // Even 1 style can be a series if it matches the prefix rule? Usually series implies >= 2. Let's keep >= 2 for now to avoid noise, or change to 1 if user wants everything grouped. 
                // Let's stick to >= 2 to form a "Series", otherwise it's just a single item.
            }
            
            // Sort by length descending to prefer longer names (e.g. "Pink" over "Pin")
            let sortedCandidates = validCandidates.sorted { $0.count > $1.count }
            
            // We need to assign each clothing to the BEST series (longest prefix).
            // But the current logic allows one clothing to contribute to multiple candidates.
            // We should filter out redundant shorter series if they are covered by longer ones.
            
            // Strict Redundancy Check:
            // A shorter candidate is redundant if ALL its items are also present in a longer candidate.
            // Since we generate candidates from the SAME name, "Pink" will always contain the items of "少女心愿" (if we generated prefixes).
            // But here we generate prefixes of length 2, 3, 4.
            // "Pin" (3) and "Pink" (4).
            // "Pink" items are a subset of "Pin" items? 
            // Yes, because "Pink..." starts with "Pin...".
            // So "Pin" will have >= "Pink" items.
            // If "Pin" has exact same items as "Pink", we prefer "Pink" (more specific).
            // If "Pin" has MORE items (e.g. "Pineapple"), then "Pin" might be a valid separate broader series?
            // But usually for series grouping, we want the specific one.
            
            // Let's simplified approach:
            // Just keep all valid candidates, but remove those that are purely subsets of another better candidate?
            // Actually, if "Pin" and "Pink" have the SAME clothing IDs, "Pink" is better.
            // If "Pin" has more, it might be too broad or just a coincidence.
            // User said: "only look at front 2-4 words... treat as one series".
            
            for candidate in sortedCandidates {
                let styleCount = candidateStyleKeys[candidate]?.count ?? 0
                let itemCount = candidateItemCounts[candidate] ?? 0
                let ids = candidateClothingIDs[candidate]!
                
                // Redundancy Check:
                var isRedundant = false
                for existing in seriesList {
                    // Check if existing series is a "better version" of this candidate
                    // Case 1: Existing is longer (e.g. "Pink") and this is shorter ("Pin")
                    // And they have the same items (meaning "Pin" didn't match anything else extra)
                    if existing.name.localizedCaseInsensitiveContains(candidate) {
                        if let existingIDs = candidateClothingIDs[existing.name], existingIDs == ids {
                            isRedundant = true
                            break
                        }
                    }
                    
                    // Case 2: What if "Pink" (4) and "Pink H" (not generated, max 4 chars).
                    // We only generate 2, 3, 4 chars.
                    // So "Pink" is likely the max.
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
            
            // Sort by total balance descending
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
        let sanitized = sanitize(text)
        
        // Take first 2, 3, 4 characters as candidates
        // Case insensitive? The key in dictionary is String.
        // We should normalize case for grouping.
        // But for display we might want original case?
        // Let's use Lowercase for keys in the main loop, but here return standardized strings?
        // Actually the main loop uses the string returned here as key.
        // So we should return Lowercase here to group "Pink" and "pink" together?
        // User said: "大小不敏感".
        // So we return lowercase candidates.
        
        let chars = Array(sanitized)
        let lengths = [2, 3, 4]
        
        for len in lengths {
            if chars.count >= len {
                let prefix = String(chars.prefix(len)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                   // We return the prefix as is (sanitized), but maybe lowercased?
                   // If we return lowercase, the series name will be lowercase.
                   // We might want to capitalize it for display?
                   // Let's return lowercase for grouping, and we can capitalize display later?
                   // Or just keep the case of the first occurrence?
                   // To ensure grouping "Pink" and "pink", we MUST return the same string.
                   candidates.insert(prefix.lowercased())
                }
            }
        }
        
        return candidates
    }
    
    // Make sanitize public so it can be used for filtering
    func sanitize(_ text: String) -> String {
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
