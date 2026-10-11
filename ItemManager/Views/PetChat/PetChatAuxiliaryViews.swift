import SwiftUI

struct PetStampView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "FF69B4").opacity(0.6), lineWidth: 3)
                .frame(width: 60, height: 60)

            Circle()
                .stroke(Color(hex: "FF69B4").opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .frame(width: 52, height: 52)

            Image(systemName: "pawprint.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color(hex: "FF69B4").opacity(0.5))
                .rotationEffect(.degrees(10))

            Text("REVIEWED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "FF69B4"))
                .offset(y: 22)
                .rotationEffect(.degrees(-10))
        }
        .compositingGroup()
        .opacity(0.8)
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
