import SwiftUI

/// A contrast adapter for the shared theme. Small labels use opaque, theme-derived plates.
nonisolated struct WardrobeStorageRGB: Equatable, Sendable {
    let r: Double
    let g: Double
    let b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        func channel(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        self.r = channel(r); self.g = channel(g); self.b = channel(b)
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
    }

    var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    func contrast(against other: Self) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }

    func mixed(with other: Self, fraction: Double) -> Self {
        let t = min(1, max(0, fraction))
        return Self(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    func ensuringContrast(on surfaces: [Self], dark: Bool, minimum: Double) -> Self {
        guard surfaces.contains(where: { contrast(against: $0) < minimum }) else { return self }
        let target = Self(hex: dark ? 0xFFFFFF : 0x000000)
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            let candidate = mixed(with: target, fraction: middle)
            if surfaces.allSatisfy({ candidate.contrast(against: $0) >= minimum }) { high = middle }
            else { low = middle }
        }
        return mixed(with: target, fraction: high)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

nonisolated struct WardrobeStoragePalette: Equatable, Sendable {
    let isDark: Bool
    let increasedContrast: Bool
    let scene: WardrobeStorageRGB
    let rear: WardrobeStorageRGB
    let card: WardrobeStorageRGB
    let selected: WardrobeStorageRGB
    let label: WardrobeStorageRGB
    let primary: WardrobeStorageRGB
    let secondary: WardrobeStorageRGB
    let accent: WardrobeStorageRGB
    let border: WardrobeStorageRGB
    let iconTop: WardrobeStorageRGB
    let iconBottom: WardrobeStorageRGB
    let iconFill: WardrobeStorageRGB
    let gold: WardrobeStorageRGB

    var textSurfaces: [WardrobeStorageRGB] { [label, selected] }

    /// Fallback for standalone art previews without a ThemeManager environment.
    static func resolve(dark: Bool, increasedContrast: Bool = false, accent: WardrobeStorageRGB? = nil) -> Self {
        let scene = WardrobeStorageRGB(hex: dark ? 0x181319 : 0xFAEEF1)
        let rear = WardrobeStorageRGB(hex: dark ? 0x221A23 : 0xF7EBEE)
        let card = WardrobeStorageRGB(hex: dark ? 0x2D222D : 0xFFF9F8)
        let selected = WardrobeStorageRGB(hex: dark ? 0x362332 : 0xF0DBE2)
        let label = WardrobeStorageRGB(hex: dark ? 0x261B22 : 0xFFF8EF)
        let surfaces = [scene, rear, card, selected, label]
        let minimum = increasedContrast ? 9.0 : 7.0
        let primary = WardrobeStorageRGB(hex: dark ? 0xFFF5F5 : 0x4F363D)
            .ensuringContrast(on: surfaces, dark: dark, minimum: minimum)
        let secondary = WardrobeStorageRGB(hex: dark ? 0xCDBBC9 : 0x70565F)
            .ensuringContrast(on: surfaces, dark: dark, minimum: minimum)
        let readableAccent = (accent ?? WardrobeStorageRGB(hex: dark ? 0xF4A9C5 : 0xAD4061))
            .ensuringContrast(on: surfaces, dark: dark, minimum: minimum)
        return Self(isDark: dark, increasedContrast: increasedContrast, scene: scene, rear: rear, card: card,
                    selected: selected, label: label, primary: primary, secondary: secondary, accent: readableAccent,
                    border: WardrobeStorageRGB(hex: dark ? (increasedContrast ? 0xA48A9B : 0x6D5365) : 0xB598A3),
                    iconTop: WardrobeStorageRGB(hex: dark ? 0x463340 : 0xFFFDFB),
                    iconBottom: WardrobeStorageRGB(hex: dark ? 0x281C28 : 0xF5DBDF),
                    iconFill: WardrobeStorageRGB(hex: dark ? 0x926477 : 0xEFADB8),
                    gold: WardrobeStorageRGB(hex: dark ? 0xE5BA84 : 0xAE8052))
    }

    /// Rendering surfaces are supplied by the app's theme, not a second set of theme swatches.
    static func fromUnified(dark: Bool, increasedContrast: Bool, scene: WardrobeStorageRGB,
                            surface: WardrobeStorageRGB, primary: WardrobeStorageRGB,
                            secondary: WardrobeStorageRGB, accent: WardrobeStorageRGB) -> Self {
        let minimum = increasedContrast ? 9.0 : 7.0
        let lightText = surface.luminance < 0.18
        let endpoint = WardrobeStorageRGB(hex: lightText ? 0xFFFFFF : 0x000000)
        // Mid-tone cards cannot provide 7:1 with any text. Only the small reading plate
        // receives the minimum adjustment; the theme's wallpaper/card drawing stays intact.
        let label = surface.ensuringContrast(on: [endpoint], dark: !lightText, minimum: minimum)
        let selected = label.mixed(with: accent, fraction: 0.08)
            .ensuringContrast(on: [endpoint], dark: !lightText, minimum: minimum)
        let plates = [label, selected]
        let readablePrimary = primary.ensuringContrast(on: plates, dark: lightText, minimum: minimum)
        let readableSecondary = secondary.ensuringContrast(on: plates, dark: lightText, minimum: minimum)
        let readableAccent = accent.ensuringContrast(on: plates, dark: lightText, minimum: minimum)
        return Self(isDark: dark, increasedContrast: increasedContrast, scene: scene, rear: surface, card: surface,
                    selected: selected, label: label, primary: readablePrimary, secondary: readableSecondary,
                    accent: readableAccent, border: readableSecondary,
                    iconTop: label.mixed(with: readableAccent, fraction: 0.16), iconBottom: label,
                    iconFill: label.mixed(with: readableAccent, fraction: 0.48),
                    gold: readableAccent.mixed(with: readablePrimary, fraction: 0.20))
    }

}

private struct WardrobeStoragePaletteKey: EnvironmentKey {
    static let defaultValue = WardrobeStoragePalette.resolve(dark: false)
}
private struct WardrobeStorageCabinetLightingKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var wardrobeStoragePalette: WardrobeStoragePalette {
        get { self[WardrobeStoragePaletteKey.self] }
        set { self[WardrobeStoragePaletteKey.self] = newValue }
    }
    var wardrobeStorageCabinetLighting: Bool {
        get { self[WardrobeStorageCabinetLightingKey.self] }
        set { self[WardrobeStorageCabinetLightingKey.self] = newValue }
    }
}

extension WardrobeStoragePalette {
    @MainActor static func themed(_ manager: ThemeManager, scheme: ColorScheme, contrast: ColorSchemeContrast) -> Self {
        let surfaceColor = manager.cardSurfaceColor(for: scheme)
        let unified = manager.getPaletteForContainer(containerBackground: .solid(color: surfaceColor), colorScheme: scheme)
        let surfaceRGBA = surfaceColor.rgba
        let sceneRGBA = manager.backgroundColor.rgba
        let surface = surfaceRGBA.map { WardrobeStorageRGB($0.r, $0.g, $0.b) }
            ?? WardrobeStorageRGB(hex: scheme == .dark ? 0x202020 : 0xFFFFFF)
        func textRGB(_ color: Color) -> WardrobeStorageRGB {
            guard let rgba = color.rgba else { return surface.luminance < 0.18 ? .init(hex: 0xFFFFFF) : .init(hex: 0x000000) }
            return surface.mixed(with: WardrobeStorageRGB(rgba.r, rgba.g, rgba.b), fraction: rgba.a)
        }
        return fromUnified(dark: scheme == .dark, increasedContrast: contrast == .increased,
                           scene: sceneRGBA.map { WardrobeStorageRGB($0.r, $0.g, $0.b) } ?? surface,
                           surface: surface, primary: textRGB(unified.primary), secondary: textRGB(unified.secondary),
                           accent: textRGB(unified.accent))
    }
}

private struct WardrobeStorageAppearanceModifier: ViewModifier {
    @Environment(ThemeManager.self) private var manager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let palette = WardrobeStoragePalette.themed(manager, scheme: scheme, contrast: contrast)
        let unified = manager.getPaletteForContainer(containerBackground: .solid(color: manager.cardSurfaceColor(for: scheme)), colorScheme: scheme)
        content.environment(\.containerPalette, unified)
            .environment(\.wardrobeStoragePalette, palette)
            .foregroundStyle(palette.primary.color).tint(palette.accent.color)
    }
}
extension View {
    func wardrobeStorageAppearance() -> some View { modifier(WardrobeStorageAppearanceModifier()) }
}
