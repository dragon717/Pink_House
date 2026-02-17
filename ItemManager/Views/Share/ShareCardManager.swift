//
//  ShareCardManager.swift
//  ItemManager
//
//  分享卡片管理器 - 负责生成分享图片和管理卡牌资源
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
        // 返回缩略图用于预览
        return image.preparingThumbnail(of: size)
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "分享图片"
    }
}

// MARK: - 分享卡片管理器
class ShareCardManager {
    static let shared = ShareCardManager()
    
    // 卡牌资源图片
    private var cardFrontImage: UIImage?
    private var cardBackImage: UIImage?
    
    private init() {
        loadCardImages()
    }
    
    // MARK: - 加载卡牌图片
    private func loadCardImages() {
        // 尝试从Assets加载卡牌图片
        cardFrontImage = UIImage(named: "card_front")
        cardBackImage = UIImage(named: "card_back")
        
        // 如果没有在Assets中找到，尝试从temp目录加载
        if cardFrontImage == nil {
            let frontPath = "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/temp/processed/正面.png"
            if FileManager.default.fileExists(atPath: frontPath) {
                cardFrontImage = UIImage(contentsOfFile: frontPath)
            }
        }
        
        if cardBackImage == nil {
            let backPath = "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/temp/processed/背面.png"
            if FileManager.default.fileExists(atPath: backPath) {
                cardBackImage = UIImage(contentsOfFile: backPath)
            }
        }
    }
    
    // MARK: - 获取卡牌图片
    func getCardFrontImage() -> UIImage? {
        return cardFrontImage
    }
    
    func getCardBackImage() -> UIImage? {
        return cardBackImage
    }
    
    // MARK: - 生成裙子分享图片
    func generateClothingShareImage(clothing: Clothing) -> UIImage? {
        // 加载裙子主图
        var clothingImage: UIImage?
        if let firstPath = clothing.imagePaths.first {
            clothingImage = ImageManager.shared.loadImage(fileName: firstPath)
        }
        
        // 创建分享卡片视图
        let cardView = ClothingShareCardFullView(
            clothing: clothing,
            image: clothingImage,
            cardBackground: cardFrontImage,
            fontProvider: CustomFontProvider()
        )
        
        // 渲染为图片
        return renderViewToImage(cardView, size: CGSize(width: 320, height: 520))
    }
    
    // MARK: - 生成书页分享图片（平面书页）
    func generateOutfitShareImage(outfit: Outfit) -> UIImage? {
        let cardView = OutfitShareCardView(
            outfit: outfit,
            cardBackground: cardFrontImage
        )
        .environment(\.fontProvider, CustomFontProvider())
        
        return renderViewToImage(cardView, size: CGSize(width: 320, height: 520))
    }
    
    // MARK: - 生成书页分享图片（空间书页）
    func generateSpaceOutfitShareImage(outfit: SpaceOutfit) -> UIImage? {
        let cardView = SpaceOutfitShareCardView(
            outfit: outfit,
            cardBackground: cardFrontImage
        )
        .environment(\.fontProvider, CustomFontProvider())
        
        return renderViewToImage(cardView, size: CGSize(width: 320, height: 520))
    }
    
    // MARK: - 渲染视图为图片
    private func renderViewToImage<V: View>(_ view: V, size: CGSize) -> UIImage? {
        let controller = UIHostingController(rootView: view)
        let view = controller.view
        
        let targetSize = size
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - 分享类型枚举
enum ShareContentType {
    case clothing(Clothing)
    case outfit(Outfit)
    case spaceOutfit(SpaceOutfit)
}

// MARK: - 裙子分享卡片容器视图（带快速翻转动画）
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
                // 正面（裙子内容）
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
                                
                                Text("Pink House")
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
                            // 直接调用原生分享，带图片预览
                            if let image = ShareCardManager.shared.generateClothingShareImage(clothing: clothing) {
                                presentShareSheet(with: image)
                            }
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
                        
                        // 取消按钮
                        Button {
                            onDismiss()
                        } label: {
                            Text("取消")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(MonicaColors.mediumText)
                        }
                    }
                    .padding(.bottom, 50)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            startAnimation()
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
        let totalDegrees = Double(totalFlips * 180)
        let startTime = Date()
        let frameInterval: TimeInterval = 1.0 / 60.0 // 60fps
        var displayLink: Timer?
        
        displayLink = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / self.animationDuration, 1.0)
            
            // 使用 easeInOut 曲线：由慢到快到慢
            let easeInOutProgress = progress < 0.5 
                ? 2 * progress * progress 
                : 1 - pow(-2 * progress + 2, 2) / 2
            
            let currentRotation = totalDegrees * easeInOutProgress
            let currentFlip = Int(currentRotation / 180)
            let isFront = currentFlip % 2 == 0
            
            // 更新状态
            self.rotationY = currentRotation
            self.isShowingFront = isFront
            
            // 在翻转中间时降低透明度
            let flipProgress = (currentRotation.truncatingRemainder(dividingBy: 180)) / 180
            let distanceFromMiddle = abs(flipProgress - 0.5) * 2
            self.opacity = 0.3 + (0.7 * distanceFromMiddle)
            
            if progress >= 1.0 {
                timer.invalidate()
                
                // 在背面停留0.5秒
                self.isShowingFront = false
                self.rotationY = totalDegrees
                self.opacity = 1.0
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // 翻转到正面
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.rotationY = totalDegrees + 360
                        self.isShowingFront = true
                    }
                    
                    // 动画完成，显示分享按钮
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.showShareButton = true
                        }
                    }
                }
            }
        }
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
            if themeManager.backgroundStyle == .image, let image = themeManager.backgroundImage {
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
                                
                                Text("Pink House")
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
                            // 直接调用原生分享，带图片预览
                            if let image = generateShareImage() {
                                presentShareSheet(with: image)
                            }
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
                        
                        // 取消按钮
                        Button {
                            onDismiss()
                        } label: {
                            Text("取消")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(MonicaColors.mediumText)
                        }
                    }
                    .padding(.bottom, 50)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            startAnimation()
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
        let totalDegrees = Double(totalFlips * 180)
        let startTime = Date()
        let frameInterval: TimeInterval = 1.0 / 60.0 // 60fps
        var displayLink: Timer?
        
        displayLink = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / self.animationDuration, 1.0)
            
            // 使用 easeInOut 曲线：由慢到快到慢
            let easeInOutProgress = progress < 0.5 
                ? 2 * progress * progress 
                : 1 - pow(-2 * progress + 2, 2) / 2
            
            let currentRotation = totalDegrees * easeInOutProgress
            let currentFlip = Int(currentRotation / 180)
            let isFront = currentFlip % 2 == 0
            
            // 更新状态
            self.rotationY = currentRotation
            self.isShowingFront = isFront
            
            // 在翻转中间时降低透明度
            let flipProgress = (currentRotation.truncatingRemainder(dividingBy: 180)) / 180
            let distanceFromMiddle = abs(flipProgress - 0.5) * 2
            self.opacity = 0.3 + (0.7 * distanceFromMiddle)
            
            if progress >= 1.0 {
                timer.invalidate()
                
                // 在背面停留0.5秒
                self.isShowingFront = false
                self.rotationY = totalDegrees
                self.opacity = 1.0
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // 翻转到正面
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.rotationY = totalDegrees + 360
                        self.isShowingFront = true
                    }
                    
                    // 动画完成，显示分享按钮
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.showShareButton = true
                        }
                    }
                }
            }
        }
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
