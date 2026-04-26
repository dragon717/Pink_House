# Android Migration · Dream Dress Calendar 梦裙日历

## BATCH-M4-02 CalendarRoute 首屏 + 近期/月/年视图

**背景**

- iOS 母本：`ItemManager/Views/Calendar/DreamDressCalendarView.swift`。
- iOS 页面核心结构是 `近期 / 月视图 / 年视图` 三种模式，默认只看心愿尾款，并按衣物的定金日、尾款日生成日程。
- Android 本批优先接真实衣橱数据查询，不做主题选择器、弹窗详情、通知事件上报和分享能力。

**改动范围**

- `feature/calendar/CalendarRoute.kt`（新建）
  - 从 `PinkHouseApplication.appContainer.wardrobeRepositoryForViewModel.observeItems()` 读取真实衣橱数据。
  - 新增会话内 `只看心愿尾款 / 全部衣物日期` 筛选；默认只看心愿尾款，对齐 iOS `calendarShowDepositPlanOnly` 默认行为。
  - 将 `WardrobeItem` 转成日历事件：`定金`、`尾款开始`、`尾款截止`，非尾款模式下补 `入手` 日期。
  - 新增顶部统计：未来 30 天安排数、待付尾款金额与最近日期。
  - 新增三段视图：
    - `近期`：昨天 / 今天 / 明天 + 未来一周摘要。
    - `月视图`：当前月 + 下月双月滚动日历，日期格显示事件圆点，点按日期可看当天安排。
    - `年视图`：12 个月热力概览，月卡展示事件密度与尾款金额，点月卡回到该月。
- `feature/smallworld/SmallWorldRoute.kt`
  - `SmallWorldDestination.Calendar` 接入 `CalendarRoute()`，从 House 菜单和小世界热区均可进入。
  - 对 `每日打卡 / 梦裙日历` 这类已复刻独立页，隐藏通用“复刻规则 / 快速入口”占位卡，减少对真实页面 UI 的干扰。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：本批业务文件无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中；`git diff --check` 通过。
- Android Emulator 装机验证：
  - `House → 菜单 → 梦裙日历` 可见 `梦裙日历`、`30天安排`、`待付尾款`、`只看心愿尾款`、`近期 / 月视图 / 年视图`。
  - 月视图可见 `双月滚动视图` 与日期圆点；年视图可见 `2026年 概览`、1–6 月热力卡与 4 月事件/金额；近期视图可见 `昨天 / 今天 / 明天` 与定金、尾款开始等真实数据。
- 截图记录：
  - `/tmp/pinkhouse_m4_02_calendar_month.png`
  - `/tmp/pinkhouse_m4_02_calendar_year.png`
  - `/tmp/pinkhouse_m4_02_calendar_recent.png`

**后续待办**

- 弹窗详情：对齐 iOS `UnifiedEventsPopup`，点日期或月份时显示当天/当月全部事件列表。
- 主题选择器：后续单批对齐 iOS `CalendarThemeSelectorView`，但不得引入 dynamicColor。
- 持久化：如需记住视图模式与筛选偏好，再接入 DataStore。
