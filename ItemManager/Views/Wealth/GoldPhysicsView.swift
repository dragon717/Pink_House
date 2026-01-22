import SwiftUI
import SpriteKit
import CoreMotion

struct GoldPhysicsView: View {
    let totalWeightGrams: Double
    let beanWeight: Double // Weight per real bean (e.g. 1g)
    
    @Environment(\.colorScheme) var colorScheme
    
    // Scene Configuration
    @State private var scene: GoldScene?
    
    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: createScene(size: proxy.size))
                // Transparent to let ZStack background show through if needed,
                // but we will manage background color in scene.
                .background(Color.clear) 
                .ignoresSafeArea()
                .onAppear {
                    // Update bean count when view appears
                    scene?.updateBeans(totalWeight: totalWeightGrams, beanWeight: beanWeight)
                }
                .onChange(of: totalWeightGrams) { _, newValue in
                    scene?.updateBeans(totalWeight: newValue, beanWeight: beanWeight)
                }
                .onChange(of: colorScheme) { _, newScheme in
                    scene?.updateBackgroundColor(for: newScheme)
                }
        }
    }
    
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

class GoldScene: SKScene {
    private let motionManager = CMMotionManager()
    private var beanNodes: [SKNode] = []
    
    // Config
    private let maxVisualBeans = 300 // Limit for performance
    private let beanRadius: CGFloat = 8.0
    private let bottomPadding: CGFloat = 100.0 // Reserve space for TabBar
    
    override func didMove(to view: SKView) {
        setupPhysicsBoundary()
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8) // Default gravity
        
        startMotionUpdates()
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
        let safeFrame = CGRect(
            x: frame.minX,
            y: frame.minY + bottomPadding,
            width: frame.width,
            height: frame.height - bottomPadding
        )
        physicsBody = SKPhysicsBody(edgeLoopFrom: safeFrame)
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        setupPhysicsBoundary()
    }
    
    func updateBeans(totalWeight: Double, beanWeight: Double) {
        // Calculate how many beans to show
        // If we have 100g and 1g/bean -> 100 beans.
        // If we have 1000g -> 1000 beans (too many? maybe limit).
        
        let totalRealBeans = Int(totalWeight / beanWeight)
        let beansToShow = min(totalRealBeans, maxVisualBeans)
        
        let currentCount = beanNodes.count
        
        if currentCount < beansToShow {
            // Add more
            addBeans(count: beansToShow - currentCount)
        } else if currentCount > beansToShow {
            // Remove some
            removeBeans(count: currentCount - beansToShow)
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
        // Create a visual gold bean
        // Use ShapeNode for vector drawing
        let node = SKShapeNode(circleOfRadius: beanRadius)
        
        // Gold Color Gradient simulation (Solid color for now, maybe simple shading)
        node.fillColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) // Gold
        node.strokeColor = UIColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0) // Darker gold stroke
        node.lineWidth = 1.0
        
        // Physics
        let body = SKPhysicsBody(circleOfRadius: beanRadius)
        body.mass = 0.002 // 2g visual mass
        body.restitution = 0.2 // Bounciness (low for gold, it's heavy/soft)
        body.friction = 0.5
        node.physicsBody = body
        
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
                // Scene X = -Device Y
                // Scene Y = Device X
                gravityX = -data.gravity.y
                gravityY = data.gravity.x
            case .landscapeRight:
                // Device rotated Left (Home button Right).
                // Device +X is Down in UI. Device +Y is Left in UI.
                // Scene X = Device Y
                // Scene Y = -Device X
                gravityX = data.gravity.y
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
