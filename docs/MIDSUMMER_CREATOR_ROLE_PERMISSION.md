# 仲夏物语 · 创作者角色权限（2026-09-18）

> 目标：**普通用户（非创作者）看不到、也用不了任何创作者专属能力**；
> 创作者对「自己发布的系列」与「平台历史内容 / 外部渠道导入的条目」有**一致**的编辑能力。

## 一、改动前的两个敞口

| 敞口 | 现状 | 风险 |
|---|---|---|
| 入口无门控 | 系列详情「上新管理」2026-09-16 深夜起对所有用户无条件开放 | 任何用户都能进上架管理、改价、换图 |
| 服务层无校验 | `MidsummerListingStore` / `MidsummerCloudService.publish` 不校验角色 | 绕过界面直接调用即可写入本地存档与云端公共库 |

另外「谁是创作者」此前散在三处各自判定（`CreatorMode` 本机开关、
`NoticeCloudKitService.CreatorGate` 白名单、`MidsummerStore.canEnterCreatorView`），
口径不一致是敞口的根因。

## 二、单一真值：`CreatorAccess`

`ItemManager/Services/CreatorAccess.swift`：

- `CreatorRole`：`viewer` / `creator`
- `CreatorOperation`：被保护的动作（`listingPublish` / `listingStatus` / `listingDelete` /
  `listingEdit` / `priceEdit` / `imageReplace` / `seriesCreate` / `cloudPublish`）
- `CreatorAccess.shared.isCreator`：界面门控读它
- `CreatorAccess.requireCreator(_:)`：**服务层写接口第一行**调它，非创作者抛
  `CreatorAccessDenied`（带「哪一步被拦 + 为什么 + 怎么办」）

判定矩阵（保守优先，取不到身份一律按普通用户）：

| CloudKit 白名单 | 本机「创作者模式」开关 | 角色 | 依据 |
|---|---|---|---|
| `allowed` | 任意 | 创作者 | 白名单 |
| `denied` | 任意（含开） | **普通用户** | 明确不在白名单，开关撬不开 |
| `unresolved`（模拟器 / 未登录 iCloud / 断网） | 开 | 创作者 | 本机开关放行（维护者通路） |
| `unresolved` | 关 | 普通用户 | 默认态 |

设置页「创作者模式」开关在 `denied` 时**锁定为关**，避免本机自提权。

## 三、前端门控清单

| 能力 | 位置 | 门控 |
|---|---|---|
| 上新管理入口 | `MidsummerSeriesDetailView`（`series-listing-workspace-button`） | `canEditContent = CreatorAccess.shared.isCreator` |
| 工作台：发布新商品 / 编辑 / 改价 / 上下架 / 删除 | `MidsummerListingWorkspaceView` | `canEdit`，另给只读说明 `listing-workspace-viewer-notice` |
| **上新工作台整页**（防深链 / 场景恢复） | `MidsummerListingWorkspaceView.body` | `if canEdit { … } else { viewerNotice }`——普通用户进不了编辑态，也不渲染任何上架记录与价格 |
| **四步上新表单整页**（防深链 / 场景恢复） | `MidsummerListingFormView.body` | `if canEdit { formContent } else { viewerPage }`（`listing-form-viewer-notice`）——不预填草稿、不渲染四步表单 |
| 系列详情价格总表改价 | `MidsummerSeriesListView.priceTableRow` | `canEditContent`（普通用户行是纯文本） |
| 工作台价格总表改价 | `MidsummerListingWorkspaceView.priceTableRowContent` | `canEdit` |
| 改价 + 商品图面板（自建商品） | `MidsummerListingPriceEditSheet` | 非创作者显示 `MidsummerCreatorOnlyNotice`，无输入、无保存按钮 |
| 改价 + 商品图面板（历史 / 导入条目） | `MidsummerItemPriceEditSheet` | 同上（CloudKit 链路） |
| 品牌页「上传上新」+ 双视角切换 | `MidsummerBrandView` | `creatorAccess.isCreator` |
| 商品详情：编辑资料 / 换主图 / 换款式图 | `MidsummerItemDetailSheet` | `viewMode.isCreator && creatorAccess.isCreator` |

三层拒绝的文案共用 `CreatorAccess.shared.deniedGuidance`（复用 `CreatorAccessDenied.recoverySuggestion`），
避免「列表页一句、面板里另一句」的文案漂移：入口层隐藏 → 页面层整页拒绝 → 服务层抛错。

「深链」在本工程的含义是**绕过入口直接呈现页面**（`sheet` 被状态重建、场景恢复、
将来新增的呈现方式），不是 URL Scheme——两个页面都自己守一次，不依赖入口是否门控正确。

## 四、服务层校验清单（防绕过）

| 接口 | 文件 | 校验 |
|---|---|---|
| `upsert` / `updateStatus` / `delete` | `MidsummerListingStore` | `requireCreator(.listingEdit / .listingStatus / .listingDelete)` |
| `saveImages` / `saveStyleImage` | `MidsummerListingStore` | `requireCreator(.imageReplace)`，且**在删旧图之前** |
| `add` | `MidsummerCustomSeriesStore` | `requireCreator(.seriesCreate)` |
| `publish(series:)` / `publish(item:)` | `MidsummerCloudService` | `requireCreator(.cloudPublish)`，在建 `CKRecord` 之前 |
| 上新表单提交 / 存草稿 | `MidsummerListingFormView` | 进入落盘前先 `requireCreator(.listingPublish)` |

被拒时不落盘、不删图、不改状态；界面把 `error.userMessage` 显示出来，不静默失败。

## 五、两类内容的一致处理

| 内容 | 编辑面板 | 落点 | 校验 |
|---|---|---|---|
| 创作者自建系列 / 工作台商品 | `MidsummerListingPriceEditSheet` | 本地 JSON 存档 | 同一个 `MidsummerPriceValidator` + 同一个 `MidsummerPriceImageGrid` |
| 平台历史内容 / 外部渠道（微博、淘宝等）导入条目 | `MidsummerItemPriceEditSheet` | CloudKit 公共库（整条重写发布） | 同上 |

差别只在「落到哪里」，**权限校验、价格规则、图片宫格交互、保存后的刷新方式一致**；
内容与来源不参与门控判定（不看 `sourceKind` / `verified` / 是否种子数据）。

## 六、边界与已知限制

1. **客户端是预校验，不是安全边界**：真正的写权限在 CloudKit Console 的 Security Roles
   （`_world` / `_icloud` 必须 Read-only）。本层挡的是「App 内越权」，挡不住拿凭据直连 CloudKit。
2. **预售相位自动流转不受权限影响**：`refreshPresaleTransitions` 是时间驱动的系统行为，
   走无校验的私有落盘通道 `write(_:)`，否则普通用户 App 里到期商品永远推不到尾款期。
3. **角色判定是异步的**：启动与云端刷新各问一次 CloudKit；判定回来之前一律按普通用户渲染
   （保守优先），回来后 `@Published` 触发界面刷新。
4. **本机开关只在 `unresolved` 时生效**：已登录 iCloud 且不在白名单的设备，开关锁定，
   改不了角色；模拟器 / 未登录 iCloud 靠它维护内容。
5. **普通用户能力不受影响**：浏览、规格面板、一键入库、购买等路径不经过任何新增校验。
6. **UI 用例依赖启动参数**：创作者流程需 `-ui-test-enable-creator-mode`；
   `TimeHallEntryExplorationUITests.testD2_...` 验普通用户看不到入口。

## 七、测试

- `ItemManagerTests/CreatorAccessTests`：角色矩阵 + 服务层拦截（被拒不改数据、不删原图）
  + 自动流转不受门控影响。
- 既有 `MidsummerListingTests` / `MidsummerPresalePhaseTests` / `MidsummerCustomSeriesStoreTests`：
  在 `setUp` 注入创作者角色，继续验各自的业务逻辑。
- UI：`TimeHallEntryExplorationUITests` 的 `testD_...`（创作者可见可进）
  与 `testD2_...`（普通用户不可见，但价格总表照常只读展示）。

## 八、附带修复：首页 feed 的卡片层级 == 跳转目标层级

排查「入口跳转异常」时定位到的根因**不在导航代码**，而在首页 feed 决定「这一行出哪种卡」的判定上。

- 现象：品牌首页「浪漫蔷薇」这张卡（自建系列 + 1 条上架商品）文案是 `浪漫蔷薇 系列 · 1 个商品链接`、
  右侧是橙色 `chevron`（系列入口语义），但**同一件商品紧接着又以商品卡出现一次**（`吊带粉色`）。
  两张卡指向同一件东西，落点却是两个层级：系列卡 → 系列详情（还得再点一次才到商品），
  商品卡 → 单品详情。
- 根因：`MidsummerBrandView.itemList` 只按**基础条目**数量分支——
  `baseItems.count == 1` 出商品卡，否则一律出 `MidsummerSeriesGroupCard`。
  自建系列（上传上新直达新建）没有任何基础条目，于是 `baseItems.count == 0` 掉进「组卡」分支，
  被当成「多链接系列」处理。
- 修法：把层级归属按**本系列实际有几件商品**判定
  （`ItemManager/Views/Midsummer/MidsummerBrandView.swift`）：

  | 本系列内容 | 出哪种卡 | 点击落点 |
  |---|---|---|
  | 唯一基础条目（种子 / 云端 / 导入） | 商品卡 | 单品详情 |
  | 无基础条目 + 恰好 1 条上架商品 | **商品卡**（本次修复） | 单品详情 |
  | 多个基础条目 / 多条上架商品 | 系列入口卡 | 系列详情 |
  | 无基础条目 + 多条上架商品 | 系列入口卡（收敛，避免每条各占一行） | 系列详情 |

  既有交互不变：樱花小羊（唯一基础条目）仍然首页直开单品详情，上架新品作为商品卡追加在下方。

### 复现与验证

模拟器数据：自建系列 `midsummer-custom-rosedemo`（浪漫蔷薇，2026 / 定金期 / 尺码 S）+
上架商品 `upload-rosedemo1`（吊带粉色，现货 ¥258 / 预约 ¥249 / 定金 ¥50 + 尾款 ¥199）。

临时探针 `ItemManagerUITests/_ProbeCardJumpUITests`（跑完已删）把落点打到 xcodebuild 日志：

- 修前：首页 `浪漫蔷薇，系列入口，1 个商品链接，¥258`；点它 → 系列详情
  （`series-price-table` + `series-listing-workspace-button` + 上新（定金）1 件）。
- 修后：`midsummer-series-card-midsummer-custom-rosedemo` 在首页消失，浪漫蔷薇只出商品卡，
  点它 → 单品详情（`midsummer-detail-hero`）。
