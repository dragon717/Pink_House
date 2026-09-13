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

在 **Security Roles** 里，对 `_world`（公开角色）**只给 Read**：

| Record Type | `_world` (public) | 任何 authenticated 角色 |
|---|---|---|
| `THRelease` | **Read** | **不授予 Read，更不授予 Write** |
| `THDataPack` | **Read** | 同上 |
| `THMedia` | **Read** | 同上 |

**绝对不要**给任何角色 `Write` / `Create`。

原因（设计 §0.3 第一条硬约束）：普通用户零写。
如果 public 角色能写，任何人都能伪造发布头指向自己上传的内容，
把未审核图片推进全量用户的时光馆——这比"读不到"严重得多。

写权限只保留给 **server-to-server key**（发布流水线用，见下）。

## 3. 建 server-to-server key（发布凭证）

在 **Tokens & Keys → Server-to-Server Keys** 里建一把 key：

- 记下 **Key ID**
- 下载 **私钥 PEM**（只给一次，务必安全保存）

然后按 `tools/time_hall/publication/README.md` 的「凭证」一节写进 macOS Keychain：

```bash
security add-generic-password -s PinkHouseTimeHallPublisher -a keyID       -w '<KEY_ID>'
security add-generic-password -s PinkHouseTimeHallPublisher -a privateKey  -w '<私钥 PEM 全文>'
security add-generic-password -s PinkHouseTimeHallPublisher -a containerID -w 'iCloud.bugod2.ItemManager'
```

**私钥不要**提交到仓库、不要贴进聊天记录、不要作为命令行参数传递。

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
| 签名错误 | 核对日期格式 `%Y-%m-%dT%H:%M:%SZ`；请求体必须是**规范化 JSON 字节**（已排序、无多余空白） |
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
