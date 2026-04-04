import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject private var audioManager = AudioManager.shared
    
    var body: some View {
        AdaptiveSettingsView(title: "音量调节") {
            AdaptiveSection(header: "音量设置") {
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
                .adaptiveRow(showDivider: false)
            }
        }
    }
}

#Preview {
    AudioSettingsView()
}
