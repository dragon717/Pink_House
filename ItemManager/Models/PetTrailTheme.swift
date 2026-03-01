import SwiftUI

enum PetTrailTheme: String, CaseIterable, Identifiable, Codable {
    case defaultPink
    case ocean
    case sunset
    case forest
    case custom
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .defaultPink: return "默认 (粉/莫/白)"
        case .ocean: return "海洋之歌"
        case .sunset: return "日落黄昏"
        case .forest: return "森林秘境"
        case .custom: return "自定义"
        }
    }
    
    func colors(custom1: String? = nil, custom2: String? = nil, custom3: String? = nil) -> [Color] {
        switch self {
        case .defaultPink:
            // 粉，莫妮卡粉(深粉)，米白
            let colors: [Color] = [Color(hex: "FFC0CB"), Color(hex: "D87093"), Color(hex: "F5F5DC")]
            return colors
        case .ocean:
            let colors: [Color] = [Color(hex: "006994"), Color(hex: "00CED1"), Color(hex: "F0F8FF")]
            return colors
        case .sunset:
            let colors: [Color] = [Color(hex: "FF4500"), Color(hex: "FF69B4"), Color(hex: "8A2BE2")]
            return colors
        case .forest:
            let colors: [Color] = [Color(hex: "228B22"), Color(hex: "90EE90"), Color(hex: "FFFFF0")]
            return colors
        case .custom:
            let c1: Color = Color(hex: custom1 ?? "808080")
            let c2: Color = Color(hex: custom2 ?? "808080")
            let c3: Color = Color(hex: custom3 ?? "808080")
            return [c1, c2, c3]
        }
    }
}
