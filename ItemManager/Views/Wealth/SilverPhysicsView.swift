import SwiftUI
import SpriteKit
import CoreMotion

struct SilverPhysicsView: View {
    let totalWeightGrams: Double
    let beanWeight: Double // Weight per real bean (e.g. 50g)
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.isSimulationActive) var isSimulationActive
    
    // Scene Configuration
    @State private var scene: SilverScene?
    @State private var isViewVisible: Bool = false
    
    // Computed pause state for SpriteView
    private var shouldPause: Bool {
        return !isViewVisible || !isSimulationActive || scenePhase != .active
    }
    
    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: createScene(size: proxy.size), isPaused: shouldPause)
                .background(Color.clear) 
                .onAppear {
                    isViewVisible = true
                    scene?.updateBeans(totalWeight: totalWeightGrams, beanWeight: beanWeight)
                    
                    // 强制测试震动，确认引擎是否工作
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        HapticEngineManager.shared.playTestHaptic()
                    }
                }
                .onDisappear {
                    isViewVisible = false
                }
                .onChange(of: totalWeightGrams) { _, newValue in
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
    
    private func createScene(size: CGSize) -> SKScene {
        if let existingScene = scene {
            if existingScene.size != size {
                existingScene.size = size
            }
            return existingScene
        }
        
        let newScene = SilverScene(size: size)
        newScene.scaleMode = .aspectFill
        newScene.updateBackgroundColor(for: colorScheme)
        
        newScene.updateBeans(totalWeight: totalWeightGrams, beanWeight: beanWeight)
        
        DispatchQueue.main.async {
            if self.scene == nil {
                self.scene = newScene
            }
        }
        
        return newScene
    }
}

// Reuse PhysicsCategory from GoldPhysicsView or define locally
// Since they are in the same module, we can reuse if it's public/internal.
// But to be safe and self-contained:
struct SilverPhysicsCategory {
    static let none: UInt32 = 0
    static let wall: UInt32 = 0b1
    static let beanLayer1: UInt32 = 0b10
    static let beanLayer2: UInt32 = 0b100
}

class SilverScene: SKScene, SKPhysicsContactDelegate {
    private let motionManager = CMMotionManager()
    private var beanNodes: [SKNode] = []
    
    // Haptic Control
    private var lastHapticTime: TimeInterval = 0
    private let hapticMinInterval: TimeInterval = 0.08
    
    // Performance Optimization: Aggregated Collision Data
    private var frameMaxImpulse: CGFloat = 0.0
    private var frameContactPoint: CGPoint = .zero
    private var frameCollisionCount: Int = 0
    private var isWallCollisionFrame: Bool = false
    
    // Config
    private let maxVisualBeans = 5000
    private let beanRadius: CGFloat = 10.0 // Slightly larger for Silver (50g vs 1g)
    private let bottomPadding: CGFloat = 0.0
    private let sidePadding: CGFloat = 30.0
    
    // Batch Processing
    private var targetBeanCount: Int = 0
    private let beansPerFrameAdd: Int = 50
    private let beansPerFrameRemove: Int = 100
    
    func pauseSimulation() {
        self.isPaused = true
        motionManager.stopDeviceMotionUpdates()
        HapticEngineManager.shared.updateHapticParameters(intensity: 0, sharpness: 0)
    }
    
    func resumeSimulation() {
        self.isPaused = false
        startMotionUpdates()
    }
    
    override func didMove(to view: SKView) {
        setupPhysicsBoundary()
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
        
        startMotionUpdates()
    }
    
    override func update(_ currentTime: TimeInterval) {
        processBeanQueue()

        if frameCollisionCount > 0 {
            triggerAggregatedHaptic(currentTime: currentTime)
        }
        
        let currentEnergy = min(CGFloat(frameCollisionCount) * 0.1 + frameMaxImpulse * 0.5, 1.0)
        
        if currentEnergy > 0.05 {
             HapticEngineManager.shared.playRollingTexture(intensity: Float(currentEnergy))
        } else {
             HapticEngineManager.shared.playRollingTexture(intensity: 0)
        }

        frameMaxImpulse = 0.0
        frameContactPoint = .zero
        frameCollisionCount = 0
        isWallCollisionFrame = false
    }
    
    func didBegin(_ contact: SKPhysicsContact) {
        let impulse = contact.collisionImpulse
        
        if impulse > 0.0001 {
            if impulse > frameMaxImpulse {
                frameMaxImpulse = impulse
                frameContactPoint = contact.contactPoint
            }
            frameCollisionCount += 1
            
            if (contact.bodyA.categoryBitMask == SilverPhysicsCategory.wall) || 
               (contact.bodyB.categoryBitMask == SilverPhysicsCategory.wall) {
                isWallCollisionFrame = true
            }
        }
    }
    
    private func triggerAggregatedHaptic(currentTime: TimeInterval) {
        guard currentTime - lastHapticTime > hapticMinInterval else { return }
        
        lastHapticTime = currentTime
        
        let normalizedIntensity: Float
        let sharpness: Float
        let impactType: SoundManager.ImpactType
        
        if isWallCollisionFrame {
             normalizedIntensity = Float(min(frameMaxImpulse * 10.0, 1.0))
             sharpness = 0.8 // Slightly less sharp than Gold?
             impactType = .hard
        } else {
             let baseIntensity = Float(min(frameMaxImpulse * 15.0, 1.0))
             normalizedIntensity = baseIntensity * 0.6
             sharpness = 0.35 // Slightly lower pitch/sharpness for Silver
             impactType = .soft
        }
        
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
        if scheme == .dark {
            self.backgroundColor = .black
        } else {
            self.backgroundColor = .white
        }
    }
    
    private func setupPhysicsBoundary() {
        let safeFrame = CGRect(
            x: frame.minX + sidePadding,
            y: frame.minY + bottomPadding,
            width: frame.width - (sidePadding * 2),
            height: frame.height - bottomPadding
        )
        
        physicsBody = SKPhysicsBody(edgeLoopFrom: safeFrame)
        physicsBody?.categoryBitMask = SilverPhysicsCategory.wall
        physicsBody?.collisionBitMask = SilverPhysicsCategory.beanLayer1 | SilverPhysicsCategory.beanLayer2
        physicsBody?.contactTestBitMask = SilverPhysicsCategory.beanLayer1 | SilverPhysicsCategory.beanLayer2
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        setupPhysicsBoundary()
    }
    
    func updateBeans(totalWeight: Double, beanWeight: Double) {
        guard beanWeight > 0 else { return }
        
        let totalRealBeans = Int(totalWeight / beanWeight)
        let beansToShow = min(totalRealBeans, maxVisualBeans)
        
        self.targetBeanCount = beansToShow
    }
    
    private func processBeanQueue() {
        let currentCount = beanNodes.count
        
        if currentCount < targetBeanCount {
            let countToAdd = min(beansPerFrameAdd, targetBeanCount - currentCount)
            addBeans(count: countToAdd)
        } else if currentCount > targetBeanCount {
            let countToRemove = min(beansPerFrameRemove, currentCount - targetBeanCount)
            removeBeans(count: countToRemove)
        }
    }
    
    private func addBeans(count: Int) {
        let safeMinX = sidePadding + beanRadius
        let safeMaxX = size.width - sidePadding - beanRadius
        
        guard safeMaxX > safeMinX else { return }
        
        for _ in 0..<count {
            let bean = createBeanNode()
            let randomX = CGFloat.random(in: safeMinX...safeMaxX)
            let spawnY = size.height - bottomPadding - beanRadius - 20
            
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
        let texture = SilverTextureGenerator.shared.getTexture()
        let node = SKSpriteNode(texture: texture)
        
        let diameter = beanRadius * 2
        node.size = CGSize(width: diameter, height: diameter)
        
        let body = SKPhysicsBody(circleOfRadius: beanRadius)
        body.mass = 0.005 // 5g visual mass
        body.restitution = 0.2
        body.friction = 0.5
        body.allowsRotation = true
        
        let isLayer2 = Bool.random()
        
        let isSensor = Int.random(in: 1...10) == 1
        let contactMask: UInt32 = isSensor ? (SilverPhysicsCategory.beanLayer1 | SilverPhysicsCategory.beanLayer2) : 0
        
        if isLayer2 {
            node.zPosition = 10
            body.categoryBitMask = SilverPhysicsCategory.beanLayer2
            body.collisionBitMask = SilverPhysicsCategory.beanLayer2 | SilverPhysicsCategory.wall
            body.contactTestBitMask = contactMask
        } else {
            node.zPosition = 0
            body.categoryBitMask = SilverPhysicsCategory.beanLayer1
            body.collisionBitMask = SilverPhysicsCategory.beanLayer1 | SilverPhysicsCategory.wall
            body.contactTestBitMask = contactMask
            
            node.color = .black
            node.colorBlendFactor = 0.2
        }
        
        node.physicsBody = body
        node.zRotation = CGFloat.random(in: 0...(2 * .pi))
        
        return node
    }
    
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (data, error) in
            guard let data = data, let self = self else { return }
            
            let interfaceOrientation = self.view?.window?.windowScene?.interfaceOrientation ?? .portrait
            
            let gravityX: Double
            let gravityY: Double
            
            switch interfaceOrientation {
            case .landscapeLeft:
                gravityX = data.gravity.y
                gravityY = data.gravity.x
            case .landscapeRight:
                gravityX = -data.gravity.y
                gravityY = -data.gravity.x
            case .portraitUpsideDown:
                gravityX = -data.gravity.x
                gravityY = -data.gravity.y
            default:
                gravityX = data.gravity.x
                gravityY = data.gravity.y
            }
            
            self.physicsWorld.gravity = CGVector(dx: gravityX * 20, dy: gravityY * 20)
        }
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
