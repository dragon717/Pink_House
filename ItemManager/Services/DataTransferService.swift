//
//  DataTransferService.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/25/26.
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
    
    func exportToCSV(container: ModelContainer) async throws -> URL {
        return try await Task.detached(priority: .medium) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            
            var descriptor = FetchDescriptor<Clothing>(sortBy: [SortDescriptor(\.purchaseDate, order: .reverse)])
            // 深度隔离：只从磁盘读取已持久化的数据，忽略内存中不稳定的挂起更改
            descriptor.includePendingChanges = false
            
            let clothings = try context.fetch(descriptor)
            
            var csvString = "名称,品牌,标签,类型,颜色,尺码,衣长,状态,小物,原价人民币,原价日元,原价币种,价格,定金,尾款,小物总价,邮费人民币,邮费日元,邮费币种,含邮合计,购买日期,是否定金,定金日期,尾款开始,尾款截止,备注,库存\n"
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            for faultItem in clothings {
                let id = faultItem.persistentModelID
                // 使用 ID 在当前上下文中安全地重新获取对象，防止失效
                guard let item = context.model(for: id) as? Clothing, !item.isDeleted else {
                    continue
                }
                
                // 安全地获取关联关系：此时 item 属于背景上下文，读取其属性是线程安全的
                let brandName = item.brand?.name ?? ""
                let tagNames = item.tags?.compactMap { $0.name }.joined(separator: ";") ?? ""
                let purchaseDateStr = dateFormatter.string(from: item.purchaseDate)
                
                let depositDateStr = item.depositDate.map { dateFormatter.string(from: $0) } ?? ""
                let finalPaymentStartStr = item.finalPaymentDate.map { dateFormatter.string(from: $0) } ?? ""
                let finalPaymentEndStr = item.finalPaymentEndDate.map { dateFormatter.string(from: $0) } ?? ""
                
                let row: [String] = [
                    self.escapeCSV(item.name),
                    self.escapeCSV(brandName),
                    self.escapeCSV(tagNames),
                    self.escapeCSV(item.types),
                    self.escapeCSV(item.colors),
                    self.escapeCSV(item.sizes),
                    self.escapeCSV(item.length),
                    self.escapeCSV(item.condition),
                    self.escapeCSV(item.accessories),
                    "\(item.originalPrice)",
                    "\(item.originalPriceJPY)",
                    self.escapeCSV(item.originalPriceCurrencyCode),
                    "\(item.price)",
                    "\(item.deposit)",
                    "\(item.balance)",
                    "\(item.resolvedAccessoriesPrice)",
                    "\(item.resolvedShippingFee)",
                    "\(item.shippingFeeJPY)",
                    self.escapeCSV(item.shippingFeeCurrencyCode),
                    "\(item.inventoryTotalPrice)",
                    purchaseDateStr,
                    "\(item.isDepositPlan)",
                    depositDateStr,
                    finalPaymentStartStr,
                    finalPaymentEndStr,
                    self.escapeCSV(item.note),
                    "\(item.stock)"
                ]
                
                csvString.append(row.joined(separator: ",") + "\n")
            }
            
            let fileName = "少女心愿_导出表格_\(Int(Date().timeIntervalSince1970)).csv"
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }.value
    }
    
    nonisolated private func escapeCSV(_ text: String) -> String {
        var newText = text.replacingOccurrences(of: "\"", with: "\"\"")
        if newText.contains(",") || newText.contains("\n") || newText.contains("\"") {
            newText = "\"\(newText)\""
        }
        return newText
    }
    
    // MARK: - Backup
    
    func createBackup(container: ModelContainer) async throws -> URL {
        return try await BackupService.shared.exportBackup(container: container)
    }
    
    func restoreBackup(from url: URL, context: ModelContext) async throws {
        try await BackupService.shared.importBackup(from: url, context: context)
    }
}
