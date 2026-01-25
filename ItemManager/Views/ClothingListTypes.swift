import SwiftUI

// View Layout Management
enum ViewLayout: String, CaseIterable, Identifiable {
    case listBrief = "单行简略"
    case listDetailed = "单行详细"
    case grid2 = "双列"
    case grid3 = "三列"
    case grid6 = "六列"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .listBrief: return "list.bullet"
        case .listDetailed: return "list.bullet.rectangle.portrait"
        case .grid2: return "square.grid.2x2"
        case .grid3: return "square.grid.3x3"
        case .grid6: return "square.grid.3x2"
        }
    }
}
