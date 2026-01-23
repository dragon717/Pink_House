import SwiftUI
import SpriteKit
import CoreMotion

struct GoldPhysicsView: View {
    let totalWeightGrams: Double
    let beanWeight: Double // Weight per real bean (e.g. 1g)
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.isSimulationActive) var isSimulationActive
    
    // Scene Configuration
    @State private var scene: GoldScene?
    @State private var isViewVisible: Bool = false
    
    // Computed pause state for SpriteView
    private var shouldPause: Bool {
        // print("GoldPhysicsView: shouldPause check - Visible: \(isViewVisible), SimActive: \(isSimulationActive), Scene: \(scenePhase)")
        return !isViewVisible || !isSimulationActive || scenePhase != .active
    }
    
    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: createScene(size: proxy.size), isPaused: shouldPause)
                // Transparent to let ZStack background show through if needed,
                // but we will manage background color in scene.
                .background(Color.clear) 
                .ignoresSafeArea()
                .onAppear {
                    isViewVisible = true
                    // Update bean count when view appears
                    scene?.updateBeans(totalWeight: totalWeightGrams, beanWeight: beanWeight)
                    // checkState() // No longer needed, handled by onChange(of: shouldPause)
                }
                .onDisappear {
                    isViewVisible = false
                    // checkState()
                }
                .onChange(of: totalWeightGrams) { _, newValue in
                    // Ensure update runs on main thread and scene is ready
                    if let scene = scene {
                        scene.updateBeans(totalWeight: newValue, beanWeight: beanWeight)
                    }
                }
                .onChange(of: colorScheme) { _, newScheme in
                    scene?.updateBackgroundColor(for: newScheme)
                }
                .onChange(of: shouldPause) { _, newValue in
                    if newValue {
                        scene?.pauseSimulation()
                    } else {
                        scene?.resumeSimulation()
                    }
                }
        }
    }
    
    // Removed checkState() as it's replaced by shouldPause and onChange
    
    private func createScene(size: CGSize) -> SKScene {
        if let existingScene = scene, existingScene.size == size {
            return existingScene
        }
        let newScene = GoldScene(size: size)
        newScene.scaleMode = .aspectFill
        newScene.updateBackgroundColor(for: colorScheme)
        
        // Initial population
        newScene.updateBeans(totalWeight: totalWeightGrams, beanWeight: beanWeight)
        
        self.scene = newScene
        return newScene
    }
}

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let wall: UInt32 = 0b1
    static let beanLayer1: UInt32 = 0b10
    static let beanLayer2: UInt32 = 0b100
}

class GoldScene: SKScene, SKPhysicsContactDelegate {
    private let motionManager = CMMotionManager()
    private var beanNodes: [SKNode] = []
    
    // Haptic Control
    private var lastHapticTime: TimeInterval = 0
    private let hapticMinInterval: TimeInterval = 0.08
    
    // Performance Optimization: Aggregated Collision Data
    private var frameMaxImpulse: CGFloat = 0.0
    private var frameContactPoint: CGPoint = .zero
    private var frameCollisionCount: Int = 0
    
    // Config
    private let maxVisualBeans = 5000 // Significantly increased to match 1g binding
    private let beanRadius: CGFloat = 8.0
    private let bottomPadding: CGFloat = 100.0 // Reserve space for TabBar
    
    // Batch Processing for Performance
    private var targetBeanCount: Int = 0
    private let beansPerFrameAdd: Int = 50 // Add 50 beans per frame (~3000/sec at 60fps)
    private let beansPerFrameRemove: Int = 100 // Remove faster
    
    func pauseSimulation() {
        self.isPaused = true
        motionManager.stopDeviceMotionUpdates()
        // Stop any continuous haptics
        HapticEngineManager.shared.updateHapticParameters(intensity: 0, sharpness: 0)
    }
    
    func resumeSimulation() {
        self.isPaused = false
        startMotionUpdates()
    }
    
    override func didMove(to view: SKView) {
        setupPhysicsBoundary()
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8) // Default gravity
        physicsWorld.contactDelegate = self // Set contact delegate
        
        startMotionUpdates()
    }
    
    override func update(_ currentTime: TimeInterval) {
        // 0. Batch Processing for Bean Management
        processBeanQueue()

        // 1. Process aggregated collision data for transient haptics (瞬态撞击)
        if frameCollisionCount > 0 {
            triggerAggregatedHaptic(currentTime: currentTime)
        }
        
        // 2. Real-time Modulation for Continuous Haptics (持续震动调制)
        // 计算当前所有金豆的总动能，作为持续震动的强度依据
        // 遍历所有 beanNodes 可能太耗时 (5000个)，我们可以采样或者利用物理世界的整体属性
        // 但 SpriteKit 没有直接提供 "Total Energy"
        // 替代方案：利用上一帧的碰撞次数和最大冲量来估算“混乱度”
        
        // 衰减因子：如果这一帧没有碰撞，能量快速衰减
        // 我们维护一个平滑的 energyLevel
        
        let currentEnergy = min(CGFloat(frameCollisionCount) * 0.1 + frameMaxImpulse * 0.5, 1.0)
        
        // 发送给 HapticEngine 进行调制
        // 注意：不要每一帧都发，除非有变化，而且 Core Haptics 处理频率很高，可以每帧发
        if currentEnergy > 0.01 {
             HapticEngineManager.shared.updateHapticParameters(
                intensity: Float(currentEnergy),
                sharpness: 0.5 // 持续震动保持低沉，模拟背景噪音
             )
        } else {
             // 静止时关闭
             HapticEngineManager.shared.updateHapticParameters(intensity: 0, sharpness: 0)
        }

        // Reset for next frame
        frameMaxImpulse = 0.0
        frameContactPoint = .zero
        frameCollisionCount = 0
    }
    
    func didBegin(_ contact: SKPhysicsContact) {
        // Lightweight check: only aggregate data, do not run heavy logic here
        // The bitmasks ensure we only get Wall <-> Bean collisions
        
        // Accumulate impulse
        let impulse = contact.collisionImpulse
        
        // Threshold check to ignore micro-collisions (noise)
        if impulse > 0.05 {
            if impulse > frameMaxImpulse {
                frameMaxImpulse = impulse
                frameContactPoint = contact.contactPoint
            }
            frameCollisionCount += 1
        }
    }
    
    private func triggerAggregatedHaptic(currentTime: TimeInterval) {
        // Throttle haptics based on time
        guard currentTime - lastHapticTime > hapticMinInterval else { return }
        
        lastHapticTime = currentTime
        
        // Logic:
        // If single collision with high impulse -> Sharp, Strong haptic
        // If multiple collisions (e.g. rolling pile) -> Muffled, Rumbly haptic
        
        // Normalize Impulse (0.0 - 1.0)
        // Assume max impulse around 3.0 for very hard shake
        let normalizedIntensity = Float(min(frameMaxImpulse / 2.0, 1.0))
        
        // Calculate Sharpness
        // If many collisions, it's a "thud" or "rumble" -> Lower sharpness
        // If single collision, it's a "clink" -> Higher sharpness
        // But also depend on total bean count?
        // Let's use collision count in this frame as a proxy for "density"
        let densityFactor = min(Float(frameCollisionCount) / 5.0, 1.0) // 5+ collisions = max density effect
        let sharpness: Float = 0.9 - (densityFactor * 0.4) // 0.9 (sharp) -> 0.5 (dull)
        
        // Spatial Position
        let normalizedX = frameContactPoint.x / self.size.width
        let normalizedY = frameContactPoint.y / self.size.height
        
        HapticEngineManager.shared.playCollisionHaptic(
            intensity: normalizedIntensity,
            sharpness: sharpness,
            position: CGPoint(x: normalizedX, y: normalizedY)
        )
    }
    
    func updateBackgroundColor(for scheme: ColorScheme) {
        if scheme == .dark {
            self.backgroundColor = .black
        } else {
            self.backgroundColor = .white
        }
    }
    
    private func setupPhysicsBoundary() {
        // Create a boundary that is raised from the bottom to avoid TabBar
        // And inset from the sides to avoid edge overflow
        let sidePadding: CGFloat = 2.0 // Small padding to keep beans fully visible
        
        let safeFrame = CGRect(
            x: frame.minX + sidePadding,
            y: frame.minY + bottomPadding,
            width: frame.width - (sidePadding * 2),
            height: frame.height - bottomPadding
        )
        
        physicsBody = SKPhysicsBody(edgeLoopFrom: safeFrame)
        physicsBody?.categoryBitMask = PhysicsCategory.wall
        // Walls collide with beans
        physicsBody?.collisionBitMask = PhysicsCategory.beanLayer1 | PhysicsCategory.beanLayer2
        // Walls notify contact only with beans (to trigger haptics)
        // CRITICAL: We only want to know when beans hit the wall, not when beans hit beans.
        physicsBody?.contactTestBitMask = PhysicsCategory.beanLayer1 | PhysicsCategory.beanLayer2
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        setupPhysicsBoundary()
    }
    
    func updateBeans(totalWeight: Double, beanWeight: Double) {
        guard beanWeight > 0 else { return }
        
        let totalRealBeans = Int(totalWeight / beanWeight)
        let beansToShow = min(totalRealBeans, maxVisualBeans)
        
        // Just update the target, let update() handle the convergence
        self.targetBeanCount = beansToShow
    }
    
    private func processBeanQueue() {
        let currentCount = beanNodes.count
        
        if currentCount < targetBeanCount {
            // Add beans
            let countToAdd = min(beansPerFrameAdd, targetBeanCount - currentCount)
            addBeans(count: countToAdd)
        } else if currentCount > targetBeanCount {
            // Remove beans
            let countToRemove = min(beansPerFrameRemove, currentCount - targetBeanCount)
            removeBeans(count: countToRemove)
        }
    }
    
    private func addBeans(count: Int) {
        for _ in 0..<count {
            let bean = createBeanNode()
            // Spawn at random x, top y
            let randomX = CGFloat.random(in: beanRadius...(size.width - beanRadius))
            let spawnY = size.height - beanRadius - 10 // Start a bit down from top
            
            bean.position = CGPoint(x: randomX, y: spawnY)
            addChild(bean)
            beanNodes.append(bean)
        }
    }
    
    private func removeBeans(count: Int) {
        for _ in 0..<count {
            if let node = beanNodes.popLast() {
                node.removeFromParent()
            }
        }
    }
    
    private func createBeanNode() -> SKNode {
        // Create a visual gold bean using Texture
        let texture = GoldTextureGenerator.shared.getTexture()
        let node = SKSpriteNode(texture: texture)
        
        // Size: The texture is 128x128. We need to scale it to beanRadius * 2
        let diameter = beanRadius * 2
        node.size = CGSize(width: diameter, height: diameter)
        
        // Physics
        // Use a circle physics body for performance and stability
        // Allow rotation
        let body = SKPhysicsBody(circleOfRadius: beanRadius)
        body.mass = 0.002 // 2g visual mass
        body.restitution = 0.2 // Bounciness (low for gold, it's heavy/soft)
        body.friction = 0.5
        body.allowsRotation = true // Enable rotation
        
        // Randomly assign to a layer
        // Layer 1: zPosition 0, Collides with Layer 1 + Wall
        // Layer 2: zPosition 1, Collides with Layer 2 + Wall
        let isLayer2 = Bool.random()
        
        if isLayer2 {
            node.zPosition = 10 // Visual Front
            body.categoryBitMask = PhysicsCategory.beanLayer2
            body.collisionBitMask = PhysicsCategory.beanLayer2 | PhysicsCategory.wall
            
            // Slightly darken the back layer beans or lighten the front ones for depth?
            // Actually, front layer should cast shadow on back layer? Too complex for 2D.
            // Just size variation?
            // Let's make front beans slightly larger or same size.
            // Maybe slight color tint variation.
            // node.color = .white
            // node.colorBlendFactor = 0.0
        } else {
            node.zPosition = 0 // Visual Back
            body.categoryBitMask = PhysicsCategory.beanLayer1
            body.collisionBitMask = PhysicsCategory.beanLayer1 | PhysicsCategory.wall
            
            // Darken back layer slightly for depth perception
            node.color = .black
            node.colorBlendFactor = 0.2 // 20% Darker
        }
        
        node.physicsBody = body
        
        // Add random initial rotation for natural look
        node.zRotation = CGFloat.random(in: 0...(2 * .pi))
        
        return node
    }
    
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (data, error) in
            guard let data = data, let self = self else { return }
            
            // Map gravity based on device orientation
            // In SpriteKit (and CoreMotion's gravity vector):
            // +X is Right
            // +Y is Up
            // CoreMotion gravity: (x: -1) means device is tilted left (landscape left?) NO.
            // When holding phone portrait: gravity is (0, -1, 0) approx.
            // When holding phone landscape left (home button right): gravity is (-1, 0, 0)
            // When holding phone landscape right (home button left): gravity is (1, 0, 0)
            
            // SpriteKit coordinate system matches CoreMotion's 2D projection quite well for Portrait.
            // Portrait: Gravity (0, -1) -> Gravity Down. Correct.
            // Landscape Left (Home Right): Gravity (-1, 0). Vector (-1, 0) means force to LEFT.
            // If we rotate the device, the "Down" of the physical world is relative to the screen.
            // If we are in Portrait UI, and we rotate device to Landscape:
            // The screen is still Portrait (locked?).
            // If the UI DOES NOT rotate (Portrait Lock), then:
            // Physical Down is to the "Left" of the screen.
            // So beans should fall to the Left.
            // Gravity vector (-1, 0) pushes Left. Correct.
            
            // However, user says "Gravity direction is wrong in Landscape".
            // This usually happens if the UI rotates but the coordinate system logic doesn't adapt,
            // OR if the user expects the beans to always fall to the "Bottom of the Device" regardless of rotation?
            // Wait, if the UI rotates to Landscape:
            // The "Bottom" of the screen is now the long edge.
            // CoreMotion gravity is relative to the DEVICE HARDWARE, not the UI Interface Orientation.
            
            // Case 1: UI is Portrait Locked.
            // User rotates phone to Landscape.
            // Physical Down is now "Left" or "Right" of the screen.
            // Beans should fall to the side.
            // data.gravity.x will be +/- 1.
            // data.gravity.y will be 0.
            // physicsWorld.gravity = (x, y)
            // If x = -1, gravity points Left. Beans fall Left. This is physically correct for a real container.
            
            // Case 2: UI Rotates to Landscape.
            // If the View rotates, the Coordinate System rotates.
            // In SwiftUI, if the app supports Landscape, the view layout changes.
            // But CoreMotion `gravity` vector is always relative to the Device Frame (Portrait).
            // - X axis: passes through the side buttons (Right is +X).
            // - Y axis: passes through top/bottom (Top is +Y).
            
            // If the App UI is in Landscape (Home button on Right):
            // The "Top" of the UI corresponds to the "Left" of the Device.
            // The "Bottom" of the UI corresponds to the "Right" of the Device.
            // The "Right" of the UI corresponds to the "Top" of the Device.
            // The "Left" of the UI corresponds to the "Bottom" of the Device.
            
            // Let's get current interface orientation to adjust gravity vector mapping.
            // Since we are in a View, we can try to detect orientation.
            // But SKScene doesn't automatically know about UIInterfaceOrientation.
            
            // Simple Fix: Map gravity based on current interface orientation.
            
            let interfaceOrientation = self.view?.window?.windowScene?.interfaceOrientation ?? .portrait
            
            let gravityX: Double
            let gravityY: Double
            
            switch interfaceOrientation {
            case .landscapeLeft:
                // Device rotated Right (Home button Left).
                // Device +X is Up in UI. Device +Y is Right in UI.
                // Gravity vector (x, y, z) from CM is relative to Device.
                // We need to map Device (x, y) to Scene (x, y).
                // Scene X = Device Y
                // Scene Y = Device X
                gravityX = data.gravity.y
                gravityY = data.gravity.x
            case .landscapeRight:
                // Device rotated Left (Home button Right).
                // Device +X is Down in UI. Device +Y is Left in UI.
                // Scene X = -Device Y
                // Scene Y = -Device X
                gravityX = -data.gravity.y
                gravityY = -data.gravity.x
            case .portraitUpsideDown:
                // Device upside down.
                // Scene X = -Device X
                // Scene Y = -Device Y
                gravityX = -data.gravity.x
                gravityY = -data.gravity.y
            default: // Portrait
                // Standard mapping
                gravityX = data.gravity.x
                gravityY = data.gravity.y
            }
            
            // Amplify gravity for better feel
            self.physicsWorld.gravity = CGVector(dx: gravityX * 20, dy: gravityY * 20)
        }
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
