import SwiftUI

// MARK: - 拼豆配置管理
enum PerlerBeadsConfig {

    // MARK: - 分辨率选项
    enum Resolution: Int, CaseIterable, Identifiable {
        case x4 = 4
        case x8 = 8
        case x16 = 16
        case x32 = 32
        case x64 = 64      // 默认
        case x128 = 128
        case x144 = 144
        case x192 = 192

        var id: Int { self.rawValue }
        var description: String { "\(self.rawValue) x \(self.rawValue)" }
        var pixelCount: Int { self.rawValue * self.rawValue }
    }

    // MARK: - 颜色数量选项
    enum PaletteSize: Int, CaseIterable, Identifiable {
        case c24 = 24
        case c48 = 48     // 默认
        case c72 = 72
        case c96 = 96
        case c120 = 120

        var id: Int { self.rawValue }
        var description: String { "\(self.rawValue) 色" }
    }

    // MARK: - 画布样式
    enum CanvasStyle {
        case pixelArt     // 像素风格 - 方形
        case perlerBeads  // 拼豆风格 - 圆形带孔

        var displayName: String {
            switch self {
            case .pixelArt: return "像素风格"
            case .perlerBeads: return "拼豆图纸"
            }
        }
    }

    // MARK: - 默认配置
    static let defaultResolution: Resolution = .x64
    static let defaultPaletteSize: PaletteSize = .c48
    static let defaultCanvasStyle: CanvasStyle = .perlerBeads

    // MARK: - 画布渲染配置
    static let gridLineWidth: CGFloat = 0.5
    static let gridLineColor = Color.gray.opacity(0.3)
    static let beadGap: CGFloat = 0.15  // 拼豆之间的间隙比例

    // MARK: - 缩放限制
    static let minZoomScale: CGFloat = 0.5
    static let maxZoomScale: CGFloat = 5.0
}

// MARK: - 拼豆颜色定义
struct BeadColor: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let r: Double
    let g: Double
    let b: Double
    var count: Int = 0  // 使用数量（非持久化）

    var color: Color {
        Color(red: r, green: g, blue: b)
    }

    var uiColor: UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    // 计算颜色距离（欧几里得距离）
    func distance(to other: BeadColor) -> Double {
        let dr = r - other.r
        let dg = g - other.g
        let db = b - other.b
        return sqrt(dr*dr + dg*dg + db*db)
    }

    // 从UIColor计算距离
    func distance(to uiColor: UIColor) -> Double {
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        uiColor.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let dr = r - Double(r2)
        let dg = g - Double(g2)
        let db = b - Double(b2)
        return sqrt(dr*dr + dg*dg + db*db)
    }
    
    // 计算色相 (0-360)
    var hue: Double {
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal
        
        guard delta > 0 else { return 0 }
        
        var h: Double = 0
        if maxVal == r {
            h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxVal == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        
        h *= 60
        if h < 0 { h += 360 }
        return h
    }
    
    // 计算亮度 (0-1)
    var brightness: Double {
        return max(r, max(g, b))
    }
}

// MARK: - 标准拼豆色卡 (基于常见拼豆品牌)
enum BeadColorPalette {

    // 120色完整色卡
    static let standard120: [BeadColor] = [
        // 白色系 (1-8)
        BeadColor(id: "C01", name: "白色", r: 1.000, g: 1.000, b: 1.000),
        BeadColor(id: "C02", name: "乳白色", r: 0.980, g: 0.961, b: 0.922),
        BeadColor(id: "C03", name: "象牙白", r: 1.000, g: 1.000, b: 0.941),
        BeadColor(id: "C04", name: "珍珠白", r: 0.950, g: 0.950, b: 0.970),
        BeadColor(id: "C05", name: "浅灰", r: 0.827, g: 0.827, b: 0.827),
        BeadColor(id: "C06", name: "银灰", r: 0.753, g: 0.753, b: 0.753),
        BeadColor(id: "C07", name: "中灰", r: 0.663, g: 0.663, b: 0.663),
        BeadColor(id: "C08", name: "炭灰", r: 0.502, g: 0.502, b: 0.502),
        
        // 黑色系 (9-12)
        BeadColor(id: "C09", name: "深灰", r: 0.412, g: 0.412, b: 0.412),
        BeadColor(id: "C10", name: "烟灰", r: 0.333, g: 0.333, b: 0.333),
        BeadColor(id: "C11", name: "暗灰", r: 0.200, g: 0.200, b: 0.200),
        BeadColor(id: "C12", name: "黑色", r: 0.133, g: 0.133, b: 0.133),

        // 红色系 (13-24)
        BeadColor(id: "C13", name: "大红", r: 0.902, g: 0.157, b: 0.157),
        BeadColor(id: "C14", name: "深红", r: 0.698, g: 0.133, b: 0.133),
        BeadColor(id: "C15", name: "朱红", r: 1.000, g: 0.294, b: 0.294),
        BeadColor(id: "C16", name: "绯红", r: 0.804, g: 0.200, b: 0.200),
        BeadColor(id: "C17", name: "玫红", r: 0.902, g: 0.294, b: 0.478),
        BeadColor(id: "C18", name: "粉红", r: 1.000, g: 0.753, b: 0.796),
        BeadColor(id: "C19", name: "浅粉", r: 1.000, g: 0.882, b: 0.906),
        BeadColor(id: "C20", name: "桃粉", r: 1.000, g: 0.714, b: 0.757),
        BeadColor(id: "C21", name: "珊瑚粉", r: 0.941, g: 0.502, b: 0.502),
        BeadColor(id: "C22", name: "热粉", r: 1.000, g: 0.412, b: 0.706),
        BeadColor(id: "C23", name: "酒红", r: 0.502, g: 0.000, b: 0.125),
        BeadColor(id: "C24", name: "砖红", r: 0.698, g: 0.235, b: 0.157),

        // 橙色系 (25-32)
        BeadColor(id: "C25", name: "橙色", r: 1.000, g: 0.647, b: 0.000),
        BeadColor(id: "C26", name: "浅橙", r: 1.000, g: 0.824, b: 0.400),
        BeadColor(id: "C27", name: "杏色", r: 1.000, g: 0.741, b: 0.478),
        BeadColor(id: "C28", name: "蜜橘", r: 1.000, g: 0.627, b: 0.298),
        BeadColor(id: "C29", name: "南瓜", r: 1.000, g: 0.459, b: 0.094),
        BeadColor(id: "C30", name: "胡萝卜", r: 0.933, g: 0.569, b: 0.129),
        BeadColor(id: "C31", name: "肤色", r: 1.000, g: 0.804, b: 0.698),
        BeadColor(id: "C32", name: "深肤色", r: 0.855, g: 0.576, b: 0.439),

        // 黄色系 (33-42)
        BeadColor(id: "C33", name: "黄色", r: 1.000, g: 0.898, b: 0.200),
        BeadColor(id: "C34", name: "柠檬黄", r: 1.000, g: 0.961, b: 0.000),
        BeadColor(id: "C35", name: "金黄", r: 1.000, g: 0.843, b: 0.000),
        BeadColor(id: "C36", name: "奶油黄", r: 1.000, g: 0.937, b: 0.835),
        BeadColor(id: "C37", name: "玉米黄", r: 1.000, g: 0.922, b: 0.231),
        BeadColor(id: "C38", name: "芥末黄", r: 0.957, g: 0.820, b: 0.231),
        BeadColor(id: "C39", name: "土黄", r: 0.855, g: 0.647, b: 0.125),
        BeadColor(id: "C40", name: "卡其", r: 0.765, g: 0.690, b: 0.569),
        BeadColor(id: "C41", name: "香槟", r: 0.969, g: 0.906, b: 0.776),
        BeadColor(id: "C42", name: "麦色", r: 0.910, g: 0.765, b: 0.490),

        // 绿色系 (43-54)
        BeadColor(id: "C43", name: "草绿", r: 0.565, g: 0.933, b: 0.565),
        BeadColor(id: "C44", name: "绿色", r: 0.133, g: 0.545, b: 0.133),
        BeadColor(id: "C45", name: "深绿", r: 0.000, g: 0.392, b: 0.000),
        BeadColor(id: "C46", name: "薄荷绿", r: 0.596, g: 0.984, b: 0.596),
        BeadColor(id: "C47", name: "青绿", r: 0.000, g: 0.800, b: 0.600),
        BeadColor(id: "C48", name: "橄榄绿", r: 0.420, g: 0.557, b: 0.137),
        BeadColor(id: "C49", name: "苹果绿", r: 0.604, g: 0.804, b: 0.196),
        BeadColor(id: "C50", name: "翡翠绿", r: 0.000, g: 0.659, b: 0.420),
        BeadColor(id: "C51", name: "森林绿", r: 0.133, g: 0.545, b: 0.133),
        BeadColor(id: "C52", name: "苔藓绿", r: 0.541, g: 0.604, b: 0.357),
        BeadColor(id: "C53", name: "海绿", r: 0.180, g: 0.545, b: 0.341),
        BeadColor(id: "C54", name: "春绿", r: 0.000, g: 1.000, b: 0.498),

        // 青色系 (55-62)
        BeadColor(id: "C55", name: "青色", r: 0.000, g: 1.000, b: 1.000),
        BeadColor(id: "C56", name: "湖蓝", r: 0.000, g: 0.780, b: 0.780),
        BeadColor(id: "C57", name: "天蓝", r: 0.529, g: 0.808, b: 0.922),
        BeadColor(id: "C58", name: "水鸭", r: 0.000, g: 0.855, b: 0.871),
        BeadColor(id: "C59", name: "碧蓝", r: 0.204, g: 0.827, b: 0.855),
        BeadColor(id: "C60", name: "薄荷青", r: 0.498, g: 1.000, b: 0.831),
        BeadColor(id: "C61", name: "青柠", r: 0.196, g: 0.804, b: 0.196),
        BeadColor(id: "C62", name: "松石", r: 0.251, g: 0.878, b: 0.816),

        // 蓝色系 (63-74)
        BeadColor(id: "C63", name: "蓝色", r: 0.000, g: 0.000, b: 1.000),
        BeadColor(id: "C64", name: "深蓝", r: 0.000, g: 0.000, b: 0.545),
        BeadColor(id: "C65", name: "宝蓝", r: 0.000, g: 0.200, b: 0.600),
        BeadColor(id: "C66", name: "海军蓝", r: 0.000, g: 0.000, b: 0.333),
        BeadColor(id: "C67", name: "浅蓝", r: 0.678, g: 0.847, b: 0.902),
        BeadColor(id: "C68", name: "钴蓝", r: 0.000, g: 0.278, b: 0.671),
        BeadColor(id: "C69", name: "靛蓝", r: 0.294, g: 0.000, b: 0.510),
        BeadColor(id: "C70", name: "午夜蓝", r: 0.098, g: 0.098, b: 0.439),
        BeadColor(id: "C71", name: "矢车菊", r: 0.392, g: 0.584, b: 0.929),
        BeadColor(id: "C72", name: "皇家蓝", r: 0.255, g: 0.412, b: 0.882),
        BeadColor(id: "C73", name: "钢蓝", r: 0.275, g: 0.510, b: 0.706),
        BeadColor(id: "C74", name: "天青", r: 0.529, g: 0.808, b: 0.980),

        // 紫色系 (75-84)
        BeadColor(id: "C75", name: "紫色", r: 0.627, g: 0.125, b: 0.941),
        BeadColor(id: "C76", name: "深紫", r: 0.294, g: 0.000, b: 0.510),
        BeadColor(id: "C77", name: "浅紫", r: 0.867, g: 0.627, b: 0.867),
        BeadColor(id: "C78", name: "薰衣草", r: 0.902, g: 0.745, b: 1.000),
        BeadColor(id: "C79", name: "紫罗兰", r: 0.933, g: 0.510, b: 0.933),
        BeadColor(id: "C80", name: "葡萄紫", r: 0.569, g: 0.173, b: 0.773),
        BeadColor(id: "C81", name: "兰花紫", r: 0.855, g: 0.439, b: 0.839),
        BeadColor(id: "C82", name: "李子紫", r: 0.604, g: 0.196, b: 0.800),
        BeadColor(id: "C83", name: "紫水晶", r: 0.663, g: 0.361, b: 0.820),
        BeadColor(id: "C84", name: "蓟紫", r: 0.847, g: 0.749, b: 0.847),

        // 棕色系 (85-96)
        BeadColor(id: "C85", name: "棕色", r: 0.647, g: 0.165, b: 0.165),
        BeadColor(id: "C86", name: "深棕", r: 0.396, g: 0.263, b: 0.129),
        BeadColor(id: "C87", name: "浅棕", r: 0.804, g: 0.522, b: 0.247),
        BeadColor(id: "C88", name: "米色", r: 0.961, g: 0.871, b: 0.702),
        BeadColor(id: "C89", name: "驼色", r: 0.741, g: 0.576, b: 0.376),
        BeadColor(id: "C90", name: "赭石", r: 0.804, g: 0.522, b: 0.247),
        BeadColor(id: "C91", name: "赭黄", r: 0.855, g: 0.647, b: 0.125),
        BeadColor(id: "C92", name: "巧克力", r: 0.482, g: 0.247, b: 0.000),
        BeadColor(id: "C93", name: "咖啡", r: 0.439, g: 0.259, b: 0.078),
        BeadColor(id: "C94", name: "焦糖", r: 1.000, g: 0.694, b: 0.376),
        BeadColor(id: "C95", name: "胡桃", r: 0.525, g: 0.376, b: 0.220),
        BeadColor(id: "C96", name: "砂褐", r: 0.957, g: 0.643, b: 0.376),

        // 粉色系 (97-108)
        BeadColor(id: "C97", name: "玫瑰粉", r: 1.000, g: 0.800, b: 0.820),
        BeadColor(id: "C98", name: "樱花粉", r: 1.000, g: 0.714, b: 0.757),
        BeadColor(id: "C99", name: "腮红", r: 0.957, g: 0.643, b: 0.678),
        BeadColor(id: "C100", name: "洋红", r: 1.000, g: 0.000, b: 0.573),
        BeadColor(id: "C101", name: "品红", r: 1.000, g: 0.000, b: 1.000),
        BeadColor(id: "C102", name: "紫红", r: 0.780, g: 0.082, b: 0.522),
        BeadColor(id: "C103", name: "玫瑰红", r: 0.886, g: 0.078, b: 0.357),
        BeadColor(id: "C104", name: "覆盆子", r: 0.890, g: 0.043, b: 0.424),
        BeadColor(id: "C105", name: "甜粉", r: 0.969, g: 0.569, b: 0.725),
        BeadColor(id: "C106", name: "贝壳粉", r: 1.000, g: 0.753, b: 0.796),
        BeadColor(id: "C107", name: "芭蕾粉", r: 0.957, g: 0.800, b: 0.820),
        BeadColor(id: "C108", name: "糖果粉", r: 1.000, g: 0.627, b: 0.678),

        // 特殊色 (109-120)
        BeadColor(id: "C109", name: "透明", r: 0.900, g: 0.900, b: 0.900),
        BeadColor(id: "C110", name: "夜光绿", r: 0.800, g: 1.000, b: 0.800),
        BeadColor(id: "C111", name: "夜光蓝", r: 0.800, g: 0.900, b: 1.000),
        BeadColor(id: "C112", name: "夜光黄", r: 1.000, g: 1.000, b: 0.600),
        BeadColor(id: "C113", name: "夜光橙", r: 1.000, g: 0.800, b: 0.600),
        BeadColor(id: "C114", name: "夜光粉", r: 1.000, g: 0.800, b: 0.800),
        BeadColor(id: "C115", name: "金属金", r: 1.000, g: 0.843, b: 0.000),
        BeadColor(id: "C116", name: "金属银", r: 0.753, g: 0.753, b: 0.753),
        BeadColor(id: "C117", name: "金属铜", r: 0.722, g: 0.451, b: 0.200),
        BeadColor(id: "C118", name: "珠光白", r: 0.980, g: 0.980, b: 1.000),
        BeadColor(id: "C119", name: "珠光粉", r: 1.000, g: 0.882, b: 0.906),
        BeadColor(id: "C120", name: "珠光蓝", r: 0.882, g: 0.922, b: 1.000),
    ]

    // MARK: - 排序方式
    enum SortOrder {
        case byId       // 按编号排序
        case byHue      // 按色相排序
        
        var displayName: String {
            switch self {
            case .byId: return "按编号"
            case .byHue: return "按色相"
            }
        }
    }

    // 根据调色板大小和排序方式获取颜色
    static func colors(for size: PerlerBeadsConfig.PaletteSize, sortedBy sortOrder: SortOrder = .byId) -> [BeadColor] {
        let count = size.rawValue
        var colors = Array(standard120.prefix(count))
        
        switch sortOrder {
        case .byId:
            // 保持原有顺序（按编号）
            break
        case .byHue:
            // 按色相排序
            colors.sort { color1, color2 in
                let hue1 = color1.hue
                let hue2 = color2.hue
                if hue1 != hue2 {
                    return hue1 < hue2
                }
                // 色相相同时按亮度排序
                return color1.brightness < color2.brightness
            }
        }
        
        return colors
    }

    // 查找最接近的颜色
    static func findClosestColor(to uiColor: UIColor, in palette: [BeadColor]) -> BeadColor? {
        guard !palette.isEmpty else { return nil }
        return palette.min { $0.distance(to: uiColor) < $1.distance(to: uiColor) }
    }
}
