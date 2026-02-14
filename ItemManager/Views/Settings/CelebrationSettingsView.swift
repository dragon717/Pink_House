
import SwiftUI

struct CelebrationSettingsView: View {
    @AppStorage("isPayBalanceCelebrationEnabled") private var isPayBalanceCelebrationEnabled = false
    @AppStorage("isFireworksEnabled") private var isFireworksEnabled = true
    @AppStorage("isButterfliesEnabled") private var isButterfliesEnabled = false
    
    // Moved from HapticSettingsView/MeView
    @AppStorage("isCelebrationHapticsEnabled") private var isCelebrationHapticsEnabled = true
    @AppStorage("isCelebrationSoundEnabled") private var isCelebrationSoundEnabled = true
    @ObservedObject private var soundManager = SoundManager.shared
    
    var body: some View {
        AdaptiveSettingsView(title: "彩蛋设置") {
            AdaptiveSection(footer: "开启后，当标记“已付尾款”时，屏幕将播放庆祝特效。") {
                Toggle("付尾款彩蛋", isOn: $isPayBalanceCelebrationEnabled)
                    .tint(.pink)
                    .adaptiveRow(showDivider: false)
            }
            
            if isPayBalanceCelebrationEnabled {
                AdaptiveSection(header: "特效类型", footer: "随机播放已勾选的特效类型。如果未勾选任何类型，将默认播放礼花。") {
                    Toggle("礼花 (Fireworks)", isOn: $isFireworksEnabled)
                        .adaptiveRow()
                    Toggle("蝴蝶 (Butterflies)", isOn: $isButterfliesEnabled)
                        .adaptiveRow(showDivider: false)
                }
                
                AdaptiveSection(header: "感官反馈") {
                    Toggle(isOn: $isCelebrationHapticsEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text("彩蛋震动")
                                    .foregroundStyle(.primary)
                                Text("庆祝特效时的震动反馈")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .adaptiveRow()
                    
                    Toggle(isOn: $isCelebrationSoundEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.wave.2")
                                .foregroundStyle(.pink)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text("彩蛋音效")
                                    .foregroundStyle(.primary)
                                Text("庆祝特效时的爆炸与礼花声")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .adaptiveRow(showDivider: isCelebrationSoundEnabled)
                    
                    if isCelebrationSoundEnabled {
                        VStack {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                    .frame(width: 24)
                                Text("彩蛋音量: \(Int(soundManager.celebrationVolume * 100))%")
                                Spacer()
                            }
                            Slider(value: $soundManager.celebrationVolume, in: 0...1) {
                                Text("彩蛋音量")
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
    }
}

#Preview {
    NavigationView {
        CelebrationSettingsView()
    }
}
