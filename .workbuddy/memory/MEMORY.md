# Pink_House 硬规则（红线 + 索引）
> **完整规则表 / 函数口径见同目录 `RULES.md`**；事故经过见 `YYYY-MM-DD.md`。动对应模块前先读 RULES.md 那一节。

## 红线（违反必出事）
- **单测宿主 = 主 App**，`FileManager.default` 就是**用户真实沙盒**：落盘测试必须 `ShopCatalogStorage.useTemporaryForTesting()`，禁碰生产路径；`.shared` 跨套件累积 → setUp 要 `loadDrafts()`，断言只比前后快照或按 `batchID` 收窄。
- 启动：`INFOPLIST_KEY_UILaunchScreen_Generation` 必须 `NO`（YES = 空字典 = 深色纯黑，被误判「打不开」）；方向只由 Info.plist / pbxproj 的 `UISupportedInterfaceOrientations[_iPhone]` 决定。
- 构建测试走 skill `pink-house-xcodebuild-acceptance`；destination 用 UDID `FA7332BE-B29E-4879-A139-C68A24314DB1`（写 `name=` 会 exit 70）。
- 搜索用 `grep -E`/`-F`（BSD 禁空交替，`(a|b|)` **静默不过滤**）；搜中文兼搜 `\uXXXX`。
- 列表一律走 `AZIndexGrouping` / `*SortedByName()`：数组是**录入顺序**不是字典序。
- 价格：**修正 ≠ 追加**且不共用逻辑；修正**留空 = 清除**；`CatalogSaleEvent` 只 append、**永不 remove/replace**；缺失一律「暂无」，禁 `deposit ?? 0`。
- 图表：两卡只消费同一个 `ShopCatalogChartPresentation.plan(...)`；`sourceImage` 非空绝不静默 `.none`；**识别结果必须过 `CatalogChartQuality` 门禁**，未过门禁一个字都不写进输入框（弹窗「解析失败，请手动录入」+ 恢复识别前快照）；粘贴与多模态回复共用 `parsePastedText`，**预览即落库**。（**09-23 需求一后图片识别入口已移除**，`CatalogChartExtraction` 无调用方、文件暂留；系列编辑页的 `priceChartImageText` state 必须留着，它承载既有原图。）
- **「同款商品集合」只能有一处定义**（`ShopCatalogDesignPalette.sameDesignProducts`）：详情页「配色」行 = **同款颜色集合**（`store.designColors`），**不能**读本商品规格色 —— 否则 SPU/SKU 下会「标题写 3 色、配色行整行消失」（09-23 事故）。加购弹窗的色号选择器是另一回事，仍读 `colors(forProduct:)`，禁合并。
- 删除：预检与执行**共用** `plan*Deletion`；批量删除**整批只写一次覆盖层**；销售事件保留；部分成功绝不静默。
- 发布幂等 ID 必须按**该类型自己的**价格指纹；草稿坏 JSON 留原件 + 备份 + 阻止写回。
- 录入端**一个表单一个款式**：`applyStyleForm` 一次 persist 完成新增/更新/移除并如实回报 `skippedSettled`；**款式名一处决议**（逐条派生会让新色拿空款名 → 加一色变两款）；**同款家族必须同源**（`sameStyleFamily`，否则**误删**草稿）；图片绑定 `ColorRow.imageRefs → draft.images → variant.imageAssetID`。
- 加购记账：**金额零手输**（预约价/定金/尾款全取 `CatalogPriceArchive`；**尾款读 `currentBalance`，禁现算**，落库与弹窗共用 `ShopCatalogWardrobeAmount`）；分支唯一口径 `ShopCatalogWardrobeEntryPolicy`；全款走 `PriceMode.fullReservation`（`isFullPaymentReservation` + `pendingFinalPaymentAmount == 0`，**绝不生成尾款任务**）；衣橱**记录名**走 `ShopCatalogWardrobeTitle.recordName`（三段式），**不与商品标题合并**；状态标签唯一口径 `ShopCatalogWardrobeStatusTag.chips`；`ClothingEditDraft` 新增字段**必须 Optional**（非 Optional 会让旧草稿 JSON 解码失败）。
- 系列发售阶段：`CatalogSeries.salePhase`/`reservationEndAt`（**必须 Optional**）；**自动流转=读取时判定**（`CatalogSeriesSalePhaseResolver.effectivePhase`），**不做定时任务回写**（会覆盖运营声明）；详情页**系列声明优先 → 未声明落回档期推导**；保存只写这两个字段，**不碰任何价格**；⚠️ 预约已结束**只改引导不剥夺能力**：全款为主按钮，【加入心愿尾款】收进「其他记账方式」折叠区，**禁止隐藏/置灰**。

## 主题索引 → RULES.md
环境/工具 · 启动与「强制横屏/打不开」 · 测试数据隔离 · SPU/SKU 分层与录入期同步 · 尺码表=款式级共享 · 列表/归组/标题与同款颜色 · 价格（修正 vs 追加） · 图表展示同源 · 图表识别与录入（门禁/多模态/粘贴） · 系列发售阶段与自动流转 · 加购记账与衣橱标题 · 删除守卫 · 币种与发布幂等

## 两个易踩
- `CatalogProductDraft` 新增款式字段必须进 `publishOperationKey` 指纹，否则「改了再发布」被幂等入口吞掉。
- `colorWords` 必须含**复合色**（`生成色`/`粉紫色`，长词优先），否则同款三色被拆成三款。
