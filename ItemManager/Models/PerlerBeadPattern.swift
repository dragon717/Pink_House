//
//  PerlerBeadPattern.swift
//  ItemManager
//
//  拼豆/像素画数据模型
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - 拼豆/像素画类型
enum PerlerPatternType: String, Codable, CaseIterable, Identifiable {
    case perlerBeads = "拼豆"
    case pixelArt = "像素画"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .perlerBeads: return "circle.grid.2x2"
        case .pixelArt: return "square.grid.2x2"
        }
    }
}

// MARK: - 拼豆/像素画模型
@Model
final class PerlerBeadPattern {
    var id: UUID = UUID()
    var name: String = ""           // 名称
    var patternType: String = ""    // 类型: "拼豆" 或 "像素画"
    
    // 画布配置
    var resolution: Int = 64        // 分辨率 (4, 8, 16, 32, 64, 128, 144, 192)
    var paletteSize: Int = 48       // 颜色数量 (24, 48, 72, 96, 120)
    var canvasStyle: String = ""    // 样式: "pixelArt" 或 "perlerBeads"
    
    // 像素数据 - 存储颜色索引 (-1 表示空白/透明)
    var pixelData: [Int] = []
    
    // 调色板排序方式
    var paletteSortOrder: String = "byId"  // "byId" 或 "byHue"
    
    // 缩略图路径
    var thumbnailPath: String? = nil
    
    // 系统字段
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastModified: Date = Date()
    var sortIndex: Int = 0
    
    // MARK: - 计算属性
    
    var typeEnum: PerlerPatternType {
        PerlerPatternType(rawValue: patternType) ?? .perlerBeads
    }
    
    var resolutionEnum: PerlerBeadsConfig.Resolution {
        PerlerBeadsConfig.Resolution(rawValue: resolution) ?? .x64
    }
    
    var paletteSizeEnum: PerlerBeadsConfig.PaletteSize {
        PerlerBeadsConfig.PaletteSize(rawValue: paletteSize) ?? .c48
    }
    
    var canvasStyleEnum: PerlerBeadsConfig.CanvasStyle {
        canvasStyle == "pixelArt" ? .pixelArt : .perlerBeads
    }
    
    var paletteSortOrderEnum: BeadColorPalette.SortOrder {
        paletteSortOrder == "byHue" ? .byHue : .byId
    }
    
    /// 总像素数
    var totalPixels: Int {
        pixelData.filter { $0 >= 0 }.count
    }
    
    /// 使用的颜色种类数
    var usedColorCount: Int {
        Set(pixelData.filter { $0 >= 0 }).count
    }
    
    /// 是否有内容
    var hasContent: Bool {
        pixelData.contains { $0 >= 0 }
    }
    
    // MARK: - 初始化
    
    init(
        name: String,
        patternType: PerlerPatternType,
        resolution: PerlerBeadsConfig.Resolution,
        paletteSize: PerlerBeadsConfig.PaletteSize,
        canvasStyle: PerlerBeadsConfig.CanvasStyle,
        pixelData: [Int],
        paletteSortOrder: BeadColorPalette.SortOrder = .byId,
        thumbnailPath: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.patternType = patternType.rawValue
        self.resolution = resolution.rawValue
        self.paletteSize = paletteSize.rawValue
        self.canvasStyle = canvasStyle == .pixelArt ? "pixelArt" : "perlerBeads"
        self.pixelData = pixelData
        self.paletteSortOrder = paletteSortOrder == .byHue ? "byHue" : "byId"
        self.thumbnailPath = thumbnailPath
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastModified = Date()
    }
    
    // MARK: - 转换为 CanvasModel
    
    func toCanvasModel() -> PixelCanvasModel {
        PixelCanvasModel(
            resolution: resolutionEnum,
            paletteSize: paletteSizeEnum,
            canvasStyle: canvasStyleEnum,
            pixelData: pixelData,
            paletteSortOrder: paletteSortOrderEnum
        )
    }
    
    // MARK: - 从 CanvasModel 更新
    
    func update(from canvasModel: PixelCanvasModel, name: String? = nil) {
        if let newName = name {
            self.name = newName
        }
        self.resolution = canvasModel.resolution.rawValue
        self.paletteSize = canvasModel.paletteSize.rawValue
        self.canvasStyle = canvasModel.canvasStyle == .pixelArt ? "pixelArt" : "perlerBeads"
        self.pixelData = canvasModel.pixelData
        self.paletteSortOrder = canvasModel.paletteSortOrder == .byHue ? "byHue" : "byId"
        self.updatedAt = Date()
        self.lastModified = Date()
    }
    
    // MARK: - 生成缩略图
    
    func generateThumbnail() -> UIImage? {
        let canvasModel = toCanvasModel()
        return canvasModel.toUIImage(scale: 4)
    }
}

// MARK: - 扩展 PerlerBeadPattern 用于显示

extension PerlerBeadPattern {
    /// 获取材料清单
    func getMaterialList() -> [(beadColor: BeadColor, count: Int)] {
        let palette = BeadColorPalette.colors(for: paletteSizeEnum, sortedBy: paletteSortOrderEnum)
        var counts: [String: Int] = [:]
        
        for colorIndex in pixelData {
            if colorIndex >= 0 && colorIndex < palette.count {
                let colorId = palette[colorIndex].id
                counts[colorId, default: 0] += 1
            }
        }
        
        return counts.compactMap { id, count in
            guard let color = palette.first(where: { $0.id == id }) else { return nil }
            return (beadColor: color, count: count)
        }.sorted { $0.count > $1.count }
    }
}
