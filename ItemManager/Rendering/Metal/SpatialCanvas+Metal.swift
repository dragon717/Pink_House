//
//  SpatialCanvas+Metal.swift
//  ItemManager
//
//  SpatialCanvas 与 Metal 3DGS 渲染器的集成示例
//

import SwiftUI
import simd
import SceneKit
import MetalKit

// MARK: - 使用示例

/*
 在 SpatialCanvasEditorView 中使用 Metal 渲染器的示例代码：
 
 1. 替换原有的 SceneKit 视图：
 
 ```swift
 struct SpatialCanvasEditorView: View {
     // ... 原有代码 ...
     
     var body: some View {
         ZStack {
             // 使用 Metal 渲染器替代 SceneKit
             if let gsModelPath = gsModelPath {
                 SpatialCanvasMetalView(
                     selectedObject: $selectedObject,
                     onObjectTap: handleObjectTap,
                     gsModelPath: gsModelPath
                 )
             } else {
                 // 原有 SceneKit 视图用于普通对象
                 SpatialSceneView(...)
             }
             
             // ... 其他 UI 组件 ...
         }
     }
 }
 ```
 
 2. 处理 GS 模型选中事件：
 
 ```swift
 .onReceive(NotificationCenter.default.publisher(for: .gsModelSelected)) { notification in
     if let gsObject = notification.object as? GSModelObject {
         // 创建兼容的 SpatialObject
         let node = SCNNode() // 虚拟节点，实际渲染在 Metal 中
         let object = SpatialObject(
             id: gsObject.id,
             type: .gsModel,
             node: node,
             position: SCNVector3(gsObject.position),
             rotation: SCNVector3(gsObject.rotation),
             scale: SCNVector3(gsObject.scale)
         )
         selectedObject = object
     }
 }
 ```
 */

// MARK: - 便捷扩展

/*
 在 SpatialCanvasEditorView 中添加以下方法来使用 Metal 渲染器：
 
 /// 使用 Metal 渲染器加载生成的 GS 模型
 func loadGSModelWithMetal(path: String) {
     // 更新模型路径，触发 Metal 视图显示
     gsModelPath = path
     
     // 创建对应的 SpatialObject 用于 UI 状态管理
     let node = SCNNode()
     let object = SpatialObject(
         id: UUID(),
         type: .gsModel,
         node: node,
         position: SCNVector3(0, 0, 0),
         rotation: SCNVector3(0, 0, 0),
         scale: SCNVector3(1, 1, 1)
     )
     spatialObjects.append(object)
 }
 */

// MARK: - 渲染配置预设

public extension RenderConfiguration {
    
    /// 高质量渲染配置
    static var highQuality: RenderConfiguration {
        RenderConfiguration(
            backgroundColor: SIMD4<Float>(0.15, 0.15, 0.15, 1.0),
            enableFrustumCulling: true,
            enableDepthSorting: true,
            gaussianScale: 1.0,
            maxRenderCount: 2_000_000,
            useSphericalHarmonics: true
        )
    }
    
    /// 性能优先配置
    static var performance: RenderConfiguration {
        RenderConfiguration(
            backgroundColor: SIMD4<Float>(0.15, 0.15, 0.15, 1.0),
            enableFrustumCulling: true,
            enableDepthSorting: true,
            gaussianScale: 1.0,
            maxRenderCount: 500_000,
            useSphericalHarmonics: false
        )
    }
    
    /// 省电模式配置
    static var powerSaving: RenderConfiguration {
        RenderConfiguration(
            backgroundColor: SIMD4<Float>(0.15, 0.15, 0.15, 1.0),
            enableFrustumCulling: true,
            enableDepthSorting: false, // 关闭排序以节省电量
            gaussianScale: 1.0,
            maxRenderCount: 200_000,
            useSphericalHarmonics: false
        )
    }
}

// MARK: - 相机控制扩展

public extension GaussianSplatView {
    
    /// 创建环绕相机视角
    static func orbitCamera(
        radius: Float = 5.0,
        height: Float = 1.0,
        angle: Float = 0
    ) -> (position: SIMD3<Float>, target: SIMD3<Float>) {
        let x = radius * sin(angle)
        let z = radius * cos(angle)
        let position = SIMD3<Float>(x, height, z)
        let target = SIMD3<Float>(0, 0, 0)
        return (position, target)
    }
    
    /// 创建俯视相机
    static func topDownCamera(
        height: Float = 5.0
    ) -> (position: SIMD3<Float>, target: SIMD3<Float>) {
        let position = SIMD3<Float>(0, height, 0)
        let target = SIMD3<Float>(0, 0, 0)
        return (position, target)
    }
    
    /// 创建正面相机
    static func frontCamera(
        distance: Float = 5.0
    ) -> (position: SIMD3<Float>, target: SIMD3<Float>) {
        let position = SIMD3<Float>(0, 0, distance)
        let target = SIMD3<Float>(0, 0, 0)
        return (position, target)
    }
}

// MARK: - 调试工具

public struct GaussianSplatDebugger {
    
    /// 打印渲染统计信息
    public static func printStats(_ stats: RenderStats) {
        print("""
        === 3DGS Render Stats ===
        FPS: \(Int(stats.fps))
        Frame Time: \(String(format: "%.2f", stats.frameTime * 1000)) ms
        Total Points: \(stats.pointCount)
        Rendered Points: \(stats.renderedPoints)
        ========================
        """)
    }
    
    /// 检查设备 Metal 支持
    public static func checkMetalSupport() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[GaussianSplatDebugger] Metal is not supported on this device")
            return false
        }
        
        print("[GaussianSplatDebugger] Metal Device: \(device.name)")
        print("[GaussianSplatDebugger] Max Buffer Length: \(device.maxBufferLength / 1024 / 1024) MB")
        print("[GaussianSplatDebugger] Has Unified Memory: \(device.hasUnifiedMemory)")
        
        return true
    }
}
