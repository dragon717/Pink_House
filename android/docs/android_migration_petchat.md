# Android 复刻记录 · PetChat 萌宠对话

## BATCH-M3-01 · 首屏 + 3 个意图按钮

- 业务范围：新增 `feature/petchat/PetChatRoute.kt`，并在 `core/navigation/PinkHouseApp.kt` 将底部 `萌宠对话` Tab 绑定到该页面。
- iOS 母本：`ItemManager/Views/PetChat/PetChatView.swift:1-300`，抽取 `NavigationStack` 标题、聊天滚动区、欢迎气泡、历史搜索入口与搜索/输入入口语义。
- Android 降级：不接 AI / TTS / 智能穿搭；输入或意图按钮会立即追加用户气泡，并从本地兜底文案中随机回复。BATCH-M3-02 再把兜底文案池迁到 `strings_petchat.xml`。
- UI 结构：浅粉渐变背景、顶部返回/标题/历史搜索、毛毛立绘、欢迎卡片、A/B/C 三个意图按钮、底部输入栏。
- 资源说明：本批复用现有 `PinkHouseAssets.maomaoPortrait`，多姿态聊天素材后续单独补。

### 验证

- `JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home ./gradlew :app:assembleDebug`：通过。
- 红线 grep：新增/改动业务文件内 `0xFF[0-9A-F]{6}`、`\d+\.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 均无命中。
- 装机验证：`emulator-5554` 安装 `app-debug.apk`，点击底部 `萌宠对话` 后看到欢迎气泡、3 个意图按钮与底部输入；点击 `A. 帮我搭一套` 后追加用户气泡和本地兜底回复。截图：`/tmp/pinkhouse_m3_01_petchat.png`、`/tmp/pinkhouse_m3_01_petchat_intent.png`。

### 待办

- BATCH-M3-02：新增 `strings_petchat.xml`，将兜底回复池迁移为 string-array，并保证至少 10 条。
- 后续 M3：接宠物状态、历史记录持久化、更多菜单与素材替换。
