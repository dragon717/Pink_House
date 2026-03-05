import SwiftUI

// MARK: - 圆圈检测配置

struct CircleDetectionConfig {
    let minPoints: Int
    let closeThreshold: CGFloat
    let minDistance: CGFloat
    let minArea: CGFloat
    
    static let `default` = CircleDetectionConfig(
        minPoints: 20,
        closeThreshold: 80,
        minDistance: 250,
        minArea: 50 * 50
    )
}

// MARK: - 圆圈检测结果

struct CircleDetectionResult {
    let isDetected: Bool
    let boundingBox: CGRect?
    let loopPoints: [CGPoint]?
    
    static let notDetected = CircleDetectionResult(
        isDetected: false,
        boundingBox: nil,
        loopPoints: nil
    )
}

// MARK: - 圆圈检测器

class CircleDetector {
    static let shared = CircleDetector()
    
    private let config: CircleDetectionConfig
    
    init(config: CircleDetectionConfig = .default) {
        self.config = config
    }
    
    // MARK: - 核心检测方法
    
    /// 检测给定点序列是否形成圆圈
    /// - Parameter points: 点序列
    /// - Returns: (是否检测到圆圈, 包围盒)
    func detectCircle(in points: [CGPoint]) -> (Bool, CGRect?) {
        guard points.count >= config.minPoints else {
            return (false, nil)
        }
        
        let currentPoint = points.last!
        
        // 查找闭合点
        let minLoopIndex = points.count - config.minPoints
        
        guard minLoopIndex >= 0 else {
            return (false, nil)
        }
        
        // 从后向前查找闭合点
        for i in stride(from: minLoopIndex, through: 0, by: -1) {
            let candidatePoint = points[i]
            let distance = calculateDistance(from: candidatePoint, to: currentPoint)
            
            if distance < config.closeThreshold {
                // 找到可能的闭合点，提取环
                let loopPoints = Array(points[i..<points.count])
                
                // 验证环是否有效
                if validateLoop(loopPoints) {
                    let bbox = calculateBoundingBox(for: loopPoints)
                    return (true, bbox)
                }
            }
        }
        
        return (false, nil)
    }
    
    /// 检测给定点序列并返回详细结果
    /// - Parameter points: 点序列
    /// - Returns: 检测结果
    func detectCircleWithResult(in points: [CGPoint]) -> CircleDetectionResult {
        let (isDetected, bbox) = detectCircle(in: points)
        
        guard isDetected, let boundingBox = bbox else {
            return .notDetected
        }
        
        // 提取环的点
        let currentPoint = points.last!
        let minLoopIndex = points.count - config.minPoints
        
        for i in stride(from: minLoopIndex, through: 0, by: -1) {
            let candidatePoint = points[i]
            let distance = calculateDistance(from: candidatePoint, to: currentPoint)
            
            if distance < config.closeThreshold {
                let loopPoints = Array(points[i..<points.count])
                if validateLoop(loopPoints) {
                    return CircleDetectionResult(
                        isDetected: true,
                        boundingBox: boundingBox,
                        loopPoints: loopPoints
                    )
                }
            }
        }
        
        return .notDetected
    }
    
    // MARK: - 验证方法
    
    /// 验证环是否有效
    /// - Parameter points: 环的点序列
    /// - Returns: 是否有效
    private func validateLoop(_ points: [CGPoint]) -> Bool {
        // 检查路径长度
        guard calculatePathLength(points) >= config.minDistance else {
            return false
        }
        
        // 检查包围盒面积
        let bbox = calculateBoundingBox(for: points)
        guard bbox.width * bbox.height >= config.minArea else {
            return false
        }
        
        return true
    }
    
    /// 检查路径是否闭合（首尾点距离足够近）
    /// - Parameter points: 点序列
    /// - Returns: 是否闭合
    func isPathClosed(_ points: [CGPoint]) -> Bool {
        guard points.count >= config.minPoints else {
            return false
        }
        
        let firstPoint = points.first!
        let lastPoint = points.last!
        let distance = calculateDistance(from: firstPoint, to: lastPoint)
        
        return distance < config.closeThreshold
    }
    
    // MARK: - 计算方法
    
    /// 计算两点间距离
    /// - Parameters:
    ///   - p1: 点1
    ///   - p2: 点2
    /// - Returns: 距离
    private func calculateDistance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return hypot(dx, dy)
    }
    
    /// 计算路径长度
    /// - Parameter points: 点序列
    /// - Returns: 路径长度
    private func calculatePathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        
        var totalDistance: CGFloat = 0
        for i in 1..<points.count {
            totalDistance += calculateDistance(from: points[i-1], to: points[i])
        }
        return totalDistance
    }
    
    /// 计算点序列的包围盒
    /// - Parameter points: 点序列
    /// - Returns: 包围盒
    func calculateBoundingBox(for points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else {
            return .zero
        }
        
        var minX: CGFloat = CGFloat.infinity
        var minY: CGFloat = CGFloat.infinity
        var maxX: CGFloat = -CGFloat.infinity
        var maxY: CGFloat = -CGFloat.infinity
        
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
    
    /// 计算点序列的中心点
    /// - Parameter points: 点序列
    /// - Returns: 中心点
    func calculateCenter(for points: [CGPoint]) -> CGPoint {
        let bbox = calculateBoundingBox(for: points)
        return CGPoint(
            x: bbox.midX,
            y: bbox.midY
        )
    }
    
    /// 计算点序列的近似半径
    /// - Parameter points: 点序列
    /// - Returns: 近似半径
    func calculateApproximateRadius(for points: [CGPoint]) -> CGFloat {
        let bbox = calculateBoundingBox(for: points)
        return min(bbox.width, bbox.height) / 2
    }
}

// MARK: - 圆圈检测视图组件

struct CircleDetectionOverlay: View {
    let isTriggered: Bool
    let boundingBox: CGRect?
    let animation: Animation
    
    init(
        isTriggered: Bool,
        boundingBox: CGRect?,
        animation: Animation = .easeInOut(duration: 0.3)
    ) {
        self.isTriggered = isTriggered
        self.boundingBox = boundingBox
        self.animation = animation
    }
    
    var body: some View {
        ZStack {
            if isTriggered, let bbox = boundingBox {
                // 包围盒
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: 3,
                            dash: [10]
                        )
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: bbox.width, height: bbox.height)
                    .position(x: bbox.midX, y: bbox.midY)
                
                // 确认图标
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .background(Circle().fill(Color.mint))
                    .position(x: bbox.maxX, y: bbox.minY)
                    .offset(x: 10, y: -10)
            }
        }
        .animation(animation, value: isTriggered)
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.black.opacity(0.1)
        
        CircleDetectionOverlay(
            isTriggered: true,
            boundingBox: CGRect(x: 100, y: 100, width: 200, height: 200)
        )
    }
}
