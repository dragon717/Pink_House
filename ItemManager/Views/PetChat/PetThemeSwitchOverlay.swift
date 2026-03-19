import SwiftUI

struct PetThemeSwitchOverlay: View {
    @State private var pulse = false
    @State private var sparkle = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.white.opacity(0.42),
                    Color.pink.opacity(0.20),
                    Color.clear
                ],
                center: .center,
                startRadius: 6,
                endRadius: pulse ? 220 : 90
            )
            .opacity(pulse ? 0.86 : 0.30)

            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow.opacity(0.95), .pink.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(sparkle ? 1.0 : 0.6)
                .opacity(sparkle ? 1 : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.36)) {
                pulse = true
                sparkle = true
            }
        }
    }
}
