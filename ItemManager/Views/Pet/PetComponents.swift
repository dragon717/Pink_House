import SwiftUI

// MARK: - General UI Components

struct RollingNumberView: View {
    var value: Int
    var font: Font = .system(size: 14, weight: .bold)
    
    var body: some View {
        // 使用 contentTransition 实现数字滚动 (iOS 16+)
        if #available(iOS 16.0, *) {
            Text("\(value)")
                .font(font)
                .contentTransition(.numericText())
                .animation(.default, value: value)
        } else {
            // Fallback for older iOS versions
            Text("\(value)")
                .font(font)
        }
    }
}

struct CurrencyView: View {
    enum CurrencyType {
        case meowCoin
        case fishCoin
        
        var name: String {
            switch self {
            case .meowCoin: return "喵币"
            case .fishCoin: return "鱼币"
            }
        }
        
        var color: Color {
            switch self {
            case .meowCoin: return .yellow
            case .fishCoin: return .orange
            }
        }
        
        var iconName: String {
            switch self {
            case .meowCoin: return "centsign.circle.fill" // 临时图标
            case .fishCoin: return "fish.circle.fill"   // 临时图标
            }
        }
    }
    
    let type: CurrencyType
    let amount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: type.iconName)
                    .foregroundColor(type.color)
                    .font(.system(size: 20))
                
                RollingNumberView(value: amount)
                    .foregroundColor(.primary)
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.8))
            .cornerRadius(15)
            .shadow(radius: 1)
        }
    }
}

struct StatusView: View {
    let icon: String
    let value: Double
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .cornerRadius(5)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value / 100.0))
                        .cornerRadius(5)
                }
            }
            .frame(height: 10)
        }
        .padding(8)
        .background(Color.white.opacity(0.8))
        .cornerRadius(10)
    }
}

// MARK: - Shop & Inventory Items

struct ShopItemView: View {
    let item: PetItemType
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: item.icon)
                    .font(.system(size: 30))
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                
                Text(item.rawValue)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                HStack(spacing: 2) {
                    Image(systemName: "fish.circle.fill") // 鱼币图标
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(item.price)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80)
        }
    }
}

struct InventoryItemView: View {
    let item: PetItemType
    let count: Int
    
    var body: some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.icon)
                    .font(.system(size: 30))
                    .frame(width: 50, height: 50)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(4)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Circle())
                    .offset(x: 5, y: -5)
            }
            
            Text(item.rawValue)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .frame(width: 80)
    }
}

// MARK: - Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
