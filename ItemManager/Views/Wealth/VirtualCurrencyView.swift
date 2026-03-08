import SwiftUI

// MARK: - 虚拟币视图

struct VirtualCurrencyView: View {
    @Bindable var viewModel: WealthViewModel
    let isActive: Bool
    
    // 从 PetStatus 获取货币数据
    @State private var petStatus: PetStatus?
    
    var body: some View {
        VStack(spacing: 24) {
            // 标题
            Text("萌宠世界货币")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 16)
            
            // 三种虚拟币展示
            VStack(spacing: 20) {
                // 鱼币 - 使用与萌宠货币栏相同的图标
                VirtualCoinCard(
                    coinType: .fishCoin,
                    name: "鱼币",
                    amount: petStatus?.fishCoin ?? 0
                )
                
                // 喵币 - 使用与萌宠货币栏相同的图标
                VirtualCoinCard(
                    coinType: .meowCoin,
                    name: "喵币",
                    amount: petStatus?.meowCoin ?? 0
                )
                
                // 骨头币 - 使用与萌宠货币栏相同的图标
                VirtualCoinCard(
                    coinType: .boneCoin,
                    name: "骨头币",
                    amount: petStatus?.boneCoin ?? 0
                )
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .onAppear {
            loadPetStatus()
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                loadPetStatus()
            }
        }
    }
    
    private func loadPetStatus() {
        if let data = UserDefaults.standard.data(forKey: "PetStatus_Data"),
           let status = try? JSONDecoder().decode(PetStatus.self, from: data) {
            petStatus = status
        }
    }
}

// MARK: - 虚拟币类型枚举

enum VirtualCoinType {
    case fishCoin    // 鱼币
    case meowCoin    // 喵币
    case boneCoin    // 骨头币
    
    // 图标容器 - 鱼币和喵币直接使用 circle.fill 图标，骨头币使用圆圈+emoji
    @ViewBuilder
    var iconContainer: some View {
        switch self {
        case .fishCoin:
            // 鱼币: 直接使用 fish.circle.fill，不需要额外背景
            Image(systemName: "fish.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange)
                .shadow(color: .orange.opacity(0.4), radius: 8, x: 0, y: 4)
        case .meowCoin:
            // 喵币: 直接使用 pawprint.circle.fill，不需要额外背景
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.yellow)
                .shadow(color: .yellow.opacity(0.4), radius: 8, x: 0, y: 4)
        case .boneCoin:
            // 骨头币: 铜色圆圈 + 🦴 emoji (参考萌宠货币栏样式)
            ZStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Color(hex: "CD7F32")) // Bronze color
                Text("🦴")
                    .font(.system(size: 32))
            }
            .shadow(color: Color(hex: "CD7F32").opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }
    
    // 背景渐变色（用于卡片边框）
    var gradientColors: [Color] {
        switch self {
        case .fishCoin:
            return [Color.orange, Color.orange.opacity(0.7)]
        case .meowCoin:
            return [Color.yellow, Color.orange.opacity(0.6)]
        case .boneCoin:
            return [Color(hex: "CD7F32"), Color(hex: "8B4513")] // Bronze to dark bronze
        }
    }
}

// MARK: - 虚拟币卡片

struct VirtualCoinCard: View {
    let coinType: VirtualCoinType
    let name: String
    let amount: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标容器 - 参考萌宠货币栏样式
            // 鱼币和喵币使用 circle.fill 图标，不需要额外背景
            // 骨头币使用圆圈+emoji组合
            coinType.iconContainer
                .frame(width: 56, height: 56)
            
            // 名称和数量
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                
                // 使用人民币风格的数字显示
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    LiquidRollingNumber(
                        value: Double(amount),
                        exchangeRateToCNY: 1.0,
                        fixedTier: getTierForAmount(amount)
                    )
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.6))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [
                            coinType.gradientColors[0].opacity(0.3),
                            coinType.gradientColors[1].opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // 根据金额返回对应的财富等级（用于数字颜色）
    private func getTierForAmount(_ amount: Int) -> WealthTier {
        switch amount {
        case 0..<1000:
            return .copper
        case 1000..<5000:
            return .silver
        case 5000..<50000:
            return .gold
        case 50000..<100000:
            return .emerald
        case 100000..<200000:
            return .platinum
        case 200000..<500000:
            return .diamond
        case 500000..<1000000:
            return .sparklingGold
        default:
            return .rainbow
        }
    }
}
