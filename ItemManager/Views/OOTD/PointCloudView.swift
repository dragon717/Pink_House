import SwiftUI
import SceneKit
import UIKit

struct PointCloudView: UIViewRepresentable {
    let splats: [GaussianSplat]
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor.black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.showsStatistics = true // Debug info
        
        // Improve camera control experience
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.inertiaEnabled = true
        scnView.defaultCameraController.automaticTarget = true
        
        // Setup Scene
        let scene = SCNScene()
        scnView.scene = scene
        
        // Add Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(cameraNode)
        
        context.coordinator.updateGeometry(in: scnView, with: splats)
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        if context.coordinator.splatCount != splats.count {
            context.coordinator.updateGeometry(in: uiView, with: splats)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: PointCloudView
        var splatCount: Int = 0
        var pointCloudNode: SCNNode?
        
        init(_ parent: PointCloudView) {
            self.parent = parent
        }
        
        func updateGeometry(in view: SCNView, with splats: [GaussianSplat]) {
            guard let scene = view.scene, !splats.isEmpty else { return }
            
            self.splatCount = splats.count
            
            // Remove old node
            pointCloudNode?.removeFromParentNode()
            
            // Optimization: Use UnsafeMutableRawBufferPointer for faster data writing
            let vertexStride = MemoryLayout<SCNVector3>.size
            let colorStride = MemoryLayout<SCNVector3>.size
            let vertexDataSize = splats.count * vertexStride
            let colorDataSize = splats.count * colorStride
            
            var vertexData = Data(count: vertexDataSize)
            var colorData = Data(count: colorDataSize)
            
            // Calculate bounding box for auto-scaling
            var minVec = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
            var maxVec = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
            
            vertexData.withUnsafeMutableBytes { (vertexPtr: UnsafeMutableRawBufferPointer) in
                colorData.withUnsafeMutableBytes { (colorPtr: UnsafeMutableRawBufferPointer) in
                    // Rebind to typed pointers for easier access
                    guard let vBase = vertexPtr.baseAddress?.bindMemory(to: SCNVector3.self, capacity: splats.count),
                          let cBase = colorPtr.baseAddress?.bindMemory(to: SCNVector3.self, capacity: splats.count) else {
                        return
                    }
                    
                    for (i, splat) in splats.enumerated() {
                        let pos = SCNVector3(splat.position.x, splat.position.y, splat.position.z)
                        vBase[i] = pos
                        cBase[i] = SCNVector3(splat.color.x, splat.color.y, splat.color.z)
                        
                        // Update bounds
                        if pos.x < minVec.x { minVec.x = pos.x }
                        if pos.y < minVec.y { minVec.y = pos.y }
                        if pos.z < minVec.z { minVec.z = pos.z }
                        if pos.x > maxVec.x { maxVec.x = pos.x }
                        if pos.y > maxVec.y { maxVec.y = pos.y }
                        if pos.z > maxVec.z { maxVec.z = pos.z }
                    }
                }
            }
            
            // Create Sources
            let vertexSource = SCNGeometrySource(
                data: vertexData,
                semantic: .vertex,
                vectorCount: splats.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: vertexStride
            )
            
            let colorSource = SCNGeometrySource(
                data: colorData,
                semantic: .color,
                vectorCount: splats.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: colorStride
            )
            
            // Create Element (Points)
            let element = SCNGeometryElement(
                data: nil,
                primitiveType: .point,
                primitiveCount: splats.count,
                bytesPerIndex: 0
            )
            element.pointSize = 10.0 // Increased from 5.0
            element.minimumPointScreenSpaceRadius = 3.0 // Increased from 2.0
            element.maximumPointScreenSpaceRadius = 20.0 // Increased from 10.0
            
            // Create Geometry
            let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
            
            // Material
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white // Base color, vertex colors will modulate
            material.lightingModel = .constant // Unlit
            material.isDoubleSided = true
            geometry.materials = [material]
            
            // Node
            let node = SCNNode(geometry: geometry)
            
            // Auto-Scaling & Centering
            let size = SCNVector3(maxVec.x - minVec.x, maxVec.y - minVec.y, maxVec.z - minVec.z)
            let maxDim = max(size.x, max(size.y, size.z))
            
            if maxDim > 0.0001 {
                // Normalize scale to fit in ~4 units (Camera is at z=5)
                let targetSize: Float = 4.0
                let scale = targetSize / maxDim
                node.scale = SCNVector3(scale, scale, scale)
                print("PointCloudView: Auto-scaled by factor \(scale) (Original size: \(maxDim))")
            } else {
                print("PointCloudView: Warning - Point cloud is degenerate (size ~ 0)")
            }
            
            // Center the node content
            let center = SCNVector3((minVec.x + maxVec.x) / 2, (minVec.y + maxVec.y) / 2, (minVec.z + maxVec.z) / 2)
            // Move the geometry so its center is at (0,0,0) locally
            // We use pivot to offset the geometry's origin
            node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
            
            scene.rootNode.addChildNode(node)
            self.pointCloudNode = node
            
            // Auto rotate
            node.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat(Float.pi * 2), z: 0, duration: 10)))
            
            print("PointCloudView: Created geometry with \(splats.count) points")
        }
    }
}
