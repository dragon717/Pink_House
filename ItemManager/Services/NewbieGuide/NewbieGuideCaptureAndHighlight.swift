import SwiftUI
import UIKit

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

    func captureGuideToolbarIconTarget(
        _ key: GuideTargetKey,
        touchSize: CGFloat = 36
    ) -> some View {
        overlay {
            Color.clear
                .frame(width: touchSize, height: touchSize)
                .allowsHitTesting(false)
                .captureGuideTarget(key)
        }
    }
}

struct HighlightPulseViewNoClick: View {
    let center: CGPoint
    let radius: CGFloat

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.8

    private var adaptiveRadius: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let scaleFactor = screenWidth / 375.0
        return radius * scaleFactor
    }

    var body: some View {
        Group {
            if radius > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                        .frame(width: adaptiveRadius * 2 * pulseScale, height: adaptiveRadius * 2 * pulseScale)
                        .position(center)

                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: adaptiveRadius * 2, height: adaptiveRadius * 2)
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
            } else {
                EmptyView()
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

    private var adaptiveFrame: CGRect {
        let screenWidth = UIScreen.main.bounds.width
        let scaleFactor = screenWidth / 375.0
        let newWidth = frame.width * scaleFactor
        let newHeight = frame.height * scaleFactor
        let newX = frame.midX - newWidth / 2
        let newY = frame.midY - newHeight / 2
        return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    var body: some View {
        Group {
            if !frame.isEmpty {
                ZStack {
                    if showPulse {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                            .frame(width: adaptiveFrame.width * pulseScale, height: adaptiveFrame.height * pulseScale)
                            .position(x: adaptiveFrame.midX, y: adaptiveFrame.midY)
                    }

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: adaptiveFrame.width, height: adaptiveFrame.height)
                        .position(x: adaptiveFrame.midX, y: adaptiveFrame.midY)
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
            } else {
                EmptyView()
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

    private var scaleFactor: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return screenWidth / 375.0
    }

    private var pawSize: CGFloat {
        30 * scaleFactor
    }

    private var circleSize: CGFloat {
        50 * scaleFactor
    }

    var body: some View {
        Group {
            if position.x > 0, position.y > 0 {
                ZStack {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: pawSize))
                        .foregroundColor(.white)
                        .scaleEffect(tapScale)
                        .opacity(tapOpacity)
                        .position(position)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

                    Circle()
                        .stroke(Color.white.opacity(tapOpacity * 0.5), lineWidth: 2)
                        .frame(width: circleSize * tapScale, height: circleSize * tapScale)
                        .position(position)
                }
                .allowsHitTesting(false)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        startAnimation()
                    }
                }
            } else {
                EmptyView()
            }
        }
    }
}

extension CatPawTapAnimation {
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

    private var adaptiveHighlightFrame: CGRect {
        let screenWidth = UIScreen.main.bounds.width
        let scaleFactor = screenWidth / 375.0
        let newWidth = highlightFrame.width * scaleFactor
        let newHeight = highlightFrame.height * scaleFactor
        let newX = highlightFrame.midX - newWidth / 2
        let newY = highlightFrame.midY - newHeight / 2
        return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    var body: some View {
        GeometryReader { _ in
            Group {
                if !highlightFrame.isEmpty {
                    ZStack {
                        Color.black
                            .opacity(0.5)
                            .ignoresSafeArea()

                        switch highlightType {
                        case .circle:
                            Circle()
                                .frame(width: adaptiveHighlightFrame.width, height: adaptiveHighlightFrame.height)
                                .position(x: adaptiveHighlightFrame.midX, y: adaptiveHighlightFrame.midY)
                                .blendMode(.destinationOut)
                        case .roundedRect:
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .frame(width: adaptiveHighlightFrame.width, height: adaptiveHighlightFrame.height)
                                .position(x: adaptiveHighlightFrame.midX, y: adaptiveHighlightFrame.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                    .allowsHitTesting(false)
                } else {
                    Color.clear
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
