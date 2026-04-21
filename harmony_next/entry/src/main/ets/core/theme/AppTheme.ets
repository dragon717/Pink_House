interface AppThemeColors {
  background: string;
  backgroundLight: string;
  surface: string;
  surfaceTint: string;
  surfaceMuted: string;

  primary: string;
  primaryStrong: string;
  primarySoft: string;
  primaryPale: string;
  primaryHalo: string;

  accent: string;
  accentSoft: string;

  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  textOnPrimary: string;
  textOnAccent: string;

  border: string;
  borderStrong: string;

  overlayGlass: string;
  overlayGlassStrong: string;
  shadowSoft: string;
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
    // 水彩粉底：纯色 + 近似绘制（不依赖图片）
    background: '#F5D6DB',
    backgroundLight: '#FAE6EA',
    surface: '#FFFFFF',
    surfaceTint: '#FFF4F7',
    surfaceMuted: '#FBEEF1',

    // 品牌粉：CTA / 胶囊 / 选中态
    primary: '#C97884',
    primaryStrong: '#B85E6F',
    primarySoft: '#FADEE2',
    primaryPale: '#F7CAD1',
    primaryHalo: '#F4B1BD',

    // 金色：价格 / 数字 / VIP
    accent: '#E4B248',
    accentSoft: '#F7E4A8',

    // 文本
    textPrimary: '#3A2A30',
    textSecondary: '#8C7179',
    textTertiary: '#B89FA6',
    textOnPrimary: '#FFFFFF',
    textOnAccent: '#3A2A30',

    // 边框
    border: '#F0D4DA',
    borderStrong: '#E5B8C0',

    // 玻璃覆盖层（配合 backgroundBlurStyle 使用）
    overlayGlass: 'rgba(255, 255, 255, 0.72)',
    overlayGlassStrong: 'rgba(255, 255, 255, 0.88)',
    shadowSoft: 'rgba(201, 120, 132, 0.18)'
  },
  radius: {
    card: 22,
    cardLarge: 28,
    chip: 14,
    pill: 999,
    tile: 18
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
