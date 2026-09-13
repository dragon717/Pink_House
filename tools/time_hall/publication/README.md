# 时光馆静态内容发布流水线（Mac 端）

对应 `docs/Pink_House_TimeHall_Static_CloudKit_Design.md` 的 §8 / §9 / §18 / §20。

把「已审核的整馆 catalog」变成「公共库里可被普通读者拉取的不可变发布产物」。
生产端只有这一条通路；importer（`tools/time_hall/import_*.py`）只负责把资料落成 catalog，
**不参与上传**。

```
catalog*.json（已审核输入）
      │
      ▼  build_release.py
发布产物目录（不可变）
  ├── root-index.json          ← 根清单：品牌 + 分片契约 + 撤回清单
  ├── release.json             ← 发布头草稿（recordName / releaseSeq / rootIndexHash）
  ├── packs/<payloadHash>.json.gz
  ├── media/<contentHash>.<ext>       （可选）
  ├── media.json                      （可选）
  └── audit/
      ├── release-manifest.json  ← 授权状态、分片清单、媒体清单（审计用）
      └── checksums.txt
      │
      ▼  validate_release.py     （发布前自检，离线）
      ▼  verify_publication.py   （读者视角回读，上线后自证）
      │
      ▼  publish_cloudkit.py
公共库（CloudKit public database / filesystem 演练目录）
  THRelease     ← 发布头，**唯一**的版本生效点
  THDataPack    ← 数据包（不可变）
  THMedia       ← 图片 / 视频（不可变）
```

## 文件一览

| 文件 | 职责 | 依赖 |
|---|---|---|
| `protocol.py` | 协议纯函数：规范化 JSON、sha256、确定性 gzip、记录命名、三层校验谓词 | 无第三方依赖 |
| `sources.yaml` | 品牌来源与授权登记。**默认全部 `pending_review`，即默认禁止发布** | — |
| `sources_loader.py` | 严格子集 YAML 解析器（看不懂就报错，不猜） | 无第三方依赖 |
| `build_release.py` | 构建不可变产物 | 无第三方依赖 |
| `validate_release.py` | 校验产物（发布者自检） | 无第三方依赖 |
| `publish_adapters.py` | 发布适配层：`filesystem`（演练）/ `cloudkit`（真实） | cloudkit 需 `cryptography` |
| `publish_cloudkit.py` | 发布主入口（固定 7 步顺序） | 同上 |
| `verify_publication.py` | 读者视角回读验证 | 同上 |
| `rollback_release.py` | 回滚：历史内容 + 新更高发布号 | 无第三方依赖 |

## 快速演练（不需要凭证、不联网）

```bash
cd tools/time_hall/publication
PY=python3

# 0) 准备输入（本地联调用 Bundle 里的 catalog）
mkdir -p /tmp/th_in && cp ../../../ItemManager/Resources/TimeHall/catalog*.json /tmp/th_in/

# 1) 构建（--allow-unapproved-local-fixture 会打上 localFixture 标记）
$PY build_release.py --input /tmp/th_in --output /tmp/th_out --release-seq 1 \
    --allow-unapproved-local-fixture

# 2) 自检
$PY validate_release.py --release /tmp/th_out

# 3) 演练发布：先看计划，再落盘
$PY publish_cloudkit.py --release /tmp/th_out --adapter filesystem --filesystem-root /tmp/th_fs
$PY publish_cloudkit.py --release /tmp/th_out --adapter filesystem --filesystem-root /tmp/th_fs --apply

# 4) 读者视角回读
$PY verify_publication.py --adapter filesystem --filesystem-root /tmp/th_fs

# 5) 回滚演练（把历史内容以新发布号再发一次）
$PY rollback_release.py --from-release /tmp/th_out --output /tmp/th_rb \
    --release-seq 5 --reason "演练：模拟线上内容错位" --published-root /tmp/th_fs --apply
$PY publish_cloudkit.py --release /tmp/th_rb --adapter filesystem --filesystem-root /tmp/th_fs --apply
$PY verify_publication.py --adapter filesystem --filesystem-root /tmp/th_fs
```

`filesystem` 适配器会把公共库语义落在一个本地目录，用于验证
「不可变资源 + 最后切换发布头 + 冲突检测 + 回读确认」这套**应用层协议**。
它不是部署目标，也不替代真实权限验证。

## 真实发布

### 1. 凭证（绝不进命令行、绝不进日志）

优先 Keychain：

```bash
security add-generic-password -s PinkHouseTimeHallPublisher -a keyID       -w '<KEY_ID>'
security add-generic-password -s PinkHouseTimeHallPublisher -a privateKey  -w '<P-256 私钥 PEM 全文>'
security add-generic-password -s PinkHouseTimeHallPublisher -a containerID -w 'iCloud.bugod2.ItemManager'
```

开发环境可改用环境变量指向的 JSON 文件（会在输出里明确警告）：

```bash
export PINK_HOUSE_TIMEFIELD_CREDENTIAL_FILE=/path/to/dev-credentials.json
# {"keyID":"...","privateKey":"-----BEGIN PRIVATE KEY-----\n...","containerID":"iCloud.bugod2.ItemManager"}
```

### 2. CloudKit Console 前置（**人工一次性操作，脚本不做也不能做**）

设计 §7.3 明确：权限**不能**只靠客户端 `adminIDs` 判断，必须在 Console 侧收紧。

在 CloudKit Dashboard（容器 `iCloud.bugod2.ItemManager`，**两个环境各做一次**）建
Record Type 与 Security Role：

| Record Type | 字段 | Public 读 | Public 写 |
|---|---|---|---|
| `THRelease` | `releaseSeq`(Int64) `schemaVersion`(Int64) `revocationEpoch`(Int64) `minimumReaderVersion`(Int64) `previousReleaseSeq`(Int64) `publishedAt`(String) `rootIndexHash`(String) `rootIndexAsset`(Asset) | ✅ 允许 | ❌ 拒绝 |
| `THDataPack` | `partitionID`(String) `releaseSeq`(Int64) `sha256`(String) `byteCount`(Int64) `asset`(Asset) | ✅ 允许 | ❌ 拒绝 |
| `THMedia` | `mediaKey`(String) `mimeType`(String) `sha256`(String) `byteCount`(Int64) `asset`(Asset) | ✅ 允许 | ❌ 拒绝 |

在 **Security Roles** 里给 `_world`（或等价的 public 角色）只赋 `Read`，
`Write` 只留给发布用的 server-to-server key。**不要**给任何 authenticated 角色写权限——
普通用户零写是设计 §0.3 的第一条硬约束。

Query 索引（如果运营侧要用 query 拉取而非 lookup）：`THDataPack.partitionID`、
`THMedia.mediaKey` 需要标记 Queryable。

### 3. 发布

```bash
python3 build_release.py --input <已审核目录> --output <产物目录> --release-seq <N>

python3 validate_release.py --release <产物目录>

# 首次务必先 dry-run + print-requests 核对请求形状
python3 publish_cloudkit.py --release <产物目录> --adapter cloudkit \
    --environment development --print-requests

python3 publish_cloudkit.py --release <产物目录> --adapter cloudkit \
    --environment development --apply --receipt publish-receipt.json

# 上线后自证
python3 verify_publication.py --adapter cloudkit --environment development
```

## 发布顺序为什么是这个顺序（§9.1）

```
[2] 读当前 THRelease + changeTag
[3] 上传缺失 THMedia        ┐
[4] 上传缺失 THDataPack     ├─ 不可变，只增不改，失败只留下未被引用的孤儿资源
[5] 回读核对可获取性        ┘
[6] 条件更新 THRelease       ← **唯一**让新版本对用户生效的动作
[7] 回读确认发布头
```

- 第 3–5 步失败：用户看到的还是旧版本，线上没有半成品。
- 第 6 步使用第 2 步读到的 `changeTag` 做冲突检测；冲突时**中止**，
  绝不改成无条件覆盖（§9.3）。
- 第 6 步失败：不可变资源已就位，重跑即可（幂等）。
- 分片字节已经存在但**摘要漂移**时，发布会在第 5 步中止——这比"覆盖上去"更安全。

## 回滚语义（§9.2）

回滚**不是**把发布号改小，而是「旧内容 + 更高发布号」：

```bash
python3 rollback_release.py --from-release <历史产物> --output <新产物> \
    --release-seq <更高的号> --reason "<必填，写进审计>" --apply
python3 publish_cloudkit.py --release <新产物> --adapter cloudkit --environment production --apply
```

- 分片字节原样复用（不可变，不重打包）；
- 撤回清单**只增不减**，回滚不会让已撤回的内容重新出现；
- `audit/rollback-manifest.json` 记录回滚原因、来源发布号、新发布号。

## 硬约束（改代码前先读）

1. **`localFixture` 产物不可发布**。`build_release.py` 的
   `--allow-unapproved-local-fixture` 只用于本地联调；带此标记的产物用
   `--adapter cloudkit` 会被**强制拒绝**（退出码 4），且**不提供覆盖开关**。
2. **发布号严格递增**。`publish_cloudkit.py` 比对线上当前 `releaseSeq`，
   本地不大于线上即拒绝（退出码 5）。
3. **撤回只能累加**。`revocationEpoch` 与 `withdrawals` 都不允许回退。
4. **凭证不明文传参、不打印**。私钥只从 Keychain 或环境变量指向的文件读取。
5. **摘要一致 ≠ 来源合法**。哈希只证明字节一致，不证明授权；
   授权状态看 `audit/release-manifest.json` 与 `sources.yaml`。

## 已知未验证部分

- `publish_adapters.CloudKitWebServicesAdapter` 与
  `verify_publication.CloudKitPublicReader` 的请求构造按 Apple 公开文档实现，
  **未经真实环境验证**。首次使用必须在 `--environment development` 下用
  `--print-requests` 逐条核对，再考虑生产。
- 签名算法为 `SignatureV1`（ECDSA P-256 / SHA-256，签名对象为
  `日期:请求体` 的 UTF-8 字节）。若 Apple 侧报签名错误，优先核对
  日期格式（`%Y-%m-%dT%H:%M:%SZ`）与请求体是否为规范化 JSON 字节。
- 资产上传按「三步：占位 → POST 上传地址 → 带 receipt 再 modify」实现。

## 验收对照（设计 §18.1）

| 验收点 | 由谁保证 |
|---|---|
| D09 重复 ID / 悬空关系 / 错误品牌范围 | `protocol.validate_fragment` + `validate_release_references`，在 `build_release` 与 `validate_release` 各跑一次 |
| D10 partial 包少记录不当作删除 | `TimeHallRepository.composeLocalFragment`（客户端侧，见 Swift 实现） |
| D11 complete 新快照的移除是有意行为 | `build_release.diff_summary` + `validate_release --previous` 输出条目数下降提示 |
| D12 schema 不受支持时明确拒绝 | `check_release_header` 校验 `schemaVersion` / `minimumReaderVersion` |
| 只增不改与最后切换 | `publish_cloudkit` 的 7 步顺序 |
| 冲突不吃掉 | `put_release(expected_change_tag)` |
| 回滚不倒退 | `rollback_release.py` + `publish_cloudkit` 递增校验 |
