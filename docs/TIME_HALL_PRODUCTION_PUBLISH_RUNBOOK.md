# Time Hall / 店家上新 · Production 发布 Runbook

> 2026-09-25 事故复盘：TestFlight 包看不到公共库数据，Xcode 本地构建正常。

## 根因

**CloudKit 环境分离**：

| 构建来源 | 读取的 CloudKit 环境 |
|---|---|
| Xcode 安装到模拟器/真机（Debug/开发者签名） | **Development** |
| TestFlight / App Store（Release） | **Production** |

Development 与 Production 是**两套完全隔离的库**：记录不互通，Schema 不互通，
**s2s key（Server-to-Server Key）也不互通**。此前发布流水线只发到了
Development（`publish_cloudkit.py` 的 `--environment` 默认值就是 `development`），
所以 TestFlight 读 Production 是空的，客户端按「公共库还没发布过」空态处理（`nothingPublished`）。

实测证据（2026-09-25）：

```
verify_publication.py --adapter cloudkit --environment development
  → releaseSeq 1，1404 条目，回读通过 ✅
verify_publication.py --adapter cloudkit --environment production
  → HTTP 401 Unauthorized（s2s key 没有 Production 访问权）❌
```

## 上线步骤（一次性配置 + 每次发布）

### 第一步：CloudKit Console 配置（需要 Apple ID 登录，人工操作）

1. **部署 Schema 到 Production**
   CloudKit Console → 选中容器 `iCloud.bugod2.ItemManager` →
   **Deploy Schema Changes to Production**。
   （Development 里建的 `THRelease` / `THDataPack` / `THMedia` 及其字段、
   Query 索引必须显式部署，否则 Production 查询会报 Unknown record type。）

2. **配置 Production Security Roles**（见 publication/README.md §2）
   - `_world`（所有用户）：只 Read；
   - 建自定义角色 `TimeHallPublisher`：授 Create + Read + Write，
     把开发者自己的 User Record 加进去（发布端 s2s 请求继承 key 创建者的权限）；
   - Authenticated 行**收掉** Create/Write（普通用户对公共库零写权限）。

3. **创建 Production 的 s2s key**
   Console 顶部环境切到 **Production** → API Access →
   Server-to-Server Keys → 新建（可以复用同一对 EC P-256 公私钥，
   注册出属于 Production 环境的 Key ID）。
   ⚠️ Apple 官方：key/token 按环境隔离，Development 的 key 打 Production
   URL 必 401。

### 第二步：把 Production key 写入本机 Keychain

```bash
security add-generic-password -s PinkHouseTimeHallPublisher -a keyID.production       -w <PROD_KEY_ID>
security add-generic-password -s PinkHouseTimeHallPublisher -a privateKey.production  -w "$(cat eckey.pem)"
security add-generic-password -s PinkHouseTimeHallPublisher -a containerID.production -w iCloud.bugod2.ItemManager
```

（Development 仍用无后缀账户名 `keyID` / `privateKey` / `containerID`，互不干扰。）

### 第三步：发布到 Production

```bash
cd tools/time_hall/publication

# 首次先 dry-run 核对请求形状（不带 --apply 不会写）
python3 publish_cloudkit.py --release <产物目录> --adapter cloudkit \
    --environment production --print-requests

# 正式发布
python3 publish_cloudkit.py --release <产物目录> --adapter cloudkit \
    --environment production --apply --receipt publish-receipt-prod.json

# 上线后自证（只读回读）
python3 verify_publication.py --adapter cloudkit --environment production
```

发布器硬约束照常生效：发布号严格递增、不可变资源只增不改、
`THRelease` 条件更新（changeTag 冲突即中止）。

### 第四步：TestFlight 验证

安装/更新 TestFlight 版本 → 进「店家上新」页 → 首次进入触发同步
（30 分钟节流；手动刷新可 `force`）。看到数据即闭环。
如仍为空，检查发布器输出的 state：
`nothingPublished` = Production 仍无发布头（发布没成功）；
`failed` = 错误原因会如实展示，不会静默吞掉。

## 工具层的防再犯改动（2026-09-25）

- `publish_adapters.py` `Credentials.load(environment)`：Production 环境读取
  `.production` 后缀的 Keychain 账户；缺失时直接报错并给出配置指引，
  **拒绝拿 Development key 去碰 Production**（过去会发出请求然后 401，误导排查）。
- `publish_adapters.py` / `verify_publication.py`：HTTP 401 翻译为明确诊断
  「s2s key 没有该环境的访问权」，指向本文档。
