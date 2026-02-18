//
//  BigWorldView.swift
//  ItemManager
//
//  大世界 - 3D交互地球视图
//  参考: voyage, Astronomy, dot-globe
//

import SwiftUI
import SceneKit
import Combine
import UIKit

// MARK: - 图钉数据模型
struct WorldPin: Identifiable, Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let title: String
    let clothingId: UUID?
    let imageData: Data?
    let createdAt: Date
    
    init(id: UUID = UUID(), latitude: Double, longitude: Double, title: String, clothingId: UUID? = nil, imageData: Data? = nil, createdAt: Date = Date()) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.title = title
        self.clothingId = clothingId
        self.imageData = imageData
        self.createdAt = createdAt
    }
}

// MARK: - 大世界视图模型
@MainActor
class BigWorldViewModel: ObservableObject {
    @Published var pins: [WorldPin] = []
    @Published var selectedPin: WorldPin?
    @Published var isShowingPinDetail = false
    @Published var isAddingPin = false
    @Published var isDayMode = true
    
    // 用户位置（默认北京）
    @Published var userLatitude: Double = 39.9042
    @Published var userLongitude: Double = 116.4074
    
    private let pinsKey = "bigWorldPins"
    
    init() {
        loadPins()
    }
    
    func loadPins() {
        if let data = UserDefaults.standard.data(forKey: pinsKey),
           let savedPins = try? JSONDecoder().decode([WorldPin].self, from: data) {
            pins = savedPins
        }
    }
    
    func savePins() {
        if let data = try? JSONEncoder().encode(pins) {
            UserDefaults.standard.set(data, forKey: pinsKey)
        }
    }
    
    func addPin(_ pin: WorldPin) {
        pins.append(pin)
        savePins()
    }
    
    func removePin(_ pin: WorldPin) {
        pins.removeAll { $0.id == pin.id }
        savePins()
    }
    
    // 经纬度转3D坐标
    func geoToCartesian(lat: Double, lon: Double, radius: Float) -> SCNVector3 {
        let latRad = Float(lat) * .pi / 180
        let lonRad = Float(lon) * .pi / 180
        let x = radius * cos(latRad) * sin(lonRad)
        let y = radius * sin(latRad)
        let z = radius * cos(latRad) * cos(lonRad)
        return SCNVector3(x, y, z)
    }
    
    // 重置到用户当前位置
    func resetToUserLocation() {
        // 触发通知让 SceneKit 视图重置相机位置
        NotificationCenter.default.post(name: .resetGlobeToUserLocation, object: nil)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let resetGlobeToUserLocation = Notification.Name("resetGlobeToUserLocation")
}

// MARK: - 大世界主视图
struct BigWorldView: View {
    @StateObject private var viewModel = BigWorldViewModel()
    @StateObject private var textureManager = EarthTextureManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingTextureSettings = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                // 3D地球场景
                GlobeSceneView(viewModel: viewModel)
                    .ignoresSafeArea()
                
                // UI 覆盖层 - 只保留底部信息栏
                VStack {
                    Spacer()
                    
                    // 底部信息栏
                    if let selectedPin = viewModel.selectedPin {
                        PinInfoCard(pin: selectedPin, viewModel: viewModel)
                            .padding(.horizontal)
                            .padding(.bottom, 30)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .navigationTitle("大世界")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左侧：重置到当前位置 + 纹理设置
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        Button(action: { viewModel.resetToUserLocation() }) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.pink)
                        }
                        
                        Button(action: { showingTextureSettings = true }) {
                            Image(systemName: "photo")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                // 右侧：昼夜切换 + 添加图钉
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // 昼夜切换
                        Button(action: { viewModel.isDayMode.toggle() }) {
                            Image(systemName: viewModel.isDayMode ? "sun.max.fill" : "moon.fill")
                                .foregroundStyle(viewModel.isDayMode ? .orange : .indigo)
                        }
                        
                        // 添加图钉
                        Button(action: { viewModel.isAddingPin = true }) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.pink)
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.isAddingPin) {
                AddPinView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingTextureSettings) {
                EarthTextureSettingsView()
            }
        }
    }
}

// MARK: - SceneKit 地球视图
struct GlobeSceneView: UIViewRepresentable {
    @ObservedObject var viewModel: BigWorldViewModel
    @ObservedObject var textureManager = EarthTextureManager.shared
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = createScene()
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = false
        sceneView.backgroundColor = .clear
        sceneView.delegate = context.coordinator
        
        // 添加手势识别
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
        
        context.coordinator.sceneView = sceneView
        context.coordinator.viewModel = viewModel
        
        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.updateDayNightMode(isDay: viewModel.isDayMode)
        context.coordinator.updatePins()
        context.coordinator.updateTextures(dayTexture: textureManager.dayTexture, nightTexture: textureManager.nightTexture)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // 创建地球节点
        let earthNode = createEarthNode()
        scene.rootNode.addChildNode(earthNode)
        
        // 创建光源
        let sunNode = createSunLight()
        scene.rootNode.addChildNode(sunNode)
        
        // 创建环境光
        let ambientNode = createAmbientLight()
        scene.rootNode.addChildNode(ambientNode)
        
        // 创建相机
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.name = "camera"
        cameraNode.position = SCNVector3(0, 0, 3.5)
        scene.rootNode.addChildNode(cameraNode)
        
        // 添加星空背景粒子效果
        addStarfield(to: scene)
        
        return scene
    }
    
    private func createEarthNode() -> SCNNode {
        let sphere = SCNSphere(radius: 1.0)
        
        // 使用真实地图纹理
        let material = SCNMaterial()
        material.diffuse.contents = loadEarthTexture()
        material.emission.contents = loadNightLightsTexture()
        material.specular.contents = UIColor.white
        material.shininess = 0.1
        
        sphere.materials = [material]
        
        let earthNode = SCNNode(geometry: sphere)
        earthNode.name = "earth"
        
        // 添加自转动画
        let rotation = CABasicAnimation(keyPath: "rotation")
        rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotation.duration = 120 // 120秒一圈
        rotation.repeatCount = .infinity
        earthNode.addAnimation(rotation, forKey: "rotate")
        
        return earthNode
    }
    
    // 加载真实地球纹理
    private func loadEarthTexture() -> UIImage {
        return EarthTextureManager.shared.getDayTexture()
    }
    
    // 加载夜晚灯光纹理
    private func loadNightLightsTexture() -> UIImage {
        return EarthTextureManager.shared.getNightTexture()
    }
    
    private func createSunLight() -> SCNNode {
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .directional
        lightNode.light?.intensity = 1000
        lightNode.light?.castsShadow = true
        lightNode.position = SCNVector3(5, 3, 5)
        lightNode.look(at: SCNVector3(0, 0, 0))
        return lightNode
    }
    
    private func createAmbientLight() -> SCNNode {
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .ambient
        lightNode.light?.intensity = 200
        lightNode.light?.color = UIColor.white
        return lightNode
    }
    
    private func addStarfield(to scene: SCNScene) {
        let particleSystem = SCNParticleSystem()
        particleSystem.particleImage = createStarImage()
        particleSystem.birthRate = 50
        particleSystem.particleLifeSpan = 10
        particleSystem.particleSize = 0.02
        particleSystem.emitterShape = SCNSphere(radius: 10)
        particleSystem.birthLocation = .surface
        particleSystem.speedFactor = 0.0
        particleSystem.loops = true
        
        let particleNode = SCNNode()
        particleNode.addParticleSystem(particleSystem)
        scene.rootNode.addChildNode(particleNode)
    }
    
    // 创建程序化白天纹理
    private func createDayTexture() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        
        // 海洋背景
        context.setFillColor(UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // 绘制简单的大陆轮廓
        context.setFillColor(UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1.0).cgColor)
        
        // 亚洲
        context.fillEllipse(in: CGRect(x: 600, y: 150, width: 200, height: 150))
        // 欧洲
        context.fillEllipse(in: CGRect(x: 480, y: 140, width: 80, height: 60))
        // 非洲
        context.fillEllipse(in: CGRect(x: 480, y: 220, width: 100, height: 140))
        // 北美
        context.fillEllipse(in: CGRect(x: 150, y: 100, width: 180, height: 120))
        // 南美
        context.fillEllipse(in: CGRect(x: 200, y: 250, width: 100, height: 150))
        // 澳洲
        context.fillEllipse(in: CGRect(x: 800, y: 320, width: 100, height: 60))
        
        // 添加云层效果
        context.setFillColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        for i in 0..<20 {
            let x = CGFloat.random(in: 0...size.width)
            let y = CGFloat.random(in: 0...size.height)
            let w = CGFloat.random(in: 50...150)
            let h = CGFloat.random(in: 30...80)
            context.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
    
    // 创建程序化夜晚纹理（城市灯光）
    private func createNightTexture() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        
        // 黑色背景
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // 绘制城市灯光点
        context.setFillColor(UIColor.yellow.withAlphaComponent(0.8).cgColor)
        
        // 随机生成城市灯光
        for _ in 0..<500 {
            let x = CGFloat.random(in: 0...size.width)
            let y = CGFloat.random(in: 0...size.height)
            let size = CGFloat.random(in: 1...3)
            context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }
        
        // 主要城市区域
        let cities = [
            CGPoint(x: 650, y: 200), // 东京
            CGPoint(x: 600, y: 180), // 北京
            CGPoint(x: 550, y: 190), // 上海
            CGPoint(x: 500, y: 160), // 莫斯科
            CGPoint(x: 450, y: 180), // 巴黎
            CGPoint(x: 420, y: 170), // 伦敦
            CGPoint(x: 250, y: 160), // 纽约
            CGPoint(x: 220, y: 200), // 洛杉矶
            CGPoint(x: 280, y: 280), // 圣保罗
        ]
        
        for city in cities {
            context.setFillColor(UIColor.orange.withAlphaComponent(0.6).cgColor)
            context.fillEllipse(in: CGRect(x: city.x - 10, y: city.y - 10, width: 20, height: 20))
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
    
    private func createStarImage() -> UIImage {
        let size = CGSize(width: 4, height: 4)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, SCNSceneRendererDelegate {
        weak var sceneView: SCNView?
        weak var viewModel: BigWorldViewModel?
        
        private var earthNode: SCNNode?
        private var pinNodes: [SCNNode] = []
        private var cameraNode: SCNNode?
        
        override init() {
            super.init()
            // 监听重置位置通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(resetToUserLocation),
                name: .resetGlobeToUserLocation,
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc private func resetToUserLocation() {
            guard let viewModel = viewModel,
                  let sceneView = sceneView,
                  let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: true) else { return }
            
            // 计算用户位置的3D坐标
            let position = viewModel.geoToCartesian(
                lat: viewModel.userLatitude,
                lon: viewModel.userLongitude,
                radius: 3.5
            )
            
            // 动画移动相机到用户位置
            let moveAction = SCNAction.move(to: position, duration: 1.0)
            moveAction.timingMode = .easeInEaseOut
            cameraNode.runAction(moveAction)
        }
        
        func updateDayNightMode(isDay: Bool) {
            guard let earthNode = earthNode ?? sceneView?.scene?.rootNode.childNode(withName: "earth", recursively: true) else { return }
            
            self.earthNode = earthNode
            
            if let geometry = earthNode.geometry as? SCNSphere,
               let material = geometry.materials.first {
                // 调整材质属性实现昼夜变化
                if isDay {
                    material.emission.intensity = 0.0
                    material.diffuse.intensity = 1.0
                } else {
                    // 夜晚模式：保持 diffuse 可见度，让地球背面也能看到
                    material.emission.intensity = 0.8
                    material.diffuse.intensity = 0.6
                }
            }
        }
        
        func updatePins() {
            guard let viewModel = viewModel,
                  let earthNode = earthNode ?? sceneView?.scene?.rootNode.childNode(withName: "earth", recursively: true) else { return }
            
            self.earthNode = earthNode
            
            // 移除旧的图钉
            pinNodes.forEach { $0.removeFromParentNode() }
            pinNodes.removeAll()
            
            // 添加新图钉
            for pin in viewModel.pins {
                let position = viewModel.geoToCartesian(lat: pin.latitude, lon: pin.longitude, radius: 1.02)
                let pinNode = createPinNode(at: position, pin: pin)
                earthNode.addChildNode(pinNode)
                pinNodes.append(pinNode)
            }
        }
        
        func updateTextures(dayTexture: UIImage?, nightTexture: UIImage?) {
            guard let earthNode = earthNode ?? sceneView?.scene?.rootNode.childNode(withName: "earth", recursively: true),
                  let geometry = earthNode.geometry as? SCNSphere,
                  let material = geometry.materials.first else { return }
            
            self.earthNode = earthNode
            
            // 更新白天纹理
            if let dayTexture = dayTexture {
                material.diffuse.contents = dayTexture
            }
            
            // 更新夜晚纹理
            if let nightTexture = nightTexture {
                material.emission.contents = nightTexture
            }
        }
        
        private func createPinNode(at position: SCNVector3, pin: WorldPin) -> SCNNode {
            // 图钉圆柱体 - 使用莫妮卡粉
            let cylinder = SCNCylinder(radius: 0.015, height: 0.08)
            let material = SCNMaterial()
            let monicaPink = UIColor(red: 1.0, green: 0.604, blue: 0.635, alpha: 1.0) // FF9AA2
            material.diffuse.contents = monicaPink
            material.emission.contents = monicaPink.withAlphaComponent(0.5)
            cylinder.materials = [material]
            
            let node = SCNNode(geometry: cylinder)
            node.position = position
            node.look(at: SCNVector3(0, 0, 0))
            node.name = pin.id.uuidString
            
            // 图钉头部
            let sphere = SCNSphere(radius: 0.025)
            let sphereMaterial = SCNMaterial()
            sphereMaterial.diffuse.contents = UIColor.red
            sphere.materials = [sphereMaterial]
            
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.position = SCNVector3(0, 0.04, 0)
            node.addChildNode(sphereNode)
            
            // 脉冲动画
            let pulse = CABasicAnimation(keyPath: "scale")
            pulse.fromValue = NSValue(scnVector3: SCNVector3(1, 1, 1))
            pulse.toValue = NSValue(scnVector3: SCNVector3(1.3, 1.3, 1.3))
            pulse.duration = 1.0
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            sphereNode.addAnimation(pulse, forKey: "pulse")
            
            return node
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = sceneView else { return }
            
            let location = gesture.location(in: sceneView)
            let hitResults = sceneView.hitTest(location, options: nil)
            
            if let result = hitResults.first {
                let node = result.node
                
                // 检查是否点击了图钉
                if let pinId = UUID(uuidString: node.name ?? ""),
                   let pin = viewModel?.pins.first(where: { $0.id == pinId }) {
                    viewModel?.selectedPin = pin
                    return
                }
                
                // 检查是否点击了地球
                if node.name == "earth" || node.parent?.name == "earth" {
                    // 计算点击位置的经纬度
                    let localPoint = result.localCoordinates
                    let lat = Double(asin(localPoint.y)) * 180 / .pi
                    let lon = Double(atan2(localPoint.x, localPoint.z)) * 180 / .pi
                    
                    print("Tapped at: lat \(lat), lon \(lon)")
                }
            } else {
                viewModel?.selectedPin = nil
            }
        }
    }
}

// MARK: - 图钉信息卡片
struct PinInfoCard: View {
    let pin: WorldPin
    @ObservedObject var viewModel: BigWorldViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pin.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("\(String(format: "%.2f", pin.latitude))°, \(String(format: "%.2f", pin.longitude))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: { viewModel.selectedPin = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            if let imageData = pin.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            HStack {
                Spacer()
                
                Button(action: { viewModel.removePin(pin) }) {
                    Label("删除", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 添加图钉视图
struct AddPinView: View {
    @ObservedObject var viewModel: BigWorldViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var latitude: Double = 39.9042
    @State private var longitude: Double = 116.4074
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("位置信息") {
                    TextField("标题", text: $title)
                    
                    HStack {
                        Text("纬度")
                        Spacer()
                        TextField("纬度", value: $latitude, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("经度")
                        Spacer()
                        TextField("经度", value: $longitude, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("图片") {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Button("选择图片") {
                        showingImagePicker = true
                    }
                }
            }
            .navigationTitle("添加图钉")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let imageData = selectedImage?.jpegData(compressionQuality: 0.8)
                        let pin = WorldPin(
                            latitude: latitude,
                            longitude: longitude,
                            title: title.isEmpty ? "未命名位置" : title,
                            imageData: imageData
                        )
                        viewModel.addPin(pin)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker { image in
                    selectedImage = image
                }
            }
        }
    }
}

// MARK: - 预览
#Preview {
    BigWorldView()
        .environment(ThemeManager())
}
