export enum AppRoute {
    Home = "home",
    Wardrobe = "wardrobe",
    Pet = "pet",
    SmallWorld = "smallworld",
    Wealth = "wealth",
    Vip = "vip",
    Settings = "settings"
}
export interface RouteTab {
    readonly route: AppRoute;
    readonly title: string;
    readonly subtitle: string;
}
export const HOME_TABS: RouteTab[] = [
    { route: AppRoute.Wardrobe, title: '衣橱', subtitle: '服饰资产、搭配与导入' },
    { route: AppRoute.Pet, title: '宠物', subtitle: '饱食度、互动和提醒' },
    { route: AppRoute.SmallWorld, title: '小世界', subtitle: '天气、签到与场景入口' },
    { route: AppRoute.Wealth, title: '财富', subtitle: '喵币、账本和尾款' },
    { route: AppRoute.Vip, title: 'VIP', subtitle: '会员权益与 HMS IAP' },
    { route: AppRoute.Settings, title: '设置', subtitle: '备份、隐私和调试' }
];
