import SwiftUI

struct SmallWorldSettingsView: View {
    @AppStorage("smallWorldSceneMode") private var smallWorldSceneMode = SmallWorldSceneMode.auto.rawValue
    @AppStorage("smallWorldStyle") private var smallWorldStyle = SmallWorldStyle.journalRoom.rawValue
    @AppStorage("isSpatialSceneEnabled") private var isSpatialSceneEnabled = false
    
    @State private var showingClearCacheAlert = false
    
    var body: some View {
        AdaptiveSettingsView(title: "House设置") {
            // 预览区域
            AdaptiveSection(header: "预览") {
                SmallWorldPreview(
                    style: SmallWorldStyle(rawValue: smallWorldStyle) ?? .journalRoom,
                    sceneMode: SmallWorldSceneMode(rawValue: smallWorldSceneMode) ?? .auto,
                    isSpatialEnabled: isSpatialSceneEnabled
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .adaptiveRow(showDivider: false)
            }
            
            AdaptiveSection(header: "风格选择") {
                Picker("House风格", selection: $smallWorldStyle) {
                    ForEach(SmallWorldStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .adaptiveRow(showDivider: false)
            }
            
            // House场景设置 (仅在法式复古风格下显示)
            if smallWorldStyle == SmallWorldStyle.frenchRetro.rawValue {
                AdaptiveSection(header: "场景环境") {
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
                    .adaptiveRow(showDivider: false)
                }
            }
            
            AdaptiveSection(header: "高级特性") {
                if #available(iOS 26.0, *) {
                    Toggle(isOn: $isSpatialSceneEnabled) {
                        VStack(alignment: .leading) {
                            Text("开启3D景深空间场景")
                            Text("iOS 26 专属特性")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .adaptiveRow(showDivider: false)
                } else {
                    HStack {
                        Text("3D景深空间场景")
                        Spacer()
                        Text("仅支持 iOS 26+")
                            .foregroundStyle(.secondary)
                    }
                    .adaptiveRow(showDivider: false)
                }
            }
            
            // 存储管理
            AdaptiveSection(header: "存储管理") {
                Button(role: .destructive) {
                    SpatialAssetManager.shared.clearAllCache()
                    showingClearCacheAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("清理 3D 场景缓存")
                    }
                }
                .adaptiveRow(showDivider: false)
            }
        }
        .alert("缓存清理完成", isPresented: $showingClearCacheAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("所有的 3D 场景缓存文件已被清理。下次进入House时将重新生成。")
        }
    }
}

// MARK: - Preview Component
struct SmallWorldPreview: View {
    let style: SmallWorldStyle
    let sceneMode: SmallWorldSceneMode
    let isSpatialEnabled: Bool
    
    private var imageName: String {
        switch style {
        case .frenchRetro:
            return sceneMode.backgroundImageName()
        case .journalRoom:
            return "small_world_rococo_1"
        case .rococo:
            // 洛可可风格默认预览图1
            return "small_world_rococo_1"
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            if #available(iOS 26.0, *), isSpatialEnabled {
                SpatialBackgroundView(
                    imageName: imageName,
                    imageExtension: "png"
                ) {
                    EmptyView()
                }
            } else {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
    }
}
