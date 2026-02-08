import SwiftUI

enum PetBubbleSize: String, CaseIterable, Identifiable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .small: return "小"
        case .medium: return "默认"
        case .large: return "大"
        }
    }
    
    var fontSize: CGFloat {
        switch self {
        case .small: return 24 // 进一步调小
        case .medium: return 30 // 比原来小一些 (原来是36)
        case .large: return 36  // 保持原来大小
        }
    }
}
