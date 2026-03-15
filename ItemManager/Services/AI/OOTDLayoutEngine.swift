import Foundation
import UIKit

// MARK: - 布局信息结构体
struct LayoutInfo {
    let cutoutID: UUID
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let rotation: Double
    let zIndex: Int
}

// MARK: - OOTD 布局引擎
/// 负责计算抠图贴纸在画布上的不重合布局
/// 采用分级区域放置策略，确保搭配物品摆放美观且互不重叠
class OOTDLayoutEngine {
    static let shared = OOTDLayoutEngine()

    // 画布标准尺寸（与 OOTDCanvasView 保持一致）
    private let canvasWidth: CGFloat = 1080
    private let canvasHeight: CGFloat = 1440

    // 画布中心点
    private var canvasCenter: CGPoint {
        CGPoint(x: canvasWidth / 2, y: canvasHeight / 2)
    }

    // MARK: - 区域定义

    /// 画布逻辑区域
    private enum Zone {
        case dress      // 裙装区 - 中心偏下（主体）
        case top        // 上衣区 - 中心偏上
        case shoes      // 鞋履区 - 底部
        case accessory  // 配饰区 - 两侧

        /// 区域锚点（理想中心位置）
        var anchorPoint: CGPoint {
            switch self {
            case .dress:
                // 裙装区：中心偏下，占据视觉焦点
                return CGPoint(x: 540, y: 750)
            case .top:
                // 上衣区：中心偏上
                return CGPoint(x: 540, y: 380)
            case .shoes:
                // 鞋履区：底部
                return CGPoint(x: 540, y: 1180)
            case .accessory:
                // 配饰区：默认左侧，使用时动态调整
                return CGPoint(x: 180, y: 600)
            }
        }

        /// 区域范围（用于约束物品不超出边界）
        var bounds: CGRect {
            switch self {
            case .dress:
                return CGRect(x: 200, y: 500, width: 680, height: 500)
            case .top:
                return CGRect(x: 250, y: 200, width: 580, height: 360)
            case .shoes:
                return CGRect(x: 300, y: 1050, width: 480, height: 300)
            case .accessory:
                return CGRect(x: 50, y: 300, width: 980, height: 800)
            }
        }
    }

    // MARK: - 类别映射

    /// 类别到区域的映射
    private func zone(for category: String) -> Zone {
        let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "裙装":
            return .dress
        case "外套", "上衣":
            return .top
        case "鞋子":
            return .shoes
        case "配饰", "包包", "袜子", "裤子":
            return .accessory
        default:
            // 默认根据关键词判断
            if normalized.contains("裙") || normalized.contains(" dress") {
                return .dress
            } else if normalized.contains("鞋") || normalized.contains("shoe") {
                return .shoes
            } else if normalized.contains("配饰") || normalized.contains("包") || normalized.contains("袜") {
                return .accessory
            }
            return .accessory
        }
    }

    /// 类别放置优先级（数值越高越先放置）
    private func priority(for category: String) -> Int {
        let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "裙装":
            return 5
        case "外套":
            return 4
        case "上衣":
            return 3
        case "鞋子":
            return 2
        case "配饰", "包包":
            return 1
        case "袜子", "裤子":
            return 0
        default:
            return 1
        }
    }

    /// 类别基础尺寸（决定贴纸在画布上的相对大小）
    private func baseSize(for category: String) -> CGFloat {
        let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "裙装":
            return 450  // 裙装最大，作为视觉主体
        case "外套":
            return 380  // 外套次之
        case "上衣":
            return 320  // 上衣
        case "鞋子":
            return 220  // 鞋子适中
        case "配饰":
            return 150  // 配饰较小
        case "包包":
            return 180  // 包包
        case "袜子":
            return 120  // 袜子最小
        case "裤子":
            return 280  // 裤子
        default:
            return 200  // 默认尺寸
        }
    }

    // MARK: - 核心布局算法

    /// 计算布局
    /// - Parameters:
    ///   - cutouts: 要放置的抠图项数组
    ///   - canvasType: 画布类型（影响布局策略）
    /// - Returns: 每个 cutout 对应的布局信息数组
    func calculateLayout(for cutouts: [CutoutItem], canvasType: String = "mannequin") -> [LayoutInfo] {
        guard !cutouts.isEmpty else { return [] }

        var layouts: [LayoutInfo] = []
        var placedRects: [CGRect] = []

        // 按优先级排序：高优先级先放置
        let sortedCutouts = cutouts.sorted { c1, c2 in
            priority(for: c1.category) > priority(for: c2.category)
        }

        // 统计各区域物品数量，用于动态调整配饰位置
        var accessoryCount = 0

        for (index, cutout) in sortedCutouts.enumerated() {
            let zone = zone(for: cutout.category)

            // 计算基础尺寸（保持原始宽高比）
            let baseWidth = baseSize(for: cutout.category)
            let aspectRatio = cutout.width / max(cutout.height, 1) // 防止除零
            let size = CGSize(
                width: baseWidth,
                height: baseWidth / aspectRatio
            )

            // 确定锚点
            var anchor = zone.anchorPoint

            // 配饰类动态分布：左右交替
            if zone == .accessory {
                if accessoryCount % 2 == 0 {
                    // 左侧配饰
                    anchor = CGPoint(x: 150, y: 500 + CGFloat(accessoryCount / 2) * 150)
                } else {
                    // 右侧配饰
                    anchor = CGPoint(x: canvasWidth - 150, y: 500 + CGFloat(accessoryCount / 2) * 150)
                }
                accessoryCount += 1
            }

            // 尝试放置，处理碰撞
            let layout = tryPlaceItem(
                cutout: cutout,
                at: anchor,
                size: size,
                zone: zone,
                placedRects: placedRects,
                zIndex: index
            )

            layouts.append(layout)

            // 记录已放置的矩形（用于后续碰撞检测）
            let rect = CGRect(
                x: layout.x - size.width / 2,
                y: layout.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            placedRects.append(rect)
        }

        // 全局优化：整体居中
        return optimizeGlobalCenter(layouts: layouts, placedRects: placedRects)
    }

    /// 尝试放置单个物品
    /// - Parameters:
    ///   - cutout: 抠图项
    ///   - anchor: 锚点位置
    ///   - size: 目标尺寸
    ///   - zone: 所属区域
    ///   - placedRects: 已放置的矩形数组
    ///   - zIndex: 层级索引
    /// - Returns: 布局信息
    private func tryPlaceItem(
        cutout: CutoutItem,
        at anchor: CGPoint,
        size: CGSize,
        zone: Zone,
        placedRects: [CGRect],
        zIndex: Int
    ) -> LayoutInfo {
        var position = anchor
        var rect = CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        // 碰撞检测与修正
        var attempts = 0
        let maxAttempts = 20

        while collides(rect: rect, with: placedRects) && attempts < maxAttempts {
            // 根据区域决定修正方向
            let offset = calculateOffset(for: zone, attempt: attempts, anchor: anchor)
            position = CGPoint(
                x: anchor.x + offset.x,
                y: anchor.y + offset.y
            )

            // 确保不超出画布边界
            position = constrainToCanvas(position: position, size: size)

            rect = CGRect(
                x: position.x - size.width / 2,
                y: position.y - size.height / 2,
                width: size.width,
                height: size.height
            )

            attempts += 1
        }

        return LayoutInfo(
            cutoutID: cutout.id,
            x: position.x,
            y: position.y,
            scale: 1.0,
            rotation: 0,
            zIndex: zIndex
        )
    }

    /// 计算偏移量（用于碰撞修正）
    private func calculateOffset(for zone: Zone, attempt: Int, anchor: CGPoint) -> CGPoint {
        let baseSpacing: CGFloat = 60

        switch zone {
        case .dress:
            // 裙装：优先向左右扩展
            let directions: [CGPoint] = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: baseSpacing, y: 0),
                CGPoint(x: -baseSpacing, y: 0),
                CGPoint(x: 0, y: baseSpacing * 0.5),
                CGPoint(x: 0, y: -baseSpacing * 0.5),
                CGPoint(x: baseSpacing * 1.5, y: 0),
                CGPoint(x: -baseSpacing * 1.5, y: 0),
            ]
            return directions[min(attempt, directions.count - 1)]

        case .top:
            // 上衣：优先上下微调
            let directions: [CGPoint] = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 0, y: -baseSpacing * 0.5),
                CGPoint(x: baseSpacing, y: 0),
                CGPoint(x: -baseSpacing, y: 0),
                CGPoint(x: 0, y: baseSpacing * 0.5),
            ]
            return directions[min(attempt, directions.count - 1)]

        case .shoes:
            // 鞋子：左右分布
            let directions: [CGPoint] = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: baseSpacing, y: 0),
                CGPoint(x: -baseSpacing, y: 0),
                CGPoint(x: baseSpacing * 2, y: 0),
                CGPoint(x: -baseSpacing * 2, y: 0),
            ]
            return directions[min(attempt, directions.count - 1)]

        case .accessory:
            // 配饰：螺旋向外扩展
            let angle = Double(attempt) * 0.8 // 弧度
            let radius = baseSpacing * (1.0 + Double(attempt) * 0.3)
            return CGPoint(
                x: CGFloat(cos(angle) * radius),
                y: CGFloat(sin(angle) * radius * 0.5) // Y轴压缩，保持横向分布
            )
        }
    }

    /// 碰撞检测
    private func collides(rect: CGRect, with placedRects: [CGRect]) -> Bool {
        // 添加安全边距
        let margin: CGFloat = 20
        let expandedRect = rect.insetBy(dx: -margin, dy: -margin)

        for placed in placedRects {
            if expandedRect.intersects(placed) {
                return true
            }
        }
        return false
    }

    /// 约束位置不超出画布边界
    private func constrainToCanvas(position: CGPoint, size: CGSize) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2

        let minX = halfWidth + 20
        let maxX = canvasWidth - halfWidth - 20
        let minY = halfHeight + 20
        let maxY = canvasHeight - halfHeight - 20

        return CGPoint(
            x: max(minX, min(maxX, position.x)),
            y: max(minY, min(maxY, position.y))
        )
    }

    // MARK: - 全局优化

    /// 优化整体布局居中
    private func optimizeGlobalCenter(layouts: [LayoutInfo], placedRects: [CGRect]) -> [LayoutInfo] {
        guard !layouts.isEmpty else { return layouts }

        // 计算所有物品的外接矩形
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity

        for (index, layout) in layouts.enumerated() {
            let rect = placedRects[index]
            minX = min(minX, rect.minX)
            maxX = max(maxX, rect.maxX)
            minY = min(minY, rect.minY)
            maxY = max(maxY, rect.maxY)
        }

        // 计算外接矩形的中心
        let boundingCenterX = (minX + maxX) / 2
        let boundingCenterY = (minY + maxY) / 2

        // 计算需要移动的偏移量（使外接矩形居中于画布）
        let offsetX = canvasCenter.x - boundingCenterX
        let offsetY = canvasCenter.y - boundingCenterY

        // 应用偏移（限制在一定范围内，避免过度偏移）
        let limitedOffsetX = max(-100, min(100, offsetX))
        let limitedOffsetY = max(-100, min(100, offsetY))

        // 更新所有布局
        return layouts.map { layout in
            LayoutInfo(
                cutoutID: layout.cutoutID,
                x: layout.x + limitedOffsetX,
                y: layout.y + limitedOffsetY,
                scale: layout.scale,
                rotation: layout.rotation,
                zIndex: layout.zIndex
            )
        }
    }

    // MARK: - 便捷方法

    /// 为搭配建议创建 Outfit 并添加物品
    /// - Parameters:
    ///   - cutouts: 选中的抠图项
    ///   - book: 所属书组
    ///   - description: 搭配描述
    /// - Returns: 创建的 Outfit
    func createOutfitWithLayout(
        cutouts: [CutoutItem],
        book: BookGroup? = nil,
        description: String = "AI搭配"
    ) -> Outfit {
        // 计算布局
        let layouts = calculateLayout(for: cutouts)

        // 创建 Outfit
        let outfit = Outfit(
            note: description,
            canvasType: "mannequin",
            book: book
        )

        // 创建 OutfitItem 并应用布局
        var items: [OutfitItem] = []
        for (index, cutout) in cutouts.enumerated() {
            if let layout = layouts.first(where: { $0.cutoutID == cutout.id }) {
                let item = OutfitItem(
                    cutout: cutout,
                    x: Double(layout.x),
                    y: Double(layout.y),
                    rotation: layout.rotation,
                    scale: Double(layout.scale),
                    zIndex: layout.zIndex
                )
                // 设置双向关系
                item.outfit = outfit
                items.append(item)
            }
        }

        outfit.items = items
        return outfit
    }
}

// MARK: - 调试扩展

extension OOTDLayoutEngine {
    /// 调试打印布局信息
    func debugPrint(layouts: [LayoutInfo], cutouts: [CutoutItem]) {
        print("=== OOTDLayoutEngine Debug ===")
        print("画布尺寸: \(canvasWidth) x \(canvasHeight)")
        print("物品数量: \(layouts.count)")

        for layout in layouts {
            if let cutout = cutouts.first(where: { $0.id == layout.cutoutID }) {
                print("""
                [\(cutout.category)] \(cutout.clothingName ?? "未命名")
                  位置: (\(String(format: "%.1f", layout.x)), \(String(format: "%.1f", layout.y)))
                  缩放: \(String(format: "%.2f", layout.scale))
                  层级: \(layout.zIndex)
                """)
            }
        }
        print("================================")
    }
}
