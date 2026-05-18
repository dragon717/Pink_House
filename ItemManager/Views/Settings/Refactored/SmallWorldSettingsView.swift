import SwiftUI

struct SmallWorldSettingsView: View {
    @AppStorage("smallWorldStyle") private var smallWorldStyle = SmallWorldStyle.rococo.rawValue
    @AppStorage("isSpatialSceneEnabled") private var isSpatialSceneEnabled = false
    
    @State private var showingClearCacheAlert = false
    
    var body: some View {
        AdaptiveSettingsView(title: "House设置") {
            // 预览区域
            AdaptiveSection(header: "预览") {
                SmallWorldPreview(
                    isSpatialEnabled: isSpatialSceneEnabled
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .adaptiveRow(showDivider: false)
            }
            
            AdaptiveSection(header: "风格选择") {
                HStack {
                    Image(systemName: "cube.transparent")
                        .foregroundStyle(.purple)
                    Text("House风格")
                    Spacer()
                    Text(SmallWorldStyle.rococo.displayName)
                        .foregroundStyle(.secondary)
                }
                .adaptiveRow(showDivider: false)
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
        .onAppear {
            if smallWorldStyle != SmallWorldStyle.rococo.rawValue {
                smallWorldStyle = SmallWorldStyle.rococo.rawValue
            }
        }
    }
}

// MARK: - Preview Component
struct SmallWorldPreview: View {
    let isSpatialEnabled: Bool
    
    private var imageName: String {
        "small_world_rococo_1"
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
