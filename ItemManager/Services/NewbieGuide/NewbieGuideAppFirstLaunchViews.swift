import SwiftUI
import UIKit
import Combine
import AVFoundation

struct GuideCatVideoPlayer: View {
    let videoName: String
    let isLooping: Bool
    let playbackRate: Float
    let isFlipped: Bool
    let onFinished: (() -> Void)?

    @State private var shouldShowMissingResourceFallback = false

    var body: some View {
        Group {
            if shouldUseStaticFallback {
                fallbackImage
            } else {
                FirstLaunchTransparentVideoPlayer(
                    videoName: videoName,
                    isLooping: isLooping,
                    isMirrored: isFlipped,
                    playbackRate: playbackRate,
                    onFinished: onFinished,
                    onMissingResource: {
                        #if DEBUG
                        print("FirstLaunchGuide: Missing \(videoName), falling back to static image")
                        #endif
                        DispatchQueue.main.async {
                            shouldShowMissingResourceFallback = true
                        }
                    }
                )
            }
        }
        .frame(width: 100, height: 100)
        .onChange(of: videoName) { _, _ in
            shouldShowMissingResourceFallback = false
        }
    }

    private var shouldUseStaticFallback: Bool {
        shouldShowMissingResourceFallback || TransparentVideoSupport.shouldSuppress(videoName: videoName)
    }

    private var fallbackImage: some View {
        Image("naicha_right_back")
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
            .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
    }
}

private struct FirstLaunchTransparentVideoPlayer: UIViewRepresentable {
    let videoName: String
    let isLooping: Bool
    let isMirrored: Bool
    let playbackRate: Float
    let onFinished: (() -> Void)?
    let onMissingResource: (() -> Void)?

    func makeUIView(context: Context) -> FirstLaunchTransparentVideoPlayerView {
        let view = FirstLaunchTransparentVideoPlayerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: FirstLaunchTransparentVideoPlayerView, context: Context) {
        uiView.update(
            videoName: videoName,
            isLooping: isLooping,
            isMirrored: isMirrored,
            playbackRate: playbackRate,
            onFinished: onFinished,
            onMissingResource: onMissingResource
        )
    }

    static func dismantleUIView(_ uiView: FirstLaunchTransparentVideoPlayerView, coordinator: ()) {
        uiView.cleanup()
    }
}

private final class FirstLaunchTransparentVideoPlayerView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var currentVideoName: String?
    private var currentURL: URL?
    private var isLooping: Bool = false
    private var playbackRate: Float = 1
    private var onFinished: (() -> Void)?
    private var onMissingResource: (() -> Void)?
    private var finishObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var didFinishCurrentItem = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        isOpaque = false
        backgroundColor = .clear
        layer.isOpaque = false
        layer.backgroundColor = UIColor.clear.cgColor

        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.isOpaque = false
        playerLayer.frame = bounds
        layer.addSublayer(playerLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func update(
        videoName: String,
        isLooping: Bool,
        isMirrored: Bool,
        playbackRate: Float,
        onFinished: (() -> Void)?,
        onMissingResource: (() -> Void)?
    ) {
        self.isLooping = isLooping
        self.playbackRate = max(0.1, playbackRate)
        self.onFinished = onFinished
        self.onMissingResource = onMissingResource
        applyMirror(isMirrored)

        if currentVideoName == videoName {
            resumeIfNeeded()
            return
        }

        guard let url = findFirstLaunchVideoURL(name: videoName) else {
            #if DEBUG
            print("FirstLaunchGuide: Missing transparent guide video \(videoName)")
            #endif
            fallbackForMissingResource()
            return
        }

        load(videoName: videoName, url: url)
    }

    private func findFirstLaunchVideoURL(name videoName: String) -> URL? {
        // 首启引导视频位于 asserts 根目录。DEBUG 下 VideoResourceManager 会优先返回
        // iCloud 源码目录的绝对路径，AVPlayer 在 App/模拟器沙盒内可能因权限 257 打不开。
        // 这里优先使用 App Bundle 里的资源，保证 iOS 18+ 透明 MOV 走可访问路径。
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mov", subdirectory: "asserts") {
            return url
        }
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4", subdirectory: "asserts") {
            return url
        }
        return VideoResourceManager.shared.findVideoURL(name: videoName)
    }

    private func load(videoName: String, url: URL) {
        cleanupCurrentItem()
        didFinishCurrentItem = false
        currentVideoName = videoName
        currentURL = url

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.volume = 0
        queuePlayer.actionAtItemEnd = .pause
        queuePlayer.replaceCurrentItem(with: item)
        player = queuePlayer
        playerLayer.player = queuePlayer

        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.currentVideoName == videoName else { return }
                switch item.status {
                case .readyToPlay:
                    self.play()
                case .failed:
                    #if DEBUG
                    print("FirstLaunchGuide: Failed to load transparent guide video \(videoName): \(String(describing: item.error))")
                    #endif
                default:
                    break
                }
            }
        }

        finishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackFinished(item: item)
        }

        play()
    }

    private func handlePlaybackFinished(item: AVPlayerItem) {
        guard !didFinishCurrentItem else { return }

        if isLooping {
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                self?.play()
            }
            return
        }

        didFinishCurrentItem = true
        player?.pause()
        seekToLastFrameIfPossible(item: item)
        onFinished?()
    }

    private func seekToLastFrameIfPossible(item: AVPlayerItem) {
        let duration = item.duration
        guard duration.isValid, duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 else {
            return
        }
        player?.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func resumeIfNeeded() {
        guard player?.currentItem != nil else {
            if let name = currentVideoName, let url = currentURL {
                load(videoName: name, url: url)
            }
            return
        }

        if player?.timeControlStatus != .playing, !didFinishCurrentItem {
            play()
        }
    }

    private func play() {
        guard let player = player, !didFinishCurrentItem else { return }
        if abs(playbackRate - 1) < 0.01 {
            player.play()
        } else {
            player.playImmediately(atRate: playbackRate)
        }
    }

    private func applyMirror(_ isMirrored: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.transform = CATransform3DMakeScale(isMirrored ? -1 : 1, 1, 1)
        CATransaction.commit()
    }

    private func fallbackForMissingResource() {
        cleanup()
        onMissingResource?()
    }

    private func cleanupCurrentItem() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let finishObserver {
            NotificationCenter.default.removeObserver(finishObserver)
            self.finishObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }

    func cleanup() {
        cleanupCurrentItem()
        playerLayer.player = nil
        player = nil
        currentVideoName = nil
        currentURL = nil
        didFinishCurrentItem = false
    }

    deinit {
        cleanup()
    }
}

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
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过".appLocalized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 12) {
                Text("欢迎来到少女心愿衣橱".appLocalized)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text("我是你的向导奶茶，让我带你了解一下这个魔法衣橱吧！".appLocalized)
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Button {
                    onStart()
                } label: {
                    Text("开始探索".appLocalized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(magicPalette.bubbleUserTextColor)
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
        .captureGuideInteractionRegion("guide.text.bubble")
    }
}

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
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过".appLocalized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 12) {
                Text("添加你的第一件裙子".appLocalized)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text("这里是衣橱的手动创建入口，你可以一件一件添加你的裙子。\n\n当然，我们也支持批量创建，一次导入多件衣物，省时省力！".appLocalized)
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text("点击右上角的 + 号试试".appLocalized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(magicPalette.accent)
                    .padding(.top, 4)

                Button {
                    onComplete()
                } label: {
                    Text("知道了".appLocalized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(magicPalette.bubbleUserTextColor)
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
        .captureGuideInteractionRegion("guide.text.bubble")
    }
}

struct SkipGuideConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("跳过新手引导？".appLocalized)
                    .font(.system(size: 18, weight: .bold))

                Text("跳过之后可以随时在设置中重新开启引导".appLocalized)
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Text("继续引导".appLocalized)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(magicPalette.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(magicPalette.quickOptionFill)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        onConfirm()
                    } label: {
                        Text("确认跳过".appLocalized)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(magicPalette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(magicPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 40)
            .captureGuideInteractionRegion("guide.text.bubble")
        }
    }
}

struct AppFirstLaunchGuideOverlay: View {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @State private var showingSkipConfirmation = false
    
    private var welcomeHighlightDiameter: CGFloat {
        guard guideManager.isPadGuideLayout else { return 100 }
        let widthBased = UIScreen.main.bounds.width * 0.18
        return min(max(widthBased, 128), 150)
    }

    var body: some View {
        ZStack {
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

            if showingSkipConfirmation {
                SkipGuideConfirmationView(
                    onConfirm: {
                        showingSkipConfirmation = false
                        guideManager.completeGuide(shouldGrantFirstCompletionReward: false)
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

    private var welcomeMask: some View {
        ZStack {
            GeometryReader { _ in
                ZStack {
                    Color.black
                        .opacity(0.5)
                        .ignoresSafeArea()

                    Circle()
                        .frame(width: welcomeHighlightDiameter, height: welcomeHighlightDiameter)
                        .position(guideManager.floatingCatStartPosition)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }

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

    private var runningMask: some View {
        ZStack {
            Color.black
                .opacity(0.3)
                .ignoresSafeArea()

            if guideManager.isRunningAnimation {
                GuideCatVideoPlayer(
                    videoName: guideManager.runningVideoName,
                    isLooping: guideManager.isRunningVideoLooping,
                    playbackRate: guideManager.guideVideoPlaybackRate,
                    isFlipped: guideManager.isGuideCatFlipped,
                    onFinished: {
                        guideManager.handleRunningVideoPlaybackFinished()
                    }
                )
                .position(guideManager.catPosition)
            }
        }
    }

    private var pointingMask: some View {
        ZStack {
            GeometryReader { _ in
                ZStack {
                    Color.black
                        .opacity(0.4)
                        .ignoresSafeArea()

                    let screenWidth = UIScreen.main.bounds.width
                    let scaleFactor = GuideAdaptiveScale.factor(screenWidth: screenWidth)
                    let holeSize = 80 * scaleFactor
                    
                    Circle()
                        .frame(width: holeSize, height: holeSize)
                        .position(guideManager.highlightCirclePosition)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)
            }

            if guideManager.showPointingVideo {
                GuideCatVideoPlayer(
                    videoName: guideManager.pointingVideoName,
                    isLooping: false,
                    playbackRate: guideManager.guideVideoPlaybackRate,
                    isFlipped: guideManager.isGuideCatFlipped,
                    onFinished: nil
                )
                .position(guideManager.catPosition)
                .allowsHitTesting(false)
            }

            if guideManager.showCreateButtonHighlight {
                HighlightPulseViewNoClick(
                    center: guideManager.highlightCirclePosition,
                    radius: 35
                )
                .allowsHitTesting(false)
            }

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

extension View {
    func withAppFirstLaunchGuide() -> some View {
        modifier(AppFirstLaunchGuideModifier())
    }
}

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

struct GlobalGuideOverlaySceneInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> GuideOverlaySceneProbeView {
        let view = GuideOverlaySceneProbeView()
        view.onSceneChange = { scene in
            Task { @MainActor in
                GuideTopOverlayWindowManager.shared.attach(to: scene)
            }
        }
        return view
    }

    func updateUIView(_ uiView: GuideOverlaySceneProbeView, context: Context) {
        Task { @MainActor in
            GuideTopOverlayWindowManager.shared.attach(to: uiView.window?.windowScene)
        }
    }

    static func dismantleUIView(_ uiView: GuideOverlaySceneProbeView, coordinator: ()) {
        Task { @MainActor in
            GuideTopOverlayWindowManager.shared.detach()
        }
    }
}

final class GuideOverlaySceneProbeView: UIView {
    var onSceneChange: ((UIWindowScene?) -> Void)?
    private weak var lastScene: UIWindowScene?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        notifySceneIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        notifySceneIfNeeded()
    }

    private func notifySceneIfNeeded() {
        let scene = window?.windowScene
        guard scene !== lastScene else { return }
        lastScene = scene
        onSceneChange?(scene)
    }
}

@MainActor
final class GuideTopOverlayWindowManager {
    static let shared = GuideTopOverlayWindowManager()

    private let guideManager = AppFirstLaunchGuideManager.shared
    private var cancellables = Set<AnyCancellable>()
    private weak var currentScene: UIWindowScene?
    private var overlayWindow: GuidePassThroughWindow?

    private init() {
        guideManager.$isShowingGuide
            .combineLatest(guideManager.$isShowingFeatureExperienceGuide)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isShowingGuide, isShowingFeatureGuide in
                Task { @MainActor in
                    self?.setWindowVisible(isShowingGuide || isShowingFeatureGuide)
                }
            }
            .store(in: &cancellables)
    }

    func attach(to scene: UIWindowScene?) {
        let targetScene = scene ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        guard let targetScene else { return }

        if currentScene !== targetScene || overlayWindow == nil {
            configureWindow(for: targetScene)
        }

        setWindowVisible(guideManager.isShowingGuide || guideManager.isShowingFeatureExperienceGuide)
    }

    func detach() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
        currentScene = nil
    }

    private func configureWindow(for scene: UIWindowScene) {
        let rootView = GlobalGuideTopOverlayView()
            .environment(ThemeManager.shared)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false

        let window = GuidePassThroughWindow(windowScene: scene)
        window.rootViewController = hostingController
        window.backgroundColor = .clear
        window.isOpaque = false
        window.windowLevel = .alert + 1
        window.isHidden = true

        // 显式设置 window 的 frame 为整个 scene 的 bounds
        window.frame = scene.coordinateSpace.bounds

        overlayWindow = window
        currentScene = scene
    }

    private func setWindowVisible(_ isVisible: Bool) {
        guard let window = overlayWindow else { return }
        window.isHidden = !isVisible
    }
}

private struct GlobalGuideTopOverlayView: View {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared

    var body: some View {
        ZStack {
            if guideManager.isShowingGuide {
                AppFirstLaunchGuideOverlay()
            }

            if guideManager.isShowingFeatureExperienceGuide {
                FeatureExperienceGuideOverlay()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .ignoresSafeArea()
    }
}

private final class GuidePassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else {
            return nil
        }

        let guideManager = AppFirstLaunchGuideManager.shared

        if guideManager.hasGuideInteractiveRegions() {
            return guideManager.isPointInGuideInteractiveRegions(point, hitSlop: 0) ? hitView : nil
        }

        return nil
    }
}
