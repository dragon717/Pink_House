//
//  NodeCountFormatter.swift
//  裙装股市 - 节点数量格式化
//
//  用于隐私保护地显示节点数量
//

import Foundation

/// 节点数量格式化器 - 保护隐私的显示逻辑
enum NodeCountFormatter {
    
    /// 格式化节点数量显示
    /// - Parameter realCount: 真实的节点数量
    /// - Returns: 格式化后的显示字符串
    static func format(_ realCount: Int) -> String {
        #if DEBUG
        // Debug 模式显示真实数量
        return "\(realCount)"
        #else
        // 发行版隐私保护显示
        return formatForRelease(realCount)
        #endif
    }
    
    /// 发行版的格式化逻辑
    private static func formatForRelease(_ count: Int) -> String {
        switch count {
        case 0..<100:
            // 100人以下：实时显示
            return "\(count)"
            
        case 100..<1000:
            // 100-999人：显示范围区间，随时间增长
            return formatRangeCount(count)
            
        case 1000...:
            // 1000人以上：显示 999+ 爆满
            return "999+"
            
        default:
            return "0"
        }
    }
    
    /// 范围计数格式化（100-999）
    /// 随着时间推移，显示的值会逐渐接近真实值
    private static func formatRangeCount(_ count: Int) -> String {
        // 获取应用启动时间（用于计算时间因子）
        let timeFactor = calculateTimeFactor()
        
        // 基础显示值（从较小的值开始）
        let baseDisplay = max(100, count / 3)
        
        // 随着时间推移，显示值逐渐接近真实值
        let displayValue = baseDisplay + Int(Double(count - baseDisplay) * timeFactor)
        
        // 取整到十位，增加模糊度
        let roundedValue = (displayValue / 10) * 10
        
        return "\(roundedValue)+"
    }
    
    /// 计算时间因子（0.0 - 1.0）
    /// 应用运行时间越长，因子越接近1.0
    private static func calculateTimeFactor() -> Double {
        // 获取应用已运行时间（分钟）
        let uptime = ProcessInfo.processInfo.systemUptime / 60.0
        
        // 前30分钟从0逐渐增长到1
        let factor = min(uptime / 30.0, 1.0)
        
        // 使用 ease-out 曲线，让增长先快后慢
        return 1.0 - pow(1.0 - factor, 2)
    }
    
    /// 获取节点状态描述
    static func statusDescription(_ count: Int) -> String {
        #if DEBUG
        return count <= 1 ? "单机运行" : "\(count) 节点在线"
        #else
        switch count {
        case 0..<10:
            return "种子期"
        case 10..<100:
            return "成长期"
        case 100..<500:
            return "繁荣期"
        case 500..<1000:
            return "火爆期"
        default:
            return "爆满 🔥"
        }
        #endif
    }
    
    /// 获取节点状态颜色
    static func statusColor(_ count: Int) -> String {
        switch count {
        case 0..<10:
            return "#A3C1AD" // 薄荷灰绿 - 种子期
        case 10..<100:
            return "#E29399" // 莫妮卡粉 - 成长期
        case 100..<500:
            return "#FFD700" // 金色 - 繁荣期
        case 500..<1000:
            return "#FF6B6B" // 橙红 - 火爆期
        default:
            return "#FF0000" // 红色 - 爆满
        }
    }
}

// MARK: - 使用示例

/*
// 在视图中使用
Text("\(NodeCountFormatter.format(nodeCount)) 节点")
    .foregroundColor(Color(hex: NodeCountFormatter.statusColor(nodeCount)))

// 获取状态描述
Text(NodeCountFormatter.statusDescription(nodeCount))
*/
