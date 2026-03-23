import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - App首次启动引导步骤

enum AppFirstLaunchStep: String, CaseIterable, Identifiable {
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

// MARK: - 功能体验引导状态管理

extension FeatureUnlockManager {
    // 需要体验引导的功能列表
    static let experienceGuidedFeatures: [FeatureItem] = [
        .dataBackup,      // 数据备份
        .cloudSync,       // iCloud同步
        .batchImport,     // 批量导入
        .themeCustomize,  // 魔法配色
        .filterClassic,   // 筛选偏好
        .spaceBook,       // 空间手帐
        .batchEdit,       // 批量编辑
        .ootd,            // 穿搭手帐
        .wealth,          // 来财求签
        .aiAnalysis,      // 萌宠智能对话
    ]

    // 检查功能是否需要体验引导
    func needsFeatureExperienceGuide(for feature: FeatureItem) -> Bool {
        guard FeatureUnlockManager.experienceGuidedFeatures.contains(feature) else { return false }
        guard isUnlocked(feature) else { return false }
        let key = "featureExperienceGuide_\(feature.rawValue)"
        return !UserDefaults.standard.bool(forKey: key)
    }

    // 标记功能已完成体验引导
    func markFeatureExperienceGuideCompleted(for feature: FeatureItem) {
        let key = "featureExperienceGuide_\(feature.rawValue)"
        UserDefaults.standard.set(true, forKey: key)
    }

    // 重置功能体验引导状态
    func resetFeatureExperienceGuide(for feature: FeatureItem) {
        let key = "featureExperienceGuide_\(feature.rawValue)"
        UserDefaults.standard.set(false, forKey: key)
    }
}

// MARK: - App首次启动引导状态

struct AppFirstLaunchState: Codable {
    var isCompleted: Bool = false
    var currentStep: String = AppFirstLaunchStep.none.rawValue
    var skippedAt: Date? = nil
    var startedAt: Date = Date()
}

// MARK: - App首次启动引导管理器

final class AppFirstLaunchGuideManager: ObservableObject {
    static let shared = AppFirstLaunchGuideManager()
    
    // MARK: - Published Properties

    @Published var state: AppFirstLaunchState = AppFirstLaunchState()
    @Published var isShowingGuide: Bool = false
    @Published var currentStep: AppFirstLaunchStep = .none
    @Published var isRunningAnimation: Bool = false
    @Published var catPosition: CGPoint = .zero
    @Published var showPointingVideo: Bool = false
    @Published var showCreateButtonHighlight: Bool = false  // 是否显示创建按钮高亮

    // 功能体验引导相关
    @Published var isShowingFeatureExperienceGuide: Bool = false
    @Published var currentFeatureExperienceFeature: FeatureItem? = nil
    @Published var aiAnalysisVIPCardGlobalFrame: CGRect? = nil
    @Published var aiAnalysisExchangeButtonGlobalFrame: CGRect? = nil
    
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
           let decoded = try? JSONDecoder().decode(AppFirstLaunchState.self, from: data) {
            state = decoded
            currentStep = AppFirstLaunchStep(rawValue: decoded.currentStep) ?? .none
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

    // MARK: - 功能体验引导

    /// 开始显示功能体验引导
    func startFeatureExperienceGuide(for feature: FeatureItem) {
        print("[FeatureExperienceGuide] 尝试启动引导: \(feature.rawValue)")
        
        guard FeatureUnlockManager.experienceGuidedFeatures.contains(feature) else {
            print("[FeatureExperienceGuide] 失败: 功能不在experienceGuidedFeatures列表中")
            return
        }
        
        let isUnlocked = FeatureUnlockManager.shared.isUnlocked(feature)
        print("[FeatureExperienceGuide] 功能解锁状态: \(isUnlocked)")
        
        guard isUnlocked else {
            print("[FeatureExperienceGuide] 失败: 功能未解锁")
            return
        }

        print("[FeatureExperienceGuide] 启动引导成功: \(feature.rawValue)")
        resetAIAnalysisGuideTargetFrames()
        currentFeatureExperienceFeature = feature
        isShowingFeatureExperienceGuide = true
    }

    /// 完成当前功能体验引导
    func completeFeatureExperienceGuide() {
        if let feature = currentFeatureExperienceFeature {
            FeatureUnlockManager.shared.markFeatureExperienceGuideCompleted(for: feature)
        }
        isShowingFeatureExperienceGuide = false
        currentFeatureExperienceFeature = nil
        resetAIAnalysisGuideTargetFrames()
    }

    /// 关闭功能体验引导（不标记为完成）
    func dismissFeatureExperienceGuide() {
        isShowingFeatureExperienceGuide = false
        currentFeatureExperienceFeature = nil
        resetAIAnalysisGuideTargetFrames()
    }

    // MARK: - 萌宠智能对话引导目标位置信息

    func updateAIAnalysisVIPCardFrame(_ frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        aiAnalysisVIPCardGlobalFrame = frame
    }

    func updateAIAnalysisExchangeButtonFrame(_ frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        aiAnalysisExchangeButtonGlobalFrame = frame
    }

    private func resetAIAnalysisGuideTargetFrames() {
        aiAnalysisVIPCardGlobalFrame = nil
        aiAnalysisExchangeButtonGlobalFrame = nil
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
        state = AppFirstLaunchState()
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
        // 允许点击穿透
        .allowsHitTesting(false)
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

// MARK: - 圆角矩形高亮遮罩（可穿透点击）

struct RoundedRectHighlightView: View {
    let frame: CGRect
    let cornerRadius: CGFloat
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    
    var body: some View {
        ZStack {
            // 外圈脉冲动画
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: frame.width * pulseScale, height: frame.height * pulseScale)
                .position(x: frame.midX, y: frame.midY)
            
            // 内圈白色边框
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
        }
        // 允许点击穿透
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                pulseScale = 1.05
                pulseOpacity = 0.0
            }
        }
    }
}

// MARK: - 小猫爪点击动画组件

struct CatPawTapAnimation: View {
    let position: CGPoint
    let delay: Double
    
    @State private var isAnimating = false
    @State private var tapScale: CGFloat = 1.0
    @State private var tapOpacity: Double = 1.0
    
    var body: some View {
        ZStack {
            // 小猫爪图标
            Image(systemName: "pawprint.fill")
                .font(.system(size: 30))
                .foregroundColor(.white)
                .scaleEffect(tapScale)
                .opacity(tapOpacity)
                .position(position)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
            
            // 点击波纹效果
            Circle()
                .stroke(Color.white.opacity(tapOpacity * 0.5), lineWidth: 2)
                .frame(width: 50 * tapScale, height: 50 * tapScale)
                .position(position)
        }
        // 允许点击穿透
        .allowsHitTesting(false)
        .onAppear {
            // 延迟后开始动画
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                startAnimation()
            }
        }
    }
    
    private func startAnimation() {
        // 点击动画：缩小然后弹回，同时透明度变化
        withAnimation(.easeInOut(duration: 0.3)) {
            tapScale = 0.7
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.2)) {
                tapScale = 1.0
            }
        }
        
        // 波纹扩散动画
        withAnimation(.easeOut(duration: 0.6)) {
            tapScale = 1.5
            tapOpacity = 0.0
        }
        
        // 循环动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            tapScale = 1.0
            tapOpacity = 1.0
            startAnimation()
        }
    }
}

// MARK: - 带挖空的半透明遮罩（可穿透点击）

struct HollowMaskView: View {
    let highlightFrame: CGRect
    let highlightType: HighlightType
    let cornerRadius: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 半透明背景
                Color.black
                    .opacity(0.5)
                    .ignoresSafeArea()
                
                // 挖空区域
                switch highlightType {
                case .circle:
                    Circle()
                        .frame(width: highlightFrame.width, height: highlightFrame.height)
                        .position(x: highlightFrame.midX, y: highlightFrame.midY)
                        .blendMode(.destinationOut)
                case .roundedRect:
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .frame(width: highlightFrame.width, height: highlightFrame.height)
                        .position(x: highlightFrame.midX, y: highlightFrame.midY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            // 允许点击穿透到挖空区域
            .allowsHitTesting(false)
        }
    }
}

// MARK: - App首次启动引导遮罩视图

struct AppFirstLaunchGuideOverlay: View {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
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
    func withAppFirstLaunchGuide() -> some View {
        modifier(AppFirstLaunchGuideModifier())
    }
}

// MARK: - App首次启动引导修饰器

struct AppFirstLaunchGuideModifier: ViewModifier {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            if guideManager.isShowingGuide {
                AppFirstLaunchGuideOverlay()
            }

            if guideManager.isShowingFeatureExperienceGuide {
                FeatureExperienceGuideOverlay()
            }
        }
    }
}

// MARK: - 萌宠智能对话引导步骤

enum AIAnalysisGuideStep: Int, CaseIterable {
    case step1_returnToMe = 1  // 返回「我」界面
    case step2_clickVIP = 2    // 点击VIP卡片
    case step3_exchange = 3    // 兑换会员时长
    
    var title: String {
        switch self {
        case .step1_returnToMe: return "返回「我」界面"
        case .step2_clickVIP: return "点击VIP卡片"
        case .step3_exchange: return "兑换会员时长"
        }
    }
    
    var message: String {
        switch self {
        case .step1_returnToMe: return "首先，请返回到「我」界面，我们将引导你开通VIP会员"
        case .step2_clickVIP: return "点击VIP会员卡片，进入会员中心"
        case .step3_exchange: return "点击「兑换会员时长」，使用喵币兑换VIP天数"
        }
    }
    
    var bubblePosition: BubblePosition {
        switch self {
        case .step1_returnToMe: return .bottom
        case .step2_clickVIP: return .bottom
        case .step3_exchange: return .top
        }
    }
    
    var highlightType: HighlightType {
        switch self {
        case .step1_returnToMe: return .circle
        case .step2_clickVIP: return .roundedRect
        case .step3_exchange: return .roundedRect
        }
    }
    
    var showCatPaw: Bool {
        switch self {
        case .step1_returnToMe: return true
        case .step2_clickVIP: return false
        case .step3_exchange: return true
        }
    }
}

enum HighlightType {
    case circle
    case roundedRect
}

// MARK: - 功能体验引导遮罩视图

struct FeatureExperienceGuideOverlay: View {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @State private var showingFullDescription = false
    
    // aiAnalysis引导专用状态
    @State private var aiAnalysisStep: AIAnalysisGuideStep = .step1_returnToMe
    @State private var currentTab: String = "wardrobe"  // 当前tab，用于检测是否返回了「我」界面

    var body: some View {
        ZStack {
            // 半透明背景 - 允许点击穿透（具体内容的遮罩各自控制）
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let feature = guideManager.currentFeatureExperienceFeature {
                // 根据功能显示不同的引导内容
                guideContent(for: feature)
            }
        }
        .transition(.opacity)
        .zIndex(1000)
        .onAppear {
            print("[FeatureExperienceGuide] onAppear, feature: \(guideManager.currentFeatureExperienceFeature?.rawValue ?? "nil")")
            
            // 监听tab切换通知
            NotificationCenter.default.addObserver(
                forName: .homeTabChanged,
                object: nil,
                queue: .main
            ) { notification in
                if let tab = notification.userInfo?["tab"] as? String {
                    currentTab = tab
                    print("[FeatureExperienceGuide] Tab切换到: \(tab), 当前步骤: \(aiAnalysisStep)")
                    // 如果当前是aiAnalysis引导的第一步，且用户切换到了me tab，自动进入第二步
                    if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                       aiAnalysisStep == .step1_returnToMe,
                       tab == "me",
                       guideManager.aiAnalysisVIPCardGlobalFrame != nil {
                        print("[FeatureExperienceGuide] 从step1自动进入step2")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            aiAnalysisStep = .step2_clickVIP
                        }
                    }
                }
            }
            
            // 监听VIP中心打开通知
            NotificationCenter.default.addObserver(
                forName: .vipCenterOpened,
                object: nil,
                queue: .main
            ) { _ in
                // 如果当前是aiAnalysis引导的第二步，且用户打开了VIP中心，自动进入第三步
                if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
                   aiAnalysisStep == .step2_clickVIP {
                    print("[FeatureExperienceGuide] 从step2自动进入step3")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        aiAnalysisStep = .step3_exchange
                    }
                }
            }
        }
        .onDisappear {
            // 移除通知监听
            NotificationCenter.default.removeObserver(self, name: .homeTabChanged, object: nil)
            NotificationCenter.default.removeObserver(self, name: .vipCenterOpened, object: nil)
        }
        .onChange(of: guideManager.aiAnalysisVIPCardGlobalFrame) { vipCardFrame in
            // step1 -> step2：只有当用户真的回到「我」页并拿到 VIP 卡片真实位置后才前进
            if guideManager.currentFeatureExperienceFeature == .aiAnalysis,
               aiAnalysisStep == .step1_returnToMe,
               vipCardFrame != nil {
                print("[FeatureExperienceGuide] 检测到VIP卡片位置，step1进入step2")
                withAnimation(.easeInOut(duration: 0.3)) {
                    aiAnalysisStep = .step2_clickVIP
                }
            }
        }
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
        case .filterClassic:
            filterClassicGuideContent
        case .spaceBook:
            spaceBookGuideContent
        case .batchEdit:
            batchEditGuideContent
        case .ootd:
            ootdGuideContent
        case .wealth:
            wealthGuideContent
        case .aiAnalysis:
            aiAnalysisGuideContent
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
                    guideManager.dismissFeatureExperienceGuide()
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
                        guideManager.completeFeatureExperienceGuide()
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
                    guideManager.dismissFeatureExperienceGuide()
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
                        guideManager.completeFeatureExperienceGuide()
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
                    guideManager.dismissFeatureExperienceGuide()
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
                        guideManager.completeFeatureExperienceGuide()
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

    // MARK: - 筛选偏好引导

    private var filterClassicGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFeatureExperienceGuide()
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
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.purple)

                Text("筛选偏好")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("选择适合你的筛选样式")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showingFullDescription {
                    Text("经典筛选：简洁直观，适合快速浏览\n多维筛选：多重条件组合，精准定位")
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
                        guideManager.completeFeatureExperienceGuide()
                    } label: {
                        Text("去设置")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(Color.purple)
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

    // MARK: - 空间手帐引导

    private var spaceBookGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFeatureExperienceGuide()
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
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)

                Text("空间手帐")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("3D展示你的衣橱")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showingFullDescription {
                    Text("在3D空间中浏览你的裙子收藏~\n\n可以从任意角度欣赏你的衣橱\n还能查看裙子的详细信息")
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
                        guideManager.completeFeatureExperienceGuide()
                    } label: {
                        Text("去体验")
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

    // MARK: - 批量编辑引导

    private var batchEditGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFeatureExperienceGuide()
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
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)

                Text("批量编辑")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("一次修改多条裙子")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if showingFullDescription {
                    Text("选择多条裙子同时编辑~\n\n可以批量修改标签、分类、季节等信息\n省时省力管理你的衣橱")
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
                        guideManager.completeFeatureExperienceGuide()
                    } label: {
                        Text("去体验")
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
                    guideManager.dismissFeatureExperienceGuide()
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
                        guideManager.completeFeatureExperienceGuide()
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
                        guideManager.completeFeatureExperienceGuide()
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
                    guideManager.dismissFeatureExperienceGuide()
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
                        guideManager.completeFeatureExperienceGuide()
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

    // MARK: - 萌宠智能对话引导（三步骤）

    private var aiAnalysisGuideContent: some View {
        GeometryReader { geometry in
            ZStack {
                // 根据当前步骤显示不同的遮罩和高亮
                switch aiAnalysisStep {
                case .step1_returnToMe:
                    // 第一步：高亮返回按钮
                    step1Content(in: geometry)
                case .step2_clickVIP:
                    // 第二步：高亮VIP卡片
                    step2Content(in: geometry)
                case .step3_exchange:
                    // 第三步：高亮兑换按钮
                    step3Content(in: geometry)
                }
            }
        }
    }

    // 步骤1：返回「我」界面
    private func step1Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        // 返回按钮位置（左上角导航栏区域）
        let backButtonFrame = CGRect(
            x: 16,
            y: 8,  // 调整到导航栏顶部区域
            width: 44,
            height: 44
        )
        
        return ZStack {
            // 带挖空的遮罩 - 允许点击穿透到挖空区域
            HollowMaskView(
                highlightFrame: backButtonFrame,
                highlightType: .circle,
                cornerRadius: 22
            )
            
            // 圆形高亮边框 - 仅视觉，不拦截点击
            HighlightPulseViewNoClick(
                center: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                radius: 28
            )
            
            // 小猫爪点击动画 - 仅视觉，不拦截点击
            if aiAnalysisStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                    delay: 0.5
                )
            }
            
            // 引导对话框（底部）
            VStack {
                Spacer()
                
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    // 步骤2：点击VIP卡片
    private func step2Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        // 优先使用真实VIP卡片位置，兜底再用估算值（兼容两种卡片高度）
        let fallbackVIPFrame = CGRect(
            x: 16,
            y: screenBounds.height * 0.16,
            width: screenBounds.width - 32,
            height: VIPManager.shared.isVIP ? 180 : 100
        )
        let vipCardFrame = aiGuideTargetFrame(
            globalFrame: guideManager.aiAnalysisVIPCardGlobalFrame,
            in: geometry,
            fallback: fallbackVIPFrame
        )
        
        return ZStack {
            // 带挖空的遮罩（圆角矩形）
            HollowMaskView(
                highlightFrame: vipCardFrame,
                highlightType: .roundedRect,
                cornerRadius: 20
            )
            
            // 圆角矩形高亮边框
            RoundedRectHighlightView(
                frame: vipCardFrame,
                cornerRadius: 20
            )
            .allowsHitTesting(false)
            
            // 引导对话框（底部）
            VStack {
                Spacer()
                
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    // 步骤3：兑换会员时长
    private func step3Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        // 优先使用真实按钮位置；按反馈将高亮略微下移，避免偏上
        let fallbackExchangeFrame = CGRect(
            x: 20,
            y: screenBounds.height * 0.44,
            width: screenBounds.width - 40,
            height: 56
        )
        let exchangeButtonFrame = aiGuideTargetFrame(
            globalFrame: guideManager.aiAnalysisExchangeButtonGlobalFrame,
            in: geometry,
            fallback: fallbackExchangeFrame
        )
        .offsetBy(dx: 0, dy: 10)
        
        return ZStack {
            // 带挖空的遮罩（圆角矩形）
            HollowMaskView(
                highlightFrame: exchangeButtonFrame,
                highlightType: .roundedRect,
                cornerRadius: 12
            )
            
            // 圆角矩形高亮边框
            RoundedRectHighlightView(
                frame: exchangeButtonFrame,
                cornerRadius: 12
            )
            .allowsHitTesting(false)
            
            // 小猫爪点击动画
            if aiAnalysisStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: exchangeButtonFrame.midX, y: exchangeButtonFrame.midY),
                    delay: 0.5
                )
                .allowsHitTesting(false)
            }
            
            // 引导对话框（顶部）
            VStack {
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.top, 100)
                
                Spacer()
            }
        }
    }

    private func aiGuideTargetFrame(
        globalFrame: CGRect?,
        in geometry: GeometryProxy,
        fallback: CGRect
    ) -> CGRect {
        guard let globalFrame, globalFrame.width > 0, globalFrame.height > 0 else {
            return fallback
        }
        
        let overlayGlobalOrigin = geometry.frame(in: .global).origin
        return CGRect(
            x: globalFrame.minX - overlayGlobalOrigin.x,
            y: globalFrame.minY - overlayGlobalOrigin.y,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }

    // 萌宠智能对话引导对话框 - 复用开屏首次新手引导的PointingBubbleView设计
    private func aiAnalysisBubble(
        step: AIAnalysisGuideStep,
        onSkip: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) -> some View {
        AIAnalysisGuideBubbleView(
            step: step,
            onSkip: onSkip,
            onComplete: onComplete
        )
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
                    guideManager.completeFeatureExperienceGuide()
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

// MARK: - 萌宠智能对话引导气泡视图（复用PointingBubbleView设计风格）

struct AIAnalysisGuideBubbleView: View {
    let step: AIAnalysisGuideStep
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
                // 步骤指示器
                HStack(spacing: 4) {
                    ForEach(AIAnalysisGuideStep.allCases, id: \.rawValue) { s in
                        Circle()
                            .fill(s.rawValue <= step.rawValue ? magicPalette.accent : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Text(step.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text(step.message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)
                
                // 完成按钮（仅在最后一步显示）
                if step == .step3_exchange {
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
        .padding(.horizontal, 20)
    }
}
