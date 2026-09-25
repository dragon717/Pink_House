# Pink_House iOS 运营上传与回读修改方案

## 1. 目标与静态结论

远端基线：`main@0e5899ce41d5abbc1101ed19e18a726631d0e43f`。本文件是待实施方案，不代表本次已经改代码或上传。

目标是让现有 App 内的运营入口真正完成：

```text
选图 → 本地暂存 → CloudKit THMedia.asset
商品数据写入 mediaKey → THDataPack.asset
条件切换 THRelease → 普通 App 拉取商品与图片 → 显示
```

### 当前已实现 / 缺失

| 能力 | 当前实现 | 结论 |
|---|---|---|
| 商品录入与编辑 | `ShopCatalogOpsView`、管理页、深度编辑页 | 已有 UI |
| 选图 | `PhotosPicker`，最多多选 10 张 | 已有入口 |
| 图片处理 | 长边 1600、JPEG 0.85 | 只在本地处理 |
| 图片保存 | `Application Support/ShopCatalog/images`，引用为 `local:<文件名>` | 不是云端上传 |
| 商品草稿/覆盖层 | JSON 文件落盘 | 不是公共库 |
| JSON 导出 | 生成一个临时 JSON 后 Share Sheet/AirDrop | 不包含图片二进制 |
| iOS 商品 CloudKit 写入 | `ShopCatalogOps` 没有 `CloudKit` / `CKRecord` / `CKDatabase.save` | 缺失 |
| iOS 商品云端读 | `THRelease → THDataPack` | 已有 |
| iOS 商品图云端读 | Resolver 只处理 `http(s)` / `local:` / Bundle | 缺失 |

现有 `NoticeCloudKitService` 可以证明项目已经有“`publicCloudDatabase.save(record)` + `CKAsset(fileURL:)`”的写入样例，但它服务的是公告 `Notice`，不能直接当作商品库上传已完成；商品目录采用 `THRelease` / `THDataPack` / `THMedia` 的发布协议。

证据：

- [图片选择入口](https://github.com/dragon717/Pink_House/blob/0e5899ce41d5abbc1101ed19e18a726631d0e43f/ItemManager/Views/ShopCatalog/ShopCatalogImagePickerButton.swift)
- [图片存储与解析](https://github.com/dragon717/Pink_House/blob/0e5899ce41d5abbc1101ed19e18a726631d0e43f/ItemManager/Services/ShopCatalog/ShopCatalogStore.swift)
- [运营页导出 JSON](https://github.com/dragon717/Pink_House/blob/0e5899ce41d5abbc1101ed19e18a726631d0e43f/ItemManager/Views/ShopCatalog/ShopCatalogOpsView.swift)
- [商品公共库只读同步](https://github.com/dragon717/Pink_House/blob/0e5899ce41d5abbc1101ed19e18a726631d0e43f/ItemManager/Services/ShopCatalog/ShopCatalogCloudSyncService.swift)
- [公告的 CloudKit Asset 写入样例](https://github.com/dragon717/Pink_House/blob/0e5899ce41d5abbc1101ed19e18a726631d0e43f/ItemManager/Services/NoticeCloudKitService.swift)

## 2. 推荐的 iOS 写入架构

### 2.1 SwiftData 只做本地草稿

新增的运营草稿、上传任务、失败原因和重试次数使用 SwiftData 本地保存，显式设置 `ModelConfiguration(cloudKitDatabase: .none)`。不要让 SwiftData 自动同步商品草稿，也不要把 SwiftData 模型当作公共目录 schema。

Apple 当前 `ModelConfiguration.CloudKitDatabase` 没有 `.public` 选项；公共目录必须走显式 CloudKit API。参考：[SwiftData CloudKitDatabase](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct)。

### 2.2 直接写同一公共库

使用：

```swift
let container = CKContainer(identifier: "iCloud.bugod2.ItemManager")
let database = container.publicCloudDatabase
```

但不改变现有消费协议。商品不是直接保存成一个 `Product` Record，而是：

1. `THMedia`：每张图片一个不可变 Record，`asset` 字段放 `CKAsset(fileURL:)`；
2. `THDataPack`：完整商品目录压缩 JSON，商品图片引用改为稳定 `mediaKey`；
3. `THRelease`：最后用当前 `recordChangeTag` 做条件更新，成为唯一可见版本。

Apple 文档：[公共数据库](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)、[CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)、[保存 CKRecord](https://developer.apple.com/documentation/cloudkit/ckdatabase/save%28_%3A%29-1j6fq)。

公共库写入需要运营设备有活动 iCloud 账号，且 CloudKit Security Role 已授权；普通用户仍只读。客户端的 `CreatorAccess` 只做入口控制，不替代服务端权限。

## 3. 图片真实上传流程

### 3.1 选图和暂存

保留 `PhotosPicker`，但把结果从“本地引用”升级为“上传任务”：

1. `PhotosPickerItem.loadTransferable(Data.self)` 取得字节；
2. 在本地临时目录规范化为允许的 JPEG/PNG；
3. 计算 SHA-256，生成 `mediaKey`；
4. 创建本地任务记录：商品 ID、资产 ID、路径、hash、状态 `staged`；
5. UI 预览仍可使用本地暂存文件，但预览不能把任务标为已发布。

### 3.2 上传媒体 Record

对每张图：

1. 先按 `th.media.<mediaKey>` 精确读取；已经存在且 `sha256`、字节数一致则跳过；
2. 不存在时创建 `CKRecord(recordType: "THMedia", recordID: ...)`；
3. 设置 `mediaKey`、`mimeType`、`sha256`、`byteCount` 和 `CKAsset(fileURL:)`；
4. `try await database.save(record)`；
5. 保存服务端返回的 Record 状态，但不要保存 Asset 临时下载 URL 作为业务引用；
6. 从公共库再次读回 Asset 并计算 hash；通过后才把任务标为 `mediaVerified`。

如果设备没有 iCloud 账号、权限不足、文件损坏或 hash 不一致，任务保持失败，不得把商品标记为已发布。

### 3.3 关联商品

在写 `THDataPack` 前，将 `CatalogAsset.mediaKey` 写进商品 JSON。`originalURL` 仅保留来源 URL/旧回退值；不再写 `local:<文件名>` 作为新发布目录的唯一图片引用。

构建前硬校验：

- 每个 `mediaKey` 都有对应的已验证 `THMedia`；
- `mediaKey` 对应的 hash、MIME 和字节数一致；
- 所有商品/系列/店家引用都在同一完整目录包中可解析；
- 任一媒体未验证，禁止进入 `THDataPack` 和 `THRelease` 发布步骤。

### 3.4 发布商品包和版本头

媒体全部验证后：

1. 生成合并后的完整 `ShopCatalog` JSON；
2. 压缩并计算 `THDataPack` hash；
3. 上传不可变 `THDataPack`；
4. 以读取到的 `recordChangeTag` 条件更新固定 `THRelease`；
5. 回读 `THRelease`，确认 `releaseSeq` 已变；
6. 用普通只读路径拉取 `THRelease → root-index → THDataPack → THMedia`，验证 App 能显示；
7. 只有第 6 步成功，UI 才显示“已发布”。

在发布头切换前，即使中途留下未引用的 `THMedia` 或 `THDataPack`，用户仍看到旧版本，不会看到半套商品；发布头一旦切换，后续客户端回读失败不能承诺全局仍是旧版本。

## 4. 错误、重试与反馈

| 错误 | 任务状态 | 处理 |
|---|---|---|
| 选图读取/压缩失败 | `stagedFailed` | 显示具体图片失败，允许重新选图 |
| 无 iCloud 账号 | `blocked` | 提示运营账号登录 iCloud，不自动重试 |
| CloudKit 权限拒绝 | `blocked` | 联系权限管理员，不循环重试 |
| 网络超时/服务暂不可用 | `retryable` | 指数退避；保留本地文件和任务 |
| Asset 上传成功但 Record 写入失败 | `retryable` | hash 幂等重试；不能重复创建不同 mediaKey |
| `THMedia` 回读 hash 不一致 | `failed` | 不发布包，保留诊断信息 |
| `THRelease` changeTag 冲突 | `conflict` | 重新读取当前头、重新生成 release 序号后由运营确认；不强制覆盖 |
| 只读端拉不到图片（发布头已切换） | `publishedButUnverified` | 不显示“验证成功”；记录并报警，客户端仅在本地已有旧快照时保留旧快照，不承诺全局回滚；必要时发布更高 `releaseSeq` 的回滚快照 |

本地 SwiftData 任务至少保存：`jobID`、商品/资产 ID、阶段、mediaKey、文件路径、attemptCount、lastError、nextRetryAt、releaseSeq。图片暂存文件只有在公共库回读校验完成后才能删除。

## 5. 现有 App 回读与显示改造

消费端需要新增一个 `THMedia` 只读读取器：

```text
ShopCatalogPackPayload.shopCatalog.assets[*].mediaKey
  → CKRecord.ID("th.media.<mediaKey>")
  → publicCloudDatabase.record(for:)
  → CKAsset.fileURL
  → hash 校验
  → Application Support/ShopCatalog/cache/<hash>.jpg
  → Image(uiImage:) / AsyncImage 等现有展示层
```

要求：

- 缓存命中时不重复请求；
- 缓存文件丢失时按 `mediaKey` 重新下载；
- 下载失败显示明确占位和重试入口，不把图片当作“没有图片”；
- 旧 `http(s)` / Bundle / `local:` 继续兼容，但新公共发布不能依赖运营设备的 `local:`；
- 商品正文包校验成功不等于图片链路成功，图片应有独立状态和错误日志。

## 6. iOS 端验收

- [ ] 运营账号在 Development 环境选一张新图，能看到 `staged → uploading → verified` 状态。
- [ ] CloudKit Dashboard/只读 API 能查到 `THMedia`，下载字节 hash 与本地一致。
- [ ] 商品 JSON 中 `mediaKey` 与 `THMedia` Record ID 一致；不能只保存本地路径或 URL。
- [ ] `THDataPack` 和 `THRelease` 发布成功后，退出重启现有 App，强制刷新能显示商品和图片。
- [ ] 清除 App 图片缓存后重新拉取仍能显示。
- [ ] 断网、权限拒绝、上传超时、版本冲突各测一次：发布头切换前的失败不得切换 `THRelease`；切换后的图片回读失败必须标记“已发布未验证”，并验证本地旧快照/更高序号回滚快照路径。
- [ ] 普通用户账号不能写 `THMedia` / `THDataPack` / `THRelease`，即使手动调用写接口也被服务端拒绝。
- [ ] Development 与 Production 分别验收；TestFlight 只验证 Production。

本次静态调查没有运行上述步骤，不能声称任何图片已经上传成功。

## 7. App Store 审核与内容边界

运营入口可以保留在 App 内，但不能把权限隐藏当作安全措施，也不能依赖未披露的“暗门”。若该入口进入面向用户的 App：

- 在 App Review Notes 中说明运营入口、测试账号/演示方式、后端可用环境和远程内容审核机制；Apple 的 [2.1 App Completeness / Before You Submit](https://developer.apple.com/app-store/review/guidelines/) 要求后端可用、功能完整、必要时提供 demo 账号。
- 远程品牌图、商品图、价格和链接仍是 App 展示内容；应保存来源、授权和下架/撤回流程。Apple 的 [4.1/5.2 相关审核提示](https://developer.apple.com/app-store/review/)要求第三方商标、版权图片等具备授权材料。
- 不预判商品类型：若是线下消费的实体商品，Apple [3.1.3(e)](https://developer.apple.com/app-store/review/guidelines/)允许使用非 IAP 的实体商品付款方式；若商品实际解锁 App 内数字内容、功能、虚拟物品或订阅，则要按 [3.1.1](https://developer.apple.com/app-store/review/guidelines/)使用 IAP，具体要等产品确认。
- 若 App 让用户提交内容，则还要审视 [1.2 User-Generated Content](https://developer.apple.com/app-store/review/guidelines/)的过滤、举报、屏蔽和联系机制；本方案默认是受控运营内容，不开放普通用户投稿。
