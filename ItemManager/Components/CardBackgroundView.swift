import SwiftUI

struct CardBackgroundView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 16
    
    var body: some View {
        Group {
            switch themeManager.cardStyle {
            case .solid:
                Color(uiColor: .secondarySystemGroupedBackground)
            case .transparent:
                // Liquid Glass: UltraThin Material + Subtle Border
                ZStack {
                    if themeManager.isBlurEnabled {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                    } else {
                        // Fallback: Lighten slightly in both modes to simulate glass
                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                    }
                }
                .opacity(themeManager.transparentOpacity)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(colorScheme == .dark ? 0.25 : 0.4),
                                    .white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                
            case .tinted:
                // Acrylic/Mica: Regular Material + Tint Overlay
                ZStack {
                    if themeManager.isBlurEnabled {
                        Rectangle()
                            .fill(.regularMaterial)
                    } else {
                        // Fallback
                        Color(uiColor: .systemBackground).opacity(0.5)
                    }
                    
                    themeManager.cardTintColor
                        .opacity(themeManager.tintOpacity)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    themeManager.cardTintColor.opacity(colorScheme == .dark ? 0.3 : 0.5),
                                    themeManager.cardTintColor.opacity(colorScheme == .dark ? 0.05 : 0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
