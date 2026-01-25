//
//  StringHelper.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import Foundation

struct StringHelper {
    /// 更新逗号分隔的字符串列表
    /// - Parameters:
    ///   - original: 原始字符串（如 "A, B, C"）
    ///   - oldItem: 要修改/删除的项（如 "B"）
    ///   - newItem: 新的项（如 "D"）。如果为 nil，则表示删除。
    /// - Returns: 更新后的字符串
    static func updateStringList(original: String, oldItem: String, newItem: String?) -> String {
        // 分割并去除空白
        var items = original.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // 找到所有匹配项的索引（可能有重复，虽然理论上不应该有）
        // 这里假设我们只处理完全匹配
        if let index = items.firstIndex(of: oldItem) {
            if let newItem = newItem {
                // 修改：替换
                // 检查新值是否已存在，避免重复（可选，取决于需求，这里简单替换）
                items[index] = newItem
            } else {
                // 删除：移除
                items.remove(at: index)
            }
        }
        
        // 过滤空字符串并重新组合
        return items.filter { !$0.isEmpty }.joined(separator: ",")
    }
    
    /// 获取逗号分隔字符串中的所有独立项
    static func extractItems(from text: String) -> [String] {
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
