import SwiftUI
import Combine

// MARK: - 魔法任务完成数据模型
struct MagicTaskCompletion: Identifiable, Equatable {
    let id = UUID()
    let feature: FeatureItem
    let timestamp: Date
    var isRead: Bool = false
    var isUnlockable: Bool = false // 是否为"可解锁"状态（未达到解锁，只是满足条件）
    
    static func == (lhs: MagicTaskCompletion, rhs: MagicTaskCompletion) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 魔法任务完成管理器
// 管理多个任务完成提示，按解锁顺序堆叠（先到置于最下面）
final class MagicTaskCompletionManager: ObservableObject {
    static let shared = MagicTaskCompletionManager()
    
    // 任务完成列表（按时间顺序，新的在后面）
    @Published private(set) var completions: [MagicTaskCompletion] = []
    @Published var isExpanded = false
    
    // 最大显示数量
    private let maxVisibleCount = 5
    private let maxStoredCount = 20
    
    // 自动清理定时器
    private var cleanupTimer: Timer?
    
    private init() {
        setupAutoCleanup()
    }
    
    // MARK: - 添加任务完成
    /// 添加一个新的任务完成提示
    /// 新的任务添加到列表末尾（显示在最上面）
    func addCompletion(feature: FeatureItem) {
        // 检查是否已存在相同的未读任务（包括可解锁状态）
        let exists = completions.contains { $0.feature == feature && !$0.isRead && !$0.isUnlockable }
        guard !exists else { return }
        
        // 如果存在可解锁状态的提示，移除它（因为现在已经解锁了）
        completions.removeAll { $0.feature == feature && $0.isUnlockable }
        
        let completion = MagicTaskCompletion(feature: feature, timestamp: Date(), isUnlockable: false)
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            // 添加到列表末尾（新的在后面，显示时在最上面）
            completions.append(completion)
            
            // 限制存储数量
            if completions.count > maxStoredCount {
                completions.removeFirst(completions.count - maxStoredCount)
            }
        }
        
        // 播放提示音效和震动
        HapticEngineManager.shared.playFireworksHaptic()
    }
    
    // MARK: - 添加可解锁提示
    /// 添加一个"可解锁"状态提示（当进度达到但未解锁时）
    func addUnlockable(feature: FeatureItem) {
        // 检查是否已存在相同的未读可解锁任务
        let exists = completions.contains { $0.feature == feature && !$0.isRead && $0.isUnlockable }
        guard !exists else { return }
        
        // 检查是否已存在解锁完成的提示
        let unlockedExists = completions.contains { $0.feature == feature && !$0.isRead && !$0.isUnlockable }
        guard !unlockedExists else { return }
        
        let completion = MagicTaskCompletion(feature: feature, timestamp: Date(), isUnlockable: true)
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            // 添加到列表末尾（新的在后面，显示时在最上面）
            completions.append(completion)
            
            // 限制存储数量
            if completions.count > maxStoredCount {
                completions.removeFirst(completions.count - maxStoredCount)
            }
        }
        
        // 播放轻微的提示音效和震动
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    // MARK: - 移除任务完成
    /// 移除指定任务
    func removeCompletion(id: UUID) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            completions.removeAll { $0.id == id }
        }
        
        // 如果没有任务了，自动收起
        if completions.isEmpty {
            isExpanded = false
        }
    }
    
    /// 标记任务为已读
    func markAsRead(id: UUID) {
        if let index = completions.firstIndex(where: { $0.id == id }) {
            completions[index].isRead = true
        }
    }
    
    /// 标记所有为已读
    func markAllAsRead() {
        for index in completions.indices {
            completions[index].isRead = true
        }
    }
    
    /// 清除所有已读任务
    func clearReadCompletions() {
        withAnimation {
            completions.removeAll { $0.isRead }
        }
    }
    
    /// 清除所有任务
    func clearAll() {
        withAnimation(.spring()) {
            completions.removeAll()
            isExpanded = false
        }
    }
    
    // MARK: - 展开/收起
    func toggleExpanded() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
    }
    
    func setExpanded(_ expanded: Bool) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isExpanded = expanded
        }
    }
    
    // MARK: - 查询
    /// 获取未读任务数量
    var unreadCount: Int {
        completions.filter { !$0.isRead }.count
    }
    
    /// 是否有未读任务
    var hasUnread: Bool {
        unreadCount > 0
    }
    
    /// 获取可见任务（用于堆叠显示）
    var visibleCompletions: [MagicTaskCompletion] {
        Array(completions.suffix(maxVisibleCount))
    }
    
    // MARK: - 自动清理
    private func setupAutoCleanup() {
        // 每5分钟清理一次超过24小时的已读任务
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.cleanupOldCompletions()
        }
    }
    
    private func cleanupOldCompletions() {
        let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60) // 24小时前
        
        let oldCount = completions.filter { $0.isRead && $0.timestamp < cutoffDate }.count
        if oldCount > 0 {
            withAnimation {
                completions.removeAll { $0.isRead && $0.timestamp < cutoffDate }
            }
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
}

// MARK: - 魔法任务完成卡片视图
struct MagicTaskCompletionCard: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    let completion: MagicTaskCompletion
    let index: Int // 在堆叠中的索引，0表示最上面
    let totalCount: Int
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    @State private var isPressed = false
    @State private var showGlow = false
    @State private var iconScale: CGFloat = 0.8

    private var primaryAccent: Color {
        completion.isUnlockable ? .orange : themeManager.accentTextColor
    }

    private var secondaryAccent: Color {
        if completion.isUnlockable {
            return .yellow
        }
        return themeManager.accentTextColor.mixed(
            with: colorScheme == .dark ? .white : .black,
            amount: colorScheme == .dark ? 0.22 : 0.18
        )
    }
    
    // 堆叠效果参数
    private var stackOffset: CGFloat {
        // 折叠状态下，每张卡片向下偏移
        CGFloat(index) * 12
    }
    
    private var stackScale: CGFloat {
        // 折叠状态下，后面的卡片稍微缩小
        1.0 - CGFloat(index) * 0.03
    }
    
    private var stackOpacity: Double {
        // 折叠状态下，后面的卡片稍微透明
        1.0 - Double(index) * 0.15
    }
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                // 图标区域
                ZStack {
                    // 发光背景
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    primaryAccent.opacity(0.4),
                                    primaryAccent.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 5,
                                endRadius: 25
                            )
                        )
                        .frame(width: 50, height: 50)
                        .opacity(showGlow ? 1 : 0)
                    
                    // 图标背景
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    primaryAccent.opacity(0.3),
                                    secondaryAccent.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    // 功能图标
                    Image(systemName: completion.feature.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [primaryAccent, secondaryAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(iconScale)
                }
                
                // 文字内容
                VStack(alignment: .leading, spacing: 2) {
                    Text(completion.isUnlockable ? "🔓 可解锁" : "✨ 任务完成！")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(primaryAccent)
                    
                    Text(completion.feature.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.primaryTextColor)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // 关闭按钮
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.secondaryTextColor)
                        .padding(8)
                        .background(Circle().fill(primaryAccent.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(
                        color: .black.opacity(0.08 - Double(index) * 0.01),
                        radius: 12 - CGFloat(index) * 2,
                        x: 0,
                        y: 4 - CGFloat(index)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                primaryAccent.opacity(0.3 - Double(index) * 0.05),
                                secondaryAccent.opacity(0.2 - Double(index) * 0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = false
            }
        }
        .onAppear {
            // 入场动画
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(Double(index) * 0.05)) {
                iconScale = 1.0
            }
            
            // 发光动画
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                showGlow = true
            }
        }
    }
}

// MARK: - 魔法任务完成堆叠视图
struct MagicTaskCompletionStackView: View {
    @Environment(ThemeManager.self) private var themeManager

    @StateObject private var manager = MagicTaskCompletionManager.shared
    @State private var selectedNotification: UnlockNotification?
    @State private var showBigCard = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 透明背景用于捕获点击（仅在展开时）
                if manager.isExpanded && !manager.completions.isEmpty {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture {
                            manager.setExpanded(false)
                        }
                }
                
                // 任务卡片堆叠
                if !manager.completions.isEmpty {
                    VStack(spacing: 0) {
                        if manager.isExpanded {
                            // 展开状态：垂直排列所有卡片
                            expandedView
                        } else {
                            // 折叠状态：堆叠显示
                            stackedView
                        }
                    }
                    .padding(.top, 60)
                    .padding(.horizontal, 20)
                }
                
                // 大卡片弹窗（全屏覆盖）
                if showBigCard, let notification = selectedNotification {
                    bigCardOverlay(notification: notification)
                }
            }
        }
    }
    
    // MARK: - 展开视图
    private var expandedView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                // 顶部标题栏
                HStack {
                    Text("魔法任务完成")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.primaryTextColor)
                    
                    Spacer()
                    
                    // 未读数量
                    if manager.unreadCount > 0 {
                        Text("\(manager.unreadCount) 个新任务")
                            .font(.caption)
                            .foregroundColor(themeManager.accentTextColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(themeManager.accentTextColor.opacity(0.12))
                            .cornerRadius(8)
                    }
                    
                    // 全部已读按钮
                    if manager.hasUnread {
                        Button("全部已读") {
                            manager.markAllAsRead()
                        }
                        .font(.caption)
                        .foregroundColor(themeManager.accentTextColor)
                    }
                    
                    // 清除已读按钮
                    Button("清除已读") {
                        manager.clearReadCompletions()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .disabled(!manager.completions.contains { $0.isRead })
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
                
                // 卡片列表（倒序显示，最新的在上面）
                ForEach(Array(manager.completions.reversed().enumerated()), id: \.element.id) { index, completion in
                    MagicTaskCompletionCard(
                        completion: completion,
                        index: 0, // 展开状态下没有堆叠效果
                        totalCount: manager.completions.count,
                        onTap: {
                            handleTap(completion: completion)
                        },
                        onDismiss: {
                            manager.removeCompletion(id: completion.id)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
            .padding(.bottom, 20)
        }
        .frame(maxHeight: min(CGFloat(manager.completions.count) * 80 + 60, 400))
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
    }
    
    // MARK: - 堆叠视图
    private var stackedView: some View {
        // 只显示最新的几个，按堆叠顺序（先到在下面）
        let visibleCompletions = Array(manager.completions.suffix(5))
        
        return ZStack(alignment: .top) {
            ForEach(Array(visibleCompletions.enumerated()), id: \.element.id) { index, completion in
                // 计算反向索引（0是最老的/最下面的，最大是最新的/最上面的）
                let reverseIndex = visibleCompletions.count - 1 - index
                
                MagicTaskCompletionCard(
                    completion: completion,
                    index: reverseIndex,
                    totalCount: visibleCompletions.count,
                    onTap: {
                        handleTap(completion: completion)
                    },
                    onDismiss: {
                        manager.removeCompletion(id: completion.id)
                    }
                )
                .offset(y: CGFloat(reverseIndex) * 12) // 堆叠偏移
                .scaleEffect(1.0 - CGFloat(reverseIndex) * 0.03) // 堆叠缩放
                .opacity(1.0 - Double(reverseIndex) * 0.15) // 堆叠透明度
                .zIndex(Double(index)) // zIndex确保顺序正确
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .frame(height: 80 + CGFloat(min(visibleCompletions.count - 1, 4)) * 12)
        .onTapGesture {
            if manager.completions.count == 1, let completion = manager.completions.first {
                // 只有一个任务，点击显示大卡片
                handleTap(completion: completion)
            } else {
                // 多个任务，展开列表
                manager.toggleExpanded()
            }
        }
    }
    
    // MARK: - 大卡片覆盖层
    private func bigCardOverlay(notification: UnlockNotification) -> some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // 点击背景关闭大卡片并移除任务
                    dismissBigCardAndRemove()
                }
            
            // 大卡片
            FeatureUnlockToast(
                notification: notification,
                onTap: {
                    // 立即查看 - 关闭大卡片、移除任务并跳转
                    let feature = notification.feature
                    dismissBigCardAndRemove()
                    
                    // 延迟后跳转到对应功能
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        feature.postNavigationFromMagicTask()
                    }
                },
                onDismiss: {
                    // 稍后再看 - 关闭大卡片并移除任务
                    dismissBigCardAndRemove()
                }
            )
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 0.9).combined(with: .opacity)
            ))
        }
    }
    
    // MARK: - 处理点击
    private func handleTap(completion: MagicTaskCompletion) {
        manager.markAsRead(id: completion.id)
        
        // 创建通知数据
        let notification = UnlockNotification(
            id: completion.id,
            feature: completion.feature,
            timestamp: completion.timestamp
        )
        
        // 显示大卡片弹窗
        selectedNotification = notification
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showBigCard = true
        }
    }
    
    // MARK: - 关闭大卡片并移除任务
    private func dismissBigCardAndRemove() {
        withAnimation(.easeOut(duration: 0.3)) {
            showBigCard = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let notification = selectedNotification {
                manager.removeCompletion(id: notification.id)
            }
            selectedNotification = nil
        }
    }
}

// MARK: - 全局魔法任务完成覆盖层
struct GlobalMagicTaskCompletionOverlay: View {
    var body: some View {
        MagicTaskCompletionStackView()
            .allowsHitTesting(true)
    }
}

// MARK: - View 扩展
extension View {
    /// 添加魔法任务完成常驻提示覆盖层
    func withMagicTaskCompletions() -> some View {
        self.overlay(
            GlobalMagicTaskCompletionOverlay()
                .allowsHitTesting(true),
            alignment: .top
        )
    }
}



// MARK: - 预览
#Preview("堆叠效果") {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        
        VStack {
            Spacer()
            
            Button("添加测试任务") {
                let features: [FeatureItem] = [.pet, .bigWorld, .perler, .dressStock, .ootd]
                if let randomFeature = features.randomElement() {
                    MagicTaskCompletionManager.shared.addCompletion(feature: randomFeature)
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            
            Spacer()
        }
    }
    .withMagicTaskCompletions()
}

#Preview("单个卡片") {
    MagicTaskCompletionCard(
        completion: MagicTaskCompletion(feature: .pet, timestamp: Date()),
        index: 0,
        totalCount: 1,
        onTap: {},
        onDismiss: {}
    )
    .padding()
}
