import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject private var audioManager = AudioManager.shared
    
    var body: some View {
        AdaptiveSettingsView(title: "音量调节") {
            AdaptiveSection(header: "音量设置") {
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
                .adaptiveRow()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(.pink)
                            .frame(width: 24)
                        Text("萌宠 BGM: \(Int(audioManager.bgmVolume * 100))%")
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
        }
    }
}

#Preview {
    AudioSettingsView()
}
