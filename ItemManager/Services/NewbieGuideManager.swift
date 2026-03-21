import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - 新手引导步骤

enum NewbieGuideStep: String, CaseIterable, Identifiable {
    case none = "none"           // 无引导
    case welcome = "welcome"     // 欢迎界面
    case running = "running"     // 跑步动画中
    case pointing = "pointing"   // 指向动画（等待用户点击）
    case complete = "complete"   // 引导完成

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none, .running, .pointing: return ""
        case .welcome: return "欢迎来到少女心愿衣橱"
        case .complete: return "引导完成"
        }
    }

    var description: String {
        switch self {
        case .none, .running: return ""
        case .welcome: return "我是你的向导奶茶，让我带你了解一下这个魔法衣橱吧！"
        case .pointing: return "点击右上角的 + 号，开始添加你的第一件裙子吧！"
        case .complete: return "你已经准备好开始使用啦！有问题随时找我哦~"
        }
    }

    var targetButtonText: String {
        switch self {
        case .none, .running, .pointing, .complete: return ""
        case .welcome: return "开始探索"
        }
    }
}

// MARK: - 气泡位置

enum BubblePosition {
    case top
    case center
    case bottom
}

// MARK: - 指向方向

enum PointDirection {
    case none
    case topRight    // 指向右上角
    case topLeft     // 指向左上角
    case bottom      // 指向底部
    case center      // 居中

    var needsFlip: Bool {
        switch self {
        case .topLeft: return true
        default: return false
        }
    }
}

// MARK: - 功能首次使用引导状态管理

extension FeatureUnlockManager {
    // 需要首次使用引导的功能列表
    static let guidedFeatures: [FeatureItem] = [
        .dataBackup,      // 数据备份
        .cloudSync,       // iCloud同步
        .batchImport,     // 批量导入
        .themeCustomize,  // 魔法配色
        .ootd,            // 穿搭手帐
        .wealth,          // 来财求签
    ]

    // 检查功能是否需要首次使用引导
    func needsFirstUseGuide(for feature: FeatureItem) -> Bool {
        guard FeatureUnlockManager.guidedFeatures.contains(feature) else { return false }
        guard isUnlocked(feature) else { return false }
        let key = "firstUseGuide_\(feature.rawValue)"
        return !UserDefaults.standard.bool(forKey: key)
    }

    // 标记功能已完成首次使用引导
    func markFirstUseGuideCompleted(for feature: FeatureItem) {
        let key = "firstUseGuide_\(feature.rawValue)"
        UserDefaults.standard.set(true, forKey: key)
    }

    // 重置功能首次使用引导状态
    func resetFirstUseGuide(for feature: FeatureItem) {
        let key = "firstUseGuide_\(feature.rawValue)"
        UserDefaults.standard.set(false, forKey: key)
    }
}

// MARK: - 新手引导状态

struct NewbieGuideState: Codable {
    var isCompleted: Bool = false
    var currentStep: String = NewbieGuideStep.none.rawValue
    var skippedAt: Date? = nil
    var startedAt: Date = Date()
}

// MARK: - 新手引导管理器

final class NewbieGuideManager: ObservableObject {
    static let shared = NewbieGuideManager()
    
    // MARK: - Published Properties

    @Published var state: NewbieGuideState = NewbieGuideState()
    @Published var isShowingGuide: Bool = false
    @Published var currentStep: NewbieGuideStep = .none
    @Published var isRunningAnimation: Bool = false
    @Published var catPosition: CGPoint = .zero
    @Published var showPointingVideo: Bool = false
    @Published var showCreateButtonHighlight: Bool = false  // 是否显示创建按钮高亮

    // 首次使用引导相关
    @Published var isShowingFirstUseGuide: Bool = false
    @Published var currentFirstUseFeature: FeatureItem? = nil
    
    // MARK: - 配置
    
    private let stateKey = "newbieGuide.state"
    private let hasSeenWelcomeKey = "newbieGuide.hasSeenWelcome"
    
    let runningVideoName = "naicha_new_role"
    let pointingVideoName = "naicha_pointto"
    let runningDuration: TimeInterval = 5.0  // 跑步动画持续5秒
    
    // 小猫跑步终点位置（右上角）
    var createButtonPosition: CGPoint {
        let screenBounds = UIScreen.main.bounds
        return CGPoint(x: screenBounds.width * 0.8, y: screenBounds.height * 0.10)
    }
    
    // 高亮圈位置（+ 号按钮位置）- 可以独立调整
    var highlightCirclePosition: CGPoint {
        let screenBounds = UIScreen.main.bounds
        // 高亮圈往上挪一些
        return CGPoint(x: screenBounds.width * 0.88, y: screenBounds.height * 0.035)
    }
    
    // 悬浮小猫起始位置（底部中间）- 往上移动
    var floatingCatStartPosition: CGPoint {
        let screenBounds = UIScreen.main.bounds
        return CGPoint(x: screenBounds.width / 2, y: screenBounds.height - 155)
    }
    
    // MARK: - 计算属性
    
    var isFirstLaunch: Bool {
        return !UserDefaults.standard.bool(forKey: hasSeenWelcomeKey)
    }
    
    var shouldShowGuide: Bool {
        return !state.isCompleted && isFirstLaunch
    }
    
    // MARK: - Initialization
    
    private init() {
        loadState()
    }
    
    // MARK: - 状态管理
    
    private func loadState() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(NewbieGuideState.self, from: data) {
            state = decoded
            currentStep = NewbieGuideStep(rawValue: decoded.currentStep) ?? .none
        }
    }
    
    private func saveState() {
        state.currentStep = currentStep.rawValue
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: stateKey)
        }
    }
    
    // MARK: - 引导控制
    
    func startGuide() {
        guard shouldShowGuide else { return }
        
        currentStep = .welcome
        isShowingGuide = true
        saveState()
        
        UserDefaults.standard.set(true, forKey: hasSeenWelcomeKey)
    }
    
    /// 开始跑步动画（从欢迎界面点击后调用）
    func startRunningAnimation() {
        currentStep = .running
        isRunningAnimation = true
        showPointingVideo = false
        showCreateButtonHighlight = false
        
        // 设置起始位置（悬浮小猫位置）
        catPosition = floatingCatStartPosition
        
        // 延迟后开始动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            
            // 动画移动到目标位置（创建按钮位置）
            withAnimation(.linear(duration: self.runningDuration)) {
                self.catPosition = self.createButtonPosition
            }
            
            // 10秒后显示指向动画
            DispatchQueue.main.asyncAfter(deadline: .now() + self.runningDuration) { [weak self] in
                guard let self = self else { return }
                self.isRunningAnimation = false
                self.showPointingVideo = true
                self.showCreateButtonHighlight = true
                self.currentStep = .pointing
                self.saveState()
            }
        }
    }
    
    /// 用户点击了创建按钮，结束引导
    func userTappedCreateButton() {
        guard currentStep == .pointing else { return }
        completeGuide()
    }

    // MARK: - 首次使用引导

    /// 开始显示首次使用引导
    func startFirstUseGuide(for feature: FeatureItem) {
        guard FeatureUnlockManager.guidedFeatures.contains(feature) else { return }
        guard FeatureUnlockManager.shared.isUnlocked(feature) else { return }

        currentFirstUseFeature = feature
        isShowingFirstUseGuide = true
    }

    /// 完成当前首次使用引导
    func completeFirstUseGuide() {
        if let feature = currentFirstUseFeature {
            FeatureUnlockManager.shared.markFirstUseGuideCompleted(for: feature)
        }
        isShowingFirstUseGuide = false
        currentFirstUseFeature = nil
    }

    /// 关闭首次使用引导（不标记为完成）
    func dismissFirstUseGuide() {
        isShowingFirstUseGuide = false
        currentFirstUseFeature = nil
    }

    /// 完成引导
    func completeGuide() {
        state.isCompleted = true
        currentStep = .complete
        isShowingGuide = false
        isRunningAnimation = false
        showPointingVideo = false
        showCreateButtonHighlight = false
        saveState()
    }

    /// 重置引导状态
    func resetGuide() {
        state = NewbieGuideState()
        currentStep = .none
        isShowingGuide = false
        isRunningAnimation = false
        showPointingVideo = false
        showCreateButtonHighlight = false
        UserDefaults.standard.set(false, forKey: hasSeenWelcomeKey)
        saveState()
    }
}

// MARK: - 引导视频播放器视图

struct GuideCatVideoPlayer: View {
    let videoName: String
    let isLooping: Bool
    let isFlipped: Bool
    let onFinished: (() -> Void)?
    
    var body: some View {
        PetVideoPlayer(
            videoName: videoName,
            isLooping: isLooping,
            isMuted: true,
            onFinished: onFinished
        )
        .frame(width: 100, height: 100)
        .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
    }
}

// MARK: - 欢迎气泡视图（第一步）

struct WelcomeBubbleView: View {
    let onStart: () -> Void
    let onSkip: () -> Void
    
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 跳过按钮
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            VStack(spacing: 12) {
                Text("欢迎来到少女心愿衣橱")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("我是你的向导奶茶，让我带你了解一下这个魔法衣橱吧！")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                Button {
                    onStart()
                } label: {
                    Text("开始探索")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [magicPalette.accent, magicPalette.accent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(magicPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 320)
    }
}

// MARK: - 指向提示气泡视图

struct PointingBubbleView: View {
    let onSkip: () -> Void
    let onComplete: () -> Void
    
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 跳过按钮
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            VStack(spacing: 12) {
                Text("添加你的第一件裙子")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("这里是衣橱的手动创建入口，你可以一件一件添加你的裙子。\n\n当然，我们也支持批量创建，一次导入多件衣物，省时省力！")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                Text("点击右上角的 + 号试试")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(magicPalette.accent)
                    .padding(.top, 4)
                
                // 完成按钮
                Button {
                    onComplete()
                } label: {
                    Text("知道了")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [magicPalette.accent, magicPalette.accent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(magicPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 320)
    }
}

// MARK: - 跳过确认弹窗

struct SkipGuideConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                
                Text("跳过新手引导？")
                    .font(.system(size: 18, weight: .bold))
                
                Text("跳过之后可以随时在设置中重新开启引导")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Text("继续引导")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button {
                        onConfirm()
                    } label: {
                        Text("确认跳过")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - 脉冲高亮视图（不拦截点击，仅视觉）

struct HighlightPulseViewNoClick: View {
    let center: CGPoint
    let radius: CGFloat
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.8
    
    var body: some View {
        ZStack {
            // 外圈脉冲动画
            Circle()
                .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: radius * 2 * pulseScale, height: radius * 2 * pulseScale)
                .position(center)
            
            // 内圈白色边框
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                pulseScale = 1.5
                pulseOpacity = 0.0
            }
        }
    }
}

// MARK: - 新手引导遮罩视图

struct NewbieGuideOverlay: View {
    @StateObject private var guideManager = NewbieGuideManager.shared
    @State private var showingSkipConfirmation = false
    
    var body: some View {
        ZStack {
            // 根据当前步骤显示不同的遮罩
            switch guideManager.currentStep {
            case .welcome:
                welcomeMask
            case .running:
                runningMask
            case .pointing:
                pointingMask
            default:
                EmptyView()
            }
            
            // 跳过确认弹窗
            if showingSkipConfirmation {
                SkipGuideConfirmationView(
                    onConfirm: {
                        showingSkipConfirmation = false
                        guideManager.completeGuide()
                    },
                    onCancel: {
                        showingSkipConfirmation = false
                    }
                )
            }
        }
        .transition(.opacity)
        .zIndex(1000)
    }
    
    // MARK: - 欢迎界面遮罩
    
    private var welcomeMask: some View {
        ZStack {
            // 半透明背景 + 底部高亮
            GeometryReader { geometry in
                ZStack {
                    // 半透明背景
                    Color.black
                        .opacity(0.5)
                        .ignoresSafeArea()
                    
                    // 底部小猫位置挖空
                    Circle()
                        .frame(width: 100, height: 100)
                        .position(guideManager.floatingCatStartPosition)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            
            // 欢迎气泡
            VStack {
                Spacer()
                
                WelcomeBubbleView(
                    onStart: {
                        guideManager.startRunningAnimation()
                    },
                    onSkip: {
                        showingSkipConfirmation = true
                    }
                )
                .padding(.bottom, 160)
            }
        }
    }
    
    // MARK: - 跑步动画遮罩
    
    private var runningMask: some View {
        ZStack {
            // 半透明背景（无挖空，小猫在遮罩层之上跑动）
            Color.black
                .opacity(0.3)
                .ignoresSafeArea()
            
            // 跑步小猫
            if guideManager.isRunningAnimation {
                let needsFlip = guideManager.catPosition.x < UIScreen.main.bounds.width / 2
                
                GuideCatVideoPlayer(
                    videoName: guideManager.runningVideoName,
                    isLooping: true,
                    isFlipped: needsFlip,
                    onFinished: nil
                )
                .position(guideManager.catPosition)
            }
        }
    }
    
    // MARK: - 指向动画遮罩
    
    private var pointingMask: some View {
        ZStack {
            // 带挖空的半透明背景 - 右上角创建按钮位置挖空，允许点击穿透
            GeometryReader { geometry in
                ZStack {
                    // 半透明背景
                    Color.black
                        .opacity(0.4)
                        .ignoresSafeArea()
                    
                    // 创建按钮位置挖空 - 允许点击穿透到底层
                    Circle()
                        .frame(width: 80, height: 80)
                        .position(guideManager.highlightCirclePosition)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                // 允许点击穿透到挖空区域
                .allowsHitTesting(false)
            }
            
            // 指向小猫（不循环，停在最后一帧）- 使用小猫终点位置
            if guideManager.showPointingVideo {
                GuideCatVideoPlayer(
                    videoName: guideManager.pointingVideoName,
                    isLooping: false,  // 不循环
                    isFlipped: false,   // 指向右上角不需要翻转
                    onFinished: nil     // 停在最后一帧
                )
                .position(guideManager.createButtonPosition)
                // 小猫视频不阻挡点击
                .allowsHitTesting(false)
            }
            
            // 创建按钮高亮（仅视觉，不拦截点击）- 使用独立的高亮圈位置
            if guideManager.showCreateButtonHighlight {
                HighlightPulseViewNoClick(
                    center: guideManager.highlightCirclePosition,
                    radius: 35
                )
                // 高亮不阻挡点击
                .allowsHitTesting(false)
            }
            
            // 提示气泡（气泡本身需要拦截点击）
            VStack {
                Spacer()
                
                PointingBubbleView(
                    onSkip: {
                        showingSkipConfirmation = true
                    },
                    onComplete: {
                        guideManager.completeGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }
}

// MARK: - View Extension

extension View {
    func withNewbieGuide() -> some View {
        modifier(NewbieGuideModifier())
    }
}

// MARK: - 新手引导修饰器

struct NewbieGuideModifier: ViewModifier {
    @StateObject private var guideManager = NewbieGuideManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            if guideManager.isShowingGuide {
                NewbieGuideOverlay()
            }

            if guideManager.isShowingFirstUseGuide {
                FirstUseGuideOverlay()
            }
        }
    }
}

// MARK: - 首次使用引导遮罩视图

struct FirstUseGuideOverlay: View {
    @StateObject private var guideManager = NewbieGuideManager.shared
    @State private var showingFullDescription = false

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()

            if let feature = guideManager.currentFirstUseFeature {
                // 根据功能显示不同的引导内容
                guideContent(for: feature)
            }
        }
        .transition(.opacity)
        .zIndex(1000)
    }

    @ViewBuilder
    private func guideContent(for feature: FeatureItem) -> some View {
        switch feature {
        case .dataBackup:
            backupGuideContent
        case .cloudSync:
            cloudSyncGuideContent
        case .batchImport:
            batchImportGuideContent
        case .themeCustomize:
            themeGuideContent
        case .ootd:
            ootdGuideContent
        case .wealth:
            wealthGuideContent
        default:
            genericGuideContent(for: feature)
        }
    }

    // MARK: - 备份功能引导

    private var backupGuideContent: some View {
        VStack(spacing: 0) {
            // 跳过按钮
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFirstUseGuide()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            // 引导内容
            VStack(spacing: 16) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)

                Text("数据备份")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("保护你的数据安全")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showingFullDescription {
                    Text("支持本地备份和iCloud云端同步~\n\n本地备份：导出数据文件到本地存储\niCloud同步：在所有Apple设备间自动同步")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFirstUseGuide()
                    } label: {
                        Text("知道了")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    // MARK: - iCloud同步引导

    private var cloudSyncGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFirstUseGuide()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.cyan)

                Text("iCloud云端同步")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("数据自动同步到云端")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showingFullDescription {
                    Text("开启后，你的所有数据将在所有Apple设备间自动同步~\n\n换手机也不用担心数据丢失！")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFirstUseGuide()
                    } label: {
                        Text("知道了")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(Color.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    // MARK: - 批量导入引导

    private var batchImportGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFirstUseGuide()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)

                Text("批量导入")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("快速添加多件裙子")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showingFullDescription {
                    Text("支持从截图、相册等批量识别裙子信息~\n\n点击+号，选择批量导入功能即可使用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFirstUseGuide()
                    } label: {
                        Text("知道了")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    // MARK: - 魔法配色引导

    private var themeGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFirstUseGuide()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .purple, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("魔法配色")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("打造专属主题风格")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showingFullDescription {
                    Text("自定义应用的主题色彩~\n\n可以设置主色、辅助色、强调色\n还可以保存多套主题方案随时切换！")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFirstUseGuide()
                    } label: {
                        Text("去设置")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(
                                LinearGradient(
                                    colors: [.pink, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    // MARK: - OOTD手帐引导

    private var ootdGuideContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange)

                Text("穿搭手帐 (OOTD)")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("记录每日的美丽穿搭")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showingFullDescription {
                    Text("为每件裙子记录穿搭日记~\n\n可以关联当日的照片和心情\n还能在空间手帐中3D展示你的收藏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFirstUseGuide()
                    } label: {
                        Text("知道了")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
    }

    // MARK: - 来财求签引导

    private var wealthGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFirstUseGuide()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("来财求签")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("试试今日运势~")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showingFullDescription {
                    Text("每日求签，看看今天的财运和穿搭运势~\n\n据说很准哦！")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFirstUseGuide()
                    } label: {
                        Text("去求签")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
    }

    // MARK: - 通用引导内容

    private func genericGuideContent(for feature: FeatureItem) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: feature.icon)
                    .font(.system(size: 50))
                    .foregroundStyle(.pink)

                Text(feature.displayName)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("探索这个神奇的功能")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    guideManager.completeFirstUseGuide()
                } label: {
                    Text("知道了")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Color.pink)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
    }
}
