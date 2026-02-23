import SwiftUI
import SwiftData

// MARK: - 像素画布数据模型
@Observable
class PixelCanvasModel {

    // MARK: - 画布属性
    var resolution: PerlerBeadsConfig.Resolution
    var paletteSize: PerlerBeadsConfig.PaletteSize
    var canvasStyle: PerlerBeadsConfig.CanvasStyle

    // 像素数据 - 存储颜色索引 (-1 表示空白/透明)
    var pixelData: [Int]

    // 当前选中的颜色索引
    var selectedColorIndex: Int = 0

    // 可用颜色调色板
    var palette: [BeadColor]
    
    // 调色板排序方式
    var paletteSortOrder: BeadColorPalette.SortOrder = .byId {
        didSet {
            if paletteSortOrder != oldValue {
                updatePaletteSortOrder()
            }
        }
    }
    
    // 熨斗模式 - 显示填充的像素块而非拼豆圆形
    var isIronMode: Bool = false

    // 画布历史记录（用于撤销/重做）
    private var history: [[Int]] = []
    private var historyIndex: Int = -1
    private let maxHistoryCount = 50

    // MARK: - 初始化
    init(
        resolution: PerlerBeadsConfig.Resolution = PerlerBeadsConfig.defaultResolution,
        paletteSize: PerlerBeadsConfig.PaletteSize = PerlerBeadsConfig.defaultPaletteSize,
        canvasStyle: PerlerBeadsConfig.CanvasStyle = PerlerBeadsConfig.defaultCanvasStyle,
        pixelData: [Int]? = nil,
        paletteSortOrder: BeadColorPalette.SortOrder = .byId
    ) {
        self.resolution = resolution
        self.paletteSize = paletteSize
        self.canvasStyle = canvasStyle
        self.paletteSortOrder = paletteSortOrder
        self.palette = BeadColorPalette.colors(for: paletteSize, sortedBy: paletteSortOrder)

        let totalPixels = resolution.pixelCount
        if let data = pixelData, data.count == totalPixels {
            self.pixelData = data
        } else {
            // 默认填充为空白 (-1)
            self.pixelData = Array(repeating: -1, count: totalPixels)
        }

        // 初始化历史记录
        saveToHistory()
    }
    
    // 更新调色板排序
    private func updatePaletteSortOrder() {
        let currentColor = selectedColorIndex < palette.count ? palette[selectedColorIndex] : nil
        palette = BeadColorPalette.colors(for: paletteSize, sortedBy: paletteSortOrder)
        // 尝试保持选中颜色
        if let color = currentColor {
            selectedColorIndex = palette.firstIndex { $0.id == color.id } ?? 0
        }
    }

    // MARK: - 像素操作

    /// 获取指定坐标的颜色索引
    func getPixel(at x: Int, y: Int) -> Int {
        guard x >= 0, x < resolution.rawValue,
              y >= 0, y < resolution.rawValue else {
            return -1
        }
        let index = y * resolution.rawValue + x
        return pixelData[index]
    }

    /// 设置指定坐标的颜色索引
    func setPixel(at x: Int, y: Int, colorIndex: Int) {
        guard x >= 0, x < resolution.rawValue,
              y >= 0, y < resolution.rawValue else {
            return
        }
        let index = y * resolution.rawValue + x
        guard index < pixelData.count else { return }

        // 只有真正改变时才保存历史
        if pixelData[index] != colorIndex {
            pixelData[index] = colorIndex
        }
    }

    /// 使用当前选中的颜色绘制像素
    func drawPixel(at x: Int, y: Int) {
        setPixel(at: x, y: y, colorIndex: selectedColorIndex)
    }

    /// 擦除像素（设为空白）
    func erasePixel(at x: Int, y: Int) {
        setPixel(at: x, y: y, colorIndex: -1)
    }

    /// 清空画布
    func clearCanvas() {
        pixelData = Array(repeating: -1, count: resolution.pixelCount)
        saveToHistory()
    }

    /// 填充整个画布为当前选中颜色
    func fillCanvas() {
        pixelData = Array(repeating: selectedColorIndex, count: resolution.pixelCount)
        saveToHistory()
    }
    
    /// 填充指定位置的连通区域（洪水填充算法）
    func floodFill(at x: Int, y: Int) {
        guard x >= 0, x < resolution.rawValue,
              y >= 0, y < resolution.rawValue else { return }
        
        let targetIndex = y * resolution.rawValue + x
        guard targetIndex < pixelData.count else { return }
        
        let targetColor = pixelData[targetIndex]
        let fillColor = selectedColorIndex
        
        // 如果目标颜色已经是填充颜色，无需操作
        if targetColor == fillColor { return }
        
        // 洪水填充
        var stack: [(Int, Int)] = [(x, y)]
        var visited = Set<Int>()
        
        while !stack.isEmpty {
            let (cx, cy) = stack.removeLast()
            let index = cy * resolution.rawValue + cx
            
            guard !visited.contains(index),
                  index < pixelData.count,
                  pixelData[index] == targetColor else { continue }
            
            visited.insert(index)
            pixelData[index] = fillColor
            
            // 检查四个方向
            let directions = [(0, -1), (0, 1), (-1, 0), (1, 0)]
            for (dx, dy) in directions {
                let nx = cx + dx
                let ny = cy + dy
                if nx >= 0, nx < resolution.rawValue,
                   ny >= 0, ny < resolution.rawValue {
                    let nIndex = ny * resolution.rawValue + nx
                    if !visited.contains(nIndex) && pixelData[nIndex] == targetColor {
                        stack.append((nx, ny))
                    }
                }
            }
        }
        
        saveToHistory()
    }

    // MARK: - 历史记录（撤销/重做）

    func saveToHistory() {
        // 如果不在历史记录末尾，删除后面的记录
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }

        // 添加新记录
        history.append(pixelData)

        // 限制历史记录数量
        if history.count > maxHistoryCount {
            history.removeFirst()
        } else {
            historyIndex += 1
        }
    }

    func canUndo() -> Bool {
        return historyIndex > 0
    }

    func canRedo() -> Bool {
        return historyIndex < history.count - 1
    }

    func undo() {
        guard canUndo() else { return }
        historyIndex -= 1
        pixelData = history[historyIndex]
    }

    func redo() {
        guard canRedo() else { return }
        historyIndex += 1
        pixelData = history[historyIndex]
    }

    // MARK: - 调色板操作

    func updatePaletteSize(_ newSize: PerlerBeadsConfig.PaletteSize) {
        paletteSize = newSize
        palette = BeadColorPalette.colors(for: newSize, sortedBy: paletteSortOrder)

        // 调整现有像素数据，超出新调色板范围的颜色设为 -1
        let maxIndex = newSize.rawValue - 1
        for i in pixelData.indices {
            if pixelData[i] > maxIndex {
                pixelData[i] = -1
            }
        }

        // 确保选中颜色有效
        if selectedColorIndex > maxIndex {
            selectedColorIndex = 0
        }
    }
    
    /// 更新调色板排序方式
    func updatePaletteSortOrder(_ sortOrder: BeadColorPalette.SortOrder) {
        paletteSortOrder = sortOrder
    }
    
    // MARK: - 熨斗功能
    
    /// 熨斗功能：切换熨斗模式显示状态
    /// 开启时显示填充的像素块，关闭时显示拼豆圆形
    func toggleIronMode() {
        isIronMode.toggle()
    }

    // MARK: - 材料统计

    /// 统计每种颜色的使用数量
    func getMaterialList() -> [(beadColor: BeadColor, count: Int)] {
        var counts: [String: Int] = [:]

        for colorIndex in pixelData {
            if colorIndex >= 0 && colorIndex < palette.count {
                let colorId = palette[colorIndex].id
                counts[colorId, default: 0] += 1
            }
        }

        // 转换为数组并排序（按数量降序）
        return counts.compactMap { id, count in
            guard let color = palette.first(where: { $0.id == id }) else { return nil }
            return (beadColor: color, count: count)
        }.sorted { $0.count > $1.count }
    }

    /// 获取总像素数
    var totalBeads: Int {
        pixelData.filter { $0 >= 0 }.count
    }

    /// 获取使用的颜色种类数
    var usedColorCount: Int {
        Set(pixelData.filter { $0 >= 0 }).count
    }
    
    /// 是否有绘制内容
    var hasDrawing: Bool {
        pixelData.contains { $0 >= 0 }
    }

    // MARK: - 导出

    /// 将画布转换为 UIImage
    func toUIImage(scale: Int = 10) -> UIImage? {
        let size = resolution.rawValue
        let pixelSize = scale
        let imageSize = CGSize(width: size * pixelSize, height: size * pixelSize)

        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // 绘制背景（白色）
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: imageSize))

        // 绘制每个像素
        for y in 0..<size {
            for x in 0..<size {
                let colorIndex = getPixel(at: x, y: y)
                if colorIndex >= 0 && colorIndex < palette.count {
                    let color = palette[colorIndex].uiColor
                    let rect = CGRect(
                        x: x * pixelSize,
                        y: y * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.setFillColor(color.cgColor)
                    context.fill(rect)
                }
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    /// 生成带网格的图纸图片
    func toPatternImage(cellSize: CGFloat = 20) -> UIImage? {
        let size = resolution.rawValue
        let imageSize = CGSize(width: CGFloat(size) * cellSize + 1, height: CGFloat(size) * cellSize + 1)

        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // 绘制背景
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: imageSize))

        // 绘制每个格子
        for y in 0..<size {
            for x in 0..<size {
                let colorIndex = getPixel(at: x, y: y)
                let rect = CGRect(
                    x: CGFloat(x) * cellSize + 0.5,
                    y: CGFloat(y) * cellSize + 0.5,
                    width: cellSize - 1,
                    height: cellSize - 1
                )

                if colorIndex >= 0 && colorIndex < palette.count {
                    // 绘制颜色块
                    context.setFillColor(palette[colorIndex].uiColor.cgColor)
                    context.fill(rect)

                    // 绘制颜色编号
                    let text = palette[colorIndex].id as NSString
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: cellSize * 0.3),
                        .foregroundColor: UIColor.black
                    ]
                    let textSize = text.size(withAttributes: attributes)
                    let textRect = CGRect(
                        x: rect.midX - textSize.width / 2,
                        y: rect.midY - textSize.height / 2,
                        width: textSize.width,
                        height: textSize.height
                    )
                    text.draw(in: textRect, withAttributes: attributes)
                } else {
                    // 空白格子
                    context.setFillColor(UIColor(white: 0.95, alpha: 1.0).cgColor)
                    context.fill(rect)
                }

                // 绘制边框
                context.setStrokeColor(UIColor.lightGray.cgColor)
                context.setLineWidth(0.5)
                context.stroke(rect)
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

// MARK: - 图片转像素画处理器
enum PixelImageProcessor {

    /// 将图片转换为像素画数据
    static func convertImage(
        _ image: UIImage,
        to resolution: PerlerBeadsConfig.Resolution,
        paletteSize: PerlerBeadsConfig.PaletteSize
    ) -> [Int] {
        let palette = BeadColorPalette.colors(for: paletteSize)
        let size = resolution.rawValue

        // 1. 降采样 - 关闭抗锯齿保持像素感
        guard let pixelatedImage = downsampleImage(image, to: size) else {
            return Array(repeating: -1, count: size * size)
        }

        // 2. 颜色量化 - 映射到调色板
        return quantizeColors(pixelatedImage, palette: palette, size: size)
    }

    /// 降采样 - 将图片缩小到指定尺寸，保持比例并居中裁剪
    private static func downsampleImage(_ image: UIImage, to size: Int) -> UIImage? {
        let targetSize = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        // 计算图片在目标尺寸中的绘制区域（保持比例，居中裁剪）
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height

        var drawRect: CGRect
        if imageAspectRatio > 1.0 {
            // 图片更宽，以高度为基准，裁剪左右
            let drawWidth = CGFloat(size) * imageAspectRatio
            let drawHeight = CGFloat(size)
            let xOffset = (CGFloat(size) - drawWidth) / 2
            drawRect = CGRect(x: xOffset, y: 0, width: drawWidth, height: drawHeight)
        } else if imageAspectRatio < 1.0 {
            // 图片更高，以宽度为基准，裁剪上下
            let drawWidth = CGFloat(size)
            let drawHeight = CGFloat(size) / imageAspectRatio
            let yOffset = (CGFloat(size) - drawHeight) / 2
            drawRect = CGRect(x: 0, y: yOffset, width: drawWidth, height: drawHeight)
        } else {
            // 正方形图片，直接填充
            drawRect = CGRect(origin: .zero, size: targetSize)
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            // 关闭抗锯齿和插值，保留像素颗粒感
            context.cgContext.interpolationQuality = .none
            image.draw(in: drawRect)
        }
    }

    /// 颜色量化 - 将每个像素映射到最接近的调色板颜色
    private static func quantizeColors(_ image: UIImage, palette: [BeadColor], size: Int) -> [Int] {
        guard let cgImage = image.cgImage else {
            return Array(repeating: -1, count: size * size)
        }

        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = Array(repeating: -1, count: size * size)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return pixelData
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return pixelData }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = CGFloat(pixels[offset]) / 255.0
                let g = CGFloat(pixels[offset + 1]) / 255.0
                let b = CGFloat(pixels[offset + 2]) / 255.0
                let a = CGFloat(pixels[offset + 3]) / 255.0

                // 透明像素设为空白
                if a < 0.5 {
                    pixelData[y * size + x] = -1
                } else {
                    let uiColor = UIColor(red: r, green: g, blue: b, alpha: 1.0)
                    if let closestColor = BeadColorPalette.findClosestColor(to: uiColor, in: palette) {
                        if let index = palette.firstIndex(where: { $0.id == closestColor.id }) {
                            pixelData[y * size + x] = index
                        } else {
                            pixelData[y * size + x] = -1
                        }
                    } else {
                        pixelData[y * size + x] = -1
                    }
                }
            }
        }

        return pixelData
    }
}
