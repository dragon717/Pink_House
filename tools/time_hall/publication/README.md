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
| `selftest_signing.py` | CloudKit SignatureV1 请求签名离线自检（已知答案 + 反向断言） | cloudkit 需 `cryptography` |
| `publish_cloudkit.py` | 发布主入口（固定 7 步顺序） | 同上 |
| `verify_publication.py` | 读者视角回读验证 | 同上 |
| `rollback_release.py` | 回滚：历史内容 + 新更高发布号 | 无第三方依赖 |

## 快速演练（不需要凭证、不联网）

**最省事的方式：一条命令跑完全链路 28 项断言。**

```bash
cd /Users/sangyu/develop/Pink_House
bash tools/time_hall/publication/drill_offline.sh
```

覆盖：构建 → 自检 → dry-run 无副作用 → 发布 → 回读 → 4 条拒绝路径（重复发布号 / 回滚号不递增 / localFixture 发 CloudKit / 篡改分片）→ 回滚 → 再发布 → **商店目录整包分片（含悬空引用拒绝）**。
成功标志是 `通过 28 项，失败 0 项`。加 `--verbose` 看每步完整输出，加 `--keep` 保留工作目录与日志。

如果你想逐步手动跑、观察每一步之间发生了什么，用下面的分步版本：

```bash
cd tools/time_hall/publication
PY=python3

# 0) 准备输入（就地生成夹具；旧 `Resources/TimeHall/` 已随旧馆移除）
mkdir -p /tmp/th_in
python3 - /tmp/th_in <<'EOF'
import json, sys
from pathlib import Path
# 文件名必须等于 sources.yaml 中该品牌的 resourceName（pink-house -> "catalog"）
fixture = {
    "version": 3, "brand": "PINK HOUSE",
    "events": [{"id": "news-drill-001", "publishedOn": "2026-09-12", "title": "本地联调"}],
    "commerceItems": [{"id": "drill-item-001", "observedAt": "2026-09-12", "name": "本地联调"}],
}
Path(sys.argv[1], "catalog.json").write_text(json.dumps(fixture, ensure_ascii=False), encoding="utf-8")
EOF

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

> ⚠️ **2026-09-25 修正**：凭证的密钥对在**你自己的 Mac 上生成，只把公钥上传到 Console**，
> 私钥永不离开本机。Console 回填的只是一个 Key ID。
> 完整步骤见 `docs/TIME_HALL_CLOUDKIT_CONSOLE_SETUP.md` §3。
>
> ```bash
> openssl ecparam -name prime256v1 -genkey -noout -out pinkhouse-ck.pem  # 私钥，留本机
> openssl ec -in pinkhouse-ck.pem -pubout                                # 公钥，粘进 Console → API Access → Server-to-Server Keys
> ```

优先 Keychain：

```bash
security add-generic-password -s PinkHouseTimeHallPublisher -a keyID       -w '<KEY_ID>'
security add-generic-password -s PinkHouseTimeHallPublisher -a privateKey  -w "$(cat pinkhouse-ck.pem)"
security add-generic-password -s PinkHouseTimeHallPublisher -a containerID -w 'iCloud.bugod2.ItemManager'
```

> ⚠️ **Keychain hex 坑（2026-09-25 实测）**：`security -w "$(cat key.pem)"` 会把
> 多行 PEM 按**二进制 data** 存进钥匙串，`-w` 读回来是整段 PEM 的 **hex 编码字符串**，
> 直接喂给签名器会报 `MalformedFraming`。`publish_adapters.decode_pem_material`
> 已做「原文 PEM → hex → base64」三态自动还原，无需处理；但排查认证问题时
> 先想到这一层（症状：`selftest_signing.py` 全过、一读 Keychain 就加载失败）。
>
> 另一个实测坑：CloudKit `records/lookup` 对不存在的记录**不报 HTTP 错**，而是在
> `records` 数组里返回 `serverErrorCode: "NOT_FOUND"` 条目。读取与发布端都必须
> 过滤（`publish_adapters.first_existing_record`），否则「没发布过」会被误判成
> 「发布头存在但资产缺失」，`_asset_exists` 甚至会让发布端跳过包上传。

开发环境可改用环境变量指向的 JSON 文件（会在输出里明确警告）：

```bash
export PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE=/path/to/dev-credentials.json
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

在 **Security Roles** 里给 `_world`（或等价的 public 角色）只赋 `Read`。
**Write/Create 给谁见下——这里 2026-09-25 踩过实测坑**：

> ⚠️ **s2s key 不绕过安全角色**。按 Apple 官方 CloudKit Catalog 的说法，
> s2s 请求「inherit the privileges of the creator of the key」——继承**创建这把
> key 的开发者用户**的权限，而开发者在权限矩阵里就是一个已认证用户。
> 如果把所有角色的 Write/Create 全收掉，发布端 `records/modify` 会直接报
> `CREATE operation not permitted`（ACCESS_DENIED）。
>
> - **Development**：给 Authenticated（已认证用户）行勾 Create+Write
>   （开发环境只有团队成员能访问，放宽不泄漏给用户）；
> - **Production**：建自定义角色（如 `TimeHallPublisher`）授 Create+Read+Write，
>   把开发者自己的 User Record 加进去，再收掉 Authenticated 行的 Create/Write。
> - `_world` 任何环境都只 Read。

Query 索引（如果运营侧要用 query 拉取而非 lookup）：`THDataPack.partitionID`、
`THMedia.mediaKey` 需要标记 Queryable。

### 3. 发布

> ⚠️ **TestFlight / App Store 只读 Production 环境**，Xcode 本地构建读 Development。
> 两者记录、Schema、s2s key 完全隔离。发给 TestFlight 用户前必须按
> `docs/TIME_HALL_PRODUCTION_PUBLISH_RUNBOOK.md` 单独发布到 Production
> （含 Console 部署 Schema、建 Production s2s key、写 `.production` 后缀 Keychain 凭证）。

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

## 商店目录（店家上新）分片 —— 时光馆「商店」内容

「店家上新 / 公共 Catalog」与画册共用同一套 CloudKit 记录类型（`THRelease` / `THDataPack` /
`THMedia`）与同一个发布头，但走**整包单分片**：

| 项 | 取值 |
|---|---|
| entityType | `shop-catalog` |
| brandID | `shaonv-xinyuan`（运营自有内容源，**不与画册品牌共用**：根清单 brands 按 brandID 去重，共用会报重复品牌） |
| partitionID | `shaonv-xinyuan/shop-catalog/all` |
| 载荷键 | `shopCatalog`（TimeHall 画册分片是 `records`） |
| 载荷内容 | 合并种子与覆盖层后的**完整**商店目录（shops / series / products / variants / sizeCharts / saleEvents / assets / styleProfiles + 三组 `removed*IDs` 墓碑） |
| 审批 | `sources.yaml` 的 `shopCatalog.permissionStatus`，默认 `pending_review` |

**为什么整包不拆分**：「商品 → 系列 → 店家」「规格 / 销售记录 / 尺码表 → 商品」是强引用，
拆包会让引用跨包悬空、客户端必须一次取齐 8 个包才能渲染；商店目录体积远小于单包上限。

```bash
python3 build_release.py --input <目录> --shop-catalog <商店目录.json> \
    --output <产物目录> --release-seq <N>

# 未批准来源的本地联调：加 --allow-unapproved-local-fixture
# （产物标记 localFixture，--adapter cloudkit 会被强制拒绝）
```

结构校验由 `protocol.validate_shop_catalog` 专门负责：实体 id 非空唯一、
店家/系列/商品/规格/销售记录/尺码表/款式档案的引用**必须包内可解析**、
墓碑不得与现存实体同 id、销售记录类型/币种与发售阶段/尾款粒度枚举合法。
图片引用允许指向 Bundle 内置资源（`bundle:` 前缀），**不**做资产引用校验。

⚠️ **运营导出输入时必须导出「合并视图」**（Bundle 种子 + 覆盖层）。
只导覆盖层会因引用悬空被校验拒绝——这正是设计要拦住的错误，不是误报。

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

- ~~`publish_adapters.CloudKitWebServicesAdapter` 与
  `verify_publication.CloudKitPublicReader` 的请求构造**未经真实环境验证**~~
  → **2026-09-25 已在 Development 真实环境全链路验证通过**
  （releaseSeq=1 发布 + 读者视角回读均通过）。
- 签名算法为 `SignatureV1`（ECDSA P-256 / SHA-256）。**签名对象是三段**
  `[ISO8601 日期]:[base64(SHA-256(请求体))]:[URL subpath]`（2026-09-25 修正：
  旧实现只签「日期:请求体原文」，漏了摘要 base64 与 subpath，真机必然认证失败）。
  该算法已由 `selftest_signing.py` 离线钉死（6 项断言，含两条反向断言）。
  若仍报签名错误，优先核对日期格式（`%Y-%m-%dT%H:%M:%SZ`，无小数秒）
  与请求体是否为规范化 JSON 字节。
- 资产上传现行协议（**2026-09-25 真实环境逆向 + 验证通过**，旧「modify 带
  ASSET 占位换 uploadURL」已被 Apple 服务端拒绝）：

  1. `POST assets/upload`，body =
     `{"tokens":[{"recordType","recordName","fieldName","fileChecksum","size"}]}`，
     `fileChecksum` = 文件 SHA-256 的 base64 → `tokens[0].url` = 单次上传地址
  2. `POST` 文件**原始字节**（`application/octet-stream`）到该地址
     → 响应 `{"singleFile":{"size","fileChecksum","receipt"}}`
     ⚠️ `singleFile.fileChecksum` 是**服务器自己算的短值**（不是提交的 SHA-256），
     receipt 尾部编码了它
  3. `records/modify` 写记录，asset 字段 = **整个 `singleFile` 对象原样**
     （与 cloudkit.js `consumeUploadReceipt` 行为一致）

  **`bad upload receipt (did_not_validate)` 的实测根因**：第 3 步自拼
  `{__type, receipt, fileChecksum, size}` 且 fileChecksum 用自己的 SHA-256，
  与 receipt 内嵌的服务器校验和不一致。用服务器返回的 singleFile 原样写回即过。
  另注意：delete 操作必须带 `recordChangeTag`（先 lookup 拿 tag）。

## 验收对照（设计 §18.1）

| 验收点 | 由谁保证 |
|---|---|
| D09 重复 ID / 悬空关系 / 错误品牌范围 | `protocol.validate_pack_payload`（TimeHall → `validate_fragment`；商店目录 → `validate_shop_catalog`）+ `validate_release_references`，在 `build_release` 与 `validate_release` 各跑一次 |
| D10 partial 包少记录不当作删除 | `TimeHallRepository.composeLocalFragment`（客户端侧，见 Swift 实现） |
| D11 complete 新快照的移除是有意行为 | `build_release.diff_summary` + `validate_release --previous` 输出条目数下降提示 |
| D12 schema 不受支持时明确拒绝 | `check_release_header` 校验 `schemaVersion` / `minimumReaderVersion` |
| 只增不改与最后切换 | `publish_cloudkit` 的 7 步顺序 |
| 冲突不吃掉 | `put_release(expected_change_tag)` |
| 回滚不倒退 | `rollback_release.py` + `publish_cloudkit` 递增校验 |
