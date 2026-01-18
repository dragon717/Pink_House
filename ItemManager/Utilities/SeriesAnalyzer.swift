//
//  SeriesAnalyzer.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/18/26.
//

import Foundation
import NaturalLanguage

struct SeriesInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let count: Int
    let totalBalance: Decimal
}

class SeriesAnalyzer {
    static let shared = SeriesAnalyzer()
    
    private let stopWords: Set<String> = [
        "裙子", "连衣裙", "OP", "JSK", "SK", "衬衫", "内搭", "外套", "大衣", "斗篷",
        "现货", "定金", "尾款", "预约", "再贩", "掉落", "跑单", "转单",
        "全新", "二手", "仅试穿", "试穿", "洗", "下水",
        "尺码", "颜色", "均码", "大小", "长款", "短款",
        "正品", "日牌", "国牌", "LO", "Lolita", "洛丽塔", "洋装",
        "kc", "小物", "发带", "边夹", "帽子", "袜子", "手袖", "手套", "包包",
        "S", "M", "L", "XL", "XXL", "XS",
        "的", "了", "和", "与", "是", "在", // Common particles
        "full", "set", "fullset"
    ]
    
    // Asynchronous analysis to avoid blocking the main thread
    func analyzeSeries(from clothings: [Clothing]) async -> [SeriesInfo] {
        return await Task.detached(priority: .userInitiated) {
            var candidateCounts: [String: Int] = [:]
            var candidateBalances: [String: Decimal] = [:]
            var candidateClothingIDs: [String: Set<UUID>] = [:]
            
            // 1. Generate candidates from each clothing name
            for clothing in clothings {
                let name = clothing.name
                let candidates = self.generateCandidates(from: name)
                
                for candidate in candidates {
                    candidateCounts[candidate, default: 0] += 1
                    candidateBalances[candidate, default: 0] += clothing.balance
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
                // If this candidate is a substring of an already added series,
                // AND it covers the exact same set of items, then it's redundant.
                // e.g. "Pink House" (10 items) vs "Pink" (10 items) -> Keep "Pink House", skip "Pink"
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
                    seriesList.append(SeriesInfo(name: candidate, count: count, totalBalance: candidateBalances[candidate] ?? 0))
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
    
    private func generateCandidates(from text: String) -> Set<String> {
        var candidates: Set<String> = []
        
        // Strategy 1: NLP Tokenization (Word based)
        // Good for extracting clear words like "Angelic Pretty", "Baby"
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        
        tagger.enumerateTags(in: range, unit: .word, scheme: .tokenType, options: options) { _, tokenRange in
            let word = String(text[tokenRange]).trimmingCharacters(in: .whitespaces)
            if isValidCandidate(word) {
                candidates.insert(word)
            }
            return true
        }
        
        // Strategy 2: N-gram generation (Character based)
        // Essential for Chinese names where "夏日" might be part of "夏日梦情" and NLP fails to split it
        // We generate substrings of length 2 to 6
        let chars = Array(text)
        if chars.count >= 2 {
            let maxLen = min(6, chars.count)
            for length in 2...maxLen {
                for i in 0...(chars.count - length) {
                    let substring = String(chars[i..<(i+length)])
                    // Optimization: Only add if it doesn't start/end with whitespace (though we trimmed chars above, the substring might span words)
                    let trimmed = substring.trimmingCharacters(in: .whitespaces)
                    if trimmed.count == substring.count && isValidCandidate(trimmed) {
                        candidates.insert(trimmed)
                    }
                }
            }
        }
        
        return candidates
    }
    
    private func isValidCandidate(_ word: String) -> Bool {
        // Basic filtering
        guard word.count >= 2 else { return false }
        
        // Should not be a number
        if word.isNumber { return false }
        
        // Should not be in stop words
        if stopWords.contains(word.lowercased()) { return false }
        
        // Should not contain only special characters or numbers
        // (Simplified check: at least one letter or unicode char)
        // For now, assume if it passed above, it's okay-ish.
        
        return true
    }
}

extension String {
    var isNumber: Bool {
        return Double(self) != nil
    }
}
