# Android Migration · SmallWorld / House

## BATCH-M3-04 SmallWorld 主图 + 风格切换（日常/洛可可）

**背景**

- iOS `SmallWorldView.swift` 根据 `smallWorldStyle` 在洛可可与另一套小世界风格之间切换。
- iOS `RococoSmallWorldView.swift` 的核心视觉是房间主图：`small_world_rococo_1` / `small_world_rococo_2`，并在其上叠加热区与宠物层。
- Android 之前 House 默认进入小世界壳层，但内容仍偏“导航骨架说明”，没有把房间主图作为当前页主体。

**改动范围**

- `SmallWorldRoute.kt`
  - 在 `SmallWorldFeatureScreen` 中对 `SmallWorldDestination.SmallWorld` 做专门分支，不再只展示通用“已接通导航骨架”卡片。
  - 新增 `SmallWorldRoomStage`：根据顶部 `日常 / 洛可可` 分段选择 `PinkHouseAssets.smallWorldNormal` 或 `PinkHouseAssets.smallWorldRococo`，以原图比例 `ContentScale.Fit` 展示主图。
  - 主图上叠加当前风格胶囊：`日常小世界` / `洛可可小世界`。
  - 主图下补充阶段提示，并保留 `少女衣橱`、`萌宠对话`、`热区待接入` 软圆入口。
  - 继续复用已有资产注册；本批未新增素材。当前 Android 资产已有 `small_world_bg_normal.png` 与 `small_world_rococo_1.png`，iOS 的二层 `small_world_rococo_2` 暂缺，留给后续素材批。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中；`git diff --check` 通过。
- Android Emulator 装机验证：
  - 进入 `House → 小世界`，可见 `日常小世界` 主图、`日常房间主图已接入`、`少女衣橱`、`萌宠对话`、`热区待接入`。
  - 点击顶部 `洛可可` 分段后，主图切换为洛可可素材，可见 `洛可可小世界` 与 `洛可可房间主图已接入`。
- 截图记录：
  - `/tmp/pinkhouse_m3_04_smallworld_daily.png`
  - `/tmp/pinkhouse_m3_04_smallworld_style_switch.png`

**后续待办**

- `BATCH-M3-05`：SmallWorld 热点交互。基于主图叠加可点区域，优先接 `少女衣橱`、`心愿尾款`、`萌宠对话` / 已有 House 内页入口。
- 素材待补：`small_world_rococo_2` 二层房间图。


## BATCH-M3-05 SmallWorld 热点交互（点击场景元素）

**背景**

- M3-04 已把小世界主图接入，但仍需要通过下方按钮跳转；iOS `RococoSmallWorldView.swift` 通过 `SmallWorldHotspotSpec` 在房间图上叠加响应式热区。
- 本批先做 Android 的轻量热区层：不追求所有 iOS 坐标一次到位，先把最高频入口点通，后续可继续精调热区和调试开关。

**改动范围**

- `SmallWorldRoute.kt`
  - 新增 `SmallWorldHotspotAction` 与 `SmallWorldHotspotUi`，把热区标签、相对坐标和动作分离。
  - `SmallWorldRoomStage` 内根据 `日常 / 洛可可` 风格生成不同热区列表：
    - 日常：`少女衣橱`、`萌宠对话`、`心愿尾款`。
    - 洛可可：`少女衣橱`、`心愿尾款`、`马上来财`、`梦裙日历`、`穿搭手帐`。
  - 使用 `BoxWithConstraints` + 相对坐标 `x/y` 叠加 `SmallWorldHotspotPill`，不同屏宽下跟随主图区域移动。
  - `SmallWorldFeatureScreen` 增加 `onOpenDestination` 与 `onOpenDepositPlan` 回调，热区可直接跳衣橱 Tab、心愿尾款 Tab、萌宠对话或 House 内已有目的地。
  - 底部辅助入口从 `热区待接入` 改为 `热区已接入`。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：新增 diff 无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中；`git diff --check` 通过。
- Android Emulator 装机验证：
  - `House → 小世界` 可见叠加在主图上的 `少女衣橱`、`萌宠对话`、`心愿尾款` 热区标签，以及底部 `热区已接入`。
  - 点按主图 `心愿尾款` 热区后跳转到衣橱的心愿尾款页，可见 `总待付尾款`、`按月视图`。
- 截图记录：
  - `/tmp/pinkhouse_m3_05_smallworld_hotspots.png`
  - `/tmp/pinkhouse_m3_05_hotspot_deposit_nav.png`

**后续待办**

- 热区坐标精调：对照 iOS `SmallWorldHotspotSpec` 和实际素材，继续校准各入口点击范围。
- 后续 M4：进入签到 / 日历 / 通知等留存入口。
