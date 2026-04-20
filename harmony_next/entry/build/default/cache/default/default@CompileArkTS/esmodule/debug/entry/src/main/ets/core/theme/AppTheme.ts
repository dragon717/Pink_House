interface AppThemeColors {
    background: string;
    surface: string;
    primary: string;
    primarySoft: string;
    textPrimary: string;
    textSecondary: string;
    border: string;
}
interface AppThemeRadius {
    card: number;
    pill: number;
}
interface AppThemeSpacing {
    page: number;
    card: number;
}
interface AppThemeConfig {
    color: AppThemeColors;
    radius: AppThemeRadius;
    spacing: AppThemeSpacing;
}
export const AppTheme: AppThemeConfig = {
    color: {
        background: '#FFF7FA',
        surface: '#FFFFFF',
        primary: '#D95C82',
        primarySoft: '#FFE4EE',
        textPrimary: '#33252A',
        textSecondary: '#7A6570',
        border: '#F2CFDA'
    },
    radius: {
        card: 22,
        pill: 999
    },
    spacing: {
        page: 20,
        card: 16
    }
};
