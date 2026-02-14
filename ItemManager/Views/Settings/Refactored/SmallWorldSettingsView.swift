import SwiftUI

struct SmallWorldSettingsView: View {
    @AppStorage("smallWorldSceneMode") private var smallWorldSceneMode = SmallWorldSceneMode.auto.rawValue
    @AppStorage("smallWorldStyle") private var smallWorldStyle = SmallWorldStyle.frenchRetro.rawValue
    @AppStorage("isSpatialSceneEnabled") private var isSpatialSceneEnabled = false
    
    var body: some View {
        List {
            Section(header: Text("风格选择")) {
                Picker("小世界风格", selection: $smallWorldStyle) {
                    ForEach(SmallWorldStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
            
            // 小世界场景设置 (仅在法式复古风格下显示)
            if smallWorldStyle == SmallWorldStyle.frenchRetro.rawValue {
                Section(header: Text("场景环境")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "sun.haze.fill")
                                .foregroundStyle(.orange)
                            Text("时间与光照")
                        }
                        
                        VStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { Double(smallWorldSceneMode) },
                                set: { smallWorldSceneMode = Int($0) }
                            ), in: 0...2, step: 1) {
                                Text("场景选择")
                            } minimumValueLabel: {
                                Text("")
                            } maximumValueLabel: {
                                Text("")
                            }
                            .tint(.pink)
                            
                            HStack(spacing: 0) {
                                ForEach(SmallWorldSceneMode.allCases) { mode in
                                    Text(mode.displayName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(mode.rawValue == smallWorldSceneMode ? .primary : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .onTapGesture {
                                            withAnimation {
                                                smallWorldSceneMode = mode.rawValue
                                            }
                                        }
                                }
                            }
                            
                            if smallWorldSceneMode == SmallWorldSceneMode.auto.rawValue {
                                Text("自动模式下：\n清晨 (5:00-9:00) 与 黄昏 (16:00-19:00) 显示晨曦/夕阳场景\n其他时间显示白天场景")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .padding(.top, 4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section(header: Text("高级特性")) {
                if #available(iOS 26.0, *) {
                    Toggle(isOn: $isSpatialSceneEnabled) {
                        VStack(alignment: .leading) {
                            Text("开启3D景深空间场景")
                            Text("iOS 26 专属特性")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Text("3D景深空间场景")
                        Spacer()
                        Text("仅支持 iOS 26+")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("小世界设置")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(LiquidBackground())
    }
}
