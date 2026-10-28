import SwiftUI
import Combine
import SpriteKit
import CoreMotion

struct SilverPhysicsView: View {
    let totalWeightGrams: Double
    let beanWeight: Double

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSimulationActive) private var isSimulationActive
    @Environment(\.isWealthStorageActive) private var isWealthStorageActive
    @ObservedObject private var mediaStateManager = MediaStateManager.shared
    private var appearanceManager = WealthAppearanceManager.shared

    private var isActive: Bool {
        isSimulationActive && isWealthStorageActive && scenePhase == .active && !mediaStateManager.isPhysicsPaused
    }

    var body: some View {
        GeometryReader { proxy in
            let customImage = appearanceManager.containerBackgroundImage
            let layout = WealthContainerLayout(size: proxy.size, customImageSize: customImage?.size)
            ZStack {
                if appearanceManager.shouldShowWealthContainerBackground,
                   let image = customImage ?? UIImage(named: "WealthContainerBackground") {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: customImage == nil ? .fill : .fit)
                        .frame(width: layout.frame.width, height: layout.frame.height)
                        .position(x: layout.frame.midX, y: layout.frame.midY)
                        .clipped()
                }
                WealthPhysicsSurface(isActive: isActive, makeScene: { SilverScene(size: $0) }) { scene, size in
                    let boundary = WealthContainerLayout(size: size, customImageSize: customImage?.size)
                    scene.updateBoundary(boundary.physicsBoundary(in: size))
                    scene.updateBeans(totalWeight: totalWeightGrams, beanWeight: beanWeight)
                }
                .accessibilityIdentifier("wealth.silver.physics")
            }
            .clipped()
        }
    }
}

struct SilverPhysicsCategory {
    static let wall: UInt32 = 0b1
    static let beanLayer1: UInt32 = 0b10
    static let beanLayer2: UInt32 = 0b100
}

class SilverScene: SKScene, SKPhysicsContactDelegate, WealthPhysicsScene {
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
    
    // Boundary Control
    private var customBoundary: CGRect?
    
    func updateBoundary(_ rect: CGRect) {
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
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
        
    }
    
    override func willMove(from view: SKView) {
        motionManager.stopDeviceMotionUpdates()
        isPaused = true
        super.willMove(from: view)
    }

    override func update(_ currentTime: TimeInterval) {
        // 如果场景被暂停，不执行任何更新
        guard !isPaused else { return }
        
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
    
    
    private func setupPhysicsBoundary() {
        let boundaryRect: CGRect
        
        if let custom = customBoundary {
             boundaryRect = custom
        } else {
            let safeFrame = CGRect(
                x: frame.minX + sidePadding,
                y: frame.minY + bottomPadding,
                width: frame.width - (sidePadding * 2),
                height: frame.height - bottomPadding
            )
            boundaryRect = safeFrame
        }
        
        physicsBody = SKPhysicsBody(edgeLoopFrom: boundaryRect)
        physicsBody?.categoryBitMask = SilverPhysicsCategory.wall
        physicsBody?.collisionBitMask = SilverPhysicsCategory.beanLayer1 | SilverPhysicsCategory.beanLayer2
        physicsBody?.contactTestBitMask = SilverPhysicsCategory.beanLayer1 | SilverPhysicsCategory.beanLayer2
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        setupPhysicsBoundary()
    }
    
    func updateBeans(totalWeight: Double, beanWeight: Double) {
        targetBeanCount = WealthVisualCount.beans(totalWeight: totalWeight, beanWeight: beanWeight, limit: maxVisualBeans)
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
        
        let safeMinX = spawnRect.minX + beanRadius
        let safeMaxX = spawnRect.maxX - beanRadius
        
        guard safeMaxX > safeMinX else { return }
        
        for _ in 0..<count {
            let bean = createBeanNode()
            let randomX = CGFloat.random(in: safeMinX...safeMaxX)
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
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        
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
