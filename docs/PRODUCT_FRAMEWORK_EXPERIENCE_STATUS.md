# 产品框架体验正式状态

> 更新日期：2026-05-25  
> 只读核对来源：`ItemManager/Models/AppFeatureRegistry.swift`、`ItemManager/Models/SmallWorldStyle.swift`、`ItemManager/Views/MainTabView.swift`、`ItemManager/Views/FavoriteMenuSettingsView.swift`、`ItemManager/Views/SmallWorldView.swift`、`ItemManager/Views/BookHouseSmallWorldView.swift`、`ItemManager/Views/SmallWorldMenuOverlay.swift`、`temp/产品框架体验/*`。

## 文档定位

`temp/产品框架体验/` 是产品框架专项的历史 harness / 待迁移归档，不能继续作为长期 source of truth。后续产品框架状态以本文件、实际 Swift 代码、以及后续正式执行 / 验收文档为准。

本轮不删除 `temp/产品框架体验/`，因为其中仍包含历史执行计划、验收模板、自测 RESULT 与未闭环项；删除前需要先完成真实流程截图、accept 归档和未完成 P3/P4 的正式 backlog 迁移。

## 当前实际状态

### P0 Feature Registry

- `AppFeatureRegistry` 已统一核心功能入口：衣橱、心愿尾款、House、我、萌宠、萌宠对话、魔法贴纸、穿搭手帐、来财、梦裙日历、世界书、拼豆工坊、裙装股市、回收站。
- 每个入口包含稳定 id、标题、副标题、SF Symbol、颜色、路由、解锁项与展示容器。
- 展示容器目前是 `bottomDock`、`houseRoom`、`petPhone`。

### P1 四槽底部导航

- `BottomDockSettingsManager.slotCount` 为 4。
- 默认四槽为：`wardrobe`、`house`、`me`、`petChat`，即“衣橱 / House / 我 / 萌宠对话”。
- `house` 与 `me` 是安全入口，`sanitizedLayout` 会强制保留，避免房间和设置页失联。
- 当前持久化 key 是 `bottomDockLayout.v2`，旧 `bottomDockSelectedFeature.v1` 仅作为迁移来源。
- `MainTabView` 的自定义底栏逐槽读取 `BottomDockSettingsManager.slots`；点击入口按 `AppFeatureRoute` 跳转到主 Tab、衣橱二级 Tab 或 SmallWorld 目的地。
- `FavoriteMenuSettingsView` 只提供“底部导航”四个位置配置；选择重复入口时会槽位互换。

### 萌宠入口边界

- `petHome` 仍存在，但 surfaces 只有 `houseRoom` 与 `petPhone`，不在 `bottomDock` 候选里。
- `petChat` 保留在 `bottomDock` 与 `petPhone`，路由为主 Tab 3。
- 因此底栏不展示“萌宠”主页入口，但保留“萌宠对话”。

### House / SmallWorld

- 旧 `journalRoom` 结论已过期。
- 当前 `SmallWorldStyle` 只有 `bookHouse = "book_house"`，显示名为“书本 House（默认）”。
- `SmallWorldView` 直接渲染 `BookHouseSmallWorldView`，并在出现时把非 `book_house` 的旧存储值纠正回 `book_house`。
- `BookHouseSmallWorldView` 是当前 House 实现：书本房间原型内放置多个功能热区，包括衣橱、魔法贴纸、心愿尾款、穿搭手帐、梦裙日历、来财、世界书、裙装股市、萌宠、萌宠对话、拼豆工坊。
- `SmallWorldMenuOverlay` 仅保留 House 底栏 fallback frame helper，注释已说明 House 长按快捷菜单退休。

## 未闭环项

- P2 BookHouse / House UI 仍缺真实产品流程截图和 accept 归档；已有代码不等于视觉验收完成。
- P3 萌宠手机 MVP 未完成：`petPhone` 作为 registry surface 已存在，但手机壳、原生入口网格和对应流程验收仍待实现。
- P4 裙子股市外链情报站未完成：当前有 `dressStock` 入口，但手动链接观察列表、价格 / 图片 / 备注沉淀、宠物读取提醒等仍待正式实现。
- 真实流程截图与 `accept/<ts>/RESULT.md` 归档仍缺：底栏默认四槽、底栏配置互换、House / Me 安全入口、petHome 不进底栏、petChat 保留、BookHouse 热区进入功能等都需要补图。
- `temp/产品框架体验/_artifacts/runs/*/RESULT.md` 仍是历史证据；删除 temp 前需要决定哪些 RESULT 摘要迁入正式 docs，哪些只保留在 git 历史。

## 删除 temp 前检查

1. 确认本文件已覆盖产品框架当前状态，且 `docs/TEMP_CLEANUP_INVENTORY.md` 指向本文件。
2. 补齐 P2 真实流程截图和 accept 归档。
3. 将 P3 / P4 未完成项迁入正式 backlog、执行计划或验收文档。
4. 最后一轮扫描 `rg -n "temp/产品框架体验|journalRoom|bookHouse|bottomDockLayout" ItemManager docs scripts *.md`，确认没有 runtime 或正式文档继续依赖旧 harness 口径。
5. 另起清理任务删除 temp；本轮禁止删除。
