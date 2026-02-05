import SwiftUI
import UIKit

// 自定义 UIView 子类，处理布局更新
class CelebrationUIView: UIView {
    var effect: CelebrationEffect?
    private var didSetup = false
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 确保 bounds 有效且未初始化过
        if !didSetup && bounds.width > 0 && bounds.height > 0 {
            if let effect = effect {
                CelebrationLauncher.launch(effect, from: self)
                didSetup = true
            }
        } else {
            // 如果布局发生显著变化，可能需要更新发射器位置
            // 这里我们主要关心 Fireworks 的中心点
            updateEmitterPositions()
        }
    }
    
    private func updateEmitterPositions() {
        guard let sublayers = layer.sublayers else { return }
        
        for sublayer in sublayers {
            if let emitter = sublayer as? CAEmitterLayer {
                // 根据发射器名称或特性来更新位置
                // 这里我们假设 Fireworks 是需要在中心发射的
                // 简单起见，如果它是 Fireworks 的主发射器，我们更新它
                // 但由于我们没有给 layer 命名，这里只能做通用假设或重新计算
                
                // 为了简单且健壮，我们在 launch 时最好给 layer 设置 name
                if emitter.name == "FireworksCenter" {
                    emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY * 0.8)
                } else if emitter.name == "ButterfliesEmitter" {
                     emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
                     emitter.emitterSize = CGSize(width: bounds.width, height: bounds.height)
                }
            }
        }
    }
}

struct CelebrationEmitterView: UIViewRepresentable {
    let effect: CelebrationEffect
    
    func makeUIView(context: Context) -> CelebrationUIView {
        let view = CelebrationUIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false // Allow clicks to pass through
        view.effect = effect
        return view
    }
    
    func updateUIView(_ uiView: CelebrationUIView, context: Context) {
        // Update logic is handled internally by CelebrationUIView
    }
}

class CelebrationLauncher {
    
    static func launch(_ effect: CelebrationEffect, from view: UIView) {
        switch effect {
        case .fireworks:
            launchFireworks(from: view)
        case .butterflies:
            launchButterflies(from: view)
        }
    }
    
    // MARK: - Fireworks
    static func launchFireworks(from view: UIView) {
        // Center Explosion "Bang" Effect
        let centerX = view.bounds.midX
        let centerY = view.bounds.midY * 0.8 // Slightly above center
        
        // 1. Main Explosion Emitter
        let explosionEmitter = CAEmitterLayer()
        explosionEmitter.name = "FireworksCenter"
        explosionEmitter.emitterPosition = CGPoint(x: centerX, y: centerY)
        explosionEmitter.emitterMode = .outline
        explosionEmitter.emitterShape = .circle
        explosionEmitter.emitterSize = CGSize(width: 10, height: 10) // Start small point
        explosionEmitter.renderMode = .additive
        
        // Spark Particle (The glowing lines)
        let spark = CAEmitterCell()
        spark.birthRate = 0 // Trigger manually via burst
        spark.lifetime = 3.0
        spark.lifetimeRange = 1.0
        spark.velocity = 250
        spark.velocityRange = 100
        spark.yAcceleration = 350 // Gravity
        spark.emissionRange = .pi * 2 // 360 degrees
        spark.scale = 0.3
        spark.scaleSpeed = 0 // Keep uniform size
        spark.spin = .pi
        spark.spinRange = .pi
        spark.alphaSpeed = -0.3 // Fade out
        spark.color = UIColor.systemYellow.cgColor
        spark.contents = createParticleImage(color: .white, shape: .square)?.cgImage
        
        // Add color variations
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemYellow, .systemPurple, .white]
        var cells: [CAEmitterCell] = []
        
        for color in colors {
            let cell = spark.copy() as! CAEmitterCell
            cell.color = color.cgColor
            cell.velocity = CGFloat.random(in: 200...400) // Varied speed for depth
            // We want a burst, so we set birthRate to 0 but will use a trick or just create many cells with high birthRate and stop immediately?
            // Better: CAEmitterLayer doesn't support "One Shot" natively easily.
            // Trick: Set birthRate high, then set to 0 after small delay.
            cell.birthRate = 200 // High rate for burst
            cells.append(cell)
        }
        
        explosionEmitter.emitterCells = cells
        view.layer.addSublayer(explosionEmitter)
        
        // Stop emission almost immediately to create a "Burst"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            explosionEmitter.birthRate = 0
        }
        
        // Cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            explosionEmitter.removeFromSuperlayer()
        }
        
        // 2. Secondary "Ring" Explosion (Shockwave feel)
        let ringEmitter = CAEmitterLayer()
        ringEmitter.name = "FireworksCenter" // Share same position logic
        ringEmitter.emitterPosition = CGPoint(x: centerX, y: centerY)
        ringEmitter.emitterMode = .outline
        ringEmitter.emitterShape = .circle
        ringEmitter.emitterSize = CGSize(width: 0, height: 0)
        ringEmitter.renderMode = .additive
        
        let ring = CAEmitterCell()
        ring.birthRate = 50
        ring.lifetime = 0.5
        ring.velocity = 300
        ring.scale = 0.1
        ring.alphaSpeed = -2
        ring.color = UIColor.white.withAlphaComponent(0.8).cgColor
        ring.contents = createParticleImage(color: .white, shape: .circle)?.cgImage
        
        ringEmitter.emitterCells = [ring]
        view.layer.addSublayer(ringEmitter)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ringEmitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ringEmitter.removeFromSuperlayer()
        }
    }
    
    // MARK: - Butterflies
    static func launchButterflies(from view: UIView) {
        let emitter = CAEmitterLayer()
        emitter.name = "ButterfliesEmitter"
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        emitter.emitterShape = .rectangle
        emitter.emitterSize = CGSize(width: view.bounds.width, height: view.bounds.height)
        
        let cell = CAEmitterCell()
        cell.contents = createParticleImage(color: .cyan, shape: .butterfly)?.cgImage
        cell.birthRate = 5
        cell.lifetime = 6.0
        cell.velocity = 50
        cell.velocityRange = 20
        cell.emissionRange = .pi * 2
        cell.scale = 0.4
        cell.scaleRange = 0.2
        cell.spin = 1
        cell.alphaSpeed = -0.1
        
        emitter.emitterCells = [cell]
        view.layer.addSublayer(emitter)
        
        stopEmitter(emitter, after: 3.0)
    }

    // MARK: - Helpers
    private static func stopEmitter(_ emitter: CAEmitterLayer, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            emitter.birthRate = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                emitter.removeFromSuperlayer()
            }
        }
    }
    
    enum ParticleShape {
        case circle, butterfly, square
    }

    private static func createParticleImage(color: UIColor, shape: ParticleShape) -> UIImage? {
        let size = CGSize(width: 30, height: 30)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(color.cgColor)
        
        switch shape {
        case .circle:
            context.fillEllipse(in: CGRect(x: 5, y: 5, width: 20, height: 20))
        case .square:
            context.fill(CGRect(x: 5, y: 5, width: 20, height: 20))
        case .butterfly:
             let str = "🦋" as NSString
             let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24)]
             let textSize = str.size(withAttributes: attrs)
             str.draw(at: CGPoint(x: (size.width - textSize.width)/2, y: (size.height - textSize.height)/2), withAttributes: attrs)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
