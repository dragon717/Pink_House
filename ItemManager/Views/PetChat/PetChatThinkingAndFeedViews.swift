import SwiftUI
import UIKit

struct AIThinkingAnimation: View {
    @State private var dotScales: [CGFloat] = [0.5, 0.5, 0.5]
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.pink.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .scaleEffect(dotScales[index])
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: dotScales[index]
                    )
            }
        }
        .onAppear {
            for i in 0..<3 {
                dotScales[i] = 1.0
            }
        }
    }
}

struct ModernAIThinkingView: View {
    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    let petImageName: String?
    let isConfused: Bool

    init(petImageName: String? = nil, isConfused: Bool = false) {
        self.petImageName = petImageName
        self.isConfused = isConfused
    }

    var body: some View {
        HStack(spacing: 12) {
            if let petImageName, UIImage(named: petImageName) != nil {
                Image(petImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.pink.opacity(0.25), lineWidth: 1.5)
                    )
            }

            ZStack {
                Circle()
                    .stroke(Color.pink.opacity(0.2), lineWidth: 3)
                    .frame(width: 24, height: 24)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(rotation))
            }

            Text(isConfused ? "嗯…我有点疑惑，再想想" : "思考中")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            AIThinkingAnimation()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulseScale = 1.05
            }
        }
    }
}

struct PetFeedAnimationOverlay: View {
    let payload: PetFeedAnimationPayload
    @State private var burst = false

    private let horizontalOffsets: [CGFloat] = [-40, -22, 0, 22, 40]
    private let verticalOffsets: [CGFloat] = [110, 145, 130, 155, 120]
    private let delays: [Double] = [0.0, 0.05, 0.1, 0.16, 0.22]

    var body: some View {
        ZStack {
            if let videoAsset = payload.videoAsset {
                PetFeedTransparentVideoAssetView(asset: videoAsset)
            }

            ForEach(0..<horizontalOffsets.count, id: \.self) { index in
                Text(payload.emoji)
                    .font(.system(size: 30))
                    .offset(
                        x: burst ? horizontalOffsets[index] : 0,
                        y: burst ? -verticalOffsets[index] : 12
                    )
                    .opacity(burst ? 0 : 1)
                    .scaleEffect(burst ? 1.12 : 0.65)
                    .animation(
                        .easeOut(duration: 0.86).delay(delays[index]),
                        value: burst
                    )
            }

            Text("已投喂 \(payload.itemName)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .offset(y: -34)
                .opacity(burst ? 1 : 0.4)
                .scaleEffect(burst ? 1 : 0.9)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: burst)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 130)
        .allowsHitTesting(false)
        .onAppear {
            burst = true
        }
    }
}

struct PetFeedTransparentVideoAssetView: View {
    let asset: PetFeedVideoAssetDescriptor

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .opacity(asset.supportsAlphaChannel ? 0.001 : 0)
    }
}
