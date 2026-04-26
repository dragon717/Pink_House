interface AppThemeColors {
    background: string;
    backgroundLight: string;
    backgroundDeep: string;
    surface: string;
    surfaceTint: string;
    surfaceMuted: string;
    surfaceGlass: string;
    primary: string;
    primaryStrong: string;
    primarySoft: string;
    primaryPale: string;
    primaryHalo: string;
    primaryMist: string;
    accent: string;
    accentSoft: string;
    accentWarm: string;
    houseBlue: string;
    petOrange: string;
    success: string;
    textPrimary: string;
    textSecondary: string;
    textTertiary: string;
    textOnPrimary: string;
    textOnAccent: string;
    border: string;
    borderStrong: string;
    overlayGlass: string;
    overlayGlassStrong: string;
    overlayGlassMuted: string;
    shadowSoft: string;
    shadowStrong: string;
}
interface AppThemeRadius {
    card: number;
    cardLarge: number;
    chip: number;
    pill: number;
    tile: number;
}
interface AppThemeSpacing {
    page: number;
    card: number;
    tight: number;
    loose: number;
}
interface AppThemeFont {
    displayLarge: number;
    displayMedium: number;
    titleLarge: number;
    titleMedium: number;
    body: number;
    caption: number;
    tiny: number;
}
interface AppThemeConfig {
    color: AppThemeColors;
    radius: AppThemeRadius;
    spacing: AppThemeSpacing;
    font: AppThemeFont;
}
export const AppTheme: AppThemeConfig = {
    color: {
        // Watercolor pink base, aligned with temp/design.
        background: '#F3DDE5',
        backgroundLight: '#FFF3F7',
        backgroundDeep: '#EBC7D3',
        surface: '#FFFDFD',
        surfaceTint: '#FFF2F6',
        surfaceMuted: '#F8E6ED',
        surfaceGlass: 'rgba(255, 255, 255, 0.74)',
        // Brand pink.
        primary: '#C97884',
        primaryStrong: '#A65366',
        primarySoft: '#F6D1DA',
        primaryPale: '#FBE7ED',
        primaryHalo: '#EAB2C1',
        primaryMist: '#F2E3EA',
        // Accent set used by VIP, House and pet states.
        accent: '#E4B248',
        accentSoft: '#F7E4A8',
        accentWarm: '#F39B47',
        houseBlue: '#7868E6',
        petOrange: '#F0973D',
        success: '#79AA72',
        // Text.
        textPrimary: '#32232B',
        textSecondary: '#7D7078',
        textTertiary: '#B9A5AE',
        textOnPrimary: '#FFFFFF',
        textOnAccent: '#3A2A30',
        // Border and material overlays.
        border: '#EAD5DE',
        borderStrong: '#D6AEBB',
        overlayGlass: 'rgba(255, 255, 255, 0.66)',
        overlayGlassStrong: 'rgba(255, 255, 255, 0.86)',
        overlayGlassMuted: 'rgba(255, 244, 248, 0.58)',
        shadowSoft: 'rgba(166, 83, 102, 0.16)',
        shadowStrong: 'rgba(108, 70, 84, 0.20)'
    },
    radius: {
        card: 16,
        cardLarge: 28,
        chip: 8,
        pill: 999,
        tile: 8
    },
    spacing: {
        page: 18,
        card: 16,
        tight: 10,
        loose: 24
    },
    font: {
        displayLarge: 44,
        displayMedium: 34,
        titleLarge: 24,
        titleMedium: 18,
        body: 15,
        caption: 13,
        tiny: 11
    }
};
