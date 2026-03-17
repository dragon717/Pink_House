import SwiftUI

struct PetAISettingsView: View {
    @ObservedObject private var audioManager = AudioManager.shared
    @ObservedObject private var petDataManager = PetDataManager.shared
    
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
            
            AdaptiveSection(header: "声音交互") {
                HStack {
                    Image(systemName: "mic.and.signal.meter.fill")
                        .foregroundStyle(.pink)
                    Text("\(petDataManager.status.displayName)模仿复述音源")
                    Spacer()
                    Picker("", selection: $audioManager.selectedVoiceType) {
                        ForEach(PetVoiceType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .adaptiveRow()
                
                // 链接到更详细的声音设置（音量等）
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
                NavigationLink(destination: PetChatSkinSettingsView()) {
                    HStack {
                        Image(systemName: "message.fill")
                            .foregroundStyle(.pink)
                        Text("萌宠对话皮肤")
                        Spacer()
                    }
                }
                .adaptiveRow()

                NavigationLink(destination: PetCustomizationView()) {
                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(.orange)
                        Text("气泡与轨迹个性化")
                        Spacer()
                    }
                }
                .adaptiveRow(showDivider: false)
            }
        }
    }
}
