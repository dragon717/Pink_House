# Pink_House Android 复刻 Backlog

> 跨 session 进度看板。规范见 [PORT_HARNESS.md](PORT_HARNESS.md) §八。
> 新 session 接手前必读：本文 + PORT_HARNESS.md + 最近 5 个 commit。

---

## In Progress

无 — 等用户授权 commit 后接 ARCH-03 / ARCH-04 或进 M3。

---

## Ready

按优先级倒序，下回合从顶端取。

### 阶段 ARCH 已收尾 ✅（4 批全过）

### 阶段 CLEANUP（pre-existing tech debt，可在 ARCH 之后任意穿插）

- [ ] **BATCH-CLEANUP-01** AssetImage 占位渐变迁出硬编码
  - SCOPE: 2 文件 — `core/ui/PinkHouseDesignTokens.kt` + `core/ui/PinkHouseComponents.kt`
  - 把 `Color(0xFFF7F2F4)` / `Color(0xFFEFE8EC)` 提取到 token，遵循 R4 单一真源

### 阶段 M3（宠物 + 小世界 F-11 ~ F-25）

- [ ] **BATCH-M3-01** PetChatRoute 首屏 + 3 个意图按钮（替代当前 PetRoute 占位）
  - SCOPE: 2 文件
    - `feature/petchat/PetChatRoute.kt`（新建）
    - `core/navigation/PinkHouseApp.kt`（改 PetChat 路由绑定）
  - UPSTREAM: `ItemManager/Views/PetChat/PetChatView.swift:1-300`
  - PRD: F-19, F-20, W-03, W-04, W-05

- [ ] **BATCH-M3-02** PetChat 兜底文案池
  - SCOPE: 2 文件
    - `app/src/main/res/values/strings_petchat.xml`（新建）
    - `feature/petchat/PetChatRoute.kt`（接 stringArrayResource）
  - 至少 10 条兜底回复（PRD F-19 要求）

- [ ] **BATCH-M3-03** PetRoute 完整化（F-11 ~ F-17 宠物 home）
  - SCOPE: 2 文件 — `feature/pet/PetRoute.kt` + `feature/pet/PetViewModel.kt`
  - UPSTREAM: `ItemManager/Views/Pet/PetHomeView.swift` (588 LOC)
  - 缺资源：橘猫/奶茶犬多姿态（用粉色圆形占位）

- [ ] **BATCH-M3-04** SmallWorld 主图 + 风格切换（日常/洛可可）
  - SCOPE: 2 文件 — `feature/smallworld/SmallWorldHomeRoute.kt` + assets 注册
  - UPSTREAM: `ItemManager/Views/SmallWorldView.swift` + `RococoSmallWorldView.swift`
  - 缺资源：等距 2D 房间图（用粉色渐变占位）

- [ ] **BATCH-M3-05** SmallWorld 热点交互（点击场景元素）
  - 待 ARCH-02 + M3-04 完成后再具体化

### 阶段 M4（签到/日历/通知 F-26 ~ F-29、F-36 ~ F-38）

- [ ] **BATCH-M4-01** CheckInRoute（每日签到 F-26）
  - UPSTREAM: `ItemManager/Views/CheckIn/DailyCheckInView.swift` (1205 LOC)
  - F5 触发：超 1500 LOC 的话拆首屏 + 子区两批

- [ ] **BATCH-M4-02** CalendarRoute（梦裙日历 F-28）
  - UPSTREAM: `ItemManager/Views/Calendar/DreamDressCalendarView.swift` (918 LOC)

- [ ] **BATCH-M4-03** NoticeCenterRoute（通知中心 F-36）
  - 数据：本地表 `local_notification`，schema 升级走 Migration

### 阶段 M5（财富 + 拼豆 + OOTD）

- [ ] **BATCH-M5-01** WealthRoute 主页（F-30）
  - UPSTREAM: `ItemManager/Views/Wealth/WealthView.swift` (394 LOC)

- [ ] **BATCH-M5-02** Wealth 金币掉落动画（F-31）
  - 必须用 Compose 粒子，PRD 禁物理引擎

- [ ] **BATCH-M5-03** PerlerBeads 拼豆图案列表（F-39）
- [ ] **BATCH-M5-04** PerlerBeads 编辑器（F-40 / F-41）
- [ ] **BATCH-M5-05** OOTD 列表 + 编辑器（F-50 ~ F-53）

### 阶段 M6（VIP + IAP）

- [ ] **BATCH-M6-01** VipCenterRoute 视觉（F-32）— 仅 UI，支付下批
- [ ] **BATCH-M6-02** 微信/支付宝 SDK 接入决策与单批 gradle 改动
- [ ] **BATCH-M6-03** 喵币充值页（F-33）
- [ ] **BATCH-M6-04** VIP 开通 + 试用（F-34、F-54）

### 阶段 M7（备份/设置/分享/引导）

- [ ] **BATCH-M7-01** 数据备份导入导出（F-42 / F-43）
- [ ] **BATCH-M7-02** 设置页主体（F-44 ~ F-46）
- [ ] **BATCH-M7-03** 分享卡片（F-47 / F-48）
- [ ] **BATCH-M7-04** 新手引导（F-49）

---

## Blocked

- [ ] **BATCH-M5-01** WealthRoute — blocker: 缺 `mcoin_*.webp` / 纸币 / 金条贴图
- [ ] **BATCH-M6-02** 微信/支付宝 SDK — blocker: 决策（接入时机、商户号、合规）
- [ ] **BATCH-WEATHER-01** F-55 天气集成 — blocker: 和风 API key 申请

---

## Done

最近完成的在顶。每条带 commit hash + 链接到详细记录。

- [x] **BATCH-ARCH-04** SmallWorld 默认页左上图标语义调整 — `SmallWorldRoute.kt` SmallWorldFeatureScreen 内：destination == SmallWorld 时显 ☰ Menu 图标（语义"打开菜单"），子页保留 ← ArrowBack（语义"返回"），onClick 行为不变。assembleDebug 5s 通过。装机截图确认 ☰ 图标显示。 BackHandler 行为保留（按返回先进 Menu 再退 Tab），后续可继续优化但不阻塞 M3。
- [x] **BATCH-ARCH-03** 删除浮动 `PetChatFloatingButton` — 与底部 PetChat Tab 重复入口。改 2 文件：`PinkHouseApp.kt`（删 import + 删调用）+ `PinkHouseComponents.kt`（删函数定义）。naichaPeeking 装饰保留。assembleDebug 5s 通过。装机截图确认右下角浮动按钮消失，4 Tab 完整。
- [x] **BATCH-ARCH-02** House Tab 默认入口从 `Menu` 改为 `SmallWorld` — 改 1 处：`SmallWorldRoute.kt` line 105。装机截图确认 House Tab 直接落小世界页。assembleDebug 6s 通过。遗留：浮层菜单按钮 → ARCH-04。
- [x] **BATCH-ARCH-01** 启用第 4 底部 Tab `PetChat`（萌宠对话）— 改 1 处：`AppDestination.kt` `showInBottomBar` 默认走 true。  装机截图确认 4 Tab 对齐 iOS。assembleDebug 12s 通过。遗留：浮动猫与 Tab 重复入口 → ARCH-03。
- [x] **M2 衣橱闭环 F-01 ~ F-09** — 详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)
- [x] **本地尾款通知 F-29 部分** — `core/notification/DepositReminder*.kt` (commit 913c417)
- [x] **M1 主题 + Shell + 三 Tab + Room v1~v3** — 含资产入仓、SplashScreen 接入

---

**End of backlog**.
