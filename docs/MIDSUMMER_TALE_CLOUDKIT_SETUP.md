# 仲夏物语品牌页 · CloudKit Console 配置清单

> 对象：**人工在 CloudKit Console 完成的一次性操作**。代码无法替代。
> 归属：`docs/MIDSUMMER_TALE_BRAND_PAGE.md` 的部署章节。
> 容器：`iCloud.bugod2.ItemManager`（**复用现有容器，不要新建**）

---

## 0. 不配置会怎样

先说清楚，避免误以为「跑不起来」：

| 场景 | 表现 |
|---|---|
| 完全不配置，直接跑 App | ✅ **正常**。品牌页读 Bundle 种子（13 个系列 / 29 个单品），浏览、筛选、进详情页全部可用 |
| 上传入口 | ❌ 保存失败。会弹出「当前账号没有上传权限」或「未知的记录类型」 |
| 登录了 iCloud 也看不到上传入口 | ✅ **默认如此**。入口由 `adminIDs` 白名单 + 「创作者模式」开关共同门控（合规要求） |
| 想让入口出现 | 打开 **设置 → 创作者 → 创作者模式**，或点品牌页页脚的「我是内容维护者…」引导。**不需要重新发版** |

也就是说：**看的内容不需要配置，上传的内容才需要。**

---

## 1. Record Type 与字段

在 Development 与 Production **各配一次**。

> 提示：在 Development 环境用 App 上传一条测试数据，CloudKit 会自动创建 Record Type 与大部分字段，之后你只需补索引；但**权限与索引不会自动生成**，仍需手工完成下面第 2、3 节。

### 1.1 `MidsummerSeries`（系列）

| 字段名 | 类型 | 索引 | 说明 |
|---|---|---|---|
| `seriesID` | String | **Queryable** | 稳定 ID，同时用作 recordName |
| `name` | String | — | 系列名 |
| `year` | Int64 | **Queryable** | 年份，年份导航用 |
| `launchedOn` | String | — | `yyyy-MM-dd`，空串表示待补充 |
| `stage` | String | **Queryable** | `preview`/`deposit`/`balance`/`shipping`/`restock`/`inStock` |
| `sizes` | String List | — | 例如 `["S","M","L","XL"]` |
| `colors` | String List | — | 配色 |
| `summary` | String | — | 系列简介 |
| `sourceURL` | String | — | 原文出处（**必填**，Apple 5.2） |
| `sourceKind` | String | — | `editorial` |
| `verified` | Int64 | — | `1` = 创作者已核对 |
| `priceMin` | Int64 | — | 价格区间下限（元） |
| `priceMax` | Int64 | — | 价格区间上限（元） |
| `publishedAt` | Date/Time | **Sortable** | 上传时间，查询按此倒序 |
| `createdBy` | String | — | 上传者 recordName |
| `coverImage` | Asset | — | 封面图（长边已压到 1200px） |

### 1.2 `MidsummerItem`（单品）

| 字段名 | 类型 | 索引 | 说明 |
|---|---|---|---|
| `itemID` | String | **Queryable** | 稳定 ID，用作 recordName |
| `seriesID` | String | **Queryable** | 所属系列，读取时按它分组 |
| `name` | String | — | 款名 |
| `kind` | String | **Queryable** | `op`/`jsk`/`skirt`/`blouse`/`accessory`/`set` |
| `price` | Int64 | — | 现货价 |
| `deposit` | Int64 | — | 定金 |
| `balance` | Int64 | — | 尾款 |
| `sizes` | String List | — | 单品可选尺码 |
| `colors` | String List | — | 配色 |
| `sourceURL` | String | — | 原文出处 |
| `itemURL` | String | — | 商品链接（可空） |
| `note` | String | — | 待补项说明 |
| `publishedAt` | Date/Time | **Sortable** | |
| `createdBy` | String | — | |
| `coverImage` | Asset | — | |

**索引就这些，别多加**：Queryable 索引会影响写入性能与配额，按上表最小集配即可。

---

## 2. Security Roles —— 本期最关键的一步

> ⚠️ 现状背景：`docs/CloudKitDashboardSetup.md:110-116` 把 `_icloud` 角色配成了 **Write ✅**，等于「任何登录 iCloud 的人都能写记录」。上新流会展示跳转链接，一旦被注入钓鱼转链，影响面是**全体用户**，风险等级与公告完全不同。

操作：

1. CloudKit Console → Security Roles → 新建自定义角色，建议命名 `MidsummerEditor`
2. 成员用 `recordID.recordName` 添加（形如 `_819804d902cb79c2d6e4bf736ed6c50b`）
3. 对 `MidsummerSeries` 与 `MidsummerItem`：
   - **Create / Write 只给 `MidsummerEditor`**
   - `_icloud` 设为 **Read-only**
   - `_world` 设为 **Read-only**
4. **Development 与 Production 两个环境各配一次**——只配一个等于没配

### 为什么不能只靠客户端的 `adminIDs`

`adminIDs` 是硬编码在 App 里的数组，只决定「界面上显不显示入口」。反编译或抓包后任何人都能直接调 CloudKit 写接口。**它只是 UI 闸门，不是安全边界**——真正的边界在 Console 的角色配置里。

---

## 3. 运营 onboarding

1. 运营用**专用 Apple ID**（不要共用个人号）登录设备
2. 在 App 内触发一次 `getCurrentUserID()`，控制台会打印
   `🔑 当前用户 iCloud ID: _xxxx`
   （在公告 CMS 的管理页里已有该触发点，复用即可）
3. 把该 ID 记档，加入 `MidsummerEditor` 成员
4. 让入口显示出来 —— 两条路，**不必重新发版**：

   **（推荐）** 在 App 内打开开关：设置 → 创作者 → 「创作者模式」，
   或点仲夏物语品牌页页脚的「我是内容维护者，开启创作者模式以补充缺项」。
   该开关存在 `UserDefaults`（key `creator_mode.enabled.v1`），
   与 iCloud 账户无关，因此模拟器、换号、未登录都能用。

   **（可选，仅当要长期免开关）** 把 ID 加进代码白名单：

   `ItemManager/Services/NoticeCloudKitService.swift:84`

   ```swift
   private let adminIDs: [String] = [
       "_819804d902cb79c2d6e4bf736ed6c50b",  // 主管理员
       "_你的运营ID",                          // ← 加这里
   ]
   ```

   ⚠️ 白名单那条路需要重新发版才生效。若团队会扩，可改为在公共库放一条管理员记录
   （World 可读、仅自定义角色可写），App 启动时拉一次——但仍需保留一个硬编码 root 做冷启动引导。

该 ID 与「Apple ID + 容器」绑定，**换号即失效**，需重新走一遍。

> 补充：客户端 `adminIDs` 与「创作者模式」都只决定**界面是否显示入口**，
> 不是安全边界。把内容真正写进公共库的权限，始终由第 2 节的 Security Roles 决定。

---

## 4. 配置完成后的自检

```bash
# 1. 确认 App 侧读得到（未配置时会打印「公共库暂无创作者上传内容」）
#    在 Xcode 控制台过滤 [Midsummer] 关键字

# 2. 上传一条测试数据，然后检查：
#    • 控制台出现 ✅ [Midsummer] 公共库读取成功：N 个系列 / M 个单品
#    • 品牌页顶部出现「线上资料已更新 · N 个创作者补充系列」
#    • 杀掉 App 重进，内容仍在（说明不是内存态）
```

**反向验证权限（建议真的做一次）**：用一个**不在** `MidsummerEditor` 里的 Apple ID 登录，
尝试上传 → 应该失败。如果成功了，说明权限没配对，需要回到第 2 节。

---

## 5. 配额提醒

- `coverImage` 走 `CKAsset`，会吃容器存储配额。代码已把长边压到 1200px、JPEG 质量 0.82，
  单张通常 150–300 KB
- 建议只传**系列封面**，单品图先不传（当前实现也是这么做的）
- 公共库配额是共享的，批量上传前先估算：`系列数 × 0.25 MB`
