import SwiftUI

// MARK: - 彩蛋设置卡片
struct EasterEggSettingsCard: View {
    var body: some View {
        NavigationLink(destination: CelebrationSettingsView()) {
            SettingsGridItem(
                title: "彩蛋设置",
                subtitle: "震动 · 音效 · 音量",
                icon: "sparkles",
                iconColor: .pink
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 马上来财设置卡片
struct WealthHapticsSettingsCard: View {
    var body: some View {
        NavigationLink(destination: WealthHapticsSettingsView()) {
            SettingsGridItem(
                title: "马上来财",
                subtitle: "触感 · 音量 · 麦克风",
                icon: "banknote.fill",
                iconColor: .green
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 梦裙日历主题卡片
struct CalendarSettingsCard: View {
    var body: some View {
        NavigationLink(destination: CalendarSettingsView()) {
            SettingsGridItem(
                title: "梦裙日历",
                subtitle: "主题 · 样式 · 个性化",
                icon: "calendar",
                iconColor: .red
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 小组件设置卡片
struct WidgetSettingsCard: View {
    var body: some View {
        NavigationLink(destination: WidgetSettingsView()) {
            SettingsGridItem(
                title: "小组件",
                subtitle: "背景 · 尺寸 · 教程",
                icon: "square.text.square.fill",
                iconColor: .blue
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
