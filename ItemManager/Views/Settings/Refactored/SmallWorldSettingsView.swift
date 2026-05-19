import SwiftUI

struct SmallWorldSettingsView: View {
    @AppStorage("smallWorldStyle") private var smallWorldStyle = SmallWorldStyle.bookHouse.rawValue
    
    @State private var showingClearCacheAlert = false
    
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
                    Text("House 右上角")
                        .foregroundStyle(.secondary)
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
