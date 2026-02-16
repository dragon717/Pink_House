import Foundation
import RealityKit
import Metal
import UIKit

/// RealityKit 辅助工具类
/// 用于预加载和初始化 RealityKit 渲染资源，避免运行时材质加载错误
enum RealityKitHelper {

    /// 检查 Metal 设备是否可用
    static var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    /// 预热 RealityKit 渲染引擎
    /// 这可以减少 Object Capture 时的材质加载错误
    static func warmUp() {
        guard isMetalAvailable else {
            print("[RealityKitHelper] Metal 不可用")
            return
        }

        // 创建一个临时场景来触发 RealityKit 初始化
        // 这会预加载引擎内部材质资源，如 engine:throttleGhosted.rematerial
        let entity = Entity()

        // 生成简单几何体来触发渲染管线初始化
        let mesh = MeshResource.generatePlane(width: 0.1, depth: 0.1)
        let material = SimpleMaterial(color: .white, isMetallic: false)
        entity.components.set(ModelComponent(mesh: mesh, materials: [material]))

        print("[RealityKitHelper] RealityKit 预热完成")
    }
}
