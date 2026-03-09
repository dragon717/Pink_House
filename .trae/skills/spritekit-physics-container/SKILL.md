---
name: "spritekit-physics-container"
description: "Creates SpriteKit physics containers with 3D textures, haptic feedback, and sound effects. Invoke when implementing physics-based visual effects like falling coins, beans, or particles in SwiftUI."
---

# SpriteKit Physics Container Skill

## Purpose

This skill guides the implementation of SpriteKit-based physics containers in SwiftUI, featuring:
- 3D textured physics objects
- Collision-based haptic feedback
- Sound effects
- Performance optimization
- Lifecycle management

## When to Invoke

- Implementing physics-based visual effects (falling coins, beans, particles)
- Creating interactive physics simulations
- Adding tactile feedback to wealth/currency displays
- Building gamified UI elements with physics

## Implementation Steps

### 1. Create Texture Generator

```swift
class TextureGenerator {
    static let shared = TextureGenerator()
    private var cachedTexture: SKTexture?
    
    func getTexture() -> SKTexture {
        if let cached = cachedTexture {
            return cached
        }
        
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let cgContext = context.cgContext
            
            // 1. Radial gradient for 3D sphere effect
            let colors = [
                UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1.0).cgColor,
                UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0).cgColor,
                UIColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1.0).cgColor,
                UIColor(red: 0.7, green: 0.5, blue: 0.05, alpha: 1.0).cgColor
            ] as CFArray
            
            let locations: [CGFloat] = [0.0, 0.4, 0.7, 1.0]
            
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                cgContext.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: size.width * 0.35, y: size.height * 0.35),
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                    endRadius: size.width * 0.5,
                    options: .drawsBeforeStartLocation
                )
            }
            
            // 2. Specular highlight
            cgContext.saveGState()
            cgContext.setBlendMode(.screen)
            let highlightColors = [
                UIColor(white: 1.0, alpha: 0.8).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            if let highlightGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: highlightColors, locations: [0.0, 1.0]) {
                cgContext.drawRadialGradient(
                    highlightGradient,
                    startCenter: CGPoint(x: size.width * 0.3, y: size.height * 0.3),
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width * 0.3, y: size.height * 0.3),
                    endRadius: size.width * 0.2,
                    options: .drawsBeforeStartLocation
                )
            }
            cgContext.restoreGState()
            
            // 3. Icon or pattern
            // Add your icon here
        }
        
        let texture = SKTexture(image: image)
        self.cachedTexture = texture
        return texture
    }
}
```

### 2. Create Physics Container View

```swift
struct PhysicsContainerView: View {
    @Environment(\.isSimulationActive) var isSimulationActive
    @Environment(\.isWealthStorageActive) var isWealthStorageActive
    @Environment(\.scenePhase) var scenePhase
    
    @StateObject private var mediaStateManager = MediaStateManager.shared
    @State private var scene: PhysicsScene?
    @State private var isViewVisible: Bool = false
    
    let objectCount: Int
    
    private var shouldPause: Bool {
        !isViewVisible || 
        scenePhase != .active || 
        !isSimulationActive || 
        !isWealthStorageActive || 
        mediaStateManager.isPhysicsPaused
    }
    
    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: createScene(size: proxy.size),
                isPaused: shouldPause,
                options: [.allowsTransparency]
            )
            .background(Color.clear)
            .onAppear {
                isViewVisible = true
                HapticEngineManager.shared.resumeHaptics()
            }
            .onDisappear {
                isViewVisible = false
                scene?.pauseSimulation()
                HapticEngineManager.shared.stopHaptics()
                SoundManager.shared.stopAllSounds()
            }
            .onChange(of: objectCount) { _, newValue in
                scene?.updateObjectCount(newValue)
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
        
        let newScene = PhysicsScene(size: size)
        newScene.scaleMode = .aspectFill
        newScene.updateObjectCount(objectCount)
        
        DispatchQueue.main.async {
            if self.scene == nil {
                self.scene = newScene
            }
        }
        
        return newScene
    }
}
```

### 3. Create Physics Scene

```swift
class PhysicsScene: SKScene, SKPhysicsContactDelegate {
    private let motionManager = CMMotionManager()
    private let objectRadius: CGFloat = 12.0
    private let maxObjects = 100
    private var objectNodes: [SKNode] = []
    private var targetObjectCount: Int = 0
    private let objectsPerFrameAdd: Int = 20
    private let objectsPerFrameRemove: Int = 30
    
    // Haptic control
    private var lastHapticTime: TimeInterval = 0
    private let hapticMinInterval: TimeInterval = 0.08
    private var frameMaxImpulse: CGFloat = 0.0
    private var frameContactPoint: CGPoint = .zero
    private var frameCollisionCount: Int = 0
    private var isWallCollisionFrame: Bool = false
    
    func updateObjectCount(_ count: Int) {
        self.targetObjectCount = min(count, maxObjects)
    }
    
    func pauseSimulation() {
        self.isPaused = true
        motionManager.stopDeviceMotionUpdates()
        HapticEngineManager.shared.updateHapticParameters(intensity: 0, sharpness: 0)
        HapticEngineManager.shared.stopHaptics()
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
        startMotionUpdates()
    }
    
    override func update(_ currentTime: TimeInterval) {
        guard !isPaused else { return }
        
        processObjectQueue()
        
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
            
            if (contact.bodyA.categoryBitMask == PhysicsCategory.wall) ||
               (contact.bodyB.categoryBitMask == PhysicsCategory.wall) {
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
            sharpness = 0.9
            impactType = .hard
        } else {
            let baseIntensity = Float(min(frameMaxImpulse * 15.0, 1.0))
            normalizedIntensity = baseIntensity * 0.6
            sharpness = 0.4
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
    
    private func processObjectQueue() {
        let currentCount = objectNodes.count
        
        if currentCount < targetObjectCount {
            let countToAdd = min(objectsPerFrameAdd, targetObjectCount - currentCount)
            for _ in 0..<countToAdd {
                let node = createObjectNode()
                spawnNode(node)
                objectNodes.append(node)
            }
        } else if currentCount > targetObjectCount {
            let countToRemove = min(objectsPerFrameRemove, currentCount - targetObjectCount)
            for _ in 0..<countToRemove {
                if let node = objectNodes.popLast() {
                    node.removeFromParent()
                }
            }
        }
    }
    
    private func spawnNode(_ node: SKNode) {
        let safeMinX = objectRadius
        let safeMaxX = size.width - objectRadius
        guard safeMaxX > safeMinX else { return }
        
        let randomX = CGFloat.random(in: safeMinX...safeMaxX)
        let spawnY = size.height - objectRadius - 20
        
        node.position = CGPoint(x: randomX, y: spawnY)
        addChild(node)
    }
    
    private func createObjectNode() -> SKNode {
        let texture = TextureGenerator.shared.getTexture()
        let node = SKSpriteNode(texture: texture)
        let diameter = objectRadius * 2
        node.size = CGSize(width: diameter, height: diameter)
        
        let body = SKPhysicsBody(circleOfRadius: objectRadius)
        body.mass = 0.002
        body.restitution = 0.2
        body.friction = 0.5
        body.allowsRotation = true
        
        let isSensor = Int.random(in: 1...10) == 1
        body.categoryBitMask = PhysicsCategory.object
        body.collisionBitMask = PhysicsCategory.object | PhysicsCategory.wall
        body.contactTestBitMask = isSensor ? (PhysicsCategory.object | PhysicsCategory.wall) : 0
        
        node.physicsBody = body
        node.zRotation = CGFloat.random(in: 0...(2 * .pi))
        
        return node
    }
    
    private func setupPhysicsBoundary() {
        let boundaryRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        physicsBody = SKPhysicsBody(edgeLoopFrom: boundaryRect)
        physicsBody?.categoryBitMask = PhysicsCategory.wall
        physicsBody?.collisionBitMask = PhysicsCategory.object
        physicsBody?.contactTestBitMask = PhysicsCategory.object
        physicsBody?.restitution = 0.2
        physicsBody?.friction = 0.3
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
            
            self.physicsWorld.gravity = CGVector(dx: gravityX * 15, dy: gravityY * 15)
        }
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let wall: UInt32 = 0b1
    static let object: UInt32 = 0b10
}
```

## Key Principles

1. **Lifecycle Management**: Use environment variables to control physics simulation state
2. **Performance**: Batch object creation/removal, limit collision detection to 10% of objects
3. **Haptics**: Aggregate collision data per frame, throttle to 0.08s intervals
4. **State Safety**: Use async dispatch when assigning to @State during view updates
5. **Visual Quality**: Use radial gradients and specular highlights for 3D effect

## References

- GoldPhysicsView.swift - Gold bean physics implementation
- SilverPhysicsView.swift - Silver bead physics implementation
- VirtualCurrencyView.swift - Virtual coin physics implementation
- docs/SPRITEKIT_PHYSICS_BEST_PRACTICES.md - Detailed best practices
