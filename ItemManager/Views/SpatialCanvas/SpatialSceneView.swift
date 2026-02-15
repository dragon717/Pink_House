//
//  SpatialSceneView.swift
//  ItemManager
//
//  3D场景视图 - SceneKit包装
//

import SwiftUI
import SceneKit
import Combine

struct SpatialSceneView: UIViewRepresentable {
    let scene: SCNScene
    let cameraNode: SCNNode
    @Binding var selectedObject: SpatialObject?
    var onObjectTap: (SpatialObject) -> Void
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: UIScreen.main.bounds)
        scnView.scene = scene
        scnView.pointOfView = cameraNode
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1.0)
        scnView.antialiasingMode = .multisampling4X
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // 强制立即渲染
        scnView.isPlaying = true
        scnView.loops = true

        // 设置渲染回调
        scnView.delegate = context.coordinator

        // 添加点击手势
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
        
        // 添加平移手势用于对象移动
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scnView.addGestureRecognizer(panGesture)
        
        // 添加缩放手势
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        scnView.addGestureRecognizer(pinchGesture)
        
        // 添加旋转手势
        let rotationGesture = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotation(_:)))
        scnView.addGestureRecognizer(rotationGesture)
        
        context.coordinator.scnView = scnView
        context.coordinator.scene = scene
        context.coordinator.onObjectTap = onObjectTap
        context.coordinator.selectedObject = $selectedObject
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // 确保视图填满父容器
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        
        // 更新选中状态的高亮
        context.coordinator.updateSelectionHighlight()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, SCNSceneRendererDelegate {
        weak var scnView: SCNView?
        weak var scene: SCNScene?
        var onObjectTap: ((SpatialObject) -> Void)?
        var selectedObject: Binding<SpatialObject?>?

        // 手势状态
        private var initialObjectPosition: SCNVector3?
        private var initialObjectScale: SCNVector3?
        private var initialObjectRotation: SCNVector3?
        private var lastPanLocation: CGPoint?

        // 选中高亮节点
        private var selectionBox: SCNNode?
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView else { return }
            
            let location = gesture.location(in: scnView)
            let hitResults = scnView.hitTest(location, options: [.boundingBoxOnly: false])
            
            if let hit = hitResults.first {
                // 查找对应的SpatialObject
                var node: SCNNode? = hit.node
                while node != nil {
                    if let object = findSpatialObject(for: node!) {
                        selectedObject?.wrappedValue = object
                        onObjectTap?(object)
                        updateSelectionHighlight()
                        return
                    }
                    node = node?.parent
                }
            }
            
            // 点击空白处取消选择
            selectedObject?.wrappedValue = nil
            updateSelectionHighlight()
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = scnView,
                  let selectedNode = selectedObject?.wrappedValue?.node else { return }
            
            let location = gesture.location(in: scnView)
            
            switch gesture.state {
            case .began:
                initialObjectPosition = selectedNode.position
                lastPanLocation = location
                
            case .changed:
                guard let initialPosition = initialObjectPosition,
                      let lastLocation = lastPanLocation else { return }
                
                // 计算移动差值
                let deltaX = Float(location.x - lastLocation.x) * 0.01
                let deltaY = Float(location.y - lastLocation.y) * -0.01
                
                // 更新位置
                selectedNode.position = SCNVector3(
                    initialPosition.x + deltaX,
                    initialPosition.y + deltaY,
                    initialPosition.z
                )
                
                lastPanLocation = location
                updateSelectionHighlight()
                
            case .ended, .cancelled:
                initialObjectPosition = nil
                lastPanLocation = nil
                
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let selectedNode = selectedObject?.wrappedValue?.node else { return }
            
            switch gesture.state {
            case .began:
                initialObjectScale = selectedNode.scale
                
            case .changed:
                guard let initialScale = initialObjectScale else { return }
                let scale = Float(gesture.scale)
                selectedNode.scale = SCNVector3(
                    initialScale.x * scale,
                    initialScale.y * scale,
                    initialScale.z * scale
                )
                updateSelectionHighlight()
                
            case .ended, .cancelled:
                initialObjectScale = nil
                
            default:
                break
            }
        }
        
        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let selectedNode = selectedObject?.wrappedValue?.node else { return }
            
            switch gesture.state {
            case .began:
                initialObjectRotation = selectedNode.eulerAngles
                
            case .changed:
                guard let initialRotation = initialObjectRotation else { return }
                let rotation = Float(gesture.rotation)
                selectedNode.eulerAngles = SCNVector3(
                    initialRotation.x,
                    initialRotation.y + rotation,
                    initialRotation.z
                )
                updateSelectionHighlight()
                
            case .ended, .cancelled:
                initialObjectRotation = nil
                
            default:
                break
            }
        }
        
        func updateSelectionHighlight() {
            // 移除旧的高亮框
            selectionBox?.removeFromParentNode()
            selectionBox = nil
            
            guard let selectedNode = selectedObject?.wrappedValue?.node,
                  let scene = scene else { return }
            
            // 计算节点的包围盒
            let (min, max) = selectedNode.boundingBox
            let width = max.x - min.x
            let height = max.y - min.y
            let depth = max.z - min.z
            let center = SCNVector3((min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2)
            
            // 创建线框盒子
            let box = SCNBox(width: CGFloat(width * selectedNode.scale.x) + 0.05,
                            height: CGFloat(height * selectedNode.scale.y) + 0.05,
                            length: CGFloat(depth * selectedNode.scale.z) + 0.05,
                            chamferRadius: 0)
            
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.clear
            material.emission.contents = UIColor.systemPink
            material.isDoubleSided = true
            box.materials = [material]
            
            selectionBox = SCNNode(geometry: box)
            
            // 添加线框效果
            let lineWidth: CGFloat = 0.002
            let lineColor = UIColor.systemPink
            
            // 创建边框线
            let edges = createWireframeEdges(width: CGFloat(width * selectedNode.scale.x),
                                            height: CGFloat(height * selectedNode.scale.y),
                                            depth: CGFloat(depth * selectedNode.scale.z),
                                            lineWidth: lineWidth,
                                            color: lineColor)
            
            selectionBox?.addChildNode(edges)
            
            // 设置位置
            let worldPosition = selectedNode.convertPosition(center, to: scene.rootNode)
            selectionBox?.position = worldPosition
            selectionBox?.eulerAngles = selectedNode.eulerAngles
            
            scene.rootNode.addChildNode(selectionBox!)
        }
        
        private func createWireframeEdges(width: CGFloat, height: CGFloat, depth: CGFloat, lineWidth: CGFloat, color: UIColor) -> SCNNode {
            let edgesNode = SCNNode()
            
            let halfW = width / 2
            let halfH = height / 2
            let halfD = depth / 2
            
            // 8个顶点
            let vertices = [
                SCNVector3(-halfW, -halfH, -halfD), SCNVector3(halfW, -halfH, -halfD),
                SCNVector3(halfW, halfH, -halfD), SCNVector3(-halfW, halfH, -halfD),
                SCNVector3(-halfW, -halfH, halfD), SCNVector3(halfW, -halfH, halfD),
                SCNVector3(halfW, halfH, halfD), SCNVector3(-halfW, halfH, halfD)
            ]
            
            // 12条边
            let edges = [
                (0,1), (1,2), (2,3), (3,0), // 前面
                (4,5), (5,6), (6,7), (7,4), // 后面
                (0,4), (1,5), (2,6), (3,7)  // 连接前后
            ]
            
            for (start, end) in edges {
                let startVec = vertices[start]
                let endVec = vertices[end]
                
                let distance = sqrt(pow(endVec.x - startVec.x, 2) +
                                   pow(endVec.y - startVec.y, 2) +
                                   pow(endVec.z - startVec.z, 2))
                
                let cylinder = SCNCylinder(radius: lineWidth, height: CGFloat(distance))
                cylinder.firstMaterial?.diffuse.contents = color
                cylinder.firstMaterial?.emission.contents = color
                
                let lineNode = SCNNode(geometry: cylinder)
                lineNode.position = SCNVector3((startVec.x + endVec.x) / 2,
                                              (startVec.y + endVec.y) / 2,
                                              (startVec.z + endVec.z) / 2)
                
                // 计算旋转
                let direction = SCNVector3(endVec.x - startVec.x,
                                          endVec.y - startVec.y,
                                          endVec.z - startVec.z)
                lineNode.look(at: endVec)
                
                edgesNode.addChildNode(lineNode)
            }
            
            return edgesNode
        }
        
        private func findSpatialObject(for node: SCNNode) -> SpatialObject? {
            // 这里需要通过某种方式关联SCNNode和SpatialObject
            // 可以通过遍历所有对象来查找
            return nil
        }
    }
}

// MARK: - 变换辅助器覆盖层

struct TransformGizmoOverlay: View {
    let mode: TransformMode
    @Binding var rotationX: Double
    @Binding var rotationY: Double
    @Binding var rotationZ: Double
    @Binding var scale: Double
    var onTransformChange: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 中心3D变换指示器
                TransformIndicator3D(
                    mode: mode,
                    rotationX: $rotationX,
                    rotationY: $rotationY,
                    rotationZ: $rotationZ,
                    scale: $scale,
                    onChange: onTransformChange
                )
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }
}

// MARK: - 3D变换指示器

struct TransformIndicator3D: View {
    let mode: TransformMode
    @Binding var rotationX: Double
    @Binding var rotationY: Double
    @Binding var rotationZ: Double
    @Binding var scale: Double
    var onChange: () -> Void
    
    var body: some View {
        ZStack {
            // X轴 (红色)
            AxisArrow(color: .red, angle: rotationY, axis: .horizontal)
                .offset(x: 60, y: 0)
            
            // Y轴 (绿色)
            AxisArrow(color: .green, angle: rotationX, axis: .vertical)
                .offset(x: 0, y: -60)
            
            // Z轴 (蓝色) - 用圆形表示
            ZAxisIndicator(angle: rotationZ)
                .offset(x: -60, y: 0)
            
            // 中心控制点
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .shadow(radius: 4)
        }
    }
}

// MARK: - 轴向箭头

struct AxisArrow: View {
    let color: Color
    let angle: Double
    let axis: Axis
    
    enum Axis {
        case horizontal, vertical
    }
    
    var body: some View {
        ZStack {
            // 箭头线
            Rectangle()
                .fill(color)
                .frame(width: axis == .horizontal ? 50 : 6, height: axis == .horizontal ? 6 : 50)
            
            // 箭头头
            Image(systemName: axis == .horizontal ? "arrowtriangle.right.fill" : "arrowtriangle.up.fill")
                .foregroundStyle(color)
                .font(.system(size: 16))
                .offset(x: axis == .horizontal ? 25 : 0, y: axis == .horizontal ? 0 : -25)
        }
        .rotationEffect(.degrees(angle))
    }
}

// MARK: - Z轴指示器

struct ZAxisIndicator: View {
    let angle: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.blue, lineWidth: 3)
                .frame(width: 40, height: 40)
            
            // 旋转指示
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .offset(x: 16)
                .rotationEffect(.degrees(angle))
        }
    }
}

// MARK: - 相机位姿追踪器

class CameraPoseTracker: ObservableObject {
    @Published var positionX: Double = 0
    @Published var positionY: Double = 1.5
    @Published var positionZ: Double = 5
    @Published var eulerAngleX: Double = 0
    @Published var eulerAngleY: Double = 0
    @Published var eulerAngleZ: Double = 0
    
    var position: SCNVector3 {
        get { SCNVector3(positionX, positionY, positionZ) }
        set {
            positionX = Double(newValue.x)
            positionY = Double(newValue.y)
            positionZ = Double(newValue.z)
        }
    }
    
    var eulerAngles: SCNVector3 {
        get { SCNVector3(eulerAngleX, eulerAngleY, eulerAngleZ) }
        set {
            eulerAngleX = Double(newValue.x)
            eulerAngleY = Double(newValue.y)
            eulerAngleZ = Double(newValue.z)
        }
    }
    
    // 这里可以集成CoreMotion和ARKit来追踪相机位姿
    // 用于3DGS数据采集时的位姿记录
}
