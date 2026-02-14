
import SwiftUI

enum EffectOption: String, CaseIterable, Identifiable {
    case random = "随机播放"
    case fireworks = "礼花 (Fireworks)"
    case butterflies = "蝴蝶 (Butterflies)"
    
    var id: String { rawValue }
    
    var effect: CelebrationEffect? {
        switch self {
        case .random: return nil
        case .fireworks: return .fireworks
        case .butterflies: return .butterflies
        }
    }
}

struct TestEffectsView: View {
    @State private var showCelebration = false
    @State private var selectedOption: EffectOption = .random
    @State private var currentEffectToPlay: CelebrationEffect?
    @ObservedObject private var vipManager = VIPManager.shared
    
    var body: some View {
        ZStack {
            LiquidBackground()
            
            VStack(spacing: 20) {
                
                Text("选择特效类型并点击按钮预览")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Picker("特效类型", selection: $selectedOption) {
                    ForEach(EffectOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.wheel)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding()
                
                Button {
                    if selectedOption == .random {
                        currentEffectToPlay = CelebrationEffect.allCases.randomElement()
                    } else {
                        currentEffectToPlay = selectedOption.effect
                    }
                    showCelebration = true
                } label: {
                    Text("播放 \(selectedOption == .random ? "特效" : String(selectedOption.rawValue.split(separator: " ").first ?? ""))")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
                .shadow(color: .pink.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Divider()
                    .padding(.horizontal)
                
                Text("VIP 状态测试")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Button {
                    var status = PetDataManager.shared.status
                    status.vipStatus.isActive = false
                    status.vipStatus.expireDate = nil
                    PetDataManager.shared.saveStatus(status)
                    vipManager.reloadStatus()
                } label: {
                    Text("清除 VIP 时间 (重置为非会员)")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(16)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 50)
            
            if showCelebration {
                CelebrationOverlay(isPresented: $showCelebration, forceEffect: currentEffectToPlay)
                    .ignoresSafeArea()
                    .zIndex(100)
            }
            
        }
        .navigationTitle("特效测试实验室")
    }
}
