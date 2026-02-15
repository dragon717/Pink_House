//
//  MetalGSViewerView.swift
//  ItemManager
//
//  Metal 3D Gaussian Splatting 查看器
//  用于替换 SpatialCanvas 中的 SceneKit 视图
//

import SwiftUI
import MetalKit
import simd
import UIKit

// 导入 SpatialSceneView 中的类型
// Note: SceneObject 定义在 SpatialSceneView.swift 中

// MARK: - Metal GS 查看器视图

public struct MetalGSViewerView: View {
    
    // MARK: - 属性
    
    /// PLY 文件 URL
    let plyURL: URL?
    
    /// 背景颜色
    let backgroundColor: Color
    
    /// 是否启用交互
    let enableInteraction: Bool
    
    /// 相机初始位置
    let initialCameraPosition: SIMD3<Float>
    
    /// 选中对象回调
    var onObjectTap: (() -> Void)?
    
    /// 渲染统计回调
    var onRenderStats: ((RenderStats) -> Void)?
    
    // MARK: - State
    
    @State private var cameraPosition: SIMD3<Float>
    @State private var cameraTarget: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    @State private var renderStats: RenderStats?
    @State private var isLoading = true
    @State private var loadError: Error?
    
    // MARK: - 初始化
    
    public init(
        plyURL: URL? = nil,
        backgroundColor: Color = Color(red: 0.15, green: 0.15, blue: 0.15),
        enableInteraction: Bool = true,
        initialCameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 5),
        onObjectTap: (() -> Void)? = nil,
        onRenderStats: ((RenderStats) -> Void)? = nil
    ) {
        self.plyURL = plyURL
        self.backgroundColor = backgroundColor
        self.enableInteraction = enableInteraction
        self.initialCameraPosition = initialCameraPosition
        self.onObjectTap = onObjectTap
        self.onRenderStats = onRenderStats
        
        _cameraPosition = State(initialValue: initialCameraPosition)
    }
    
    // MARK: - Body
    
    public var body: some View {
        ZStack {
            // Metal 渲染视图
            GaussianSplatView(
                cameraPosition: $cameraPosition,
                cameraTarget: $cameraTarget,
                enableInteraction: enableInteraction,
                plyURL: plyURL,
                configuration: RenderConfiguration(
                    backgroundColor: backgroundColorToSIMD(backgroundColor),
                    enableFrustumCulling: true,
                    enableDepthSorting: true,
                    gaussianScale: 1.0,
                    maxRenderCount: 1_000_000,
                    useSphericalHarmonics: true
                ),
                onRenderStatsUpdate: { stats in
                    renderStats = stats
                    onRenderStats?(stats)
                }
            )
            .onAppear {
                isLoading = false
            }
            
            // 加载指示器
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("加载 3D 模型中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundColor)
            }
            
            // 错误提示
            if let error = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    
                    Text("加载失败")
                        .font(.headline)
                    
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundColor)
            }
            
            // 渲染统计信息 (调试用)
            if let stats = renderStats {
                VStack {
                    HStack {
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("FPS: \(Int(stats.fps))")
                                .font(.system(size: 10, design: .monospaced))
                            Text("Points: \(stats.pointCount / 1000)K")
                                .font(.system(size: 10, design: .monospaced))
                            Text("Frame: \(String(format: "%.2f", stats.frameTime * 1000))ms")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(8)
                        .background(.black.opacity(0.3))
                        .cornerRadius(8)
                        .padding(8)
                    }
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func backgroundColorToSIMD(_ color: Color) -> SIMD4<Float> {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
    }
}

// MARK: - 集成到 SpatialCanvas 的包装器

public struct SpatialCanvasMetalView: View {
    
    // MARK: - 属性
    
    @Binding var selectedObject: SceneObject?
    var onObjectTap: (SceneObject) -> Void
    var gsModelPath: String?
    
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - State
    
    @State private var cameraPosition = SIMD3<Float>(0, 0, 5)
    @State private var cameraTarget = SIMD3<Float>(0, 0, 0)
    @State private var renderStats: RenderStats?
    
    // MARK: - Body
    
    public var body: some View {
        GeometryReader { geometry in
            if let modelPath = gsModelPath,
               FileManager.default.fileExists(atPath: modelPath) {
                // 显示高斯泼溅模型
                let url = URL(fileURLWithPath: modelPath)
                
                MetalGSViewerView(
                    plyURL: url,
                    backgroundColor: backgroundColor,
                    enableInteraction: true,
                    initialCameraPosition: SIMD3<Float>(0, 0, 5),
                    onObjectTap: {
                        // 创建 SceneObject 替代原来的 SpatialObject
                        let object = SceneObject(
                            type: .gsModel,
                            gsModelPath: modelPath
                        )
                        
                        // 通过通知中心发送选中事件
                        NotificationCenter.default.post(
                            name: .gsModelSelected,
                            object: object
                        )
                    },
                    onRenderStats: { stats in
                        renderStats = stats
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                // 显示空场景提示
                emptyStateView
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
    
    // MARK: - 子视图
    
    private var emptyStateView: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 64))
                    .foregroundStyle(.purple.opacity(0.6))
                
                Text("3D 空间画布")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("添加图片开始 3D 高斯泼溅建模")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.15)
            : Color(red: 0.96, green: 0.95, blue: 0.93)
    }
}

// MARK: - GSModelObject (Metal 渲染专用)

/// 用于 Metal 3DGS 渲染的模型对象
public struct GSModelObject: Identifiable {
    public let id: UUID
    public let plyPath: String
    public var position: SIMD3<Float>
    public var rotation: SIMD3<Float>
    public var scale: SIMD3<Float>
    
    public init(
        id: UUID = UUID(),
        plyPath: String,
        position: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        rotation: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) {
        self.id = id
        self.plyPath = plyPath
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

// MARK: - 通知扩展

public extension Notification.Name {
    static let gsModelSelected = Notification.Name("gsModelSelected")
}

// MARK: - 预览

struct MetalGSViewerView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 空状态预览
            MetalGSViewerView(
                plyURL: nil,
                backgroundColor: .black,
                enableInteraction: true
            )
            .previewDisplayName("Empty State")
            
            // 加载状态预览
            MetalGSViewerView(
                plyURL: nil,
                backgroundColor: Color(red: 0.96, green: 0.95, blue: 0.93),
                enableInteraction: true
            )
            .previewDisplayName("Light Background")
        }
    }
}
