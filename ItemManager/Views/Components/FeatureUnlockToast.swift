import SwiftUI
import Combine

// MARK: - 解锁通知管理器
final class FeatureUnlockNotificationManager: ObservableObject {
    static let shared = FeatureUnlockNotificationManager()
    
    @Published var currentNotification: UnlockNotification? = nil
    @Published var isShowing = false
    
    private var dismissTimer: Timer?
    
    private init() {}
    
    /// 显示解锁完成通知
    func showUnlockNotification(feature: FeatureItem, autoDismiss: Bool = false) {
        dismissTimer?.invalidate()
        
        let notification = UnlockNotification(
            id: UUID(),
            feature: feature,
            timestamp: Date()
        )
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            self.currentNotification = notification
            self.isShowing = true
        }
        
        // 如果不自动关闭，则保持显示直到用户操作
        if autoDismiss {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                self.dismiss()
            }
        }
    }
    
    /// 关闭通知
    func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            isShowing = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.currentNotification = nil
        }
    }
}

// MARK: - 解锁通知数据
struct UnlockNotification: Identifiable {
    let id: UUID
    let feature: FeatureItem
    let timestamp: Date
}

// MARK: - 解锁完成提示弹窗
struct FeatureUnlockToast: View {
    let notification: UnlockNotification
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    @State private var showAnimation = false
    @State private var iconScale = 0.5
    @State private var iconRotation = 0.0
    @State private var glowOpacity = 0.0
    
    var body: some View {
        VStack(spacing: 16) {
            // 动画图标区域
            ZStack {
                // 外发光效果
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.pink.opacity(0.6),
                                Color.pink.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .opacity(glowOpacity)
                
                // 旋转光环
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.pink, .purple, .pink],
                            center: .center
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(iconRotation))
                
                // 图标容器
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.pink.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: notification.feature.icon)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(iconScale)
                }
                
                // 星星装饰
                ForEach(0..<6) { i in
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                        .offset(
                            x: cos(Double(i) * .pi / 3) * 70,
                            y: sin(Double(i) * .pi / 3) * 70
                        )
                        .scaleEffect(showAnimation ? 1.0 : 0.0)
                        .opacity(showAnimation ? 1.0 : 0.0)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.6)
                            .delay(Double(i) * 0.05),
                            value: showAnimation
                        )
                }
            }
            .frame(height: 180)
            
            // 文字内容
            VStack(spacing: 8) {
                Text("✨ 任务完成！")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("解锁了 \(notification.feature.displayName)")
                    .font(.headline)
                    .foregroundColor(.pink)
                
                Text("点击进入查看")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            
            // 按钮
            HStack(spacing: 12) {
                Button {
                    onDismiss()
                } label: {
                    Text("稍后再看")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.gray.opacity(0.15))
                        )
                }
                
                Button {
                    onTap()
                } label: {
                    HStack(spacing: 4) {
                        Text("立即查看")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.pink, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.pink.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 32)
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // 图标缩放动画
        withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
            iconScale = 1.0
        }
        
        // 发光淡入
        withAnimation(.easeIn(duration: 0.5)) {
            glowOpacity = 1.0
        }
        
        // 旋转动画
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            iconRotation = 360
        }
        
        // 星星弹出
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showAnimation = true
        }
    }
}

// MARK: - 解锁动画视图（用于任务详情页）
struct FeatureUnlockCelebrationView: View {
    let feature: FeatureItem
    let onComplete: () -> Void
    
    @State private var showIcon = false
    @State private var iconScale = 0.3
    @State private var iconRotation = 0.0
    @State private var showParticles = false
    @State private var showText = false
    @State private var textOffset: CGFloat = 50
    
    var body: some View {
        ZStack {
            // 背景渐变
            RadialGradient(
                colors: [
                    Color.pink.opacity(0.3),
                    Color.purple.opacity(0.2),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()
            
            // 粒子效果
            if showParticles {
                ParticleEffectView()
            }
            
            VStack(spacing: 24) {
                Spacer()
                
                // 动画图标
                ZStack {
                    // 多层光环
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        .pink.opacity(0.8 - Double(i) * 0.2),
                                        .purple.opacity(0.8 - Double(i) * 0.2),
                                        .pink.opacity(0.8 - Double(i) * 0.2)
                                    ],
                                    center: .center
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 120 + CGFloat(i * 30), height: 120 + CGFloat(i * 30))
                            .rotationEffect(.degrees(iconRotation * (1.0 + Double(i) * 0.3)))
                    }
                    
                    // 图标
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.pink, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: .pink.opacity(0.5), radius: 20, x: 0, y: 10)
                        
                        Image(systemName: feature.icon)
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(iconScale)
                    
                    // 星星装饰
                    ForEach(0..<8) { i in
                        StarView()
                            .offset(
                                x: cos(Double(i) * .pi / 4) * 90,
                                y: sin(Double(i) * .pi / 4) * 90
                            )
                            .scaleEffect(showIcon ? 1.0 : 0.0)
                            .opacity(showIcon ? 1.0 : 0.0)
                            .animation(
                                .spring(response: 0.6, dampingFraction: 0.5)
                                .delay(0.3 + Double(i) * 0.05),
                                value: showIcon
                            )
                    }
                }
                .frame(height: 200)
                
                // 文字
                VStack(spacing: 12) {
                    Text("🎉 恭喜完成！")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(feature.displayName)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("已成功解锁此功能")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .offset(y: textOffset)
                .opacity(showText ? 1 : 0)
                
                Spacer()
                
                // 完成按钮
                Button {
                    onComplete()
                } label: {
                    Text("开始使用")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.pink, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(showText ? 1 : 0)
                .offset(y: textOffset)
            }
        }
        .onAppear {
            startCelebration()
        }
    }
    
    private func startCelebration() {
        // 显示图标
        withAnimation(.spring(response: 0.8, dampingFraction: 0.5)) {
            showIcon = true
            iconScale = 1.0
        }
        
        // 旋转动画
        withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
            iconRotation = 360
        }
        
        // 粒子效果
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showParticles = true
        }
        
        // 文字动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showText = true
                textOffset = 0
            }
        }
        
        // 自动完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            onComplete()
        }
    }
}

// MARK: - 星星视图
struct StarView: View {
    @State private var isAnimating = false
    
    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 16))
            .foregroundColor(.yellow)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - 粒子效果视图
struct ParticleEffectView: View {
    @State private var particles: [Particle] = []
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    var context = context
                    context.opacity = particle.opacity
                    context.translateBy(x: particle.x, y: particle.y)
                    
                    let rect = CGRect(x: -particle.size/2, y: -particle.size/2, width: particle.size, height: particle.size)
                    context.fill(Path(ellipseIn: rect), with: .color(particle.color))
                }
            }
        }
        .onAppear {
            createParticles()
        }
    }
    
    private func createParticles() {
        let colors: [Color] = [.pink, .purple, .yellow, .orange, .cyan]
        
        for _ in 0..<50 {
            let particle = Particle(
                x: CGFloat.random(in: 100...300),
                y: CGFloat.random(in: 200...500),
                size: CGFloat.random(in: 4...12),
                color: colors.randomElement()!,
                opacity: Double.random(in: 0.3...0.8)
            )
            particles.append(particle)
        }
    }
}

// MARK: - 粒子模型
struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var opacity: Double
}

// MARK: - 全局解锁通知覆盖层
struct GlobalUnlockNotificationOverlay: View {
    @StateObject private var notificationManager = FeatureUnlockNotificationManager.shared
    @State private var showDetailView = false
    @State private var selectedFeature: FeatureItem?
    @State private var navigateToFeature = false
    @State private var targetDestination: SmallWorldDestination? = nil
    
    var body: some View {
        ZStack {
            // 半透明背景
            if notificationManager.isShowing {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        // 点击背景不关闭，必须点击按钮
                    }
            }
            
            // 通知弹窗
            if let notification = notificationManager.currentNotification, notificationManager.isShowing {
                FeatureUnlockToast(
                    notification: notification,
                    onTap: {
                        // 跳转到庆祝动画页面
                        selectedFeature = notification.feature
                        showDetailView = true
                        notificationManager.dismiss()
                    },
                    onDismiss: {
                        notificationManager.dismiss()
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                ))
            }
        }
        .sheet(item: $selectedFeature) { feature in
            NavigationStack {
                FeatureUnlockCelebrationView(feature: feature) {
                    // 动画完成后，跳转到对应功能
                    showDetailView = false
                    
                    // 延迟一点后跳转，让sheet先关闭
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let destination = feature.destination {
                            // 发送通知让MainTabView处理跳转
                            NotificationCenter.default.post(
                                name: .navigateToSmallWorldDestination,
                                object: nil,
                                userInfo: ["destination": destination]
                            )
                        } else if feature.isSettingsFeature {
                            // 设置功能，跳转到设置页面
                            NotificationCenter.default.post(
                                name: .navigateToSettings,
                                object: nil,
                                userInfo: ["feature": feature.rawValue]
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 导航通知扩展
extension Notification.Name {
    static let navigateToSmallWorldDestination = Notification.Name("navigateToSmallWorldDestination")
    static let navigateToSettings = Notification.Name("navigateToSettings")
}

// MARK: - View 扩展
extension View {
    /// 添加全局解锁通知覆盖层
    func withUnlockNotifications() -> some View {
        self.overlay(
            GlobalUnlockNotificationOverlay()
                .allowsHitTesting(true)
        )
    }
}

// MARK: - 预览
#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        
        FeatureUnlockToast(
            notification: UnlockNotification(
                id: UUID(),
                feature: .pet,
                timestamp: Date()
            ),
            onTap: {},
            onDismiss: {}
        )
    }
}

#Preview("Celebration") {
    FeatureUnlockCelebrationView(feature: .pet) {}
}
