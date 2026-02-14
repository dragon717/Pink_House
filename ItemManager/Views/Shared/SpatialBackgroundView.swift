//
//  SpatialBackgroundView.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/14/26.
//

import SwiftUI
import RealityKit
import CoreMotion

// MARK: - Generic Spatial Background View
/// 一个通用的 3D 空间背景视图，支持 iOS 26+ Spatial3DImage 特性。
/// 在旧版本或模拟器环境下，会自动降级为 "Image + CoreMotion" 的高保真视差模拟。
@available(iOS 26.0, *)
struct SpatialBackgroundView<Content: View>: View {
    let imageName: String
    let imageExtension: String
    @ViewBuilder let hotspots: Content
    
    // 监听全局资源管理器
    @ObservedObject private var assetManager = SpatialAssetManager.shared
    
    // 本地资源状态
    @State private var spatialImage: ImagePresentationComponent.Spatial3DImage?
    @State private var isLoading = false
    
    // 模拟陀螺仪视差效果（Mock 环境增强版）
    // 即使在 Mock 模式下，我们也希望看到背景的动态反馈
    @State private var motionManager = CMMotionManager()
    @State private var parallaxOffset: CGSize = .zero
    
    // 缓存背景图，避免 GeometryReader 重绘时反复 IO
    @State private var cachedBackgroundImage: UIImage?
    @State private var maxOffset: CGSize = .zero
    
    // 缩放因子：1.04 表示放大 4% 以用于视差
    // 之前是 1.15 (15%)，裁剪太多导致看不全，现在减小到 4%
    // 进一步优化：为了减少“看不全”的感觉，Loading 阶段也应用此缩放，保持前后一致
    private let scaleFactor: CGFloat = 1.025
    
    init(imageName: String, imageExtension: String = "png", @ViewBuilder hotspots: () -> Content) {
        self.imageName = imageName
        self.imageExtension = imageExtension
        self.hotspots = hotspots()
    }
    
    var body: some View {
        ZStack {
            if let _ = spatialImage {
                // 如果是真实环境，RealityView 会自动处理
                // 这里我们在 Mock 环境下增加手动视差模拟
                
                // 暂时禁用 RealityView 以避免 Mock 环境下的渲染错误日志
                // 在未来真实 iOS 26 环境下，可以恢复此代码块
                /*
                RealityView { content in
                    let entity = Entity()
                    // Create Spatial3DImage entity
                    // content.add(entity)
                }
                .overlay(hotspots) // RealityView overlay
                */
                
                // Mock 回退渲染：使用 CoreMotion 模拟视差
                mockSpatialRenderContent
            } else {
                // Loading State
                ZStack {
                    // 使用缓存的背景图作为 Loading 底图，避免全黑闪烁
                    // 并且应用相同的 scaleFactor，防止切换时跳变
                    if let image = cachedBackgroundImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 5) // Loading 状态稍微模糊一点
                            .overlay(Color.black.opacity(0.4))
                            .ignoresSafeArea()
                    } else {
                        Color.black.opacity(0.8)
                    }
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("正在构建 3D 空间...")
                            .foregroundStyle(.white)
                            .font(.headline)
                        Text("AI 生成深度信息中")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 关键优化：让 Loading 状态也应用缩放，但这里没法获取 GeometryReader 的尺寸
                // 所以我们只能在父级处理，或者在这里简单处理
                // 由于 ZStack 会占满全屏，aspectRatio(.fill) 会自动处理
                .transition(.opacity)
                .onAppear {
                    // 尝试加载一次本地图片用于占位
                    loadLocalImage()
                }
            }
        }
        .task {
            await loadResource()
            startMotionUpdates()
        }
        .onDisappear {
            stopMotionUpdates()
        }
        .onChange(of: imageName) { _ in
            Task {
                await loadResource()
            }
        }
    }
    
    private func loadResource() async {
        guard spatialImage?.url.lastPathComponent.contains(imageName) != true else { return }
        
        isLoading = true
        // 1. 先触发 SpatialAssetManager 的预加载（虽然我们直接 load 也可以，但为了保持 assetManager 的状态一致性）
        // 或者直接使用 loadSpatialImage
        let image = await assetManager.loadSpatialImage(name: imageName, extension: imageExtension)
        
        await MainActor.run {
            self.spatialImage = image
            self.isLoading = false
            // 清除旧的 UIImage 缓存以便重新加载
            self.cachedBackgroundImage = nil
        }
    }
    
    // MARK: - Mock Rendering Logic
    
    private var mockSpatialRenderContent: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Background Image with Parallax
                if let image = cachedBackgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width * scaleFactor, height: geo.size.height * scaleFactor)
                        .offset(x: parallaxOffset.width, y: parallaxOffset.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .blur(radius: 0.5) // Slight blur for depth feel
                        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: parallaxOffset)
                        .onAppear {
                            // 计算最大偏移量，防止黑边
                            let maxWidth = geo.size.width * (scaleFactor - 1.0) / 2.0
                            let maxHeight = geo.size.height * (scaleFactor - 1.0) / 2.0
                            self.maxOffset = CGSize(width: maxWidth, height: maxHeight)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            let maxWidth = newSize.width * (scaleFactor - 1.0) / 2.0
                            let maxHeight = newSize.height * (scaleFactor - 1.0) / 2.0
                            self.maxOffset = CGSize(width: maxWidth, height: maxHeight)
                        }
                } else {
                    Color.clear
                        .onAppear {
                            // Load image only once
                            loadLocalImage()
                        }
                }
                
                // 2. Hotspots Layer (Moves with Parallax but slightly less to create depth)
                // 这里的 content 是传入的 hotspots
                // 为了模拟 3D 空间中物体的位置，热区也应该有一定的视差移动，但通常跟随背景
                // 或者我们可以假设热区是贴在背景上的，所以它们应该跟随背景移动
                ZStack {
                    hotspots
                }
                .frame(width: geo.size.width * scaleFactor, height: geo.size.height * scaleFactor)
                // 关键：热区跟随背景移动，模拟它们在 3D 空间中的位置
                // 这里简单地应用相同的 offset，假设热区是在“墙上”的
                .offset(x: parallaxOffset.width, y: parallaxOffset.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: parallaxOffset)
            }
            // Clip content to bounds
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
    
    // MARK: - Helpers
    
    private func loadLocalImage() {
        Task.detached(priority: .userInitiated) {
            // 模拟异步读取
            let image = UIImage(named: imageName)
            await MainActor.run {
                self.cachedBackgroundImage = image
            }
        }
    }
    
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { data, error in
            guard let data = data else { return }
            
            // 获取倾斜角度 (Roll & Pitch)
            let roll = CGFloat(data.attitude.roll)
            let pitch = CGFloat(data.attitude.pitch)
            
            // 计算位移：最大移动范围 30pt (稍微收敛一点，避免过度移动)
            // 降低灵敏度以适应较小的移动范围
            let sensitivity: CGFloat = 15.0
            let xOffset = roll * sensitivity
            let yOffset = pitch * sensitivity
            
            // Clamp values
            let maxOffsetX = max(5.0, self.maxOffset.width)
            let maxOffsetY = max(5.0, self.maxOffset.height)
            
            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                self.parallaxOffset = CGSize(
                    width: max(-maxOffsetX, min(maxOffsetX, -xOffset)),
                    height: max(-maxOffsetY, min(maxOffsetY, yOffset))
                )
            }
        }
    }
    
    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}
