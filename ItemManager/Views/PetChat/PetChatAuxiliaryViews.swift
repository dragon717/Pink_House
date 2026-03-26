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

struct OutfitSaveSuccessToast: View {
    let message: String
    @State private var iconScale: CGFloat = 0.5
    @State private var showGlow = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.pink.opacity(0.5),
                                Color.pink.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .opacity(showGlow ? 1 : 0)

                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.pink, .purple, .pink],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 70, height: 70)

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.pink.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(iconScale)
                }

                ForEach(0..<6) { i in
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                        .offset(
                            x: cos(Double(i) * .pi / 3) * 50,
                            y: sin(Double(i) * .pi / 3) * 50
                        )
                        .scaleEffect(iconScale)
                }
            }
            .frame(height: 100)

            VStack(spacing: 8) {
                Text("✨ 保存成功！")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.pink)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.pink.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                iconScale = 1.0
            }

            withAnimation(.easeIn(duration: 0.5)) {
                showGlow = true
            }
        }
    }
}
