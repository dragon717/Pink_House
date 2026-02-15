
import SwiftUI
import SceneKit
import PhotosUI
import SwiftData

struct ThreeDOOTDView: View {
    var outfit: SpaceOutfit?
    
    @State private var scene = SCNScene()
    @State private var cameraNode = SCNNode()
    @State private var modelNode: SCNNode?
    
    // UI State
    @State private var showingImagePicker = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var processingMessage = ""
    
    // Camera State Persistence (Fallback to AppStorage if no outfit)
    @AppStorage("ThreeDCamPosX") private var defaultCamPosX: Double = 0
    @AppStorage("ThreeDCamPosY") private var defaultCamPosY: Double = 1.5
    @AppStorage("ThreeDCamPosZ") private var defaultCamPosZ: Double = 5
    
    var body: some View {
        ZStack {
            // Background
            LiquidBackground()
                .ignoresSafeArea()
            
            // 3D Scene
            SceneView(
                scene: scene,
                pointOfView: cameraNode,
                options: [.allowsCameraControl, .autoenablesDefaultLighting, .temporalAntialiasingEnabled],
                delegate: nil
            )
            .ignoresSafeArea()
            
            // UI Overlay
            VStack {
                // Header
                HStack {
                    Text(outfit?.note ?? "空间穿搭")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                    
                    Spacer()
                    
                    Button {
                        // Reset Camera
                        withAnimation {
                            resetCamera()
                        }
                    } label: {
                        Image(systemName: "camera.metering.center.weighted")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    
                    Button {
                        showingImagePicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 60)
                
                Spacer()
                
                // Controls
                HStack(spacing: 20) {
                    ControlBtn(icon: "cube.transparent", label: "生成模型") {
                        showingImagePicker = true
                    }
                    ControlBtn(icon: "light.max", label: "环境光") {
                        // Toggle lighting
                    }
                    ControlBtn(icon: "lock.open", label: "锁定视角") {
                        // Toggle lock
                    }
                }
                .padding(.bottom, 40)
            }
            
            if isProcessing {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text(processingMessage)
                        .foregroundStyle(.white)
                        .font(.headline)
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            if let newItem {
                Task {
                    // Simulate processing
                    isProcessing = true
                    processingMessage = "正在上传图片..."
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    processingMessage = "WorldLabs 生成点云中..."
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    processingMessage = "正在构建 3D 高斯泼溅..."
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    isProcessing = false
                    // Here we would load the generated model
                }
            }
        }
        .photosPicker(isPresented: $showingImagePicker, selection: $selectedItem, matching: .images)
        .onAppear {
            setupScene()
        }
        .onDisappear {
            saveState()
        }
    }
    
    private func setupScene() {
        // Setup Camera
        cameraNode.camera = SCNCamera()
        
        if let outfit = outfit {
            // Use saved camera position or default if zero (which is default init value)
            if outfit.camPosZ == 0 && outfit.camPosY == 0 && outfit.camPosX == 0 {
                cameraNode.position = SCNVector3(0, 1.5, 5)
            } else {
                cameraNode.position = SCNVector3(outfit.camPosX, outfit.camPosY, outfit.camPosZ)
            }
        } else {
            cameraNode.position = SCNVector3(defaultCamPosX, defaultCamPosY, defaultCamPosZ)
        }
        
        scene.rootNode.addChildNode(cameraNode)
        
        // Add Floor (Transparent)
        let floor = SCNFloor()
        floor.reflectivity = 0.1
        floor.firstMaterial?.diffuse.contents = UIColor.clear
        let floorNode = SCNNode(geometry: floor)
        scene.rootNode.addChildNode(floorNode)
        
        // Remove Default Background Color to allow LiquidBackground to show
        scene.background.contents = UIColor.clear
        
        // Add Placeholder Mannequin (Cylinder + Sphere)
        let bodyGeo = SCNCylinder(radius: 0.3, height: 1.5)
        bodyGeo.firstMaterial?.diffuse.contents = UIColor.systemGray6
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.position = SCNVector3(0, 0.75, 0)
        
        let headGeo = SCNSphere(radius: 0.25)
        headGeo.firstMaterial?.diffuse.contents = UIColor.systemGray5
        let headNode = SCNNode(geometry: headGeo)
        headNode.position = SCNVector3(0, 1.6, 0)
        
        let mannequin = SCNNode()
        mannequin.addChildNode(bodyNode)
        mannequin.addChildNode(headNode)
        scene.rootNode.addChildNode(mannequin)
        
        modelNode = mannequin
        
        // Add Lighting
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(0, 10, 10)
        scene.rootNode.addChildNode(lightNode)
        
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)
    }
    
    private func resetCamera() {
        cameraNode.position = SCNVector3(0, 1.5, 5)
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
    }
    
    private func saveState() {
        if let outfit = outfit {
            outfit.camPosX = Double(cameraNode.position.x)
            outfit.camPosY = Double(cameraNode.position.y)
            outfit.camPosZ = Double(cameraNode.position.z)
            // Try to take snapshot (Need SCNView snapshot, but SceneView is wrapped. Skipping for now or mocking)
        } else {
            defaultCamPosX = Double(cameraNode.position.x)
            defaultCamPosY = Double(cameraNode.position.y)
            defaultCamPosZ = Double(cameraNode.position.z)
        }
    }
}

struct ControlBtn: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .frame(width: 80, height: 80)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}
