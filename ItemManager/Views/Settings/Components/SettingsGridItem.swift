import SwiftUI

struct SettingsGridItem: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    var iconSystemName: Bool = true // 是否是 SF Symbol
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if iconSystemName {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                        .frame(width: 40, height: 40)
                        .background(iconColor.opacity(0.1))
                        .clipShape(Circle())
                } else {
                    Text(icon)
                        .font(.title)
                        .frame(width: 40, height: 40)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1.0, contentMode: .fill) // 1:1 宽高比
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        Color.pink.opacity(0.1).ignoresSafeArea()
        HStack {
            SettingsGridItem(
                title: "梦幻衣橱",
                subtitle: "外观 · 隐私 · 提醒",
                icon: "tshirt",
                iconColor: .pink
            )
            SettingsGridItem(
                title: "智能萌宠",
                subtitle: "AI 大脑 · 语音 · 形象",
                icon: "pawprint.fill",
                iconColor: .purple
            )
        }
        .padding()
    }
}
