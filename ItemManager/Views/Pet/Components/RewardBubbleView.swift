
import SwiftUI
import Combine

struct RewardBubbleView: View {
    @State private var rewards: [(amount: Int, message: String, id: UUID)] = []
    @StateObject private var rewardManager = RewardManager.shared
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.allowsHitTesting(false) // Pass through touches
            
            VStack(spacing: 10) {
                ForEach(rewards, id: \.id) { reward in
                    RewardBubble(amount: reward.amount, message: reward.message)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
            }
            .padding(.top, 60) // Avoid status bar / dynamic island
        }
        .allowsHitTesting(false) // Don't block interactions
        .onReceive(rewardManager.rewardPublisher) { (amount, message) in
            let id = UUID()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                rewards.append((amount, message, id))
            }
            
            // Auto dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    rewards.removeAll(where: { $0.id == id })
                }
            }
        }
    }
}

struct RewardBubble: View {
    let amount: Int
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.gradient)
                    .frame(width: 40, height: 40)
                    .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Image(systemName: "fish.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("+\(amount) 鱼币")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
                
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .padding(.trailing, 16)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                )
        }
        .frame(maxWidth: 300)
    }
}

#Preview {
    ZStack {
        Color.blue.opacity(0.1).ignoresSafeArea()
        
        VStack {
            Button("Trigger Reward") {
                RewardManager.shared.triggerReward(type: .payBalance)
            }
        }
        
        RewardBubbleView()
    }
}
