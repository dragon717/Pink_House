//
//  DataTransferService.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/25/26.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - DataTransferService

@MainActor
class DataTransferService {
    static let shared = DataTransferService()
    
    private init() {}
    
    // MARK: - CSV Export
    
    func exportToCSV(context: ModelContext) throws -> URL {
        let descriptor = FetchDescriptor<Clothing>(sortBy: [SortDescriptor(\.purchaseDate, order: .reverse)])
        let clothings = try context.fetch(descriptor)
        
        var csvString = "名称,品牌,标签,类型,颜色,尺码,衣长,状态,小物,价格,定金,尾款,购买日期,定金日期,尾款开始,尾款截止,备注,库存\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for item in clothings {
            let brandName = item.brand?.name ?? ""
            let tagNames = item.tags?.map { $0.name }.joined(separator: ";") ?? ""
            let purchaseDateStr = dateFormatter.string(from: item.purchaseDate)
            
            let depositDateStr = item.depositDate.map { dateFormatter.string(from: $0) } ?? ""
            let finalPaymentStartStr = item.finalPaymentDate.map { dateFormatter.string(from: $0) } ?? ""
            let finalPaymentEndStr = item.finalPaymentEndDate.map { dateFormatter.string(from: $0) } ?? ""
            
            let row: [String] = [
                escapeCSV(item.name),
                escapeCSV(brandName),
                escapeCSV(tagNames),
                escapeCSV(item.types),
                escapeCSV(item.colors),
                escapeCSV(item.sizes),
                escapeCSV(item.length),
                escapeCSV(item.condition),
                escapeCSV(item.accessories),
                "\(item.price)",
                "\(item.deposit)",
                "\(item.balance)",
                purchaseDateStr,
                depositDateStr,
                finalPaymentStartStr,
                finalPaymentEndStr,
                escapeCSV(item.note),
                "\(item.stock)"
            ]
            
            csvString.append(row.joined(separator: ",") + "\n")
        }
        
        let fileName = "少女心愿导出表格_\(Int(Date().timeIntervalSince1970)).csv"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func escapeCSV(_ text: String) -> String {
        var newText = text.replacingOccurrences(of: "\"", with: "\"\"")
        if newText.contains(",") || newText.contains("\n") || newText.contains("\"") {
            newText = "\"\(newText)\""
        }
        return newText
    }
    
    // MARK: - Backup
    
    func createBackup(context: ModelContext) throws -> URL {
        return try BackupService.shared.exportBackup(context: context)
    }
    
    func restoreBackup(from url: URL, context: ModelContext) async throws {
        try BackupService.shared.importBackup(from: url, context: context)
    }
}
