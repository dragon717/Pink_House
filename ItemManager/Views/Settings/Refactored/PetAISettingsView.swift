import SwiftUI

struct PetAISettingsView: View {
    var body: some View {
        AdaptiveSettingsView(title: "智能萌宠设置") {
            AdaptiveSection(header: "AI 大脑") {
                NavigationLink(destination: SmartManagementView()) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.purple)
                        Text("模型管理与 API 配置")
                        Spacer()
                    }
                }
                .adaptiveRow(showDivider: false)
            }
            
            AdaptiveSection(header: "声音设置") {
                NavigationLink(destination: AudioSettingsView()) {
                    HStack {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.blue)
                        Text("音量与音效设置")
                    }
                }
                .adaptiveRow(showDivider: false)
            }
            
            AdaptiveSection(header: "萌宠形象") {
                NavigationLink(destination: MagicColorSettingsView()) {
                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(.orange)
                        Text("主题配色")
                        Spacer()
                    }
                }
                .adaptiveRow()

                NavigationLink(destination: PetCustomizationView()) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.pink)
                        Text("拖拽轨迹与气泡")
                        Spacer()
                    }
                }
                .adaptiveRow(showDivider: false)
            }
        }
    }
}
