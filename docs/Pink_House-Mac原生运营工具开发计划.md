# Pink_House Mac 原生运营工具开发计划

## 1. 当前 Mac 侧事实

远端基线：`main@0e5899ce41d5abbc1101ed19e18a726631d0e43f`。

当前不存在可以直接打开、录入商品并上传图片的 macOS SwiftUI App：

- `ItemManager.xcodeproj` 的应用 target 只有 `iphoneos iphonesimulator`；测试 target 支持 macOS 不等于存在 Mac 应用。
- `ops/` 不是运营后台，只包含法律站点。
- 现有真正的 Mac 发布端是 `tools/time_hall/publication/` 下的 Python CLI。
- CLI 能处理 `shop-catalog.json`、`media-manifest.json` 和外部图片文件，并通过 CloudKit Web Services 上传 `THMedia`、`THDataPack`，最后更新 `THRelease`；它没有商品录入、图片预览、任务队列或 Mac GUI。

证据：[工程 target 配置](https://github.com/dragon717/Pink_House/blob/0e5899ce41d5abbc1101ed19e18a726631d0e43f/ItemManager.xcodeproj/project.pbxproj)、[发布流水线 README](https://github.com/dragon717/Pink_House/blob/0e5899ce41d5abbc1101ed19e18a726631d0e43f/tools/time_hall/publication/README.md)、[CloudKit 发布器](https://github.com/dragon717/Pink_House/blob/0e5899ce41d5abbc1101ed19e18a726631d0e43f/tools/time_hall/publication/publish_cloudkit.py)。

## 2. 三种方案比较

| 方案 | 优点 | 代价/风险 | 判断 |
|---|---|---|---|
| 继续用现有 Python CLI | 已有真正的 `THMedia` 上传、不可变发布顺序、server-to-server key；改动最少 | 不是 GUI；需要手工准备 JSON、manifest 和图片；当前未把 `local:` 映射成媒体引用 | 适合作为后端发布基线，不满足“直接运营工具” |
| 同一工程新增 macOS SwiftUI target | 共享 Swift 模型/校验/协议；原生文件选择、预览、任务状态；与 iOS 版本可一起演进 | 现有 iOS 代码含 UIKit/PhotosUI/移动端 UI，需要抽出跨平台层；Mac 直接写公共库需要运营 iCloud 账号和 CloudKit 角色 | 推荐 |
| 独立 macOS SwiftUI App/工程 | 发布节奏和权限隔离清楚，适合内部运营；不会把编辑器 UI 带进用户 App | 若不共享模块，商品模型、hash、发布协议会漂移；要另配签名、容器 entitlement、Dev/Prod | 运营团队完全独立时可选 |

不建议把现有 iPhone target 直接改成 Mac Catalyst 来“凑一个 Mac 工具”：运营 UI、文件访问、权限和发布协议都需要重新梳理；与用户 App 共用一个 target 会增加审核和误写公共库风险。

## 3. 推荐架构

推荐“同一仓库新增 macOS target + 共享非 UI 模块”：

```text
SharedCatalog
  ├─ ShopCatalogModels / JSON Coding
  ├─ ShopCatalogSyncProtocol / validation
  ├─ MediaStaging / SHA-256 / JPEG normalization
  └─ CloudCatalogPublisher

Mac SwiftUI target
  ├─ SwiftData local drafts/jobs (.none)
  ├─ fileImporter / preview / batch editor
  └─ publicCloudDatabase + CKRecord + CKAsset

iOS ItemManager
  ├─ existing consumer reader
  └─ iOS ops UI, if retained, uses the same publisher contract
```

SwiftData 只保存 Mac 本地草稿、已选文件的安全书签/暂存副本、上传任务和审计收据；不配置自动 CloudKit 同步。Apple 的 SwiftData 配置没有 public database 自动同步选项，见 [ModelConfiguration.CloudKitDatabase](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct)。

## 4. Mac 用户流程

### 4.1 导入与编辑

1. SwiftUI 使用系统 `.fileImporter` 选择目录 JSON、单张/多张图片；Apple API 原生支持多文件导入：[fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3Aoncancellation%3A%29)。
2. 对返回的 security-scoped URL 立即复制到应用自己的 staging 目录，避免只保存外部路径。
3. 允许手动新建店家、系列、商品、规格、售价事件和图片资产。
4. 提供本地完整预览；预览标签明确为“本地草稿”，不能冒充已发布。
5. SwiftData 保存草稿；应用退出后能恢复。

### 4.2 发布

1. 统一规范化图片，计算 SHA-256，生成 `mediaKey`。
2. 生成待发布目录，检查每个 `mediaKey` 都能命中图片文件。
3. 通过 `publicCloudDatabase` 上传/复用 `THMedia` 的 `CKAsset`。
4. 逐张读回 Asset，核对 hash。
5. 生成完整压缩 `THDataPack`，写入已验证的 `mediaKey`。
6. 写入/复用 `THDataPack`，再以 change tag 条件更新固定 `THRelease`。
7. 从普通只读路径回读商品和图片，确认现有 App 能显示后才结束任务。

Apple 的 [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)用于把外部图片文件作为 Record 的 Asset 保存；[publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)可读公共库，但写入要求运营设备有活动 iCloud 账号。若不希望把运营账号权限放进客户端，则 Mac UI 应调用/封装现有受控 CLI，而不是把 server-to-server 私钥放进 App。

## 5. 直接 CloudKit 与现有 CLI 的取舍

### 原生 Mac 直接 CloudKit

适合用户明确要求的 SwiftUI 运营工具：

- 优点：图片文件可以在选中后直接变为 `CKAsset`；上传状态能在界面实时呈现；不需要 Python 运行时或外部命令；Swift 模型与 iOS 可共享。
- 前提：运营 Apple 账号登录 iCloud；CloudKit Production/Development 角色配置正确；客户端只向已授权的运营入口开放。
- 风险：公开 App 内的高权限写入面更大；权限撤销依赖 Apple 账号/角色；要处理 `CKError`、change tag 冲突和临时 Asset URL。

### Mac SwiftUI 调用现有 CLI

适合先保留现有 server-to-server 安全边界：

- SwiftUI 负责商品表单、选图、staging、预览和进度；
- 发布器继续负责 CloudKit Web Services 签名、`THMedia` / `THDataPack` / `THRelease` 顺序和 Keychain 凭证；
- UI 必须通过受控本地 IPC/子进程传递 staging 目录，不能把私钥传给 UI 或日志；
- 仍需补上 `local:` → `mediaKey` 映射和现有 App 的 `THMedia` 回读。

这是最短的上线路径；但若产品硬性要求“原生 Swift 直接写公共库”，则采用前一种方案并保留相同发布协议。

## 6. 最小实施阶段

### P0：共享协议和图片模型

- 把目录模型、`CatalogAsset.mediaKey`、JSON 编解码、协议常量和结构校验抽成共享模块。
- 定义 `MediaUploadJob` 状态机：`staged / uploading / verified / failed / retryable`。
- 禁止发布只含 `local:` 的新目录。

### P1：Mac 本地工具

- 新建 macOS SwiftUI target。
- 加入 `.fileImporter`、staging、预览、SwiftData 本地草稿/任务。
- 在离线状态完成商品 JSON 和图片引用校验。

### P2：真实公共库上传

- Development 环境配置 Mac target 的 iCloud container entitlement。
- 只授予运营账号写权限，普通用户角色保持只读。
- 实现 `THMedia` 上传、Asset 回读 hash、`THDataPack` 上传、`THRelease` 条件切换。
- 记录发布收据：环境、releaseSeq、rootIndexHash、pack hash、media hash、时间和错误。

### P3：现有 App 消费端

- 实现 `mediaKey → THMedia → CKAsset → 本地缓存`。
- 失败显示重试/占位，不把网络失败显示成“没有图片”。
- 先在 Development 验收，再部署 Production schema/role 并用 TestFlight 验收。

### P4：决定是否保留 iOS 运营入口

- 若保留，iOS 与 Mac 必须共用同一 Publisher/协议；
- 若只保留 Mac，iOS 入口可以降级为只读/导出，避免两套写入器产生版本冲突；
- 不要同时让 Python CLI、iOS App、Mac App 各自定义一套发布格式。

## 7. 失败、重试、回滚验收

- 网络失败：本地任务不丢，指数退避后可重试；
- 权限失败：显示环境、账号和角色，不盲目重试；
- 图片上传成功但发布头尚未切换：允许孤儿 `THMedia` 留在公共库，下一次按 hash 复用；用户仍只看到旧 `THRelease`；若发布头已经切换后才发现消费端回读失败，则标记“已发布未验证”，不承诺全局自动回滚，必要时发布更高 `releaseSeq` 的回滚快照；
- 发布头冲突：重新读 change tag，不做无条件覆盖；
- 验证失败：发布状态不是“成功”，保留 staging 和日志；
- 回滚：发布更高 `releaseSeq` 的旧内容快照，不把版本号改小；
- 断网、杀进程、清本地缓存、重复点击发布、重复 hash、Development/Production 错环境都要有测试用例。

最终验收必须由一台普通只读设备完成：清缓存后重新拉取 `THRelease → THDataPack → THMedia`，图片 hash 正确且 UI 显示。仅看到 Mac 的“上传完成”或 CloudKit Dashboard 中有 Record，不能算端到端完成。

## 8. App Store / 分发边界

如果 Mac 工具只给内部运营使用，优先考虑受控分发，不把高权限运营功能和普通用户 App 的审核面混在一起。如果要上 Mac App Store，Apple [2.4.5](https://developer.apple.com/app-store/review/guidelines/)要求适当 sandbox、自包含安装包、使用公开 macOS API，不能依赖未经允许的安装器或后台常驻进程；文件导入应使用 security-scoped 访问。

iOS 用户 App 仍需遵守 Apple [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)：远程内容必须可审核、第三方图片/品牌要有授权、后台服务在审核时可用。商品究竟是实体服装、数字内容还是 App 内功能解锁尚未确认：实体线下消费通常按 3.1.3(e)处理，数字内容/功能解锁按 3.1.1 评估 IAP；本计划不替产品做这个分类。

## 9. 待确认问题

- Mac 工具是内部发布器，还是要上 Mac App Store？
- iOS 端是否继续允许录入和发布，还是 Mac 成为唯一写入者？
- 商品图片是否需要原图、预览图、缩略图三种独立版本？
- 运营是否接受 Mac/iOS 运营账号登录 iCloud，还是必须保留 server-to-server key？
- 商品销售是线下实体商品，还是可能解锁 App 内数字内容/功能？这直接影响支付与审核方案。
- 远程图片的来源授权、撤回、版权投诉和过期策略由谁负责？
