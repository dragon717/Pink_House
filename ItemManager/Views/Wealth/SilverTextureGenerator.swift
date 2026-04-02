import SwiftUI
import Combine
import SpriteKit

class SilverTextureGenerator {
    static let shared = SilverTextureGenerator()
    
    private var cachedTexture: SKTexture?
    
    // 生成一个逼真的银元宝/银豆纹理
    func getTexture() -> SKTexture {
        if let cached = cachedTexture {
            return cached
        }
        
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let cgContext = context.cgContext
            // let rect = CGRect(origin: .zero, size: size)
            
            // 1. 基础形状（圆形）
            
            // 径向渐变模拟球体体积
            // 中心点稍微偏左上，模拟光源
            let gradientCenter = CGPoint(x: size.width * 0.35, y: size.height * 0.35)
            let radius = size.width * 0.5
            
            // 银色系
            let colors = [
                UIColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1.0).cgColor, // 高光中心 (White Silver)
                UIColor(red: 0.85, green: 0.85, blue: 0.90, alpha: 1.0).cgColor, // 固有色 (Silver)
                UIColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1.0).cgColor, // 暗部 (Dark Silver)
                UIColor(red: 0.40, green: 0.40, blue: 0.45, alpha: 1.0).cgColor  // 边缘反光 (Gray)
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
            cgContext.saveGState()
            cgContext.setBlendMode(.screen)
            let highlightRect = CGRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.25, height: size.height * 0.2)
            // let highlightPath = UIBezierPath(ovalIn: highlightRect)
            
            // 模糊填充
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
                    endRadius: highlightRect.width,
                    options: .drawsBeforeStartLocation
                )
            }
            cgContext.restoreGState()
            
            // 3. 刻字 "Ag"
            let text = "Ag" as NSString
            let fontSize = size.width * 0.35
            let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(white: 0.3, alpha: 0.6) // 深色凹陷
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
            
            // 绘制浅色高光边缘 (Highlight)
            let highlightAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(white: 1.0, alpha: 0.4) // 浅色高光
            ]
            let highlightTextRect = textRect.offsetBy(dx: -1, dy: -1)
            text.draw(in: highlightTextRect, withAttributes: highlightAttributes)
        }
        
        let texture = SKTexture(image: image)
        self.cachedTexture = texture
        return texture
    }
}
