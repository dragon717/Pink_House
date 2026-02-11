import Foundation
import SwiftUI

enum SmallWorldSceneMode: Int, CaseIterable, Identifiable {
    case auto = 0
    case morning = 1
    case day = 2
    
    var id: Int { self.rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .morning: return "清晨"
        case .day: return "白天"
        }
    }
    
    func backgroundImageName(for date: Date = Date()) -> String {
        switch self {
        case .auto:
            let hour = Calendar.current.component(.hour, from: date)
            // 清晨: 5:00 - 9:00 (不包含 9:00)
            let isMorning = hour >= 5 && hour < 9
            // 黄昏: 16:00 - 19:00 (不包含 19:00)
            let isDusk = hour >= 16 && hour < 19
            
            if isMorning || isDusk {
                return "small_world_bg_sun"
            } else {
                return "small_world_bg_normal"
            }
        case .morning:
            return "small_world_bg_sun"
        case .day:
            return "small_world_bg_normal"
        }
    }
    
    // For Night mode, we might want to add a dark overlay
    func overlayColor(for date: Date = Date()) -> Color {
        return Color.clear
    }
}
