import SwiftUI
import Combine
import SpriteKit

class GoldTextureGenerator {
    static let shared = GoldTextureGenerator()
    
    private var cachedTexture: SKTexture?
    
    // 生成一个逼真的金豆纹理
    func getTexture() -> SKTexture {
        if let cached = cachedTexture {
            return cached
        }
        
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let cgContext = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            
            // 1. 基础形状（稍微不规则的圆形）
            // 为了简单，我们先画一个完美的圆，但在边缘做一些光影欺骗
            // 或者我们可以用 path 画一个稍微不规则的形状
            
            // 径向渐变模拟球体体积
            // 中心点稍微偏左上，模拟光源
            let gradientCenter = CGPoint(x: size.width * 0.35, y: size.height * 0.35)
            let radius = size.width * 0.5
            
            let colors = [
                UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1.0).cgColor, // 高光中心 (Pale Gold)
                UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0).cgColor, // 固有色 (Gold)
                UIColor(red: 0.85, green: 0.65, blue: 0.1, alpha: 1.0).cgColor, // 暗部 (Dark Gold)
                UIColor(red: 0.5, green: 0.35, blue: 0.05, alpha: 1.0).cgColor  // 边缘反光 (Bronze/Brown)
            ] as CFArray
            
            let locations: [CGFloat] = [0.0, 0.4, 0.7, 1.0]
            
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                cgContext.drawRadialGradient(
                    gradient,
                    startCenter: gradientCenter,
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                    endRadius: radius,
                    options: .drawsBeforeStartLocation
                )
            }
            
            // 2. 添加更强的高光 (Specular Highlight)
            // 在左上角画一个白色的模糊椭圆
            cgContext.saveGState()
            cgContext.setBlendMode(.screen)
            let highlightRect = CGRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.25, height: size.height * 0.2)
            let highlightPath = UIBezierPath(ovalIn: highlightRect)
            
            // 模糊填充
            // CoreGraphics 没有直接的模糊填充，我们用径向渐变模拟
            let highlightColors = [
                UIColor(white: 1.0, alpha: 0.9).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            if let highlightGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: highlightColors, locations: [0.0, 1.0]) {
                cgContext.drawRadialGradient(
                    highlightGradient,
                    startCenter: CGPoint(x: highlightRect.midX, y: highlightRect.midY),
                    startRadius: 0,
                    endCenter: CGPoint(x: highlightRect.midX, y: highlightRect.midY),
                    endRadius: highlightRect.width, // 稍微大一点
                    options: .drawsBeforeStartLocation
                )
            }
            cgContext.restoreGState()
            
            // 3. 边缘反光 (Rim Light) - 在右下角加一点点冷色反光增加金属感
            // 略过，为了性能和风格统一
            
            // 4. 刻字 "9999" (Embrossed effect)
            // 字体颜色比固有色深一点，且带有高光边
            let text = "9999" as NSString
            let fontSize = size.width * 0.25
            let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(red: 0.6, green: 0.4, blue: 0.0, alpha: 0.6) // 深色凹陷
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            // 绘制深色文字 (Shadow/Base)
            text.draw(in: textRect, withAttributes: attributes)
            
            // 绘制浅色高光边缘 (Highlight) - 稍微偏移一点点 (左上)
            let highlightAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 0.4) // 浅色高光
            ]
            let highlightTextRect = textRect.offsetBy(dx: -1, dy: -1)
            text.draw(in: highlightTextRect, withAttributes: highlightAttributes)
        }
        
        let texture = SKTexture(image: image)
        self.cachedTexture = texture
        return texture
    }
}
