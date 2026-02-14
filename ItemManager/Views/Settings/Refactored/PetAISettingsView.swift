import SwiftUI

struct PetAISettingsView: View {
    @ObservedObject private var audioManager = AudioManager.shared
    @ObservedObject private var petDataManager = PetDataManager.shared
    
    var body: some View {
        List {
            Section(header: Text("AI 大脑")) {
                NavigationLink(destination: SmartManagementView()) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.purple)
                        Text("模型管理与 API 配置")
                        Spacer()
                    }
                }
            }
            
            Section(header: Text("声音交互")) {
                HStack {
                    Image(systemName: "mic.and.signal.meter.fill")
                        .foregroundStyle(.pink)
                    Text("\(petDataManager.status.displayName)音源")
                    Spacer()
                    Picker("", selection: $audioManager.selectedVoiceType) {
                        ForEach(PetVoiceType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                
                // 链接到更详细的声音设置（音量等）
                NavigationLink(destination: HapticSettingsView()) { // HapticSettingsView 包含音量设置
                    HStack {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.blue)
                        Text("音量与音效设置")
                    }
                }
            }
            
            Section(header: Text("萌宠形象")) {
                NavigationLink(destination: PetCustomizationView()) {
                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(.orange)
                        Text("气泡与轨迹个性化")
                        Spacer()
                    }
                }
                
                NavigationLink(destination: CelebrationSettingsView()) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                        Text("彩蛋特效设置")
                        Spacer()
                    }
                }
                
                NavigationLink(destination: CalendarSettingsView()) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(.red)
                        Text("日历主题")
                        Spacer()
                    }
                }
                
                NavigationLink(destination: WealthCustomizationView()) {
                    HStack {
                        Image(systemName: "banknote")
                            .foregroundStyle(.green)
                        Text("来财样式")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("智能萌宠设置")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(LiquidBackground())
    }
}
