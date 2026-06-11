import SwiftUI

struct SmallWorldSettingsView: View {
    @AppStorage("smallWorldStyle") private var smallWorldStyle = SmallWorldStyle.bookHouse.rawValue
    @StateObject private var decorationInventoryStore = BookHouseDecorationInventoryStore.shared
    
    @State private var showingClearCacheAlert = false
    @State private var showingResetLayoutAlert = false

    private let houseFeatureIDs: [AppFeatureID] = AppFeatureRegistry.all
        .filter { $0.surfaces.contains(.houseRoom) && $0.id != .house }
        .map(\.id)
    
    var body: some View {
        AdaptiveSettingsView(title: "House设置") {
            AdaptiveSection(header: "预览") {
                SmallWorldPreview()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .adaptiveRow(showDivider: false)
            }
            
            AdaptiveSection(header: "风格选择") {
                HStack {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.purple)
                    Text("House风格")
                    Spacer()
                    Text(SmallWorldStyle.bookHouse.displayName)
                        .foregroundStyle(.secondary)
                }
                .adaptiveRow(showDivider: false)
            }
            
            AdaptiveSection(header: "交互") {
                HStack {
                    Image(systemName: "hand.point.up.left.fill")
                        .foregroundStyle(.blue)
                    Text("自由摆放")
                    Spacer()
                    Text(decorationInventoryStore.showsPlacementControls ? "已显示" : "已隐藏")
                        .foregroundStyle(.secondary)
                }
                .adaptiveRow(showDivider: false)
            }

            AdaptiveSection(header: "功能装饰背包") {
                Button {
                    decorationInventoryStore.restoreAll(houseFeatureIDs)
                } label: {
                    HStack {
                        Image(systemName: "tray.and.arrow.up.fill")
                            .foregroundStyle(.pink)
                        Text("全部摆回房间")
                        Spacer()
                    }
                }
                .adaptiveRow()

                Button {
                    decorationInventoryStore.storeAll(houseFeatureIDs)
                } label: {
                    HStack {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(.purple)
                        Text("全部收进背包")
                        Spacer()
                    }
                }
                .adaptiveRow(showDivider: false)
            }

            AdaptiveSection(header: "调试初始摆放") {
                Toggle(isOn: $decorationInventoryStore.showsPlacementControls) {
                    HStack {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .foregroundStyle(.blue)
                        Text("显示整理按钮")
                    }
                }
                .adaptiveRow()

                Toggle(isOn: $decorationInventoryStore.showsStaticDecorations) {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack")
                            .foregroundStyle(.orange)
                        Text("显示无热区静态装饰")
                    }
                }
                .adaptiveRow()

                Button(role: .destructive) {
                    showingResetLayoutAlert = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("重置 House 初始摆放")
                    }
                }
                .adaptiveRow(showDivider: false)
            }
            
            AdaptiveSection(header: "存储管理") {
                Button(role: .destructive) {
                    SpatialAssetManager.shared.clearAllCache()
                    showingClearCacheAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("清理空间缓存")
                    }
                }
                .adaptiveRow(showDivider: false)
            }
        }
        .alert("缓存清理完成", isPresented: $showingClearCacheAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("空间缓存已清理。")
        }
        .alert("重置 House 初始摆放？", isPresented: $showingResetLayoutAlert) {
            Button("取消", role: .cancel) { }
            Button("重置", role: .destructive) {
                decorationInventoryStore.resetRoomLayoutOverrides()
            }
        } message: {
            Text("会恢复到此用户保存的初始摆设；如果尚未保存调试初始值，则恢复到当前内置初始值。")
        }
        .onAppear {
            if smallWorldStyle != SmallWorldStyle.bookHouse.rawValue {
                smallWorldStyle = SmallWorldStyle.bookHouse.rawValue
            }
        }
    }
}

// MARK: - Preview Component
struct SmallWorldPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FFF7EF"), Color(hex: "F3DCE6"), Color(hex: "DDEAF4")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill([Color(hex: "EFA4BE"), Color(hex: "C9A7FF"), Color(hex: "91C9F7")][index])
                        .frame(width: 58, height: 128)
                        .rotation3DEffect(.degrees(58), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
                        .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 8)
                }
            }
            .padding(.top, 24)
        }
    }
}
