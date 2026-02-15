import SwiftUI

enum GridMode: Int, CaseIterable {
    case single = 1
    case double = 2
    case triple = 3
    
    var iconName: String {
        switch self {
        case .single: return "rectangle.grid.1x2"
        case .double: return "rectangle.grid.2x2"
        case .triple: return "rectangle.grid.3x2"
        }
    }
    
    var displayName: String {
        switch self {
        case .single: return "单列"
        case .double: return "双列"
        case .triple: return "三列"
        }
    }
}
