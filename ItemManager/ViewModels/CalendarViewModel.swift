//
//  CalendarViewModel.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import Foundation
import SwiftUI
import SwiftData

@Observable
class CalendarViewModel {
    // Cache: Date (Start of Day) -> List of Clothings
    private var dateCache: [Date: [Clothing]] = [:]
    // Cache: Month (Start of Month) -> Count/Intensity
    private var monthCache: [Date: Int] = [:]
    
    // Process raw data into cache
    // This should be called whenever the source data changes
    @MainActor
    func processClothings(_ clothings: [Clothing]) async {
        var newDateCache: [Date: [Clothing]] = [:]
        let calendar = Calendar.current
        
        // Batch processing
        // Avoid blocking main thread for too long if list is huge
        await Task.detached(priority: .userInitiated) {
            var tempCache: [Date: [Clothing]] = [:]
            
            for clothing in clothings {
                // Helper to add to cache
                func addToCache(date: Date) {
                    let startOfDay = calendar.startOfDay(for: date)
                    if tempCache[startOfDay] == nil {
                        tempCache[startOfDay] = []
                    }
                    tempCache[startOfDay]?.append(clothing)
                }
                
                if let depositDate = clothing.depositDate {
                    addToCache(date: depositDate)
                }
                
                if let finalDate = clothing.finalPaymentDate {
                    addToCache(date: finalDate)
                }
                
                if let finalEnd = clothing.finalPaymentEndDate {
                    addToCache(date: finalEnd)
                }
            }
            
            await MainActor.run {
                self.dateCache = tempCache
            }
        }.value
    }
    
    func clothings(for date: Date) -> [Clothing] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return dateCache[startOfDay] ?? []
    }
    
    func hasEvents(on date: Date) -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return dateCache[startOfDay] != nil
    }
    
    // Optimized for Month View
    func clothings(forMonth date: Date) -> [Clothing] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        
        // This is still somewhat expensive but better than full scan.
        // Can be further optimized if needed by caching month buckets.
        return dateCache.filter { (key, _) in
            let keyComp = calendar.dateComponents([.year, .month], from: key)
            return keyComp.year == components.year && keyComp.month == components.month
        }.flatMap { $0.value }.unique()
    }
}

extension Array where Element: Identifiable {
    func unique() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}
