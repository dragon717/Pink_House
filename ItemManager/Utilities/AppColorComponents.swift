import SwiftUI

// MARK: - App 通用颜色映射（用于本地算法生成的颜色）
enum AppColorMap {
    /// 颜色名称到 Color 的映射表 - 扩展支持2025流行色
    static let colorMap: [String: Color] = [
        // 基础色
        "樱花粉": Color(red: 1.0, green: 0.71, blue: 0.76),
        "奶油白": Color(red: 1.0, green: 0.98, blue: 0.94),
        "薰衣草紫": Color(red: 0.9, green: 0.8, blue: 1.0),
        "珍珠白": Color(red: 0.98, green: 0.97, blue: 0.95),
        "薄荷绿": Color(red: 0.7, green: 0.95, blue: 0.85),
        "浅灰蓝": Color(red: 0.75, green: 0.85, blue: 0.95),
        "玫瑰红": Color(red: 1.0, green: 0.4, blue: 0.5),
        "香槟金": Color(red: 0.95, green: 0.9, blue: 0.7),
        "浅金色": Color(red: 0.95, green: 0.9, blue: 0.75),
        // 2025流行色
        "莫兰迪粉": Color(red: 0.92, green: 0.78, blue: 0.82),
        "雾霾蓝": Color(red: 0.65, green: 0.75, blue: 0.85),
        "浅鹅黄": Color(red: 1.0, green: 0.95, blue: 0.75),
        "珊瑚粉": Color(red: 1.0, green: 0.65, blue: 0.6),
        "焦糖棕": Color(red: 0.8, green: 0.6, blue: 0.45),
        "奶茶色": Color(red: 0.85, green: 0.78, blue: 0.7),
        "枫叶红": Color(red: 0.9, green: 0.4, blue: 0.35),
        "酒红色": Color(red: 0.65, green: 0.15, blue: 0.25),
        "墨绿色": Color(red: 0.2, green: 0.35, blue: 0.25),
        // 天气相关色
        "明亮黄": Color(red: 1.0, green: 0.9, blue: 0.3),
        "天空蓝": Color(red: 0.5, green: 0.75, blue: 1.0),
        "海洋蓝": Color(red: 0.2, green: 0.5, blue: 0.8),
        "冰蓝": Color(red: 0.75, green: 0.9, blue: 1.0),
        "银白": Color(red: 0.9, green: 0.9, blue: 0.95),
        "雪白": Color.white,
        "深红": Color(red: 0.7, green: 0.1, blue: 0.15),
        "藏青": Color(red: 0.15, green: 0.25, blue: 0.45),
        "深灰": Color(red: 0.35, green: 0.35, blue: 0.4),
        "浅灰": Color(red: 0.75, green: 0.75, blue: 0.78),
        "银灰": Color(red: 0.75, green: 0.75, blue: 0.8),
        "深紫": Color(red: 0.4, green: 0.2, blue: 0.5),
        "杏色": Color(red: 1.0, green: 0.9, blue: 0.8),
        "玫瑰粉": Color(red: 1.0, green: 0.75, blue: 0.85),
        "浅粉": Color(red: 1.0, green: 0.88, blue: 0.93),
        "酒红": Color(red: 0.65, green: 0.15, blue: 0.25),
        "墨蓝": Color(red: 0.1, green: 0.2, blue: 0.4),
        "黑色": Color.black,
        "驼色": Color(red: 0.75, green: 0.6, blue: 0.45),
        "橄榄绿": Color(red: 0.5, green: 0.55, blue: 0.35),
        "米色": Color(red: 0.95, green: 0.92, blue: 0.85),
        "淡粉": Color(red: 1.0, green: 0.85, blue: 0.9),
        "浅紫": Color(red: 0.85, green: 0.75, blue: 0.95),
        "天蓝": Color(red: 0.6, green: 0.85, blue: 1.0),
        "深蓝": Color(red: 0.1, green: 0.3, blue: 0.6),
        "墨绿": Color(red: 0.1, green: 0.35, blue: 0.25),
        "白色": Color.white
    ]

    /// 根据颜色名称获取 Color，找不到返回默认粉色
    static func color(for name: String) -> Color {
        return colorMap[name] ?? .pink
    }
}

// MARK: - 颜色信息（名称 + 可选的 hex 值）
struct ColorInfo: Codable, Hashable {
    let name: String
    let hex: String? // AI 生成的颜色会有 hex 值

    /// 用于本地算法生成的颜色（只有名称）
    init(name: String) {
        self.name = name
        self.hex = nil
    }

    /// 用于 AI 生成的颜色（名称 + hex）
    init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }

    /// 获取 SwiftUI Color（优先使用 hex，否则使用名称映射）
    var color: Color {
        if let hex = hex {
            return Color(hex: hex)
        } else {
            return AppColorMap.color(for: name)
        }
    }

    var localizedName: String {
        name.appLocalized
    }
}

// MARK: - 颜色卡片组件
struct ColorCard: View {
    let colorName: String
    let displayName: String
    let hexColor: String? // AI 生成的颜色会使用 hex

    /// 初始化 - 用于本地算法生成的颜色（使用颜色名称）
    init(colorName: String, displayName: String? = nil) {
        self.colorName = colorName
        self.displayName = displayName ?? colorName.appLocalized
        self.hexColor = nil
    }

    /// 初始化 - 用于 AI 生成的颜色（使用 hex 值）
    init(colorName: String, displayName: String? = nil, hexColor: String) {
        self.colorName = colorName
        self.displayName = displayName ?? colorName.appLocalized
        self.hexColor = hexColor
    }

    /// 根据 hex 或颜色名称获取 Color
    private var color: Color {
        if let hex = hexColor {
            // AI 生成的颜色使用 hex
            return Color(hex: hex)
        } else {
            // 本地算法生成的颜色使用名称映射
            return AppColorMap.color(for: colorName)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 50, height: 50)
                .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)

            Text(displayName)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}
