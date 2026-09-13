# 梦裙时光馆 · CloudKit 公共库用户上传方案（V2）

> ## ⚠️ 本文档已被取代，仅作历史参考
>
> **不要按本文实现新功能。** 本文的核心前提是「**用户**可上传裙装图文到公共库」，
> 该方向已被明确否决——普通用户对公共库**零写权限**是现行设计的硬约束。
>
> 现行权威设计：`docs/Pink_House_TimeHall_Static_CloudKit_Design.md`
> （静态内容 + CloudKit 公共内容库 + 本地可清理缓存，生产通道与消费通道分离）。
>
> 现行实现与操作手册：
>
> | 内容 | 位置 |
> |---|---|
> | 发布协议与分层 DTO | `ItemManager/Models/TimeHall/TimeHallPublicationModels.swift` |
> | 三层校验 | `ItemManager/Services/TimeHall/TimeHallPublicationValidator.swift` |
> | 只读 Reader（类型层面无写能力） | `ItemManager/Services/TimeHall/TimeHallPublicCloudReader.swift` |
> | 本地缓存与清理 | `TimeHallPackCache.swift` / `TimeHallMediaCache.swift` |
> | Mac 发布流水线 | `tools/time_hall/publication/`（见其中 `README.md`） |
> | Record Type 与 Security Role 配置 | `tools/time_hall/publication/README.md` 的「CloudKit Console 前置」 |
>
> 本文中**仍然有效**的部分：容器选择（`iCloud.bugod2.ItemManager`）、
> `CKAsset` + `desiredKeys` 的取数思路。**已失效**的部分：`TimeHallEntry` 这个
> 用户投稿 Record Type、管理员 allowlist 作为唯一权限手段、以及「用户上传」整条链路。
>
> 保留原因：记录方案演进，避免重新提出「让用户写入公共库」的设计。

---

> 状态（原文）：**仅文档，V1 未实现上传**。V1 为 Bundle 本地馆藏（`ItemManager/Resources/TimeHall/`）。
> 目标：用户可上传裙装图文，写入 Apple CloudKit **Public Database**，全用户可读；调试链路复杂，先落版本管理。

## 1. 与现有能力的关系

| 现成参考 | 路径 | 可复用点 |
|---|---|---|
| Notice 公共公告 | `NoticeCloudKitService` + `Notice` | Public DB 容器 `iCloud.bugod2.ItemManager`、管理员 allowlist、`CKAsset`、desiredKeys |
| 每日问候 | `DailyGreetingManager` | 幂等 `recordName`、拉取失败回退本地 |
| 裙子股市 | `iCloud.bugod2.SkirtMarket` + GRDB SyncEngine | 多用户行情同步；**不要**把时光馆混进股市 schema |
| 衣橱 `isShared` | `Clothing.isShared` | 仅「同步到裙装广场」预留开关；**不要**把个人衣橱行直接当公共馆藏 |

结论：时光馆公共条目用 **新 record type**，不要复用 `Clothing` / `LolitaItem` / `Notice`。

## 2. 建议 Record Type

容器优先：`iCloud.bugod2.ItemManager`（与 Notice 同容器，便于统一权限调试）。

`TimeHallEntry`（Public DB）字段草案：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | String | UUID，兼作 `recordName` 建议 `th_<uuid>` |
| `title` | String | 裙名 |
| `brand` | String | 品牌 |
| `year` | Int64 | 年份 |
| `season` | String | spring/summer/autumn/winter |
| `styles` | String | 逗号分隔风格标签 |
| `storeLimit` | String? | 限定店 |
| `note` | String? | 说明 |
| `coverAsset` | CKAsset | 封面图 |
| `galleryAssets` | [CKAsset]? | 可选多图（或拆子 record） |
| `locale` | String | `zh-Hans` / `ja` |
| `status` | String | `pending` / `published` / `rejected` / `archived` |
| `createdBy` | String | `userRecordID.recordName` |
| `createdAt` / `updatedAt` | Date | |
| `sourceKind` | String | `user` / `editorial` / `import` |
| `moderationNote` | String? | 审核备注 |

Query：`status == published`，按 `year` / `createdAt` 排序。

## 3. 权限与审核

- **读**：所有已登录 iCloud 用户可读 published。
- **写**：任意登录用户可 `save` 自己的 `pending` 条目。
- **发布**：仅管理员（复用 Notice `adminIDs` 模式）把 `pending → published`。
- **删**：作者可删自己的 pending；管理员可归档任意条目。
- V2 不做开放免审直发，避免公共库被刷。

## 4. 客户端分层（实现时）

```
TimeHallCatalogStore          # V1 已有：Bundle JSON
        │
        ▼
TimeHallLibraryRepository     # V2：local cache ∪ CloudKit published ∪ 用户草稿
        │
        ├── TimeHallCloudKitService   # fetch/save/moderate（照 NoticeCloudKitService）
        └── TimeHallDraftStore        # 本地草稿 + 待上传 CKAsset
```

UI：

- 「我的投稿」：本地草稿、上传进度、审核状态。
- 编年史 / 风格浪花：合并 Bundle 种子 + CloudKit published（同 id 以云端为准）。

## 5. 调试清单（为何先写文档）

1. CloudKit Dashboard 建 `TimeHallEntry` + Security Roles（World Read / Authenticated Write）。
2. Development vs Production schema 提升。
3. 模拟器需登录 iCloud；Public DB 写入延迟与索引创建。
4. `CKAsset` 体积与压缩（沿用衣橱 downsample）。
5. 审核账号切换、拒绝回流、删后残留。
6. 与 Notice 同容器时的配额与错误隔离。

未完成以上任一步就写上传 UI，容易卡在「能编译不能同步」。

## 6. 迁移路径

1. **V1（当前）**：纯本地 `catalog.json` + `Resources/TimeHall/images`。
2. **V1.5**：只读拉取 Public `published`（仍无上传入口）。
3. **V2**：用户投稿 + 管理员审核 + 「我的投稿」。
4. **V3（可选）**：把官方编辑内容也迁到 CloudKit，Bundle 仅作离线兜底。

## 7. 明确不做

- 不把用户衣橱 `Clothing` 自动推到时光馆。
- 不新增第三方图床；媒体走 `CKAsset`。
- 不改 `ThemeSkinSlot` / 主题皮肤架构来承载馆藏图。
- 不 force-publish 到 Production，直到 Development 审核流跑通。
