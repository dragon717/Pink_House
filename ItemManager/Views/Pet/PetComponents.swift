import SwiftUI

// MARK: - General UI Components

struct RollingNumberView: View {
    var value: Int
    var font: Font = .system(size: 14, weight: .bold)
    
    var body: some View {
        // 使用 contentTransition 实现数字滚动 (iOS 16+)
        if #available(iOS 16.0, *) {
            Text(formattedString)
                .font(font)
                .contentTransition(.numericText())
                .animation(.default, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 50, alignment: .trailing)
        } else {
            // Fallback for older iOS versions
            Text(formattedString)
                .font(font)
                .frame(minWidth: 50, alignment: .trailing)
        }
    }
    
    private var formattedString: String {
        if value >= 100_000_000 {
            // 亿
            let doubleValue = Double(value) / 100_000_000.0
            return String(format: "%.2f亿", doubleValue)
        } else if value >= 10_000 {
            // 万
            let doubleValue = Double(value) / 10_000.0
            return String(format: "%.2f万", doubleValue)
        } else {
            // 保持原样，但确保至少有一定宽度或者用空格补齐（如果需要对齐）
            // 但用户要求是“最低显示4位数”，这里可能指的是保留足够的显示空间，
            // 或者仅仅是说“即使是很小的数字，也要按照正常数字显示”
            // 结合上下文“显示不全时，显示x万”，这里的逻辑主要是处理大数。
            return "\(value)"
        }
    }
}

struct CurrencyView: View {
    let type: PetCurrency
    let amount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: type.iconName)
                    .foregroundColor(type == .meowCoin ? .yellow : .orange)
                    .font(.system(size: 20))
                
                RollingNumberView(value: amount)
                    .foregroundColor(.primary)
                
                #if DEBUG
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .cornerRadius(20)
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
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value / 100.0))
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Shop & Inventory Items

struct ShopItemView: View {
    let item: PetItemDefinition
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                
                Text(item.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                HStack(spacing: 2) {
                    Image(systemName: item.petCurrency.iconName) // 动态图标
                        .font(.caption2)
                        .foregroundColor(item.petCurrency == .meowCoin ? .yellow : .orange)
                    Text("\(item.price)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
            }
            .frame(width: 80)
        }
    }
}

struct InventoryItemView: View {
    let item: PetItemDefinition
    let count: Int
    
    var body: some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                Image(item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
            
            Text(item.name)
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
