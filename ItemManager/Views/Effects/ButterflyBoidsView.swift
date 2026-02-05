import SwiftUI
import SpriteKit
import CoreMotion
import AVFoundation

struct ButterflyBoidsView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var scene: ButterflyScene?
    
    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: createScene(size: proxy.size), options: [.allowsTransparency])
                .background(Color.clear)
                .onAppear {
                    scene?.startSimulation()
                }
                .onDisappear {
                    scene?.stopSimulation()
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
        
        let newScene = ButterflyScene(size: size)
        newScene.scaleMode = .aspectFill
        newScene.backgroundColor = .clear
        
        // 延迟赋值给 state，避免视图更新时的冲突
        DispatchQueue.main.async {
            self.scene = newScene
        }
        
        return newScene
    }
}

class ButterflyScene: SKScene {
    // Boids 参数
    private let numBoids = 30
    private let visualRange: CGFloat = 80.0
    private let protectedRange: CGFloat = 20.0
    private let centeringFactor: CGFloat = 0.005 // 凝聚
    private let avoidFactor: CGFloat = 0.05      // 分离
    private let matchingFactor: CGFloat = 0.05   // 对齐
    private let turnFactor: CGFloat = 0.2        // 边界转向
    private let maxSpeed: CGFloat = 6.0
    private let minSpeed: CGFloat = 3.0
    
    private var boids: [BoidNode] = []
    private var isSimulationActive = false
    
    // 音效与震动
    private var wingSoundURL: URL?
    private let hapticEngine = UIImpactFeedbackGenerator(style: .light)
    private var lastHapticTime: TimeInterval = 0
    
    override func didMove(to view: SKView) {
        setupBoids()
        setupAudio()
        hapticEngine.prepare()
    }
    
    private func setupAudio() {
        wingSoundURL = AudioGenerator.generateWingFlapSound()
    }
    
    private func setupBoids() {
        // 清理旧的
        boids.forEach { $0.removeFromParent() }
        boids.removeAll()
        
        // 生成蝴蝶纹理
        let butterflyTexture = createButterflyTexture()
        
        for _ in 0..<numBoids {
            let boid = BoidNode(texture: butterflyTexture)
            // 随机位置
            boid.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            // 随机速度
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: minSpeed...maxSpeed)
            boid.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
            
            addChild(boid)
            boids.append(boid)
            
            // 启动扇动翅膀动画
            boid.startFlapping()
        }
    }
    
    func startSimulation() {
        isSimulationActive = true
    }
    
    func stopSimulation() {
        isSimulationActive = false
    }
    
    override func update(_ currentTime: TimeInterval) {
        guard isSimulationActive else { return }
        
        // 偶尔触发轻微震动
        if currentTime - lastHapticTime > 0.5 {
            // 只有当有蝴蝶在快速移动或转向时才震动，这里简单模拟
            if Bool.random() { 
                hapticEngine.impactOccurred(intensity: 0.3)
                lastHapticTime = currentTime
            }
        }
        
        // 更新每只蝴蝶
        for boid in boids {
            updateBoid(boid)
        }
        
        // 随机播放音效
        if Int.random(in: 0...100) < 5 { // 5% chance per frame
             playWingSound()
        }
    }
    
    private var audioPlayer: AVAudioPlayer?
    private func playWingSound() {
        guard let url = wingSoundURL else { return }
        do {
            if audioPlayer == nil {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.volume = 0.1 // 声音小一点
                audioPlayer?.prepareToPlay()
            }
            
            if audioPlayer?.isPlaying == false {
                audioPlayer?.play()
            }
        } catch {
            print("Failed to play sound: \(error)")
        }
    }
    
    private func updateBoid(_ boid: BoidNode) {
        var closeDx: CGFloat = 0
        var closeDy: CGFloat = 0
        var xVelAvg: CGFloat = 0
        var yVelAvg: CGFloat = 0
        var xPosAvg: CGFloat = 0
        var yPosAvg: CGFloat = 0
        var neighboringBoids: CGFloat = 0
        
        for otherBoid in boids {
            if boid === otherBoid { continue }
            
            let dx = boid.position.x - otherBoid.position.x
            let dy = boid.position.y - otherBoid.position.y
            let distSq = dx*dx + dy*dy
            
            if distSq < visualRange * visualRange {
                // Separation (Avoidance)
                if distSq < protectedRange * protectedRange {
                    closeDx += dx
                    closeDy += dy
                }
                
                // Alignment & Cohesion accumulators
                xVelAvg += otherBoid.velocity.dx
                yVelAvg += otherBoid.velocity.dy
                xPosAvg += otherBoid.position.x
                yPosAvg += otherBoid.position.y
                neighboringBoids += 1
            }
        }
        
        if neighboringBoids > 0 {
            xVelAvg /= neighboringBoids
            yVelAvg /= neighboringBoids
            xPosAvg /= neighboringBoids
            yPosAvg /= neighboringBoids
            
            // Alignment
            boid.velocity.dx += (xVelAvg - boid.velocity.dx) * matchingFactor
            boid.velocity.dy += (yVelAvg - boid.velocity.dy) * matchingFactor
            
            // Cohesion
            boid.velocity.dx += (xPosAvg - boid.position.x) * centeringFactor
            boid.velocity.dy += (yPosAvg - boid.position.y) * centeringFactor
        }
        
        // Separation applied
        boid.velocity.dx += closeDx * avoidFactor
        boid.velocity.dy += closeDy * avoidFactor
        
        // Screen Edges (Soft boundaries)
        let margin: CGFloat = 50
        if boid.position.x < margin { boid.velocity.dx += turnFactor }
        if boid.position.x > size.width - margin { boid.velocity.dx -= turnFactor }
        if boid.position.y < margin { boid.velocity.dy += turnFactor }
        if boid.position.y > size.height - margin { boid.velocity.dy -= turnFactor }
        
        // Speed Limit
        let speed = sqrt(boid.velocity.dx * boid.velocity.dx + boid.velocity.dy * boid.velocity.dy)
        if speed > maxSpeed {
            boid.velocity.dx = (boid.velocity.dx / speed) * maxSpeed
            boid.velocity.dy = (boid.velocity.dy / speed) * maxSpeed
        } else if speed < minSpeed {
            boid.velocity.dx = (boid.velocity.dx / speed) * minSpeed
            boid.velocity.dy = (boid.velocity.dy / speed) * minSpeed
        }
        
        // Update Position
        boid.position.x += boid.velocity.dx
        boid.position.y += boid.velocity.dy
        
        // Update Rotation (Face forward)
        boid.zRotation = atan2(boid.velocity.dy, boid.velocity.dx) - .pi / 2
    }
    
    private func createButterflyTexture() -> SKTexture {
        let size = CGSize(width: 30, height: 30)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let str = "🦋" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24)]
            let textSize = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(x: (size.width - textSize.width)/2, y: (size.height - textSize.height)/2), withAttributes: attrs)
        }
        return SKTexture(image: image)
    }
}

class BoidNode: SKSpriteNode {
    var velocity: CGVector = .zero
    
    func startFlapping() {
        // 模拟翅膀扇动：通过 X 轴缩放
        let flapIn = SKAction.scaleX(to: 0.4, duration: 0.1)
        let flapOut = SKAction.scaleX(to: 1.0, duration: 0.1)
        let sequence = SKAction.sequence([flapIn, flapOut])
        // 随机初始延迟，避免整齐划一
        let wait = SKAction.wait(forDuration: Double.random(in: 0...0.2))
        run(SKAction.sequence([wait, SKAction.repeatForever(sequence)]))
    }
}
