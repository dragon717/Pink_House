
import SwiftUI
import Combine

struct RewardBubbleView: View {
    @State private var rewards: [(amount: Int, message: String, id: UUID)] = []
    @State private var isExpanded = false
    @StateObject private var rewardManager = RewardManager.shared
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.allowsHitTesting(false) // Pass through touches
            
            VStack {
                if isExpanded {
                    // 展开状态：垂直排列所有气泡
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(rewards, id: \.id) { reward in
                                RewardBubble(amount: reward.amount, message: reward.message) {
                                    // 点击关闭单个气泡
                                    withAnimation {
                                        rewards.removeAll(where: { $0.id == reward.id })
                                        if rewards.isEmpty {
                                            isExpanded = false
                                        }
                                    }
                                }
                                .onNavigateToMagicTasks {
                                    navigateToMagicTasks()
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .padding(.top, 60)
                        .padding(.bottom, 20)
                    }
                    .background(
                        Color.black.opacity(0.01) // 透明背景以捕获点击
                            .onTapGesture {
                                withAnimation(.spring()) {
                                    isExpanded = false
                                }
                            }
                    )
                } else {
                    // 折叠状态：堆叠显示
                    ZStack(alignment: .top) {
                        // 只显示最新的 3 个
                        ForEach(Array(rewards.prefix(3).enumerated()), id: \.element.id) { index, reward in
                            RewardBubble(amount: reward.amount, message: reward.message, onClose: nil)
                                .onNavigateToMagicTasks {
                                    navigateToMagicTasks()
                                }
                                .scaleEffect(scale(for: index))
                                .offset(y: offset(for: index))
                                .zIndex(Double(rewards.count - index)) // 确保最新的在最上面
                                .opacity(opacity(for: index))
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .onTapGesture {
                                    if rewards.count > 1 {
                                        withAnimation(.spring()) {
                                            isExpanded = true
                                        }
                                    } else {
                                        navigateToMagicTasks()
                                    }
                                }
                        }
                    }
                    .padding(.top, 60)
                }
            }
        }
        .allowsHitTesting(!rewards.isEmpty) // 只有当有奖励时才允许交互
        .onReceive(rewardManager.rewardPublisher) { (amount, message) in
            let id = UUID()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                // 新奖励插入到最前面
                rewards.insert((amount, message, id), at: 0)
            }
            
            // 自动移除 (仅在未展开时，或者你可以决定展开时不自动移除)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if !isExpanded {
                    withAnimation {
                        rewards.removeAll(where: { $0.id == id })
                    }
                }
            }
        }
    }
    
    // 堆叠效果计算
    private func scale(for index: Int) -> CGFloat {
        // index 0: 1.0, index 1: 0.95, index 2: 0.9
        return 1.0 - CGFloat(index) * 0.05
    }
    
    private func offset(for index: Int) -> CGFloat {
        // 增大垂直间距，让堆叠感更强
        // index 0: 0, index 1: 35, index 2: 70
        return CGFloat(index) * 35
    }
    
    private func opacity(for index: Int) -> Double {
        return 1.0 - Double(index) * 0.15
    }
    
    private func navigateToMagicTasks() {
        withAnimation(.spring()) {
            isExpanded = false
            rewards.removeAll()
        }
        NotificationCenter.default.post(name: .navigateToMagicTasks, object: nil)
    }
}

struct RewardBubble: View {
    let amount: Int
    let message: String
    var onClose: (() -> Void)? = nil
    private var onNavigateToMagicTasks: (() -> Void)? = nil
    
    init(amount: Int, message: String, onClose: (() -> Void)? = nil) {
        self.amount = amount
        self.message = message
        self.onClose = onClose
        self.onNavigateToMagicTasks = nil
    }
    
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
                
                if let onNavigateToMagicTasks {
                    Button {
                        onNavigateToMagicTasks()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("前往魔法任务获得更多")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.pink)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            
            Spacer()
            
            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(8)
                        .background(Circle().fill(Color.gray.opacity(0.1)))
                }
            } else {
                Image(systemName: "chevron.compact.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .padding(.trailing, 10)
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
    
    func onNavigateToMagicTasks(_ action: @escaping () -> Void) -> RewardBubble {
        var bubble = self
        bubble.onNavigateToMagicTasks = action
        return bubble
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
