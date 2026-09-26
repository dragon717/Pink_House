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
| `selftest_cloudkit_read.py` | ⭐ **CloudKit 适配器读/写闸门离线回归锁**：`apply=False`（dry-run / 基线核对）时**读必须真的发出**、**写必须一个请求都不发** | 无第三方依赖（不签名、不联网） |
| `publish_cloudkit.py` | 发布主入口（固定 7 步顺序） | 同上 |
| `verify_publication.py` | 读者视角回读验证 | 同上 |
| `rollback_release.py` | 回滚：历史内容 + 新更高发布号 | 无第三方依赖 |
| `ops_publish_bridge.py` | **运营工作台（Mac App）↔ 流水线的机器可读入口**：只读一个冻结请求 JSON，吐 NDJSON 事件流。发布算法一行都不重实现（全部子进程透传）。四种模式：`baseline` / `publish` / `query` / **`pull-catalog`（只读回读线上商店目录）** | 无第三方依赖 |
| `drill_bridge_offline.py` | 上面那个桥接器的离线全链路演练（基线只读 / 拉回基线 / 演练 / 发布 / 结果查询 / **R07 过期基线闸门** / 七类拒绝路径） | 无第三方依赖 |
| `drill_offline.sh` | 发布流水线自身的离线全链路演练 | 无第三方依赖 |

## 运行环境（`cryptography` 与仓库内的 `.venv`）

`filesystem` 演练、以及桥接器本身**不需要任何第三方依赖**，系统 `python3` 就能跑。
但**真打 CloudKit** 的路径（`publish_cloudkit.py --adapter cloudkit`、`selftest_signing.py`、
以及桥接器的 `--mode baseline`）需要 `cryptography` 做 SignatureV1 签名。

⚠️ **2026-09-27 实测：系统 `python3`（3.9.6）与用户级 site-packages 都没有它**，
且候选列表里的 `/opt/homebrew/bin/python3`、`/usr/local/bin/python3` **在本机并不存在**
（候选实际只剩 `/usr/bin/python3`）。所以仓库里固定放一个 venv：

```bash
cd tools/time_hall/publication
/usr/bin/python3 -m venv .venv
.venv/bin/python -m pip install cryptography
.venv/bin/python selftest_signing.py           # 期望：通过 6 项，失败 0 项
.venv/bin/python selftest_cloudkit_read.py     # 期望：通过 18 项，失败 0 项
```

**为什么 venv 必须放在仓库里**（不能是 `~/.venv`，也不能 `pip install --user`）：
Mac 运营工具是**沙盒 App**，它只能读到自己被显式授权的那一个目录
（用户在选择面板里选过之后生成的 security-scoped bookmark）。
仓库目录就在授权范围内；`~` 下、`/Library/Python` 都不在 —— 放别处会让
「App 驱动的发布」必然报「找不到解释器」，而错误信息看起来像配置写错了。
该目录已加入 `.gitignore`。

## ⭐ 一条不能破的不变量：**读必须无视 dry-run，写必须被 dry-run 拦住**

`CloudKitWebServicesAdapter` 的 `apply=False` 语义是「**不许写**」，不是「不许联网」。
这两者一旦混淆，就会产生**静默的错误结论**（2026-09-27 实测踩到）：

CloudKit 连 `records/lookup` 这种**读**操作也用 POST 动词，早先的实现在**传输层**
一刀切 `if not self.apply: return {}`，于是读被一起挡掉。而桥接器的
`--mode baseline`（R07 只读基线核对）**恒为 `apply=False`**，后果是：

    线上明明有 releaseSeq=1，App 却被告知「线上尚无商店发布头（本次将是首次发布）」

更麻烦的是**离线演练抓不到**：`FilesystemAdapter` 的读不走 `apply` 判定，
所以 `drill_offline.sh` / `drill_bridge_offline.py` 全绿。

现行分工（改代码时不要合并回去）：

| 方法 | 用途 | `apply=False` 时 |
|---|---|---|
| `_send` | **读**（`records/lookup`）、以及写操作的底层传输 | **照发** |
| `_post` | **写路径**入口（`_modify_with_asset` 三步里的第 1/3 步） | 静默返回 `{}` |
| `_upload_file` | 资产字节上传 | 静默返回 `{}` |

回归锁是 `selftest_cloudkit_read.py`（18 项，含**反向断言**：把 `_post` 换成必然抛异常的桩，
读仍须成功 —— 防止两条路又被合并）。它注入 `http_post` 传输层，所以
**不联网、不需要凭证、也不需要 `cryptography`**。

## 快速演练（不需要凭证、不联网）

**最省事的方式：一条命令跑完全链路 34 项断言。**

```bash
cd /Users/sangyu/develop/Pink_House
bash tools/time_hall/publication/drill_offline.sh
```

覆盖：构建 → 自检 → dry-run 无副作用 → 发布 → 回读 → 4 条拒绝路径（重复发布号 / 回滚号不递增 / localFixture 发 CloudKit / 篡改分片）→ 回滚 → 再发布 → **商店目录整包分片（含悬空引用拒绝）**。
成功标志是 `通过 34 项，失败 0 项`。加 `--verbose` 看每步完整输出，加 `--keep` 保留工作目录与日志。

### 运营桥接协议（`ops_publish_bridge.py`）单独也有一份演练

Mac 工作台走的是**桥接器**这条入口（不是直接调 `build_release.py`）。它自己有一份 49 项断言：

```bash
cd /Users/sangyu/develop/Pink_House
python3 tools/time_hall/publication/drill_bridge_offline.py
```

覆盖：R07 基线只读核对（且**不产生副作用**）→ **拉回线上基线**（只读；线上是空的时如实说「没有可拉回的」、且**不产出** `shop-catalog.json`）→ 演练 dry-run（**不留线上副作用、结论绝不是 confirmed**）→ 发布到本机目录 → 回读确认（`readBackConfirmed`）→ R09 结果查询 → **R07 过期基线闸门（5 例）** → 七类拒绝路径：

| 反例 | 期望退出码 | 断言的可读结论 |
|---|---|---|
| 归档在冻结后被改动 | 3 | 「摘要与请求不一致」，而不是笼统失败 |
| `development` + `filesystem` 错配 | 2 | 点名环境/适配器，**不静默降级** |
| 协议版本不符 | 2 | 提示更新 App |
| 缺必填字段 | 2 | 带出字段名 |
| 同一发布号重发 | 5 | 冲突类结论，不当成功 |
| 缺图 | 3 | 「产物要修」，而不是可重试的网络失败 |
| 线上无发布头时查询 | 0 | 结论 = **没有生效**（绝不把「没读到」当「已确认」），且 `retryable=true` |

成功标志是 `通过 49 项，失败 0 项`。

> 这条演练的存在理由：桥接器是「App 以为发出去了」与「线上真的变了」之间**唯一**的接缝。
> 它一旦静默退化成「界面停在『上传中』」，看起来会像网络问题。

#### ⭐ R07 的过期基线闸门（发布前、构建之前）

`build_release.py` 只从**本地**已批准来源构建，**从不读线上**。所以拿一份旧导出去发布，
会把线上后来的改动**整块覆盖** —— 而产物本身是合法完整的，线上看不出来。

在补这条闸门之前，桥接器**一次都没有**读过 `baseReleaseSeq` / `baseRootIndexHash` /
`baselineAcknowledged`：App 把它们写进请求，接收方完全不看。典型的「字段传了但没人用，
看起来做了、实际没做」。现在 `run_publish` 在**构造产物之前**先比对：

| 草稿记录的基线 | 线上 | 结论 |
|---|---|---|
| 空（两个字段都没填） | 任意 | 不一致：无法证明这份内容基于线上当前版本 |
| 有 | 无发布头 | 不一致：草稿基于某个版本，线上却什么都没有 |
| 发布号不同 | — | 不一致 |
| 根清单摘要不同 | — | 不一致（**这是比发布号更强的那一条**） |
| 线上摘要读不到 | — | 不一致：拿不到证据就不能当一致（只比发布号会漏判） |
| 全一致 | — | 一致 |

不一致且 `baselineAcknowledged` 不为真 → **退出码 5（冲突）+ 结论里点名「基线已过期」**，
并提示「先读取线上基线回填，或先从线上拉回基线重建本地内容」。
`baselineAcknowledged` 是 R07 给的**唯一显式出口**：它不是「检查通过」，只是「已留痕的例外」——
放行时必须原样打 `warning`，绝不静默。**dry-run 也走同一判定**（演练不该绕过过期检测）。

#### ⭐ `--mode pull-catalog`：只读把线上商店目录整份拉回

方案 §5 要求发布 = 「**当前线上完整基线** + 变更集 → 合成完整 Catalog，保留未改动内容」。
但在此之前 App 只有「导入 JSON」：基线**内容**全靠人手导出 / 导入，与线上是什么关系没有依据。

```bash
python3 ops_publish_bridge.py --mode pull-catalog --request request.json
# 产物：<outputDirectory>/shop-catalog.json  +  pull-manifest.json
# 事件：{"type":"catalog","path":"…","releaseSeq":N,"rootIndexHash":"…","payloadHash":"…","itemCounts":{…}}
```

四道**拿不到证据就不拉**的自证：① 根清单字节的 SHA-256 必须等于发布头的 `rootIndexHash`；
② 分片必须按 `entityType == "shop-catalog"` 找，**不猜 `partitionID`**；
③ 分片字节的 SHA-256 必须等于其 `payloadHash`；④ 只认**唯一一个**商店分片 ——
多于一个说明口径被改过，此时静默取第一个只会拿到半份目录，**宁可中止**。

线上确实没有发布头 / 没有商店分片时返回 **`EXIT_OK`** 并如实说明「线上是空的、
本地内容不是从线上来的」—— 那是**事实**，不是失败；此时**不产出** `shop-catalog.json`
（产出一份空目录会被当成「拉回了一份空目录」，正好是反的）。

⚠️ 拉回的是**已下发口径**，必须显式告知、不能静默：
`strip_archived_shop_catalog` 已剔除归档条目与孤儿销售事件，
`collect_shop_catalog_media` 把 `local:` 引用改写成了 `thmedia:<内容摘要>`。
所以拉回的内容**不含归档条目**、**图片没有本地文件**。这不是缺陷，是「下发给用户的
东西」的定义 —— 但把它当「完整备份」用会出错。

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

**要拿「当前线上完整基线」就用 `--mode pull-catalog`**（见上面桥接协议那节），
不要去手抄线上内容：它是本分片**唯一**有摘要自证的读取通道。

```bash
python3 build_release.py --input <目录> --shop-catalog <商店目录.json> \
    --output <产物目录> --release-seq <N>

# 未批准来源的本地联调：加 --allow-unapproved-local-fixture
# （产物标记 localFixture，--adapter cloudkit 会被强制拒绝）
```

结构校验由 `protocol.validate_shop_catalog` 专门负责：实体 id 非空唯一、
店家/系列/商品/规格/销售记录/尺码表/款式档案的引用**必须包内可解析**、
墓碑不得与现存实体同 id、销售记录类型/币种与发售阶段/尾款粒度枚举合法。

**资产引用校验**由 `protocol.validate_shop_catalog_media` 负责（公共数据库字段配置方案 §2.3
明确要求补上的发布前错误）：包内每个 `mediaKey` / `thmedia:` 引用都必须命中
**本次真的会上传**的 THMedia；残留的 `local:` 引用一律判失败（它只在运营那台设备成立）。
`bundle:`（App 内置）与 http(s) 不属于 THMedia 通道，不在本校验范围内。

⚠️ **运营导出输入时必须导出「合并视图」**（Bundle 种子 + 覆盖层）。
只导覆盖层会因引用悬空被校验拒绝——这正是设计要拦住的错误，不是误报。

### 图片必须跟着一起发（否则用户端「有目录、没图」）

商品图在设备里的引用是 `local:<文件名>`，指向运营那台设备的沙盒
（`Application Support/ShopCatalog/images/`）——**换台设备就解不出文件**。
只发 JSON 的话，客户端目录数据全在、商品图一律占位图（2026-09-25 实测）。

所以运营端要用**「导出整包（含图片）」**（产出 `.tar`，内含 `shop-catalog.json` + `images/`），
发布端把引用到的图上传成 THMedia，并把包里的引用改写为 `thmedia:<contentHash>`：

```bash
# 方式一：直接给归档（推荐，自动解开取 JSON 与 images/）
python3 build_release.py --input <目录> \
    --shop-catalog-archive <运营导出的 .tar> \
    --output <产物目录> --release-seq <N>

# 方式二：已解开时分别指定
python3 build_release.py --input <目录> \
    --shop-catalog <shop-catalog.json> --shop-catalog-media <images 目录> \
    --output <产物目录> --release-seq <N>
```

约定与行为：

- 只处理 `local:`；`bundle:`（App 内置）与 http(s) 原样保留；
- 同一张图（同内容摘要）只上传一次，多处引用共享；
- **引用到的图缺失 → 构建硬失败（退出码 5）**，绝不静默发一个没用的包；
- 归档条目（含其专属图）先被 `strip_archived_shop_catalog` 剔除，不会白传一份；
- 客户端按需下载（屏内才拉），落 `Caches/ShopCatalogSync/media/`，命中缓存不再打网络。

#### 商品 JSON 的 canonical 媒体键（方案 §2.2）

改写引用时，`CatalogAsset` 会额外写入 **`mediaKey`** —— 取值就是该图字节的 SHA-256
（64 位小写 hex），与 `thmedia:<hash>` 里的 hash **必然一致**。它是消费端解析远端图的
首选口径（`ShopCatalogSyncProtocol.resolvedMediaKey`：`mediaKey` 优先、`thmedia:` 兜底），
旧包（只有 `thmedia:` 引用、没有 `mediaKey`）行为完全不变。

第一版只加**一个** canonical `mediaKey`（取原图）。需要多分辨率时再补
`thumbnailMediaKey` / `previewMediaKey`，或为同一张图发布多条 `CatalogAsset`。

#### 媒体清单（`media-manifest.json`）的输入约束

画册媒体走 `--input` 目录下的 `media-manifest.json`。每条至少三个键，
缺一即构建失败：

| 键 | 约束 |
|---|---|
| `mediaKey` | **必填**，且必须等于该文件字节的 SHA-256（否则报「声明 ≠ 实际」） |
| `fileName` | **必填**，相对 `--input` 的路径，文件必须存在 |
| `mimeType` | **必填**，必须在白名单内：`image/jpeg` `image/png` `image/gif` `image/webp` `image/heic` |

另有单张媒体字节上限 `MAX_MEDIA_BYTES`（20 MiB）。商店目录的图片不写 manifest，
走归档里的 `images/`，但适用**同一套** MIME 白名单与字节上限。

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
