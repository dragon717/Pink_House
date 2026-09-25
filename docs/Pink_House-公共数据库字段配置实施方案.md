# Pink_House 公共数据库字段与配置变更方案

## 1. 基线与目标

基线是远端 `main` 的 `0e5899ce41d5abbc1101ed19e18a726631d0e43f`。目标不是把商品拆成一堆可被普通用户写入的公共记录，而是让运营端把“已审核商品目录 + 图片二进制”发布到现有 App 已经读取的同一套 CloudKit 公共数据库。

目标链路：

```text
目录 JSON + 图片文件
  → THMedia（图片二进制）
  → THDataPack（商品 JSON，含 mediaKey）
  → THRelease（唯一生效点）
  → 现有 App 只读拉取并显示
```

只读静态调查，以下是待实施方案；没有改 schema、权限或云端数据。

## 2. 复用与新增字段

### 2.1 复用现有 Record Type

| Record Type | 当前作用 | 继续复用的字段 | 说明 |
|---|---|---|---|
| `THRelease` | 当前生效版本 | `releaseSeq:Int64`、`schemaVersion:Int64`、`revocationEpoch:Int64`、`minimumReaderVersion:Int64`、`previousReleaseSeq:Int64`、`publishedAt:String`、`rootIndexHash:String`、`rootIndexAsset:Asset` | 固定 Record ID `th.release.catalog-v1`；只在最后一步条件更新 |
| `THDataPack` | 不可变压缩 JSON 包 | `partitionID:String`、`releaseSeq:Int64`、`sha256:String`、`byteCount:Int64`、`asset:Asset` | 商品目录为一个整包分片，载荷键 `shopCatalog` |
| `THMedia` | 不可变图片等媒体 | `mediaKey:String`、`mimeType:String`、`sha256:String`、`byteCount:Int64`、`asset:Asset` | Record ID `th.media.<sha256>`；二进制必须进入 Asset |

当前发布文档已将实际字段口径纠正为上表；早期设计文档中的 `payloadAsset` / `contentHash` 命名不能直接照搬。

### 2.2 商品 JSON 必须新增稳定媒体关联

当前 `CatalogAsset` 只有：`id`、`type`、`thumbnailURL`、`previewURL`、`originalURL`、`width`、`height`。运营端保存的 `local:<文件名>` 只在原设备沙盒中成立，不是公共库 ID。

建议在 `CatalogAsset` 增加一个可选字段：

```json
{
  "id": "asset-product-001",
  "type": "productImage",
  "mediaKey": "<sha256>",
  "originalURL": "<原始来源 URL，可选，仅作来源/回退>",
  "width": 1200,
  "height": 1600
}
```

约束：

- `mediaKey` 是图片字节 SHA-256，用来推导 `th.media.<sha256>`，不是 CloudKit 返回的临时下载 URL；
- `originalURL` 保留来源信息和旧版本兼容，不再承担“公共图片已经上传”的语义；
- 没有 `mediaKey` 的旧包继续按 `http(s)` / Bundle / `local:` 旧逻辑读取；
- 第一版只增加一个 canonical `mediaKey`，不要先加入三套缩略图 Record Type；需要多分辨率时再增加 `thumbnailMediaKey` / `previewMediaKey`，或发布多条 `CatalogAsset`。

`mediaKey` 位于 `THDataPack.asset` 内的 JSON，不是 CloudKit Record 的字段，因此不需要为每个商品新建公共 Record Type。

### 2.3 发布输入 manifest

当前 `build_release.py` 已读取 `media-manifest.json`，至少需要 `mediaKey`、`fileName`、`mimeType`，并会重新计算文件 hash。建议将输入约束明确化：

```json
{
  "media": [
    {
      "mediaKey": "<sha256>",
      "fileName": "staging/product-001.jpg",
      "mimeType": "image/jpeg"
    }
  ]
}
```

构建时必须检查：文件存在、MIME 白名单、字节数上限、SHA-256 与 `mediaKey` 一致、商品 JSON 中每个 `mediaKey` 都有 manifest 条目。当前构建器对媒体引用“不做资产引用校验”，这是必须补上的发布前错误。

## 3. 索引与权限配置

### 3.1 索引

- `THRelease`：固定 Record ID 精确读取，不需要 Query index。
- `THDataPack`：当前由根清单给出精确 Record ID，不需要 Query index；若运营工具按 `partitionID` 查询，再将其设为 Queryable。
- `THMedia`：上传和客户端读取优先使用 `th.media.<sha256>` 精确 ID；若运营工具需要按业务键查找，再将 `mediaKey` 设为 Queryable。
- 不要通过扫描公共库寻找商品或图片；现有读链路已经按已知 ID 读取。

### 3.2 权限

目标效果：

| 主体 | 读取已发布内容 | 创建/更新/删除 |
|---|---:|---:|
| 普通用户 / `_world` | 是 | 否 |
| 普通登录用户 / `Authenticated` | 是 | 否 |
| 运营发布身份 | 是 | 是，仅正式发布工具/运营账号 |

CloudKit 客户端里的白名单只负责隐藏入口和改善体验，不能作为安全边界。当前 `CreatorAccess` 也是客户端前置检查；真正权限必须在 CloudKit Security Roles 落地并单独验证。

有两种合法写入方式：

1. **原生 Mac/iOS 运营 App**：使用 `CKContainer.publicCloudDatabase` + `CKRecord` + `CKAsset`，运营账号必须登录 iCloud，并被服务端角色授权。Apple 明确说明公共库无 iCloud 账号也能读，但写入公共库需要活动 iCloud 账号。
2. **现有 Mac CLI**：使用 CloudKit Web Services server-to-server key。私钥只留在受控 Mac 的 Keychain/受限文件中，绝不放进 App Bundle、JSON 或公共记录。

不要把 server-to-server 私钥嵌进 iOS App；如果 iOS 端直接写公共库，必须采用运营 Apple 账号 + CloudKit 角色，并接受账号、权限撤销和审核演示的运营成本。

## 4. 开发/生产环境与 schema 发布

必须按两套环境分别操作：

| 环境 | 读取方 | 发布方 | 验证要求 |
|---|---|---|---|
| Development | Xcode 调试包 | 开发角色/开发 key | 先部署开发 schema，做完整上传、下载、hash、UI 验证 |
| Production | TestFlight / App Store 包 | 生产角色/生产 key | 单独部署生产 schema，单独发布一次，不能用 Development 结果代替 |

现有代码已明确写出 Debug 读 Development、TestFlight/App Store 读 Production；两边记录、schema 和凭证不互通。生产上线前必须验证 `THRelease`、`THDataPack`、`THMedia` 三种类型及 Asset 字段都已部署。

## 5. 兼容迁移步骤

1. **先做读端兼容**：为 `CatalogAsset.mediaKey` 增加可选解码；没有它仍展示旧 Bundle/URL 图。
2. **实现媒体读取**：根据 `mediaKey` 精确读取 `THMedia`，取 Asset 文件 URL，校验 SHA-256，写入 App 缓存并显示。
3. **提升发布协议版本**：若没有 `mediaKey` 的旧客户端无法正确展示新内容，则将 `minimumReaderVersion` 提升到新读端版本；不要让旧客户端静默显示破图。
4. **开发环境增量发布**：schema → Security Role → 一张测试图片 → 一个测试商品包 → 更新发布头 → 普通只读客户端回读。
5. **生产环境部署**：重复部署并做一条真实的测试记录/发布；确认 TestFlight 读到 Production 后再切正式内容。
6. **保留旧字段**：至少一个版本周期保留 `originalURL`/Bundle 回退；确认所有生产客户端都支持 `mediaKey` 后，再决定是否停止发布 `local:`。
7. **旧数据不覆盖**：`THMedia` 和 `THDataPack` 按 hash 不可变；修订生成新 hash、新包、新 `releaseSeq`，不修改旧 Asset。

## 6. 端到端验收清单

- [ ] 上传前记录本地文件 SHA-256、MIME、字节数和商品 `mediaKey`。
- [ ] 从公共库读回 `THMedia`，下载 Asset，字节 SHA-256 与本地一致。
- [ ] 从公共库读回 `THDataPack`，解压、校验 hash，商品的 `mediaKey` 能命中 `THMedia`。
- [ ] **切换发布头前**，媒体和数据包必须均读回成功；任一步失败则不切换。发布头切换后若客户端回读图片失败，只能标记“已发布但未验证”，客户端有旧快照时本地保留旧快照；不承诺全局自动回滚，必要时发布更高 `releaseSeq` 的回滚快照。
- [ ] 普通只读账号不能创建、覆盖、删除三类记录；不能只测按钮是否隐藏。
- [ ] 失败后重跑是幂等的：已有 hash 资源跳过，未完成资源继续，发布头不会错误前进。
- [ ] 清除 App 缓存、杀进程、重新安装后，现有 App 仍能从公共库拉取并显示图片。
- [ ] Development 与 Production 各跑一遍；不能把 Development 通过当作 Production 通过。

## 7. Apple 官方依据与审核边界

- [公共数据库与角色](https://developer.apple.com/documentation/cloudkit/ckdatabase/scope/public)：公共库默认可读、默认由创建者写入，但可以在 Developer Portal 通过 Roles 收紧。
- [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)：CloudKit 保存的是 Asset 二进制；保存包含 Asset 的 Record 时，记录和文件一起保存。
- [CloudKit Web Services / server-to-server key](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html)：服务端 key 访问公共库，私钥必须受保护。
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)：远程内容也属于产品体验；需要可审核、完整、无占位内容，第三方品牌/图片应有授权。若商品是实体服装等线下消费，支付规则与数字内容不同；若未来用商品库解锁 App 内数字内容或功能，则需要单独按 3.1.1 / 3.1.3 判断 IAP，不能在本方案中预判商品性质。
