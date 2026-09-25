# 时光馆 CloudKit Console 配置清单（人工一次性操作）

> 配套设计：`docs/Pink_House_TimeHall_Static_CloudKit_Design.md`
> 配套工具：`tools/time_hall/publication/README.md`
>
> **这些步骤脚本无法代做**：设计 §7.3 明确要求公共库的写权限必须在服务端收紧，
> 「不能只靠客户端判断 adminIDs」。必须在 CloudKit Dashboard 里人工建 Schema 并配 Security Role。

## 0. 前置

- 容器：**`iCloud.bugod2.ItemManager`**（与 Notice 公共公告同容器）
- 环境：**Development 与 Production 各做一遍**（CloudKit 的 Schema 需要分别部署；
  Development 建完字段后，用 **Deploy Schema Changes** 推到 Production）
- 数据库：**Public Database**（只读读者都走 public）
- **时光馆「商店」内容（店家上新）与画册共用这 3 个 Record Type 与同一个发布头**，
  区别只在载荷内容：商店目录走整包单分片（`entityType = shop-catalog`、
  `brandID = shaonv-xinyuan`、载荷键 `shopCatalog`），Console 侧**无需**额外建类型，
  详见 `tools/time_hall/publication/README.md` 的「商店目录分片」一节。

## 1. 建 3 个 Record Type

在 **Schema → Record Types** 里新建。字段类型必须与下表一致，否则客户端 `desiredKeys` 解码会失败。

### `THRelease` —— 发布头（**只有一条记录**）

| Field Name | Type | 说明 |
|---|---|---|
| `releaseSeq` | Int64 | 发布序号，严格递增 |
| `schemaVersion` | Int64 | 协议结构版本 |
| `revocationEpoch` | Int64 | 撤回控制版本，单调递增 |
| `minimumReaderVersion` | Int64 | 最小读取协议版本 |
| `previousReleaseSeq` | Int64 | 上一发布序号（运维追踪） |
| `publishedAt` | String | ISO 8601 |
| `rootIndexHash` | String | 根清单文件 SHA-256（hex） |
| `rootIndexAsset` | Asset | 根清单 `root-index.json` |

记录名固定为 **`th.release.catalog-v1`**（见 `protocol.RELEASE_RECORD_NAME`）。

### `THDataPack` —— 不可变数据包

| Field Name | Type | 说明 |
|---|---|---|
| `partitionID` | String | 例如 `pink-house/event/all` |
| `releaseSeq` | Int64 | 首次发布该包的发布号 |
| `sha256` | String | 压缩字节 SHA-256，等于 `payloadHash` |
| `byteCount` | Int64 | 压缩后字节数 |
| `asset` | Asset | `<payloadHash>.json.gz` |

记录名固定为 **`th.pack.<payloadHash>`**。

### `THMedia` —— 不可变媒体

| Field Name | Type | 说明 |
|---|---|---|
| `mediaKey` | String | 稳定业务键，例如 `<canonicalEntityID>#thumb` |
| `mimeType` | String | `image/jpeg` / `image/png` / `image/webp` / `image/heic` / `image/gif` |
| `sha256` | String | 内容 SHA-256，等于 `contentHash` |
| `byteCount` | Int64 | 字节数 |
| `asset` | Asset | `<contentHash>.<ext>` |

记录名固定为 **`th.media.<contentHash>`**。

## 2. 配 Security Role（**最关键的一步**）

> ⚠️ **2026-09-25 二次修正（实测踩坑）**：本节此前写「任何角色都不给 Write/Create，
> 写权限只保留给 server-to-server key」——**这是错的**。
> s2s key **不绕过安全角色**：按 Apple 官方 CloudKit Catalog 的说法，
> s2s 请求「with the inherited privileges of the creator of the key」，
> 即继承**创建这把 key 的开发者用户**的权限，而开发者在权限矩阵里就是一个
> 已认证用户。把所有角色的 Write/Create 全收掉后，实测 records/modify 建记录
> 直接报 `CREATE operation not permitted`（ACCESS_DENIED）。
>
> 正确的两段式配置：
>
> **Development（现阶段）**——开发环境只有开发团队成员能访问，放宽不泄漏给用户：
>
> | Record Type | `_world` | Authenticated（已认证用户行） |
> |---|---|---|
> | `THRelease` | Read | **Create + Write** |
> | `THDataPack` | Read | **Create + Write** |
> | `THMedia` | Read | **Create + Write** |
>
> **Production（正式发布前再收紧）**——Custom Role 方案：
> 1. Security Roles 新建自定义角色（如 `TimeHallPublisher`），对三个类型授 Create+Read+Write；
> 2. 把开发者自己的 User Record 加进该角色（可在 Data 页面建一条任意记录，
>    看 `createdBy` 字段拿到自己的 user record 名）；
> 3. 验证 s2s 仍能写入后，把 Production 的 Authenticated 行 Create/Write 收掉。
>
> `_world` 任何环境都**只给 Read**——普通匿名用户能读不能写，这条不变。

## 3. 建 server-to-server key（发布凭证）

> ⚠️ **2026-09-25 修正**：本节此前写成「在 Console 建 key 后**下载私钥 PEM**」，
> 与 Apple 的实际流程相反。正确流程是：**密钥对在你自己机器上生成，只把公钥上传，
> 私钥永远不离开本机**；Console 只负责回填一个 Key ID。
> 按旧写法操作会卡在「找不到下载私钥的入口」。

### 3.1 在本地生成密钥对（不要用 Console 生成）

```bash
cd ~/.ssh   # 或任何不进仓库的目录
openssl ecparam -name prime256v1 -genkey -noout -out pinkhouse-ck.pem   # 私钥，留本机
openssl ec -in pinkhouse-ck.pem -pubout                                  # 输出即「公钥」，下一步用
```

私钥文件 `pinkhouse-ck.pem` 需要自行安全备份（Apple 侧无法找回）。密钥不设过期，
但可以在 Console 里撤销。

### 3.2 在 Console 上传公钥、领取 Key ID

**API Access → Server-to-Server Keys → Add（+）**

- 把上一步 `openssl ec -pubout` 的**完整输出**（含 `-----BEGIN PUBLIC KEY-----` 与 `-----END PUBLIC KEY-----`）粘进 **Public Key** 输入框
- （可选）填备注，例如「mac-mini 发布机 / 2026-09」
- **Save** → 页面上出现的 **Key ID** 就是要记的东西

### 3.3 把 Key ID 与私钥写进 macOS Keychain（发布脚本读这里）

按 `tools/time_hall/publication/README.md` 的「凭证」一节写入：

```bash
security add-generic-password -s PinkHouseTimeHallPublisher -a keyID       -w '<KEY_ID>'
security add-generic-password -s PinkHouseTimeHallPublisher -a privateKey  -w "$(cat ~/.ssh/pinkhouse-ck.pem)"
security add-generic-password -s PinkHouseTimeHallPublisher -a containerID -w 'iCloud.bugod2.ItemManager'
```

**私钥不要**提交到仓库、不要贴进聊天记录、不要作为命令行参数传递。

> 权限粒度提醒：server-to-server key **继承创建者在容器上的权限，无法按 Record Type 细分**。
> 所以「普通用户不能写」只能靠第 2 节的 Security Role 落实，不能靠这把 key 的配置。

## 4. Query 索引（仅当运营侧要用 query 拉取时才需要）

客户端设计只用 `records/lookup` 按 recordName 精确取，**不需要** Query 索引。
如果运营后台要按字段查：

| Record Type | Field | 标记 |
|---|---|---|
| `THDataPack` | `partitionID` | Queryable |
| `THMedia` | `mediaKey` | Queryable |

## 5. 部署到 Production

1. Development 环境把 Schema 建全、字段类型确认无误
2. **Deploy Schema Changes** 推到 Production
3. Production 环境**同样**检查一遍 Security Role（部署不一定会带过去，必须复核）
4. 用 `--environment production` 跑一次 `verify_publication.py` 确认读者能取到

## 6. 验证清单

配置完成后，按顺序跑：

```bash
cd tools/time_hall/publication

# 1) 读者能否取到发布头（未发布时应报「公共库中没有发布头」，这是正常的）
python3 verify_publication.py --adapter cloudkit --environment development

# 2) 首次发布：先 dry-run + 核对请求
python3 publish_cloudkit.py --release <产物目录> --adapter cloudkit \
    --environment development --print-requests

# 3) 确认请求形状无误后真实发布
python3 publish_cloudkit.py --release <产物目录> --adapter cloudkit \
    --environment development --apply

# 4) 上线后自证
python3 verify_publication.py --adapter cloudkit --environment development
```

## 7. 常见问题

| 现象 | 排查方向 |
|---|---|
| 签名错误 / 认证失败 | 签名对象必须是**三段** `[ISO8601 日期]:[base64(SHA-256(请求体))]:[URL subpath]`（2026-09-25 修正；旧实现只签了日期与请求体原文）。先跑 `python3 selftest_signing.py` 自检；再核对日期格式 `%Y-%m-%dT%H:%M:%SZ`（无小数秒）与请求体是否为**规范化 JSON 字节**（已排序、无多余空白） |
| 认证失败但签名看着对 | 核对 subpath 是否与真实请求 URL 一致（`/database/1/<container>/<environment>/public/<path>`，不含 query string） |
| `records/lookup` 返回空但 Dashboard 能看到记录 | 检查记录名是否完全匹配（`th.pack.<64位hex>`） |
| 客户端报 `rootIndexHashMismatch` | 上传前重新 `validate_release.py`；确认上传的是 `root-index.json` 原始字节，未被重编码 |
| 客户端能读到发布头但取不到分片 | Security Role 的 `_world` Read 没给对；或记录名与 `payloadHash` 不一致 |
| 读取被拒绝 `permissionDenied` | 记录存在但 public 角色没有 Read |
| 发布时报 changeTag 冲突 | 有另一个发布者在同一容器操作；重新读当前状态、合并后再发，**不要**改成无条件覆盖 |

## 8. 与设计的对应

| 本清单步骤 | 设计章节 |
|---|---|
| Record Type 字段定义 | §6.2 / §6.3 / §6.7 |
| Security Role 只读配置 | §7.3（服务端收紧，不能只靠客户端） |
| server-to-server key | §8.5 |
| 凭证不进日志 | §8.5 |
| 发布顺序与冲突检测 | §9.1 / §9.3 |
| 读者视角验证 | §8.2 步骤 9 / §20.2 |
