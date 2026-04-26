# Android Migration · CheckIn 每日打卡

## BATCH-M4-01 CheckInRoute 每日打卡首屏

**背景**

- iOS 母本：`ItemManager/Views/CheckIn/DailyCheckInView.swift`。
- 本批对齐首屏高频留存信息：日期问候、连续打卡、本周 7 日签到、今日穿搭色、打卡按钮与打卡后分享入口。
- Android 先做本地 UI 与会话内状态，不接 CloudKit / LLM / 天气 / 分享图生成；后续可在数据批次接持久化与同步。

**改动范围**

- `feature/checkin/CheckInRoute.kt`（新建）
  - 新增 `CheckInRoute`，用 `rememberSaveable` 保存本次会话内 `hasCheckedIn`。
  - 新增 `CheckInHeader`：显示当天日期、问候文案、萌宠推荐标签与连续打卡天数。
  - 新增 `WeekCheckInCard`：按当前周展示周一到周日，今天打卡后显示粉色选中圆与勾选图标。
  - 新增 `OutfitColorCard`：展示 `今日穿搭色`、3 个软圆色块与打卡前/后的搭配建议文案。
  - 新增 `CheckInActionButton`：`立即打卡` → `今日已打卡`；打卡后出现 `分享今日穿搭` 入口。
- `feature/smallworld/SmallWorldRoute.kt`
  - House 菜单新增 `每日打卡` 目的地，保留底部主导航不扩张。
  - `SmallWorldFeatureScreen` 新增 CheckIn 分支，House 内页内容区改为可滚动，避免签到卡片和底部主导航互相遮挡。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：本批业务文件无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中；`git diff --check` 通过。
- Android Emulator 装机验证：
  - 进入 `House → 菜单 → 每日打卡`，可见 `每日打卡`、`本周签到`、`今日穿搭色`、`立即打卡`。
  - 点按 `立即打卡` 后，按钮变为 `今日已打卡`，本周今日格子显示勾选，并出现 `分享今日穿搭`。
- 截图记录：
  - `/tmp/pinkhouse_m4_01_checkin_home.png`
  - `/tmp/pinkhouse_m4_01_checkin_checked.png`

**后续待办**

- 持久化：将每日打卡状态、连续天数与历史记录接入本地数据层。
- 数据同步：如需多端一致，再按 iOS 现有 `DailyCheckInManager` / CloudKit 语义设计 Android 同步降级方案。
- 分享：后续单批补分享卡片生成与系统分享入口。
