import SwiftUI
import SpriteKit
import CoreMotion

struct GoldPhysicsView: View {
    let totalWeightGrams: Double
    let beanWeight: Double // Weight per real bean (e.g. 1g)

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.isSimulationActive) var isSimulationActive
    @Environment(\.isWealthStorageActive) var isWealthStorageActive

    // Scene Configuration
    @State private var scene: GoldScene?
    @State private var isViewVisible: Bool = false

    // Appearance Manager (for background toggle)
    private var appearanceManager = WealthAppearanceManager.shared

    // Media State Manager
    @StateObject private var mediaStateManager = MediaStateManager.shared

    init(totalWeightGrams: Double, beanWeight: Double) {
        self.totalWeightGrams = totalWeightGrams
        self.beanWeight = beanWeight
    }

    // Computed pause state for SpriteView
    private var shouldPause: Bool {
        // print("GoldPhysicsView: shouldPause check - Visible: \(isViewVisible), SimActive: \(isSimulationActive), Scene: \(scenePhase)")
        return !isViewVisible || !isSimulationActive || !isWealthStorageActive || scenePhase != .active || mediaStateManager.isPhysicsPaused
    }
    
    var body: some View {
        GeometryReader { proxy in
            let backgroundInfo = getBackgroundInfo(proxySize: proxy.size)

            ZStack {
                // Background Image
                if appearanceManager.shouldShowWealthContainerBackground {
                    if let image = backgroundInfo.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: backgroundInfo.isCustom ? .fit : .fill)
                            .frame(width: backgroundInfo.frame.width, height: backgroundInfo.frame.height)
                            .position(x: backgroundInfo.frame.midX, y: backgroundInfo.frame.midY)
                            .clipped()
                    }
                }

                SpriteView(scene: createScene(size: proxy.size, boundary: backgroundInfo.physicsBoundary), isPaused: shouldPause, options: [.allowsTransparency])
                    // Transparent to let ZStack background show through
                    .background(Color.clear)
                    .onAppear {
                        isViewVisible = true
                        // Update bean count when view appears
                        scene?.updateBeans(totalWeight: totalWeightGrams, beanWeight: beanWeight)

                        // Update boundary in case it changed
                        scene?.updateBoundary(backgroundInfo.physicsBoundary)
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
                    .onChange(of: backgroundInfo.physicsBoundary) { _, newBoundary in
                        scene?.updateBoundary(newBoundary)
                    }
            }
        }
        .onAppear {
            isViewVisible = true
            // 恢复震动状态
            HapticEngineManager.shared.resumeHaptics()
        }
        .onDisappear {
            isViewVisible = false
            // 暂停物理模拟
            scene?.pauseSimulation()
            // 停止音效和震动
            HapticEngineManager.shared.stopHaptics()
            SoundManager.shared.stopAllSounds()
            print("🛑 GoldPhysicsView.onDisappear: 物理模拟已暂停")
        }
    }
    
    private struct BackgroundInfo {
        let image: UIImage?
        let isCustom: Bool
        let frame: CGRect
        let physicsBoundary: CGRect
    }
    
    private func getBackgroundInfo(proxySize: CGSize) -> BackgroundInfo {
        if let customBg = appearanceManager.containerBackgroundImage {
            // Custom Background: Fit mode
            let widthRatio = proxySize.width / customBg.size.width
            let heightRatio = proxySize.height / customBg.size.height
            let scale = min(widthRatio, heightRatio)
            
            let width = customBg.size.width * scale
            let height = customBg.size.height * scale
            
            let x = (proxySize.width - width) / 2
            let y = (proxySize.height - height) / 2
            
            let frame = CGRect(x: x, y: y, width: width, height: height)
            
            // Convert to SK coordinates (Y-up)
            // SK Y = ViewHeight - ViewY - ViewHeight
            // SK Rect Origin Y = proxySize.height - (y + height)
            let skY = proxySize.height - (y + height)
            let physicsBoundary = CGRect(x: x, y: skY, width: width, height: height)
            
            return BackgroundInfo(image: customBg, isCustom: true, frame: frame, physicsBoundary: physicsBoundary)
        } else {
            // Default Background: Fill mode (Full Screen)
            let frame = CGRect(origin: .zero, size: proxySize)
            return BackgroundInfo(image: UIImage(named: "WealthContainerBackground"), isCustom: false, frame: frame, physicsBoundary: frame)
        }
    }
    
    // Removed checkState() as it's replaced by shouldPause and onChange
    
    private func createScene(size: CGSize, boundary: CGRect) -> SKScene {
        if let existingScene = scene {
            if existingScene.size != size {
                // Resize existing scene instead of recreating
                existingScene.size = size
            }
            // Update boundary if needed (handled by onChange, but good for init)
             existingScene.updateBoundary(boundary)
            return existingScene
        }
        
        // Create new scene only if it doesn't exist
        let newScene = GoldScene(size: size)
        newScene.scaleMode = .aspectFill
        newScene.updateBackgroundColor(for: colorScheme)
        newScene.updateBoundary(boundary)
        
        // Initial population
        newScene.updateBeans(totalWeight: totalWeightGrams, beanWeight: beanWeight)
        
        // Assign to state asynchronously to avoid "modifying state during view update"
        // This is a workaround for initializing state that depends on GeometryReader size
        DispatchQueue.main.async {
            if self.scene == nil {
                self.scene = newScene
            }
        }
        
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
    private var isWallCollisionFrame: Bool = false // New: Track if this frame has a wall collision
    
    // Config
    private let maxVisualBeans = 5000 // Significantly increased to match 1g binding
    private let beanRadius: CGFloat = 8.0
    private let bottomPadding: CGFloat = 0.0 // No extra padding needed if not ignoring safe area
    private let sidePadding: CGFloat = 30.0 // Visible side padding
    
    // Batch Processing for Performance
    private var targetBeanCount: Int = 0
    private let beansPerFrameAdd: Int = 50 // Add 50 beans per frame (~3000/sec at 60fps)
    private let beansPerFrameRemove: Int = 100 // Remove faster
    
    // Boundary Control
    private var customBoundary: CGRect?
    
    func updateBoundary(_ rect: CGRect) {
        // Only update if changed
        if customBoundary != rect {
            self.customBoundary = rect
            setupPhysicsBoundary()
        }
    }
    
    func pauseSimulation() {
        self.isPaused = true
        motionManager.stopDeviceMotionUpdates()
        // Stop any continuous haptics and rolling haptics
        HapticEngineManager.shared.updateHapticParameters(intensity: 0, sharpness: 0)
        HapticEngineManager.shared.stopHaptics()
        // Stop rolling sound
        SoundManager.shared.stopAllSounds()
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
        // 如果场景被暂停，不执行任何更新
        guard !isPaused else { return }
        
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
        // 增加能量阈值 0.01 -> 0.05，避免静态或微小震动触发引擎噪音
        if currentEnergy > 0.05 {
             HapticEngineManager.shared.playRollingTexture(intensity: Float(currentEnergy))
        } else {
             HapticEngineManager.shared.playRollingTexture(intensity: 0)
        }

        // Reset for next frame
        frameMaxImpulse = 0.0
        frameContactPoint = .zero
        frameCollisionCount = 0
        isWallCollisionFrame = false
    }
    
    func didBegin(_ contact: SKPhysicsContact) {
        // Lightweight check: only aggregate data, do not run heavy logic here
        
        // Accumulate impulse
        let impulse = contact.collisionImpulse
        
        // Debug Log (Temporary)
        // if impulse > 0 { print("Collision Impulse: \(impulse)") }
        
        // Threshold check to ignore micro-collisions (noise)
        // Lowered threshold significantly for 2g beans
        if impulse > 0.0001 {
            if impulse > frameMaxImpulse {
                frameMaxImpulse = impulse
                frameContactPoint = contact.contactPoint
            }
            frameCollisionCount += 1
            
            // Check for wall collision
            // Wall category is 0b1 (1)
            // Bean categories are 0b10 (2) and 0b100 (4)
            if (contact.bodyA.categoryBitMask == PhysicsCategory.wall) || 
               (contact.bodyB.categoryBitMask == PhysicsCategory.wall) {
                isWallCollisionFrame = true
                // Debug high impulse wall collisions
                // if impulse > 0.01 { print("🧱 Wall Hit! Impulse: \(impulse)") }
            }
        }
    }
    
    private func triggerAggregatedHaptic(currentTime: TimeInterval) {
        // Throttle haptics based on time
        guard currentTime - lastHapticTime > hapticMinInterval else { return }
        
        lastHapticTime = currentTime
        
        // Logic:
        // Tier 1: Wall Collision (High Priority) -> Strong Impact
        // Tier 2: Bean-Bean Collision (Medium Priority) -> Medium Impact
        
        let normalizedIntensity: Float
        let sharpness: Float
        let impactType: SoundManager.ImpactType
        
        if isWallCollisionFrame {
             // WALL COLLISION: Strong & Sharp
             // Impulse 0.1+ -> Max intensity
             normalizedIntensity = Float(min(frameMaxImpulse * 10.0, 1.0))
             sharpness = 0.9 // Hard surface
             impactType = .hard
        } else {
             // BEAN COLLISION: Medium & Soft
             // Impulse 0.05+ -> Max intensity (but capped lower overall)
             // We scale it so it feels lighter than wall
             let baseIntensity = Float(min(frameMaxImpulse * 15.0, 1.0))
             normalizedIntensity = baseIntensity * 0.6 // Cap at 60% of max possible system haptic
             sharpness = 0.4 // Soft gold/wood sound
             impactType = .soft
        }
        
        // Spatial Position
        let normalizedX = frameContactPoint.x / self.size.width
        let normalizedY = frameContactPoint.y / self.size.height
        
        HapticEngineManager.shared.playCollisionHaptic(
            intensity: normalizedIntensity,
            sharpness: sharpness,
            position: CGPoint(x: normalizedX, y: normalizedY),
            type: impactType
        )
    }
    
    func updateBackgroundColor(for scheme: ColorScheme) {
        self.backgroundColor = .clear
    }
    
    private func setupPhysicsBoundary() {
        let boundaryRect: CGRect
        
        if let custom = customBoundary {
             boundaryRect = custom
        } else {
             // Default logic
             let safeFrame = CGRect(
                x: frame.minX + sidePadding,
                y: frame.minY + bottomPadding,
                width: frame.width - (sidePadding * 2),
                height: frame.height - bottomPadding
            )
            boundaryRect = safeFrame
        }
        
        physicsBody = SKPhysicsBody(edgeLoopFrom: boundaryRect)
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
        // Determine spawn area based on boundary
        let spawnRect: CGRect
        if let custom = customBoundary {
            spawnRect = custom
        } else {
            spawnRect = CGRect(
                x: sidePadding,
                y: bottomPadding,
                width: size.width - (sidePadding * 2),
                height: size.height - bottomPadding
            )
        }
        
        // Ensure spawn area is within physics boundaries
        let safeMinX = spawnRect.minX + beanRadius
        let safeMaxX = spawnRect.maxX - beanRadius
        
        // Safety check if view is too narrow
        guard safeMaxX > safeMinX else { return }
        
        for _ in 0..<count {
            let bean = createBeanNode()
            // Spawn at random x within SAFE padding
            let randomX = CGFloat.random(in: safeMinX...safeMaxX)
            
            // Ensure Y is also within boundary (below top edge)
            // Physics boundary height is frame.height - bottomPadding
            // Let's spawn them slightly lower to avoid sticking to the top ceiling
            let spawnY = spawnRect.maxY - beanRadius - 20
            
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
        
        // 性能优化：仅让约 10% 的金豆作为“触觉传感器”报告碰撞
        // 避免 5000 个金豆互相碰撞产生过多的回调导致卡顿
        let isSensor = Int.random(in: 1...10) == 1
        let contactMask: UInt32 = isSensor ? (PhysicsCategory.beanLayer1 | PhysicsCategory.beanLayer2) : 0
        
        if isLayer2 {
            node.zPosition = 10 // Visual Front
            body.categoryBitMask = PhysicsCategory.beanLayer2
            body.collisionBitMask = PhysicsCategory.beanLayer2 | PhysicsCategory.wall
            body.contactTestBitMask = contactMask
            
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
            body.contactTestBitMask = contactMask
            
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
