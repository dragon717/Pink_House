# 系统底部导航约定

更新时间：2026-10-11。此前的自绘异形底栏方案已退役。

`MainTabView` 使用 `NativeTabNavigation` 和系统 `TabView`。当前 SDK 27 构建下，系统负责 Liquid Glass、尺寸变化、安全区和无障碍表现。应用不设置 UITabBar 的主题颜色、背景或形状，不读取 UIKit 私有 platter 类，不按系统版本选择自绘底栏。

iOS 18 及以上使用 `Tab(value:content:label:)` 声明入口与稳定的功能 ID，并采用 `.tabBarOnly` 系统样式；iOS 17.4 仅保留原生 `.tabItem` 入口，这是最低部署版本需要的单一兼容分支。两条路径均无自绘底栏。每个入口的页面由独立 `NativeTabPage` 管理，页面主题不写入导航栏。路由冷却通过视图生命周期内的 `.task(id:)` 管理，快速切换会取消前一轮等待。

底部入口仍由 `BottomDockSettingsManager` 保存的四个功能配置决定，支持既有收藏入口与路由。iPad、折叠／双屏窗口的布局依据实际可用尺寸，由系统导航容器管理，不猜测设备型号。

页面滚动内容使用原生安全区。旧的固定 56 / 72pt 避让、环境值、各页面附加 padding、异形 shape 和菱形巡航已经删除。`TabBarItemAnchorResolver` 只为新手引导读取当前可见 UITabBar 中的公共控件位置；读不到时提供近似高亮位置，不能用作业务布局或内容避让依据。

主题的 `tabBarMain` / `tabBarItem` rawValue 与 18 项存档结构继续保留，避免破坏历史购买和配置。它们不再生成 descriptor、呈现开关或影响系统导航。主题商品的静态归档定义不变。
