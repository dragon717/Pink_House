# 时光馆静态内容 + CloudKit 公共库 · 验收指南

> 对应设计：`docs/Pink_House_TimeHall_Static_CloudKit_Design.md`
> 落地范围：**PR-1 / PR-2 / PR-3**
> 本文回答两个问题：**改了什么**、**怎么自己验证**。

---

## 一、这次交付了什么

把时光馆从「纯 Bundle 加载」改成三通道：

```text
生产通道（Mac，仅运营）          消费通道（App，所有人只读）
─────────────────────           ──────────────────────────
Bundle catalog.json    ──┐
（随包离线种子）          │
                         ├──►  TimeHallCatalogStore（展示层）
CloudKit 公共库          │         ▲
THRelease / THDataPack   │         │ 先验证后切换
THMedia                ──┤         │
（运营发布，不可变）        │    TimeHallRepository（读取决策）
                         │         ▲
本机下载缓存          ──┘         │ 按需补全
Library/Caches/TimeHall ─────────┘
```

**普通用户零写入能力**：客户端代码在类型层面没有写公共库的方法。

### 代码文件

| 文件 | 行数 | 作用 |
|---|---|---|
| `ItemManager/Models/TimeHall/TimeHallPublicationModels.swift` | 新增 | 发布协议模型：发布头、根清单、分片描述、撤回、控制状态、规范 ID |
| `ItemManager/Models/TimeHall/TimeHallReadModels.swift` | 新增 | 读取模型：业务日历、分片 ID、读取请求/结果、缓存用量与上限、读者协议 |
| `ItemManager/Services/TimeHall/TimeHallPublicationValidator.swift` | 新增 | 三层校验：structural / partition / brandDataset |
| `ItemManager/Services/TimeHall/TimeHallBundleSource.swift` | 新增 | Bundle 作为只读种子源，5 个品牌登记表 |
| `ItemManager/Services/TimeHall/TimeHallPackCache.swift` | 新增 | 分片缓存 actor：原子安装、generation 校验、LRU 回收、CRC32 校验 |
| `ItemManager/Services/TimeHall/TimeHallMediaCache.swift` | 新增 | 图片缓存 actor：MIME/哈希校验、降采样、预算回收 |
| `ItemManager/Services/TimeHall/TimeHallRepository.swift` | 新增 | 读取决策核心：本地快显 → 云端确认 → 按需补全 → 校验后安装 |
| `ItemManager/Services/TimeHall/TimeHallPublicCloudReader.swift` | 新增 | CloudKit 只读 Reader（`publicCloudDatabase`） |
| `ItemManager/Services/TimeHall/TimeHallUserStateStore.swift` | 新增 | 收藏存储（沿用 `timeHall.treasured.v1`，无迁移） |
| `ItemManager/Services/TimeHall/TimeHallCacheMaintenance.swift` | 新增 | 缓存维护服务 + 设置页视图模型 |
| `ItemManager/Services/TimeHall/TimeHallCatalogStore.swift` | **重写** | 展示状态适配层：先验证后切换；不再承担上传/鉴权 |
| `ItemManager/Views/Settings/TimeHallCacheSettingsView.swift` | 新增 | 「时光馆下载缓存」设置页 |
| `ItemManager/Views/Settings/Refactored/SystemSettingsView.swift` | 改动 | 在「存储与性能」挂载新页面 |
| `ItemManager/Views/TimeHall/TimeHallView.swift` | 改动 | 进入时光馆时触发一次云端确认（不阻塞首屏） |

### 发布流水线（Mac 侧，Python）

`tools/time_hall/publication/`

| 脚本 | 作用 |
|---|---|
| `protocol.py` | 协议层纯函数：规范 JSON 字节、SHA-256、gzip(mtime=0)、记录名、ID 校验 |
| `sources.yaml` | 内容来源与授权配置（**默认全部 `pending_review`，禁止发布**） |
| `sources_loader.py` | 严格子集 YAML 解析器（不依赖 PyYAML，看不懂就报错） |
| `build_release.py` | 构建不可变产物：分片、压缩、摘要、根清单、跨包依赖声明 |
| `validate_release.py` | 校验产物自洽性（含与上一版的条目数对比） |
| `publish_adapters.py` | 发布适配层：`filesystem`（演练）/ `cloudkit`（真实），含条件更新与冲突检测 |
| `publish_cloudkit.py` | 发布主入口：**不可变资源先上、发布头最后切换** |
| `verify_publication.py` | 以读者视角回读验证线上内容 |
| `rollback_release.py` | 回滚：发布号继续递增，不倒退 |
| `drill_offline.sh` | **一键离线全链路演练**（本文 L2） |

### 测试

`ItemManagerTests/TimeHallPublicationProtocolTests.swift` — 43 个用例，覆盖协议往返、撤回优先合并、分片 ID 路径穿越防护、缓存原子安装与竞态、篡改检出、Bundle 种子声明。

---

## 二、怎么测

四层，从快到慢、从离线到线上。**L1 和 L2 你现在就能跑，不需要任何凭据。**

| 层 | 覆盖 | 需要什么 | 预计 |
|---|---|---|---|
| L1 | 协议 / 缓存 / 校验逻辑 | 模拟器 | 分钟级 |
| L2 | 发布流水线全链路（含拒绝路径） | 无 | 数十秒 |
| L3 | App 内真实交互 | 模拟器 | 手动 |
| L4 | 真实 CloudKit 读写 | 凭证 + Console 配置 | 需先做前置 |

---

### L1 · 单元测试（43 个用例）

```bash
cd /Users/sangyu/develop/Pink_House

# 1) 先编译 app + 测试目标
xcodebuild -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/DerivedData \
  -IDEPackageSupportDisableManifestSandbox=YES \
  -skipPackagePluginValidation -skipMacroValidation \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' \
  build-for-testing

# 2) 再跑测试
xcodebuild -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/DerivedData \
  -IDEPackageSupportDisableManifestSandbox=YES \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' \
  -only-testing:ItemManagerTests/TimeHallPublicationProtocolTests \
  test-without-building
```

**预期**：`Executed 43 tests, with 0 failures`。

> ⚠️ 本机跑 `xcodebuild` **必须**带上面三个沙箱开关，否则会失败在环境上而不是代码上。原因见 `~/.workbuddy/skills/pink-house-xcodebuild-acceptance/`。
> 注意本机模拟器是 **iPhone 18 Pro**，`AGENTS.md` 里的 `iPhone 16 Pro` 已不存在。

**这层能证明什么**：协议实现、撤回优先合并、缓存清理不误伤、篡改能被检出。

---

### L2 · 发布流水线一键演练（推荐先跑这个）

```bash
cd /Users/sangyu/develop/Pink_House
bash tools/time_hall/publication/drill_offline.sh
```

一条命令跑完 **21 项断言**，全程离线、零凭据、不碰真实 CloudKit：

| 阶段 | 检查内容 | 期望 |
|---|---|---|
| 1 | 构建产物、根清单、分片目录、产物自洽 | 退出码 0 |
| 2 | dry-run **不留副作用**；apply 后发布头/根清单/回执落地 | 退出码 0 |
| 3 | 读者视角回读线上内容 | 退出码 0 |
| 4 | **拒绝路径**：重复发布号 → 5；回滚号不递增 → 4；localFixture 发 CloudKit → 4；**篡改分片 → 回读 3** | 全部拦住 |
| 5 | 回滚产物生成 → 校验 → 发布到干净目录 → 回读，发布号推进到 5 | 退出码 0 |

**成功标志**：`通过 21 项，失败 0 项`。

调试用：

```bash
bash tools/time_hall/publication/drill_offline.sh --verbose   # 打印每步完整输出
bash tools/time_hall/publication/drill_offline.sh --keep      # 保留工作目录与日志
```

---

### L3 · App 内手工验收（模拟器）

**准备**

```bash
cd /Users/sangyu/develop/Pink_House

xcodebuild -project ItemManager.xcodeproj -target ItemManager \
  -sdk iphonesimulator -configuration Debug \
  -IDEPackageSupportDisableManifestSandbox=YES \
  -skipPackagePluginValidation -skipMacroValidation \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  SYMROOT="$PWD/build/sym" OBJROOT="$PWD/build/obj" \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' \
  build

xcrun simctl boot "iPhone 18 Pro" 2>/dev/null || true
xcrun simctl install booted "$PWD/build/sym/Debug-iphonesimulator/ItemManager.app"
BUNDLE_ID=$(grep -m1 PRODUCT_BUNDLE_IDENTIFIER ItemManager.xcodeproj/project.pbxproj \
  | awk -F'= ' '{print $2}' | tr -d ';" ')
xcrun simctl launch booted "$BUNDLE_ID"
```

#### A. 原有功能没被破坏（回归）

| 步骤 | 操作 | 预期 |
|---|---|---|
| A1 | 底部导航 → 「时光馆」 | 页面正常渲染：年表 / 图鉴 / 品牌切换都在，无空白页、无崩溃 |
| A2 | 点「选择品牌」 | 5 个品牌都能进入并显示各自内容 |
| A3 | 随便收藏一条 → 完全退出 app → 重新进入 | **收藏还在** |

A3 是重点：改造重写了 `TimeHallCatalogStore`，收藏键 `timeHall.treasured.v1` 保持不变、无需迁移。收藏丢了就说明这里出了问题。

#### B. 新页面：设置 → 存储与性能 → 「时光馆下载缓存」

| 步骤 | 预期 |
|---|---|
| B1 | 能进入，标题为「时光馆下载缓存」 |
| B2 | 「检查线上更新」开关：**默认关闭** |
| B3 | 「图鉴数据」「图片缓存」「合计」：均为 **0 字节** |
| B4 | 「最近检查」：**尚未检查** |
| B5 | 「清理下载缓存」按钮：**置灰不可点** |

B3 + B5 一起说明一件事：**Bundle 离线资料不算「缓存」**，所以一开始没有可清理的东西——清理功能设计上不碰随包内容。

#### C. 云端不可用时的降级（关键）

现在 CloudKit 公共库还没配（Record Type 未建），所以这是**故意制造一个失败场景**来看降级行为。

| 步骤 | 操作 | 预期 |
|---|---|---|
| C1 | 在缓存设置页打开「检查线上更新」 | 开关变开 |
| C2 | 回到「时光馆」 | 内容**照旧来自 Bundle**，正常显示 |
| C3 | 观察 | **不崩溃、不白屏、不无限转圈** |

判定重点：**线上请求失败绝不能把已有内容弄没**。代码里 `performCloudRefresh` 遇到 `.failed` 会直接 return，不覆盖当前快照——C 就是在验这条。

#### D. 清理缓存的真实验证

这步需要先有下载内容，所以**只有在 L4 跑通之后才有意义**：

| 步骤 | 预期 |
|---|---|
| D1 | L4 同步过之后回到缓存设置页，「合计」应 **> 0** |
| D2 | 「清理下载缓存」按钮变为可点 |
| D3 | 点击 → 弹出确认框，文案明确写出「不会删除你的衣橱、手账、收藏或个人照片」 |
| D4 | 确认后：「清理完成」出现，占用归 0，按钮重新置灰 |
| D5 | 回时光馆：内容退回 Bundle 快照，**收藏仍在** |

---

### L4 · 真实 CloudKit 联调（需要你先做前置）

**前置 1：CloudKit Console 配置** —— 见 `docs/TIME_HALL_CLOUDKIT_CONSOLE_SETUP.md`。

Development / Production 各做一遍：建 `THRelease` / `THDataPack` / `THMedia` 三个 Record Type，**并在 Security Roles 里给 `_world` 只给 `Read`、任何角色都不给 `Write`**。

> 这一步脚本代替不了。设计 §7.3 明确写了不能只靠客户端 `adminIDs` 判断——否则任何人都能伪造发布头把未审核内容推给全量用户。

**前置 2：来源授权** —— `tools/time_hall/publication/sources.yaml` 里 5 个品牌当前全是 `permissionStatus: pending_review`，必须经运营/法务确认后改为 `approved` 并填写 `allowedContentTypes` / `allowedTerritories`，才能构建**可发布**的产物。未批准的来源只能构建 `localFixture` 产物，而 `publish_cloudkit.py` 会**硬拒绝**发布它（无覆盖开关，退出码 4）。

**前置 3：发布凭证**（只从 Keychain 或环境变量指向的文件读取，绝不作为命令行明文参数）

```bash
security add-generic-password -s PinkHouseTimeHallPublisher -a keyID        -w <KEY_ID>
security add-generic-password -s PinkHouseTimeHallPublisher -a privateKey   -w <PEM 内容>
security add-generic-password -s PinkHouseTimeHallPublisher -a containerID  -w iCloud.bugod2.ItemManager

# 开发环境可用文件凭证替代（生产请用 Keychain）
export PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE=/path/to/dev-credentials.json
```

**联调顺序**

```bash
cd /Users/sangyu/develop/Pink_House/tools/time_hall/publication
PY=/Users/sangyu/.workbuddy/binaries/python/versions/3.13.12/bin/python3

# 1) 构建可发布产物（不带 --allow-unapproved-local-fixture）
$PY build_release.py --input <已审核输入目录> --output /tmp/th_release \
  --release-seq 1 --scope legacy --coverage-mode partial

# 2) 校验
$PY validate_release.py --release /tmp/th_release

# 3) 先看请求、不发请求 —— 首次务必做这步
$PY publish_cloudkit.py --release /tmp/th_release \
  --adapter cloudkit --environment development --print-requests

# 4) 确认无误后真发
$PY publish_cloudkit.py --release /tmp/th_release \
  --adapter cloudkit --environment development --apply

# 5) 以读者视角回读
$PY verify_publication.py --adapter cloudkit --environment development
```

**App 侧验证**：打开「检查线上更新」开关 → 进时光馆 → 回设置页应看到缓存占用 **> 0**。

---

## 三、当前的验证边界（如实说明）

**已验证**

- `ItemManager` 主 target、`少女心愿衣橱Extension`、`ItemManagerTests` 编译通过，零错误
- 43 个协议单测真跑通过（0 失败）
- 发布流水线离线全链路 21 项断言通过，含 4 条拒绝路径
- 篡改分片能被回读检出（退出码 3）

**未验证**

| 项目 | 原因 | 首次怎么做 |
|---|---|---|
| `CloudKitWebServicesAdapter` 真实 HTTP 请求 | 无凭证，请求按 Apple 公开文档实现 | `--print-requests` 逐条核对后再 `--apply` |
| `TimeHallPublicCloudReader` 真实读库 | 本机无凭证 | L4 步骤 5 回读验证 |
| 模拟器 UI 视觉验收 | 本次只要求写代码 + 跑构建 | 按 L3 逐项手动过 |
| 撤回在真实库的效果 | 需要真实发布包含撤回的版本 | 用 `--withdrawals` 构建一版验证 |

**当前默认行为**

- `TimeHallRuntimeConfiguration.isCloudSyncEnabled` **默认关闭**。生产库还没有第一个 `THRelease` 之前，每次启动都发一次注定失败的请求既浪费配额也污染日志。运营发布首个版本后，在缓存设置页打开开关即可。
- 关闭时 Bundle 与本地下载缓存仍完整可用，主功能不受影响。

---

## 四、一句话总结怎么测

```bash
# 最快的两条
bash tools/time_hall/publication/drill_offline.sh     # 流水线（无凭据，21 项断言）
# 然后按 L1 跑 43 个单测，再按 L3 在模拟器上点一遍
```

L1 + L2 通过 = 逻辑正确；L3 通过 = 交互与降级正确；L4 要等你把 CloudKit Console 配好。
