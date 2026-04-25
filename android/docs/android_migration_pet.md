# Android 复刻记录 · Pet 萌宠 Home

## BATCH-M3-03 · PetRoute 完整化（F-11 ~ F-17）

- 业务范围：重做 `feature/pet/PetRoute.kt`，新增 `feature/pet/PetViewModel.kt`，并按用户确认追加 `core/navigation/PinkHouseApp.kt` 挂载入口，保证可装机验证。
- iOS 母本：`ItemManager/Views/Pet/PetHomeView.swift`、`PetStatusHeaderView.swift`、`PetBottomPanel.swift`、`PetInteractionAreaView.swift`。
- UI 合同：顶部返回/标题/货币与状态显隐；双宠切换；四项状态条；中心宠物互动区；喂食/饮水/清洁/抚摸/打工；背包/商店面板入口；互动记录。
- Android 降级：不接 AI、语音、视频播放器、真实商店支付与拖拽投喂；本批用本地 `StateFlow` 状态机与现有宠物 portrait 资源。
- 入口策略：`我 → 智能萌宠` 与底部奶茶浮层进入宠物 Home；底部 `萌宠对话` Tab 保持聊天页，避免“养宠”和“聊天”入口混淆。

### 验证

- `JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home ./gradlew :app:assembleDebug`：通过。
- 红线 grep：本批业务文件内 `0xFF[0-9A-F]{6}`、`\d+\.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 均无命中。
- 装机验证：`emulator-5554` 安装 `app-debug.apk`，从衣橱页点击底部奶茶浮层进入 `萌宠小家`，确认双宠切换、状态条、货币、喂食/饮水/清洁/抚摸/打工与互动记录可见。截图：`/tmp/pinkhouse_m3_03_pet_home.png`。

### 待办

- 宠物 Home 后续应补状态持久化、真实背包/商店数据、打工倒计时、拖拽投喂与多姿态素材。
- SmallWorld 需要承接宠物停驻入口，让 House 与宠物 Home 形成一致的空间路径。
