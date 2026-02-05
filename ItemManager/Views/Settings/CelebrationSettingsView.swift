
import SwiftUI

struct CelebrationSettingsView: View {
    @AppStorage("isPayBalanceCelebrationEnabled") private var isPayBalanceCelebrationEnabled = true
    @AppStorage("isFireworksEnabled") private var isFireworksEnabled = true
    @AppStorage("isButterfliesEnabled") private var isButterfliesEnabled = false
    
    var body: some View {
        Form {
            Section(footer: Text("开启后，当标记“已付尾款”时，屏幕将播放庆祝特效。")) {
                Toggle("付尾款彩蛋", isOn: $isPayBalanceCelebrationEnabled)
                    .tint(.pink)
            }
            
            if isPayBalanceCelebrationEnabled {
                Section(header: Text("特效类型"), footer: Text("随机播放已勾选的特效类型。如果未勾选任何类型，将默认播放礼花。")) {
                    Toggle("礼花 (Fireworks)", isOn: $isFireworksEnabled)
                    Toggle("蝴蝶 (Butterflies)", isOn: $isButterfliesEnabled)
                }
            }
        }
        .navigationTitle("彩蛋设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        CelebrationSettingsView()
    }
}
