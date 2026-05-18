# 穿搭手帐恢复与 iCloud 及时恢复 · 重构执行计划（harness）

> 状态：2026-05-01 调研首版；同日已按 M1-M5 完成首轮代码落地。iOS 阶段可按任务需要运行 `xcodebuild` 构建/测试/模拟器验收；Codex 仍需保留静态检查、`git diff --check`、parse-only 校验等轻量验证，并在最终报告中写明实际跑过的命令、结果和验证边界。

## 实施记录（2026-05-01）

- M1：`BackupService.restoreFromManifest()` 已先恢复平面 `BookGroup`，再恢复 `OOTDSnapshotDTO` 到 `Outfit`，并以 `bookID` 二次 relink，避免空库恢复时书页先变孤儿。
- M2：`BookShelfView.performMigration()` 已改为调用 `OOTDOrphanPageRepairService`；多手帐场景下无归属证据的孤儿页会被延后处理，不再批量塞入“默认手帐”。
- M3：恢复完成后已统一 `processPendingChanges()` + `save()`，并发送 `dataRestoreCompleted` / `ootdRestoreCompleted`；书架与书页详情监听通知刷新。`CloudSyncManager` 已按 widget/theme/wealth/OOTD 图片角色判断本地目标目录。
- M4：`SwiftDataMigrationManager` 已在实体迁移后统一重建 `Outfit.book`、`OutfitItem.outfit/cutout`、`SpaceOutfit.book` 与 `SceneObjectData` 关系。
- M5：`RecycleBinView` 已统一恢复后的保存口径，平面/空间手帐、书页、3D 模型与拼豆恢复后会立即持久化。
- Harness：静态验收结果写入 `temp/_ootd_restore_harness/accept/20260501-025533/RESULT.md`（`temp/*` 默认不提交）；`git diff --check`、修改 Swift 文件 `swiftc -parse`、静态 harness 7/7 均通过。

## 0. 启动协议

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
FEATURE_ID="ootd_journal_restore_v1"
HARNESS_DIR="$PROJ/temp/_ootd_restore_harness"
RUN_DIR="$HARNESS_DIR/runs/$(date +%Y%m%d-%H%M%S)"
ACCEPT_DIR="$HARNESS_DIR/accept/$(date +%Y%m%d-%H%M%S)"
```

- 所有路径、JSON、日志按 UTF-8 读写；中文路径必须 quote。
- 修改目标只限 iCloud Swift/Xcode 仓库：`$PROJ`。
- 验收产物放 `temp/_ootd_restore_harness/runs|accept/<ts>/`，默认不提交。
- 每个阶段做小版本：一个阶段一个 diff，一个验收点不通过就回滚/补丁，而不是把恢复、iCloud、UI 刷新混成一个大提交。

## 1. 调研结论（当前架构）

### 1.1 数据模型

- 模型集中在 `ItemManager/Clothing.swift`：
  - `BookGroup`：平面手帐本，`pages` 级联到 `Outfit`。
  - `Outfit`：平面书页，持有 `book: BookGroup?`、`items: [OutfitItem]?`、`snapshotPath`、`backgroundImagePath`、`canvasType`、`mannequinAssetID`、软删除与 `lastModified`。
  - `OutfitItem`：书页上的贴纸实例，引用 `CutoutItem` 与 `Outfit`。
  - `CutoutItem`：贴纸图片，图片路径保存在 `imagePath`，通过 `linkedClothingID` 解耦衣物删除。
  - 空间手帐另有 `SpaceBookGroup` / `SpaceOutfit`，场景对象通过 `SceneObjectData.spaceOutfitID` 关联。

### 1.2 UI 与自动迁移

- 入口：`OOTDView` → `BookShelfView` → `BookDetailView` → `OOTDEditorView/OOTDCanvasView`。
- `BookShelfView.performMigration()` 会把 `book == nil` 且未删除的孤儿平面书页迁到“默认手帐”；如果没有默认手帐则创建，若已有任意手帐则也可能迁到第一个手帐。
- 这段逻辑本来用于历史孤儿数据兜底，但在“恢复尚未重建 book 关系”的窗口里会把其它手帐的书页归入默认手帐，是本次问题的核心风险点之一。

### 1.3 持久化、文件与备份

- SwiftData 容器由 `SharedPersistence` / `SwiftDataMigrationManager` 创建；可选择本地或 SwiftData CloudKit 私有库。
- 图片/快照/贴纸主要经 `ImageManager.imagesDirectory` 保存：优先 iCloud Documents 的 `Documents/Images`，不可用时回退 App Documents/Images。
- 本地 `.save` 备份由 `BackupService.prepareBackupData` 产出：
  - `manifest.json` 保存 DTO。
  - 图片文件通过 `NativePackageWrapper`（FileWrapper + LZFSE）一起打包。
  - 平面书页新格式是 `OOTDSnapshotDTO`，其中 `bookID` 是恢复到原手帐的关键字段。
- 云端文件备份由 `CloudSyncManager` 使用 CloudKit Private DB：`BackupIndex_v4` 存 manifest asset，`BackupImage` 按 hash 存文件 asset；恢复后调用同一个 `BackupService.restoreFromManifest()`。

## 2. 已定位的恢复问题链路

### P0：恢复顺序导致 `bookID` 失效

当前 `restoreFromManifest()` 的阶段顺序是：基础模型 → `restoreClothingAndOutfits()` → `restoreModel3Ds()` → `restoreBookGroups()`。

但 `restoreClothingAndOutfits()` 在恢复 snapshots 时只预取“已经存在”的 `BookGroup`，然后按 `dto.bookID` 赋值：

```swift
if let bookID = dto.bookID {
    outfit.book = bookGroupMap[bookID]
}
```

如果是空库恢复或目标库还没有对应手帐，`bookGroupMap[bookID]` 为 nil，书页就变成孤儿。后面的 `restoreBookGroups()` 虽然会创建手帐，但平面书页关系重建循环是空实现，所以不会把这些书页重新接回原书。

### P0：UI 兜底迁移会放大误归因

书页成为孤儿后，`BookShelfView.performMigration()` 会把所有孤儿迁到“默认手帐”或第一个手帐。用户看到的现象就是：其它手帐的平面书页都被恢复到默认手帐。

### P1：恢复后没有统一 final save / UI 刷新通知

`restoreFromManifest()` 阶段 2 后有一次 `context.save()`，但阶段 3/4 复杂关系与设置恢复后缺少统一 final save、`processPendingChanges()` 与“恢复完成”通知。SwiftData/视图层可能等 autosave 或下次进入页面才刷新，不满足“iCloud 及时恢复”。

### P1：SwiftData 本地→iCloud 迁移复制时丢关系

`SwiftDataMigrationManager` 里 `migrateOutfits()` 先复制 `Outfit`，`migrateBookGroups()` 后复制 `BookGroup`；`createOutfitCopy(from:)` 明确 `book: nil`，`createOutfitItemCopy(from:)` 也把 `cutout/outfit` 置 nil，后续没有关系重建。这会让开启 SwiftData iCloud 同步时的老数据迁移也产生孤儿书页/贴纸实例。

### P1：云端文件恢复的文件路由不够精确

`CloudSyncManager.restoreFromCloudInternal()` 对 `externalFileHashes` 里除 widget 外的文件默认按 Documents 判断本地是否存在。但 OOTD 的 snapshot/background/cutout 多数实际在 `ImageManager.imagesDirectory`。这不一定直接导致失败，但会造成重复下载、错误本地命中判断，并增加“图片刚恢复还没显示”的概率。

### P2：回收站恢复缺少统一保存与 lastModified 口径

`RecycleBinView.restoreClothing()` 会立刻保存，但 `restoreBook()` / `restoreOutfit()` / 空间手帐恢复只改对象和 DeleteTracker，没有统一 `try modelContext.save()`。在 iCloud/SwiftData 合并场景下，恢复状态可能不够及时或被旧删除状态覆盖。

## 3. 重构目标

1. **关系优先恢复**：平面书页必须按 `OOTDSnapshotDTO.bookID` 回原 `BookGroup`；没有关系证据时不允许批量塞入默认手帐。
2. **恢复幂等**：同一备份重复恢复不重复书页/贴纸，不丢排序，不误复活删除项。
3. **iCloud 及时可见**：本地 `.save` 与 CloudKit 云备份恢复完成后，书架/书页列表立即刷新；图片缺失时触发下载并显示可恢复状态。
4. **兼容旧备份**：新增 DTO 字段必须 optional；旧备份缺字段时仍可恢复，无法还原归属的旧书页进入明确的“遗留待整理”策略，而不是默认误归因。
5. **小步提交**：每个阶段可独立开发、验收和回滚。

## 4. 目标架构方案

### 4.1 建立 OOTD 恢复上下文（不先改模型）

在 `BackupService.RestoreContext` 增加运行期映射，不改变持久化模型：

- `snapshotBookIDs: [UUID: UUID]`：`snapshot.id -> bookID`，从 manifest.snapshots 解析。
- `legacyOutfitBookIDs: [UUID: UUID]`：如果未来给 `OutfitDTO` 或 `BookGroupDTO` 增加 optional 冗余字段，放这里。
- `restoreStartedAt / restoreSource`：只用于日志与通知，不进入备份格式。

### 4.2 调整恢复顺序

推荐顺序：

1. 文件恢复。
2. 基础模型：Brand/Tag/StoredImage。
3. 先 upsert 平面 `BookGroup` 与空间 `SpaceBookGroup`（只建书本，不建空间书页场景）。
4. 恢复 Clothing / Wealth / Cutout / Model3D。
5. 恢复平面 `Outfit` / `OutfitItem`，此时 `bookGroupMap` 已可用，直接设置 `outfit.book`。
6. 恢复空间 `SpaceOutfit` / `SceneObjectData`。
7. 恢复设置、主题、签到、用户资料。
8. 统一 `context.processPendingChanges()` + `try context.save()` + 发送 `ootdRestoreCompleted` / `dataRestoreCompleted` 通知。

如果为了降低 diff 风险不拆大函数，也至少要：

- 在 `restoreClothingAndOutfits()` 开头用 `manifest.bookGroups` 预先 upsert `BookGroup`，再恢复 snapshots。
- 删除 `restoreBookGroups()` 中的空循环，改成按 `snapshotBookIDs` 二次 re-link，作为兜底校验。

### 4.3 把“孤儿书页迁移”从 View 私有逻辑移到服务

新增或重构为 `OOTDOrphanPageRepairService`：

- 输入：`ModelContext`、触发来源（startup / restoreCompleted / manualRepair）。
- 规则优先级：
  1. 有 manifest/bookID 映射：回原书。
  2. 魔法贴纸专用页（默认手帐 + `少女魔法贴`）：回默认手帐。
  3. 历史旧数据且全库无其它手帐：创建/使用默认手帐。
  4. 多手帐且无任何归属证据：不自动归默认，记录到 repair report，后续可显示“待整理书页”。
- `BookShelfView.performMigration()` 只调用服务，不再直接批量改关系。

### 4.4 Cloud/iCloud 恢复及时化

- `BackupService.restoreFromManifest()` 成功后统一保存、清缓存、发通知：
  - `Notification.Name.ootdRestoreCompleted`
  - `Notification.Name.dataRestoreCompleted`
- `BookShelfView` / `BookDetailView` 监听通知后 `loadPages()` / 刷新 `NavigationPath` 中的 book。
- `CloudSyncManager` 文件恢复前根据 manifest 建立 `fileName -> storageRole`：
  - widget 背景 → App Group。
  - `themeFiles` / `wealthFiles` → Documents。
  - 其它 OOTD/StoredImage/Cutout/Snapshot → `ImageManager.imagesDirectory`。
- 对 iCloud Documents 图片：恢复后可对缺失文件调用 `ImageManager.downloadFileIfNeeded`，但不能阻塞模型关系恢复。

### 4.5 备份格式兼容策略

- 当前新格式已有 `OOTDSnapshotDTO.bookID`，先以它为 source of truth。
- 可选增强：给 `BookGroupDTO` 增加 `pageIDs: [UUID]?` 作为冗余校验字段；必须 optional，旧备份默认 nil。
- 如给旧 `OutfitDTO` 补 `bookID: UUID?`，也必须 optional，并只影响 legacy backup 路径。
- 新增字段后同步更新：`BackupModels.swift`、`BackupService` export/import、`SwiftDataMigrationManager`、测试 fixture。

## 5. 小版本路线

### M0 — harness 与调研文档（本次）

交付：
- `docs/OOTD_JOURNAL_RESTORE_REFACTOR_EXEC_PLAN.md`
- `docs/OOTD_JOURNAL_RESTORE_REFACTOR_ACCEPT_PLAN.md`

验收：
- `git diff --check`
- 确认只新增计划/验收文档，不触碰业务代码。

### M1 — 平面手帐恢复顺序与关系修复

目标文件：
- `ItemManager/Services/BackupService.swift`
- `ItemManager/Services/BackupModels.swift`（仅当需要 optional 冗余字段）
- `ItemManagerTests/BackupRestoreIntegrationTests.swift`

任务：
- 先 upsert `BookGroup`，再恢复 snapshots。
- 用 `dto.bookID` 精确设置 `outfit.book`；恢复后扫描 `manifest.snapshots`，任何 `bookID` 非 nil 但本地关系 nil 直接报错或修复。
- 增加测试：两个手帐 + 多书页恢复到空库，重复恢复不重复，所有 `bookID` 不丢。

建议 commit：`[M1] 修复穿搭手帐备份恢复的平面书页归属`

### M2 — 默认手帐迁移服务化与安全闸门

目标文件：
- `ItemManager/Views/OOTD/BookShelfView.swift`
- 新增或并入 `OOTDOrphanPageRepairService`（当前可落在既有 OOTD 服务文件内，避免漏加 Xcode target membership）
- `ItemManagerTests/...`

任务：
- 把 `performMigration()` 的直接迁移逻辑挪到服务。
- 禁止“多手帐 + 无归属证据”的孤儿书页自动塞默认。
- 魔法贴纸默认手帐路径保留，不影响 `OOTDDefaultBookView`。

建议 commit：`[M2] 收紧穿搭手帐孤儿书页迁移规则`

### M3 — iCloud/云备份恢复后及时刷新

目标文件：
- `ItemManager/Services/BackupService.swift`
- `ItemManager/Services/CloudSyncManager.swift`
- `ItemManager/Views/OOTD/BookShelfView.swift`
- `ItemManager/Views/OOTD/BookDetail/BookDetailView.swift`

任务：
- 增加 final save + notification。
- 修正 CloudSync external file 路由。
- BookShelf/BookDetail 监听恢复完成并刷新。

建议 commit：`[M3] 提升穿搭手帐 iCloud 恢复即时性`

### M4 — SwiftData 本地到 iCloud 迁移关系补全

目标文件：
- `ItemManager/Services/SwiftDataMigrationManager.swift`
- 相关测试/调试脚本。

任务：
- 迁移时先复制书本，再复制书页，或迁移后建立 `bookID -> BookGroup`、`outfitID -> Outfit`、`cutoutID -> CutoutItem` 映射。
- `createOutfitCopy` 后设置 `new.book`。
- `createOutfitItemCopy` 后设置 `new.outfit` / `new.cutout`。
- 空间书页同理设置 `SpaceOutfit.book`，SceneObjectData 保持 `spaceOutfitID`。

建议 commit：`[M4] 补全 SwiftData iCloud 迁移中的手帐关系`

### M5 — 回收站恢复与 DeleteTracker 口径统一

目标文件：
- `ItemManager/Views/RecycleBinView.swift`
- `ItemManager/Services/DeleteTracker.swift`（如需空间手帐追踪）

任务：
- `restoreBook` / `restoreOutfit` / 空间恢复后统一保存。
- 恢复时更新 `lastModified`，移除 DeleteTracker 删除记录。
- 视需要补 SpaceBook/SpaceOutfit 的删除追踪。

建议 commit：`[M5] 统一手帐回收站恢复的保存与同步口径`

### M6 — 验收脚本与回归夹具（可选增强）

建议新增：
- `scripts/ootd_restore_harness/audit_ootd_restore_manifest.py`
- `temp/_ootd_restore_harness/fixtures/`（不放真实隐私图，仅放最小 JSON fixture 或脚本生成 fixture）

任务：
- 生成/解析最小 manifest：2 个平面手帐、3 个平面书页、1 个默认魔法贴纸页、1 个空间手帐。
- 输出 `REPORT.json`：书本数、书页数、孤儿数、默认手帐误归因数、缺图数。

建议 commit：`[M6] 增加穿搭手帐恢复 harness 验收脚本`

## 6. 验证命令

默认允许：

```bash
cd "$PROJ"
git diff --check
rg -n "bookID|restoreBookGroups|restoreClothingAndOutfits|performMigration|ootdRestoreCompleted" ItemManager docs ItemManagerTests
```

按任务需要可追加 iOS 构建/测试验证：

```bash
xcodebuild -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:ItemManagerTests/BackupRestoreIntegrationTests \
  test
```

## 7. 风险与不改边界

- 不改变 `BookGroup` / `Outfit` 的 SwiftData 模型字段，除非后续确认需要 schema 迁移。
- 不把所有旧孤儿书页默认塞回“默认手帐”；宁可输出“待整理”报告，也不要误归因。
- 不把 OOTD 图片迁出 `ImageManager.imagesDirectory`；只修正恢复时的路由和下载触发。
- 跑 `xcodebuild` 时必须记录 scheme、destination、测试范围、PASS/FAIL 与未覆盖边界；若用户明确要求本次不跑构建，则遵守该次约束。
