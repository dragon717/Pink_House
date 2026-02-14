import SwiftUI

struct GeneralSoundHapticsSettingsView: View {
    @ObservedObject private var audioManager = AudioManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    
    var body: some View {
        AdaptiveSettingsView(title: "音效与触感") {
            // MARK: - 总开关
            AdaptiveSection(header: "总开关") {
                Toggle(isOn: $soundManager.isSoundEnabled) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("应用音效")
                                .foregroundStyle(.primary)
                            Text("控制点击、碰撞等互动音效")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .adaptiveRow()
                
                Toggle(isOn: $audioManager.isBackgroundMusicEnabled) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(.pink)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("背景音乐")
                                .foregroundStyle(.primary)
                            Text("播放场景背景音乐")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .adaptiveRow()
                
                Toggle(isOn: $hapticManager.isHapticsEnabled) {
                    HStack {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .foregroundStyle(.brown)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("触感反馈")
                                .foregroundStyle(.primary)
                            Text("启用震动反馈")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 音量调节
            AdaptiveSection(header: "音量调节") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "music.quarternote.3")
                            .foregroundStyle(.pink)
                            .frame(width: 24)
                        Text("BGM 音量: \(Int(audioManager.bgmVolume * 100))%")
                    }
                    Slider(value: $audioManager.bgmVolume, in: 0...1) {
                        Text("BGM 音量")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").font(.caption)
                    }
                }
                .adaptiveRow()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        Text("萌宠语音: \(Int(audioManager.petVoiceVolume * 100))%")
                    }
                    Slider(value: $audioManager.petVoiceVolume, in: 0...1.5) {
                        Text("语音音量")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").font(.caption)
                    }
                }
                .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 输入设置
            AdaptiveSection(header: "输入设置") {
                Toggle(isOn: $audioManager.useiPhoneMicWithHeadphones) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("耳机模式使用手机收音")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("佩戴耳机时，强制使用手机麦克风以获得更好音质")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 系统触感引导
            AdaptiveSection(header: "系统触感设置", footer: "如果应用内开启后仍无震动，请检查系统设置。") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "gear")
                            .foregroundStyle(.gray)
                        Text("前往系统设置检查触感")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .adaptiveRow(showDivider: false)
            }
        }
    }
}

#Preview {
    GeneralSoundHapticsSettingsView()
}
