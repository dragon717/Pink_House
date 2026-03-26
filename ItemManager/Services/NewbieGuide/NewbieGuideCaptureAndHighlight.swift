import SwiftUI

struct GuideTargetCaptureModifier: ViewModifier {
    let key: GuideTargetKey

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear {
                        AppFirstLaunchGuideManager.shared.updateGuideTargetFrame(frame, for: key)
                    }
                    .onChange(of: frame) { _, newValue in
                        AppFirstLaunchGuideManager.shared.updateGuideTargetFrame(newValue, for: key)
                    }
            }
        )
    }
}

struct GuideInteractionRegionCaptureModifier: ViewModifier {
    let id: String
    @State private var regionUUID = UUID().uuidString

    private var regionKey: String { "\(id)#\(regionUUID)" }

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear {
                        AppFirstLaunchGuideManager.shared.updateGuideInteractiveRegion(frame, for: regionKey)
                    }
                    .onChange(of: frame) { _, newValue in
                        AppFirstLaunchGuideManager.shared.updateGuideInteractiveRegion(newValue, for: regionKey)
                    }
                    .onDisappear {
                        AppFirstLaunchGuideManager.shared.clearGuideInteractiveRegion(for: regionKey)
                    }
            }
        )
    }
}

extension View {
    func captureGuideTarget(_ key: GuideTargetKey) -> some View {
        modifier(GuideTargetCaptureModifier(key: key))
    }

    @ViewBuilder
    func captureGuideTarget(_ key: GuideTargetKey?) -> some View {
        if let key {
            modifier(GuideTargetCaptureModifier(key: key))
        } else {
            self
        }
    }

    func captureGuideInteractionRegion(_ id: String) -> some View {
        modifier(GuideInteractionRegionCaptureModifier(id: id))
    }
}

struct HighlightPulseViewNoClick: View {
    let center: CGPoint
    let radius: CGFloat

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.8

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: radius * 2 * pulseScale, height: radius * 2 * pulseScale)
                .position(center)

            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                pulseScale = 1.5
                pulseOpacity = 0.0
            }
        }
    }
}

struct RoundedRectHighlightView: View {
    let frame: CGRect
    let cornerRadius: CGFloat
    var showPulse: Bool = true

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6

    var body: some View {
        ZStack {
            if showPulse {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                    .frame(width: frame.width * pulseScale, height: frame.height * pulseScale)
                    .position(x: frame.midX, y: frame.midY)
            }

            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            if showPulse {
                withAnimation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    pulseScale = 1.05
                    pulseOpacity = 0.0
                }
            }
        }
    }
}

struct CatPawTapAnimation: View {
    let position: CGPoint
    let delay: Double

    @State private var isAnimating = false
    @State private var tapScale: CGFloat = 1.0
    @State private var tapOpacity: Double = 1.0

    var body: some View {
        ZStack {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 30))
                .foregroundColor(.white)
                .scaleEffect(tapScale)
                .opacity(tapOpacity)
                .position(position)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

            Circle()
                .stroke(Color.white.opacity(tapOpacity * 0.5), lineWidth: 2)
                .frame(width: 50 * tapScale, height: 50 * tapScale)
                .position(position)
        }
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            tapScale = 0.7
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.2)) {
                tapScale = 1.0
            }
        }

        withAnimation(.easeOut(duration: 0.6)) {
            tapScale = 1.5
            tapOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            tapScale = 1.0
            tapOpacity = 1.0
            startAnimation()
        }
    }
}

struct HollowMaskView: View {
    let highlightFrame: CGRect
    let highlightType: HighlightType
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black
                    .opacity(0.5)
                    .ignoresSafeArea()

                switch highlightType {
                case .circle:
                    Circle()
                        .frame(width: highlightFrame.width, height: highlightFrame.height)
                        .position(x: highlightFrame.midX, y: highlightFrame.midY)
                        .blendMode(.destinationOut)
                case .roundedRect:
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .frame(width: highlightFrame.width, height: highlightFrame.height)
                        .position(x: highlightFrame.midX, y: highlightFrame.midY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            .allowsHitTesting(false)
        }
    }
}
