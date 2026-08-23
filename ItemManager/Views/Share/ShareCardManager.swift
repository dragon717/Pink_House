//
//  ShareCardManager.swift
//  ItemManager
//
//  分享卡片管理器 - 负责生成分享图片和管理卡牌资源
//  优化版本：添加猫爪加载动画、异步生成、内存优化
//

import SwiftUI
import UIKit

// MARK: - 分享预览项（用于显示图片预览）
class SharePreviewItem: NSObject, UIActivityItemSource {
    let image: UIImage
    
    init(image: UIImage) {
        self.image = image
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return image
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return image
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        // 返回缩略图用于预览 - 使用更小的尺寸减少内存占用
        let targetSize = CGSize(width: min(size.width, 300), height: min(size.height, 300))
        return image.preparingThumbnail(of: targetSize)
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "分享图片"
    }
}

// MARK: - 加载动画视图
struct CatPawLoadingView: View {
    let message: String
    let title: String
    let detail: String?
    let estimatedSeconds: ClosedRange<Int>?
    let systemImage: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    @State private var startedAt = Date()

    init(
        message: String,
        title: String = "正在努力处理中".appLocalized,
        detail: String? = nil,
        estimatedSeconds: ClosedRange<Int>? = nil,
        systemImage: String = "pawprint.fill"
    ) {
        self.message = message
        self.title = title
        self.detail = detail
        self.estimatedSeconds = estimatedSeconds
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(MonicaColors.primaryPink.opacity(0.12))
                    .frame(width: 112, height: 112)
                    .scaleEffect(isAnimating && !reduceMotion ? 1.08 : 1)

                Circle()
                    .stroke(MonicaColors.primaryPink.opacity(0.16), lineWidth: 7)
                    .frame(width: 92, height: 92)

                TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                    let progress = elapsed.truncatingRemainder(dividingBy: 1.35) / 1.35
                    let rotation = UnitCurve.easeInOut.value(at: progress) * 360

                    ZStack {
                        Circle()
                            .trim(from: 0.06, to: 0.78)
                            .stroke(
                                AngularGradient(
                                    colors: [MonicaColors.primaryPink, MonicaColors.lightPink, MonicaColors.primaryPink],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round)
                            )
                            .frame(width: 92, height: 92)
                            .rotationEffect(.degrees(rotation))

                        Circle()
                            .stroke(
                                MonicaColors.primaryPink.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 7])
                            )
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-rotation * 0.65))
                    }
                }

                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MonicaColors.primaryPink, MonicaColors.lightPink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isAnimating && !reduceMotion ? 1.08 : 1)
                    .shadow(color: MonicaColors.primaryPink.opacity(0.35), radius: 10, y: 4)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MonicaColors.primaryPink)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let estimatedSeconds {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    HStack(spacing: 12) {
                        Label(
                            "通常约 \(estimatedSeconds.lowerBound)–\(estimatedSeconds.upperBound) 秒".appLocalized,
                            systemImage: "clock"
                        )
                        Text("已等待 \(max(0, Int(context.date.timeIntervalSince(startedAt)))) 秒".appLocalized)
                            .monospacedDigit()
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(MonicaColors.primaryPink)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isAnimating && !reduceMotion ? 1 : 0.55)
                        .opacity(isAnimating && !reduceMotion ? 1 : 0.35)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.55)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.16),
                            value: isAnimating
                        )
                }
            }
        }
        .onAppear {
            startedAt = Date()
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, message, detail].compactMap { $0 }.joined(separator: "，"))
    }
}

// MARK: - 分享加载遮罩
struct ShareLoadingOverlay: View {
    let message: String
    var title: String = "正在努力处理中".appLocalized
    var detail: String?
    var estimatedSeconds: ClosedRange<Int>?
    var systemImage: String = "pawprint.fill"

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            CatPawLoadingView(
                message: message,
                title: title,
                detail: detail,
                estimatedSeconds: estimatedSeconds,
                systemImage: systemImage
            )
            .frame(maxWidth: 300)
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.18), radius: 24, y: 12)
            )
            .padding(.horizontal, 30)
        }
        .transition(.opacity)
    }
}

// MARK: - 分享卡片管理器
class ShareCardManager {
    static let shared = ShareCardManager()
    
    // 卡牌资源图片
    private var cardFrontImage: UIImage?
    private var cardBackImage: UIImage?
    
    // 内存优化：根据设备内存动态调整图片质量
    private let isLowMemoryDevice: Bool
    private let renderScale: CGFloat
    
    private init() {
        // 检测设备内存
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        self.isLowMemoryDevice = totalMemory <= 2 * 1024 * 1024 * 1024 // <= 2GB
        // 低内存设备使用更低的分辨率
        self.renderScale = isLowMemoryDevice ? 1.0 : UIScreen.main.scale
        
        loadCardImages()
    }
    
    // MARK: - 加载卡牌图片
    private func loadCardImages() {
        // 尝试从Assets加载卡牌图片
        cardFrontImage = UIImage(named: "card_front")
        cardBackImage = UIImage(named: "card_back")
        
        // 用户侧只读取已打包进 Assets.xcassets 的资源，避免开发机 temp 路径泄漏。
    }
    
    // MARK: - 获取卡牌图片
    func getCardFrontImage() -> UIImage? {
        return cardFrontImage
    }
    
    func getCardBackImage() -> UIImage? {
        return cardBackImage
    }
    
    // MARK: - 异步生成裙装分享图片（优化版本）
    func generateClothingShareImageAsync(clothing: Clothing) async -> UIImage? {
        // 在主线程获取需要的值，避免跨actor访问
        let frontImage = self.cardFrontImage
        
        // 步骤1：在后台线程加载和预处理图片
        let clothingImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            return autoreleasepool {
                guard let firstPath = clothing.imagePaths.first else { return nil }
                var img = ImageManager.shared.loadImage(fileName: firstPath)
                // 如果图片太大，进行缩放
                if let image = img,
                   max(image.size.width, image.size.height) > 800 {
                    img = image.resized(toMaxDimension: 800)
                }
                return img
            }
        }.value
        
        // 步骤2：回到主线程创建和渲染SwiftUI视图
        return await MainActor.run {
            return autoreleasepool {
                let cardView = ClothingShareCardFullView(
                    clothing: clothing,
                    image: clothingImage,
                    cardBackground: frontImage,
                    fontProvider: CustomFontProvider()
                )
                return self.renderViewToImage(cardView, size: CGSize(width: 320, height: 520))
            }
        }
    }
    
    // MARK: - 异步生成书页分享图片（平面书页）
    func generateOutfitShareImageAsync(outfit: Outfit) async -> UIImage? {
        // 在主线程获取需要的值
        let frontImage = self.cardFrontImage
        
        // 直接回到主线程渲染（Outfit图片已经在加载时处理过了）
        return await MainActor.run {
            return autoreleasepool {
                let cardView = OutfitShareCardView(
                    outfit: outfit,
                    cardBackground: frontImage
                )
                .environment(\.fontProvider, CustomFontProvider())
                
                return self.renderViewToImage(cardView, size: CGSize(width: 320, height: 520))
            }
        }
    }
    
    // MARK: - 异步生成书页分享图片（空间书页）
    func generateSpaceOutfitShareImageAsync(outfit: SpaceOutfit) async -> UIImage? {
        // 在主线程获取需要的值
        let frontImage = self.cardFrontImage
        
        // 直接回到主线程渲染
        return await MainActor.run {
            return autoreleasepool {
                let cardView = SpaceOutfitShareCardView(
                    outfit: outfit,
                    cardBackground: frontImage
                )
                .environment(\.fontProvider, CustomFontProvider())
                
                return self.renderViewToImage(cardView, size: CGSize(width: 320, height: 520))
            }
        }
    }
    
    // MARK: - 同步生成方法（保留用于兼容）
    func generateClothingShareImage(clothing: Clothing) -> UIImage? {
        // 低内存设备直接返回 nil，强制使用异步方法
        if isLowMemoryDevice {
            AppLogger.info("Low memory device detected, please use async method")
            return nil
        }
        
        return autoreleasepool {
            var clothingImage: UIImage?
            if let firstPath = clothing.imagePaths.first {
                clothingImage = ImageManager.shared.loadImage(fileName: firstPath)
            }
            
            let cardView = ClothingShareCardFullView(
                clothing: clothing,
                image: clothingImage,
                cardBackground: cardFrontImage,
                fontProvider: CustomFontProvider()
            )
            
            return renderViewToImage(cardView, size: CGSize(width: 320, height: 520))
        }
    }
    
    func generateOutfitShareImage(outfit: Outfit) -> UIImage? {
        if isLowMemoryDevice { return nil }
        
        return autoreleasepool {
            let cardView = OutfitShareCardView(
                outfit: outfit,
                cardBackground: cardFrontImage
            )
            .environment(\.fontProvider, CustomFontProvider())
            
            return renderViewToImage(cardView, size: CGSize(width: 320, height: 520))
        }
    }
    
    func generateSpaceOutfitShareImage(outfit: SpaceOutfit) -> UIImage? {
        if isLowMemoryDevice { return nil }
        
        return autoreleasepool {
            let cardView = SpaceOutfitShareCardView(
                outfit: outfit,
                cardBackground: cardFrontImage
            )
            .environment(\.fontProvider, CustomFontProvider())
            
            return renderViewToImage(cardView, size: CGSize(width: 320, height: 520))
        }
    }
    
    // MARK: - 渲染视图为图片（优化版本）
    private func renderViewToImage<V: View>(_ view: V, size: CGSize) -> UIImage? {
        // 低内存设备使用更小的渲染尺寸
        let renderSize = isLowMemoryDevice ? CGSize(width: size.width * 0.75, height: size.height * 0.75) : size
        
        let controller = UIHostingController(rootView: view)
        let view = controller.view
        
        view?.bounds = CGRect(origin: .zero, size: renderSize)
        view?.backgroundColor = .clear
        
        // 使用更高效的渲染配置
        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        format.opaque = false
        // 低内存设备使用更低的质量
        if isLowMemoryDevice {
            format.preferredRange = .standard
        }
        
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        
        let image = renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        
        // 及时释放视图控制器
        controller.removeFromParent()
        
        return image
    }
}

// MARK: - 分享类型枚举
enum ShareContentType {
    case clothing(Clothing)
    case outfit(Outfit)
    case spaceOutfit(SpaceOutfit)
}

// MARK: - 翻转动画执行函数
private final class FlipAnimationDisplayLinkDriver: NSObject {
    private let totalDegrees: Double
    private let animationDuration: Double
    private let updateState: (Double, Double, Bool) -> Void
    private let showShareButton: () -> Void
    private let startTime = CACurrentMediaTime()
    private var displayLink: CADisplayLink?

    init(
        totalFlips: Int,
        animationDuration: Double,
        updateState: @escaping (Double, Double, Bool) -> Void,
        showShareButton: @escaping () -> Void
    ) {
        self.totalDegrees = Double(totalFlips * 180)
        self.animationDuration = animationDuration
        self.updateState = updateState
        self.showShareButton = showShareButton
        super.init()
    }

    func start() {
        let displayLink = CADisplayLink(target: self, selector: #selector(step(_:)))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        } else {
            displayLink.preferredFramesPerSecond = 60
        }
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc private func step(_ displayLink: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - startTime
        let progress = min(elapsed / animationDuration, 1.0)

        render(progress: progress)

        guard progress >= 1.0 else { return }

        displayLink.invalidate()
        self.displayLink = nil

        updateState(totalDegrees, 1.0, false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            withAnimation(.easeInOut(duration: 0.8)) {
                updateState(totalDegrees + 360, 1.0, true)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [self] in
                withAnimation(.easeInOut(duration: 0.3)) {
                    showShareButton()
                }
            }
        }
    }

    private func render(progress: Double) {
        // 使用 easeInOut 曲线：由慢到快到慢
        let easedProgress = progress < 0.5
            ? 2 * progress * progress
            : 1 - pow(-2 * progress + 2, 2) / 2

        let currentRotation = totalDegrees * easedProgress
        let currentFlip = Int(currentRotation / 180)
        let isFront = currentFlip % 2 == 0

        // 在翻转中间时降低透明度
        let flipProgress = (currentRotation.truncatingRemainder(dividingBy: 180)) / 180
        let distanceFromMiddle = abs(flipProgress - 0.5) * 2
        let currentOpacity = 0.3 + (0.7 * distanceFromMiddle)

        updateState(currentRotation, currentOpacity, isFront)
    }

    deinit {
        displayLink?.invalidate()
    }
}

func executeFlipAnimation(
    totalFlips: Int = 12,
    animationDuration: Double = 2.0,
    updateState: @escaping (Double, Double, Bool) -> Void,
    showShareButton: @escaping () -> Void
) {
    FlipAnimationDisplayLinkDriver(
        totalFlips: totalFlips,
        animationDuration: animationDuration,
        updateState: updateState,
        showShareButton: showShareButton
    )
    .start()
}

// MARK: - 裙装分享卡片容器视图（带快速翻转动画）
struct ClothingShareCardContainerView: View {
    let clothing: Clothing
    let onShare: (UIImage) -> Void
    let onDismiss: () -> Void
    
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var rotationY: Double = 0
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    @State private var showShareButton = false
    @State private var isShowingFront: Bool = true
    @State private var isSharing = false // 分享加载状态
    @State private var shareTask: Task<Void, Never>? // 用于取消任务
    
    // 动画配置：2秒内翻转12次（10-15次范围），由慢到快到慢
    private let totalFlips = 12
    private let animationDuration: Double = 2.0
    
    var body: some View {
        ZStack {
            // 使用 app 背景
            ShareCardBackground()
                .ignoresSafeArea()
            
            // 动画容器 - 固定在屏幕中央，不随分享按钮出现而改变位置
            ZStack {
                // 正面（裙装内容）
                ClothingShareCardFullView(
                    clothing: clothing,
                    image: clothing.imagePaths.first.flatMap { ImageManager.shared.loadImage(fileName: $0) },
                    cardBackground: ShareCardManager.shared.getCardFrontImage(),
                    fontProvider: CustomFontProvider()
                )
                .frame(width: 280, height: 440)
                .opacity(isShowingFront ? opacity : 0)
                
                // 背面（卡牌背面图片）
                if let backImage = ShareCardManager.shared.getCardBackImage() {
                    Image(uiImage: backImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 280, height: 440)
                        .cornerRadius(16)
                        .opacity(isShowingFront ? 0 : opacity)
                } else {
                    // 默认背面 - 莫妮卡色系
                    RoundedRectangle(cornerRadius: 16)
                        .fill(MonicaColors.cardGradient)
                        .frame(width: 280, height: 440)
                        .overlay(
                            VStack(spacing: 16) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 64))
                                    .foregroundColor(MonicaColors.warmWhite.opacity(0.8))
                                
                                Text("少女心愿")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(MonicaColors.warmWhite.opacity(0.9))
                            }
                        )
                        .opacity(isShowingFront ? 0 : opacity)
                }
            }
            .scaleEffect(scale)
            .rotation3DEffect(
                .degrees(rotationY),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            
            // 分享按钮 - 位于底部，不挤占动画容器
            if showShareButton {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        // 分享按钮 - 莫妮卡色系
                        Button {
                            // 异步生成分享图片，显示猫爪加载动画
                            performShare()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 20, weight: .semibold))
                                Text("分享")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: 280)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [MonicaColors.primaryPink, MonicaColors.lightPink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: MonicaColors.primaryPink.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isSharing) // 分享时禁用按钮
                        .opacity(isSharing ? 0.6 : 1.0)
                        
                        // 取消按钮
                        Button {
                            // 取消正在进行的分享任务
                            shareTask?.cancel()
                            onDismiss()
                        } label: {
                            Text("取消")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(MonicaColors.mediumText)
                        }
                        .disabled(isSharing)
                    }
                    .padding(.bottom, 50)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // 猫爪加载遮罩
            if isSharing {
                ShareLoadingOverlay(message: "正在准备分享...")
                    .transition(.opacity)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            // 清理资源
            shareTask?.cancel()
        }
    }
    
    // MARK: - 异步分享（带猫爪动画）
    private func performShare() {
        isSharing = true
        
        shareTask = Task {
            // 异步生成分享图片
            if let image = await ShareCardManager.shared.generateClothingShareImageAsync(clothing: clothing) {
                // 检查任务是否被取消
                guard !Task.isCancelled else { return }
                
                // 在主线程显示分享表
                await MainActor.run {
                    isSharing = false
                    presentShareSheet(with: image)
                }
            } else {
                await MainActor.run {
                    isSharing = false
                }
            }
        }
    }
    
    private func presentShareSheet(with image: UIImage) {
        // 创建分享项，包含图片和预览
        let shareItem = SharePreviewItem(image: image)
        let activityVC = UIActivityViewController(activityItems: [shareItem], applicationActivities: nil)
        
        // 设置预览图片
        activityVC.excludedActivityTypes = nil
        
        // 获取当前窗口场景来呈现分享表
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // 找到最顶部的视图控制器
            var topVC = rootVC
            while let presentedVC = topVC.presentedViewController {
                topVC = presentedVC
            }
            
            // iPad 需要设置弹出位置
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topVC.present(activityVC, animated: true)
        }
    }
    
    private func startAnimation() {
        // 第一阶段：淡入并放大
        withAnimation(.easeOut(duration: 0.2)) {
            opacity = 1.0
            scale = 1.0
        }
        
        // 第二阶段：翻转动画（2秒内12次），使用由慢到快到慢的曲线
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.performSmoothFlipAnimation()
        }
    }
    
    private func performSmoothFlipAnimation() {
        executeFlipAnimation(
            totalFlips: totalFlips,
            animationDuration: animationDuration,
            updateState: { rotation, opacity, isFront in
                self.rotationY = rotation
                self.opacity = opacity
                self.isShowingFront = isFront
            },
            showShareButton: {
                self.showShareButton = true
            }
        )
    }
}

// MARK: - 分享卡片背景（适配暗黑模式）
struct ShareCardBackground: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // 基础背景色
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            // 背景图片（如果有）
            if themeManager.effectiveBackgroundStyle == .image, let image = themeManager.backgroundImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .opacity(themeManager.backgroundOpacity)
                
                // 暗黑模式叠加层
                if colorScheme == .dark {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                }
            } else {
                // 默认装饰效果
                Circle()
                    .fill(Color.pink.opacity(colorScheme == .dark ? 0.2 : 0.3))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: -100, y: -200)
                
                Circle()
                    .fill(Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.2))
                    .frame(width: 250, height: 250)
                    .blur(radius: 60)
                    .offset(x: 100, y: 150)
            }
            
            // 模糊层
            if themeManager.isBlurEnabled {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
            
            // 暗黑模式额外暗化
            if colorScheme == .dark {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - 书页分享卡片容器视图（无翻转动画，直接展示）
struct BookPageShareCardContainerView: View {
    let shareType: ShareContentType
    let onShare: (UIImage) -> Void
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var rotationY: Double = 0
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    @State private var showShareButton = false
    @State private var isShowingFront: Bool = true
    @State private var isSharing = false // 分享加载状态
    @State private var shareTask: Task<Void, Never>? // 用于取消任务
    
    // 动画配置：2秒内翻转12次（10-15次范围），由慢到快到慢
    private let totalFlips = 12
    private let animationDuration: Double = 2.0
    
    var body: some View {
        ZStack {
            // 使用 app 背景
            ShareCardBackground()
                .ignoresSafeArea()
            
            // 动画容器 - 固定在屏幕中央
            ZStack {
                // 正面（书页内容）
                cardContentView
                    .frame(width: 280, height: 440)
                    .opacity(isShowingFront ? opacity : 0)
                
                // 背面（卡牌背面图片）
                if let backImage = ShareCardManager.shared.getCardBackImage() {
                    Image(uiImage: backImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 280, height: 440)
                        .cornerRadius(16)
                        .opacity(isShowingFront ? 0 : opacity)
                } else {
                    // 默认背面 - 莫妮卡色系
                    RoundedRectangle(cornerRadius: 16)
                        .fill(MonicaColors.cardGradient)
                        .frame(width: 280, height: 440)
                        .overlay(
                            VStack(spacing: 16) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 64))
                                    .foregroundColor(MonicaColors.warmWhite.opacity(0.8))
                                
                                Text("少女心愿")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(MonicaColors.warmWhite.opacity(0.9))
                            }
                        )
                        .opacity(isShowingFront ? 0 : opacity)
                }
            }
            .scaleEffect(scale)
            .rotation3DEffect(
                .degrees(rotationY),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            
            // 分享按钮 - 位于底部
            if showShareButton {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        // 分享按钮 - 莫妮卡色系
                        Button {
                            // 异步生成分享图片，显示猫爪加载动画
                            performShare()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 20, weight: .semibold))
                                Text("分享")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: 280)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [MonicaColors.primaryPink, MonicaColors.lightPink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: MonicaColors.primaryPink.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isSharing) // 分享时禁用按钮
                        .opacity(isSharing ? 0.6 : 1.0)
                        
                        // 取消按钮
                        Button {
                            // 取消正在进行的分享任务
                            shareTask?.cancel()
                            onDismiss()
                        } label: {
                            Text("取消")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(MonicaColors.mediumText)
                        }
                        .disabled(isSharing)
                    }
                    .padding(.bottom, 50)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // 猫爪加载遮罩
            if isSharing {
                ShareLoadingOverlay(message: "正在准备分享...")
                    .transition(.opacity)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            // 清理资源
            shareTask?.cancel()
        }
    }
    
    // MARK: - 异步分享（带猫爪动画）
    private func performShare() {
        isSharing = true
        
        shareTask = Task {
            // 异步生成分享图片
            if let image = await generateShareImageAsync() {
                // 检查任务是否被取消
                guard !Task.isCancelled else { return }
                
                // 在主线程显示分享表
                await MainActor.run {
                    isSharing = false
                    presentShareSheet(with: image)
                }
            } else {
                await MainActor.run {
                    isSharing = false
                }
            }
        }
    }
    
    private func generateShareImageAsync() async -> UIImage? {
        switch shareType {
        case .clothing:
            return nil
        case .outfit(let outfit):
            return await ShareCardManager.shared.generateOutfitShareImageAsync(outfit: outfit)
        case .spaceOutfit(let outfit):
            return await ShareCardManager.shared.generateSpaceOutfitShareImageAsync(outfit: outfit)
        }
    }
    
    private func presentShareSheet(with image: UIImage) {
        // 创建分享项，包含图片和预览
        let shareItem = SharePreviewItem(image: image)
        let activityVC = UIActivityViewController(activityItems: [shareItem], applicationActivities: nil)
        
        // 设置预览图片
        activityVC.excludedActivityTypes = nil
        
        // 获取当前窗口场景来呈现分享表
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // 找到最顶部的视图控制器
            var topVC = rootVC
            while let presentedVC = topVC.presentedViewController {
                topVC = presentedVC
            }
            
            // iPad 需要设置弹出位置
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topVC.present(activityVC, animated: true)
        }
    }
    
    @ViewBuilder
    private var cardContentView: some View {
        switch shareType {
        case .clothing:
            EmptyView() // 书页分享不会传clothing类型
        case .outfit(let outfit):
            OutfitShareCardView(
                outfit: outfit,
                cardBackground: ShareCardManager.shared.getCardFrontImage()
            )
            .environment(\.fontProvider, CustomFontProvider())
        case .spaceOutfit(let outfit):
            SpaceOutfitShareCardView(
                outfit: outfit,
                cardBackground: ShareCardManager.shared.getCardFrontImage()
            )
            .environment(\.fontProvider, CustomFontProvider())
        }
    }
    
    private func generateShareImage() -> UIImage? {
        switch shareType {
        case .clothing:
            return nil
        case .outfit(let outfit):
            return ShareCardManager.shared.generateOutfitShareImage(outfit: outfit)
        case .spaceOutfit(let outfit):
            return ShareCardManager.shared.generateSpaceOutfitShareImage(outfit: outfit)
        }
    }
    
    private func startAnimation() {
        // 第一阶段：淡入并放大
        withAnimation(.easeOut(duration: 0.2)) {
            opacity = 1.0
            scale = 1.0
        }
        
        // 第二阶段：翻转动画（2秒内12次），使用由慢到快到慢的曲线
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.performSmoothFlipAnimation()
        }
    }
    
    private func performSmoothFlipAnimation() {
        executeFlipAnimation(
            totalFlips: totalFlips,
            animationDuration: animationDuration,
            updateState: { rotation, opacity, isFront in
                self.rotationY = rotation
                self.opacity = opacity
                self.isShowingFront = isFront
            },
            showShareButton: {
                self.showShareButton = true
            }
        )
    }
}

// MARK: - 分享卡片 Sheet 包装器
struct ShareCardSheet: View {
    let shareType: ShareContentType
    let onDismiss: () -> Void
    
    @State private var showActivitySheet = false
    @State private var shareImage: UIImage?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 根据类型选择不同的容器视图
                switch shareType {
                case .clothing(let clothing):
                    ClothingShareCardContainerView(
                        clothing: clothing,
                        onShare: { image in
                            shareImage = image
                            showActivitySheet = true
                        },
                        onDismiss: onDismiss
                    )
                case .outfit(let outfit):
                    BookPageShareCardContainerView(
                        shareType: .outfit(outfit),
                        onShare: { image in
                            shareImage = image
                            showActivitySheet = true
                        },
                        onDismiss: onDismiss
                    )
                case .spaceOutfit(let outfit):
                    BookPageShareCardContainerView(
                        shareType: .spaceOutfit(outfit),
                        onShare: { image in
                            shareImage = image
                            showActivitySheet = true
                        },
                        onDismiss: onDismiss
                    )
                }
            }
            .navigationTitle("分享卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(MonicaColors.mediumText)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .sheet(isPresented: $showActivitySheet) {
                if let image = shareImage {
                    ShareSheet(items: [image])
                }
            }
        }
    }
}
