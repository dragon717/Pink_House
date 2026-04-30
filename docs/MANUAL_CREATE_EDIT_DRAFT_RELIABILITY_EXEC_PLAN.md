# 手动创建/编辑 草稿可靠性 · 执行计划与验收标准（harness）

> 状态：**2026-04-30 调研稿，未动代码**。仅文档。按本 harness 三阶段（D0/D1/D2）逐项落地，每阶段都必须先满足"不允许的假修复"清单，才进入下一阶段。
> 范围：`ItemManager/Views/ClothingEditView.swift`（手动创建 / 编辑单品的同一页 View）以及它的入口 `ItemManager/Views/HomeView.swift` 添加按钮 + sheet。
> 不动：SwiftData schema、`Clothing/Tag/Brand/Accessory*` 字段、CloudKit 同步链路、引导锚点 API、主题皮肤 slot 资产、ImageManager 图片落盘策略。
> 与已有计划的关系：与 `WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md` / `iOS26_WARDROBE_MENU_PERFORMANCE_EXEC_PLAN.md` 互不重叠 —— 前两者关注"列表/菜单首帧"，本文档关注"编辑页表单状态在 view 重建 / 进程被杀 / 系统打断 下不丢失"。

---

## 0. 启动协议（必读）

执行任何步骤前先把以下变量写入会话上下文：

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
TARGET_FILES=(
  "ItemManager/Views/ClothingEditView.swift"   # 草稿主战场（含 ClothingEditDraft / ClothingEditDraftManager / ClothingEditView）
  "ItemManager/Views/HomeView.swift"           # 入口（showingAddSheet / continueFromDraft）
  "ItemManager/Services/ImageManager.swift"    # 图片落盘 / 删除（草稿恢复时图片必须存在）
  "ItemManager/Services/SuggestionManager.swift" # onAppear 时的同步加载
)
LOW_END_DEVICES=("iPhone SE (3rd gen)" "iPhone XR" "iPhone 11")  # 内存最容易被回收
MID_DEVICES=("iPhone 13" "iPhone 14")
HIGH_DEVICES=("iPhone 16 Pro")
OS_TIERS=("iOS 17.5" "iOS 18.4" "iOS 26.0")    # 26 必跑（PhotosPicker / scenePhase 行为变化）
DRAFT_FIELD_TIERS=("空" "仅文本(name+brand)" "文本+1张图" "文本+5张图+尺码表+价格表+5个 Tag+3个配饰" "全字段+10张图")
INTERRUPT_MATRIX=(
  "切到桌面 5 秒回来"                          # backgrounding 短
  "切到桌面 30 分钟回来"                        # backgrounding 长（系统可能回收）
  "切到桌面 → 打开 4-5 个其它大型 App 后回"      # 强制回收（kill）
  "下拉系统通知栏并松手"                          # scenePhase=.inactive 不进 background
  "下拉控制中心 5 秒后松手"                       # 同上
  "PhotosPicker 选 1 张图"                       # 系统 sheet
  "PhotosPicker 多次选/换图后取消"                 # 系统 sheet 反复
  "切横屏 / 转回竖屏"                            # geometry change → 可能触发 view rebuild
  "弹键盘 → 切换语言/Emoji"                       # InputMethod change
  "拔/插耳机、AirPods 来电"                      # 短暂 inactive
  "断网（飞行模式开关）"                          # 网络异常（汇率刷新失败）
  "推送/弹窗（短信、闹钟、Face ID 锁）"             # 系统级中断
)
```

### 0.1 不允许的"假修复"

- **删除 `currentDraft` 内存兜底层**只靠 UserDefaults —— 等于丢失"view 重建但进程未死"场景的最后一道防线。
- 把 `@State private var draftManager` 简单改名"看起来像 `@StateObject`" —— 必须搞清楚 singleton 引用、`@Published` 订阅、view 重建三件事的真实需求，再决定属性包装器。
- 把所有 form `@State` 一口气搬到 `@Observable` ViewModel **同时不重写持久化层** —— 大爆炸式改造无法分阶段验收，必须先稳定持久化（D1）再做架构升级（D2）。
- 用 `Timer.scheduledTimer` 每 N 秒强写盘 —— 写盘频次必须由 state 变化驱动 + debounce，否则空闲用户也在反复 IO。
- 用 `@SceneStorage` 替换 UserDefaults —— iOS/iPadOS 的 `@SceneStorage` **scene 被系统清理时会丢数据**（参见外部资料 §10.2），且不能跨场景，不适合"用户期待长留的草稿"。
- 在 `onChange(of:)` 闭包里直接 `Task { await ... }` 写盘 —— 写盘是 IO 阻塞操作，且会与 view body 同周期产生时序竞争；必须经由独立的 actor / 串行 queue。
- **删除"取消按钮也保留草稿"的逻辑** —— 用户报告里有"我点了取消想后悔"的场景，回归测试必须证明它仍然能恢复。
- 把 UserDefaults 写法换成 `synchronize()` 调用更密集 —— `synchronize()` 自 iOS 12 起已是 no-op，密集调用反而误导读者；问题不在这里。
- 在 `onDisappear` 内做长任务（图片复制、网络）—— sheet 关闭动画期间主线程被占会肉眼可见。
- 用 `try?` 吞掉 JSON 编码错误 —— 必须有埋点上报失败，否则草稿默默丢了无人知晓。

---

## 1. 必读上下文（顺序固定，行号以当前 main 为准）

1. `ItemManager/Views/ClothingEditView.swift:14-30` — `TagData: Codable`（草稿里 Tag 的轻量序列化形式）。
2. `ItemManager/Views/ClothingEditView.swift:33-156` — `ClothingEditDraft: Codable` 全字段 + `hasMeaningfulData` 内置判定。
3. `ItemManager/Views/ClothingEditView.swift:158-323` — `ClothingEditDraftManager: ObservableObject`（singleton；UserDefaults Key：`ClothingEditDraft` / `ClothingEditDraftID` / `ClothingEditDraft.edit.<UUID>`；含 `currentDraft` 内存层 + `currentEditingDrafts` 字典 + `activeEditorTokens`）。
4. `ItemManager/Views/ClothingEditView.swift:325-403` — `ClothingEditView` 顶部声明：**~30 个 `@State` form 字段**全部裸露在 View 上，未集中到 ViewModel；`@State private var draftManager = ClothingEditDraftManager.shared`（line 334，**误用 `@State` 持有 ObservableObject**）；`hasProcessedDraft` / `didPersistForLifecycle` 两个生命周期标志位。
5. `ItemManager/Views/ClothingEditView.swift:435-460` — `init(clothing:initialBrandID:initialTypes:continueFromDraft:)`，`continueFromDraft` 由 HomeView 入口决定。
6. `ItemManager/Views/ClothingEditView.swift:625-661` — toolbar 的「取消 / 保存」按钮：取消时的"有数据则保留草稿，否则连同图片一起清"分支（line 633-647）。
7. `ItemManager/Views/ClothingEditView.swift:683-744` — 生命周期组合：`onAppear` / `onChange(imagePaths)` / `onChange(draftObservationKey)` / `onChange(scenePhase)` / `onReceive(didEnterBackgroundNotification)` / `onDisappear`。**核心写盘时机全在这一段**。
8. `ItemManager/Views/ClothingEditView.swift:746-785` — `initializeEditorIfNeeded`：onAppear 时的恢复优先级（编辑：DB → editingDraft；创建：continueFromDraft → persistedDraft → in-memory currentDraft）。
9. `ItemManager/Views/ClothingEditView.swift:868-934` — `makeCurrentDraft / persistCurrentStateForLifecycle / clearCurrentDraftStorage / saveCurrentStateAsDraft` 四件套。
10. `ItemManager/Views/ClothingEditView.swift:1055-1073` — `hasMeaningfulData()` 真实门槛（任一字段非空即 true，门槛低，但**取消逻辑**复用了它，需要警惕）。
11. `ItemManager/Views/HomeView.swift:362, 586-600, 1394, 1517-1526, 1534-` — `showingAddSheet` / `continueFromDraft` 状态、`.sheet` 包 `NavigationStack { ClothingEditView }`、`wardrobeAddMenuContent` 里"继续草稿/新建"两个入口对 `continueFromDraft` 的赋值差异。
12. **官方/权威文档**（PR 描述里必须引用条款编号）：
    - WWDC23 *Demystify SwiftUI performance*（view identity / state lifetime / `@StateObject` 与 view rebuild）。
    - WWDC23 *Discover Observation in SwiftUI*（`@Observable` macro，iOS 17+，本项目 deployment ≥ iOS 17 可用）。
    - WWDC22 *The SwiftUI cookbook for navigation* §State restoration / NSUserActivity。
    - Apple Developer · *Restoring your app's state with SwiftUI*（`onContinueUserActivity` / `userActivity(_:isActive:_:)`）。
    - Apple Developer · *Preserving your app's UI across launches*（NSUserActivity vs `@SceneStorage` vs `@AppStorage` 适用场景对比）。
    - Apple Developer · *UIApplication.didEnterBackgroundNotification* / *willResignActiveNotification*（两者触发顺序与对应 scenePhase）。
    - Apple HIG · *Modality* / *Sheets*（对意外退出页面的"用户期望保留"建议）。
    - Foundation · `Data.write(to:options:)` `.atomic` 选项（崩溃安全的文件写入）。
    - Combine · `Publishers.Debounce` / `RunLoop.main` 调度（按键节流写盘）。

---

## 2. 现状诊断（按风险从高到低）

> 每一条都附"用户感知症状 → 触发条件 → 代码路径 → 影响半径"。这是 D0 测量阶段的假设清单，每条都需要在 §3 矩阵里至少一例命中。

| # | 假设 / 根因 | 用户感知 | 触发条件 | 代码路径 |
|---|---|---|---|---|
| H1 | **打字过程中没有写盘**——只有 `imagePaths` 变化、scenePhase、didEnterBackground、onDisappear 才写盘；其它字段（name/brand/types/colors/sizes/length/note/价格/日期/Tag/Accessory）只 `updateCurrentDraft()` 进**内存** | 用户输入了一段文字，App 被系统直接 kill（多任务回收 / OOM）后再开，文字全没了 | 长时间后台 / 多任务页右滑关闭 / 系统级 OOM | 第 688/701/737-743 行的 `onChange(...)` 没覆盖文本/价格/Tag 字段 |
| H2 | **`@State` 误用持有 ObservableObject**（line 334） | 罕见情况下 `draftManager` 的 `@Published` 变化未触发依赖 view 刷新（如菜单的"继续草稿"按钮显隐） | 父 view 重建后 `hasPersistedDraft` 变化时机错过 | line 334 应改 `@StateObject` 或不放在属性里（直接 `ClothingEditDraftManager.shared.xxx`） |
| H3 | **取消按钮在"无意义数据"时清掉了**已存在的旧草稿 | 用户上次留了草稿，这次进来误点取消 → 旧草稿没了 | 用户进入页面、未做任何编辑、点取消（`!isEditing && hasMeaningfulData()==false` → 走 line 643 `clearDraft()`） | line 637-643 `else if !isEditing { ... clearDraft() }` —— 把"清新建草稿"和"清图片"绑死 |
| H4 | **scenePhase=.inactive 时 `hasMeaningfulData()` 门槛挡住保存**（创建模式） | 用户只输入了空格 / 全角符号 / 未触发任何字段 → 切走再回来空白 | `persistCurrentStateForLifecycle` (line 906-914) 中 `guard isEditing \|\| hasMeaningfulData() else { return }` | 创建模式下，没"有意义"数据时**主动跳过写盘** |
| H5 | **UserDefaults 不适合大对象 / 不保证落盘** | 草稿包含 imagePaths + tags + accessoryList → 序列化后可能 5–50KB；后台被强杀时最近一次写未必落盘 | UserDefaults 内部异步刷盘；进程突死 | line 199-211 `saveDraft()` 仅 `userDefaults.set(...)+synchronize()`（synchronize 自 iOS 12 是 no-op） |
| H6 | **图片孤儿 / 草稿与图片不同步** | 恢复草稿时图片打不开（Image 显示破图） | 草稿被清但图片未清 / 图片被清但草稿仍引用 | line 632 注释 + line 640-642 取消时手动删图片，缺统一 GC |
| H7 | **`hasProcessedDraft` 防多次处理但与重建混淆** | 一次进入页面途中如果 ClothingEditView identity 变了（例如父链 body 重新计算导致 sheet 内容重建），`hasProcessedDraft` 会重置 → 可能"重新覆盖"已修改字段 | 父 view 重建 → ClothingEditView identity 改变 → `@State` 全部归零 → `onAppear` 又跑一次恢复 | line 752 `guard !hasProcessedDraft` 在 view rebuild 后失效 |
| H8 | **PhotosPicker 弹出/收起的 scenePhase 行为差异** | 用户选完图回来发现表单变空 | iOS 26 PhotosPicker 在 inactive 期间触发 scenePhase 变化的具体相位需实测 | line 712-720 `onChange(of: scenePhase)` 行为依赖 OS |
| H9 | **多 sheet 同页嵌套（品牌/标签/通用选择）回弹时**短暂 disappear → onDisappear → 写盘 → 再 appear 重新恢复，看似 OK，但中间窗口内若 `currentDraft` 被外部清掉就会丢 | 多次开关品牌/标签 sheet 后偶发字段被还原到旧值 | line 662-682 三个 `.sheet`，line 726-736 onDisappear 总是触发 | `.sheet` 关闭路径 |
| H10 | **NSUserActivity 完全未使用** | iPad 多窗口 / Stage Manager 场景下，重新打开窗口无法恢复编辑态 | iPadOS 多场景 | 项目目前未实现 `userActivity(_:isActive:_:)` |
| H11 | **`refreshJPYRateForEditor()` 异步竞争** | 进入页面瞬间汇率刷新落地后，`syncCurrencyAmountsFromPreferredCurrency` 把恢复的金额覆盖了 | 弱网 / 进入瞬间恢复草稿时 | line 686 onAppear `Task { await refreshJPYRateForEditor() }` 与 line 766/771/776 的 `restoreFromDraft` 之间无 happen-before |

---

## 3. 测试矩阵（先建后改）

> 每个 cell = "字段集 × 中断方式 × 设备/OS"。D0 阶段必须把矩阵全部跑一遍，记录"清掉/恢复/部分恢复"三态。**不靠回忆判断，靠日志 + 截屏**。

### 3.1 字段集（由 `DRAFT_FIELD_TIERS` 决定，每档预置一个 macro 录屏脚本）

| Tier | 内容 |
|---|---|
| F0 | 空表单进入即触发中断 |
| F1 | 仅 name + brandName |
| F2 | name + 1 张图 + 1 个 Tag |
| F3 | F2 + 价格(原价 + JPY 汇率)+ 尺码表 + 价格表 + 3 个配饰 |
| F4 | 10 张图 + 满字段 + 5 配饰 + 5 Tag + 备注 200 字 |

### 3.2 中断方式（`INTERRUPT_MATRIX`，每条单独跑一次）

需要采集：
- **打断前**：所有字段值（截屏 + 日志 dump `makeCurrentDraft()` JSON）。
- **打断 / 恢复后**：再次进入页面看到的值（截屏 + 日志）。
- **进程是否被杀**：通过 Console.app 看 `osanalyticsd` 的 jetsam log 或 Xcode Devices 的 Crashes。

### 3.3 设备 × OS

每个字段集 × 每种中断 至少跑：
- 1 台 LOW_END iOS 26（最容易触发系统强杀）
- 1 台 MID iOS 18.4（基线）
- 1 台 HIGH iOS 17.5（旧 OS 对照，若仍支持）

### 3.4 期望结果矩阵（D0 后根据真机数据填，作为 D1/D2 的回归基线）

| Tier × 中断 | 期望（D2 完成后） | 当前（D0 实测） |
|---|---|---|
| F4 × 系统强杀 30min | 100% 字段恢复 + 图片可显示 + Tag/配饰齐 | _待填_ |
| F3 × 下拉通知栏 | 100% 字段保留（无重建发生） | _待填_ |
| F1 × PhotosPicker 选图取消 | 100% 字段保留 | _待填_ |
| F0 × 任何中断 | 不创建任何残留草稿（避免下次"继续草稿"按钮误亮） | _待填_ |
| ... | ... | ... |

---

## 4. D0 阶段：测量 + 最小止血（不改架构）

> 目标：**不写功能代码、只加埋点和最小修复**，把 §2 的 11 条假设全部用真机日志证伪或证实。所有改动可独立回滚。

### 4.1 埋点（使用 `os_signpost` + `Logger`，category = `"DraftReliability"`）

- `signpost("draft.save", reason)` 包住 `saveDraft / saveEditingDraft`，metadata 记录 `imageCount / hasName / byteSize`。
- `signpost("draft.load", source)` source ∈ {`memory_currentDraft`, `userdefaults_persisted`, `userdefaults_editing`, `none`}。
- `signpost("draft.clear", reason)` —— **每一处 `clearDraft` / `clearEditingDraft` / UserDefaults remove 都要包**，这是定位"被清掉"的关键证据链。
- `signpost("editor.identity", "init")` 在 `init` 中 log `ObjectIdentifier(self)` 等价物（用 `UUID()` per-instance 也行），以辨识"view rebuild 次数"。
- `signpost("scenePhase", oldValue, newValue)` 记录所有 phase 切换。

### 4.2 真机录像 + 日志收集脚本

- 在 `temp/_drafts/` 建 5 份 `seed_<tierID>.json`，提供 macOS Shortcut 一键填充字段。
- 每跑一个矩阵 cell：`xcrun simctl spawn booted log stream --predicate 'subsystem == "com.itemmanager"' --style ndjson > temp/_drafts/run-<id>.ndjson`。
- 真机用"控制台.app + iPhone 已连接"，按时间窗口导出。

### 4.3 D0 最小止血（**不改架构，仅修明显逻辑漏洞**）

1. **取消按钮不再误清旧草稿**（应对 H3）：line 637-643 的 `else if !isEditing { ... draftManager.clearDraft() }` 改为"取消时**只删本次会话已上传的图片**，不清 UserDefaults"。把"清旧草稿"的责任交给 §4.3.4 的入口逻辑。
2. **更宽松的写盘门槛**（应对 H4）：`persistCurrentStateForLifecycle` 把 `hasMeaningfulData()` 改为"任一字段被用户碰过（包括尚未达到 hasMeaningfulData 阈值）"——通过新增 `hasUserTouchedAnyField` 标志位。后台 phase 时**只要标志位为真就写盘**。
3. **文本字段也立即触发写盘**（应对 H1，过渡期方案）：在 `onChange(of: draftObservationKey)`（line 701）加 debounce 500ms 之后调用 `saveCurrentStateAsDraft()`（D0 用 `Task.sleep` 简易实现，D1 替换为 Combine debounce）。
4. **入口决定旧草稿命运**（应对 H3 + H7）：`HomeView.wardrobeAddMenuContent` 的"新建空白 / 继续草稿"分支，**只有"新建空白"按钮按下时才 `clearDraft()`**；其余路径（含取消、误关 sheet、系统打断）一律保留。
5. **`@State draftManager` 改 `@ObservedObject draftManager = ClothingEditDraftManager.shared`**（应对 H2）。仅一行，但要在 D0 单独验收 `draftManager.$hasPersistedDraft` 的订阅链是否生效（HomeView 菜单显隐变化）。
6. **失败上报**（应对 H5）：所有 `try? JSONEncoder().encode(draft)` 改成 `do/catch`，失败时 signpost 一条 `draft.save_failed` 并 `print` 完整 error。

### 4.4 D0 验收门槛

- 矩阵跑完，§3.4 表格全部填写实测值。
- §2 的 H1/H3/H4 确认为**主因**（具体百分比）。
- 上面 6 条 D0 改动落地后，**F1+F2+F3 × 切后台 5 秒/30 分钟、下拉通知栏、PhotosPicker** 这 12 个 cell 100% 恢复。
- F4 × 系统强杀 30 分钟仍可能丢（留给 D1）。

---

## 5. D1 阶段：持久化重写（架构稳定，行为提升）

> 目标：UserDefaults 退役，写盘机制改为**文件 + 原子写入 + debounce + 串行 actor**。`@State` 数量保持不变（不动架构），只换持久化层。

### 5.1 存储格式与位置

- 路径：`~/Library/Application Support/ItemManager/Drafts/`
  - `create.json`（创建模式唯一草稿，对应原 `draftKey`）
  - `edit/<clothingUUID>.json`（编辑模式，对应原 `editingDraftKeyPrefix`）
  - `_index.json`（轻索引：是否有创建草稿、编辑草稿 UUID 列表、最近修改时间）
- 写入：`Data.write(to:options:.atomic)`（保证"全部写入或回退到旧文件"）。
- 不入 iCloud Documents（对照 ImageManager 选址，避免 CloudKit 异步同步把草稿误删/误覆盖）。
- 迁移：D1 启动时一次性把现存 UserDefaults 草稿读出 → 写文件 → `userDefaults.removeObject`，记录迁移日志。

### 5.2 写入时机重构

- 引入 `DraftPersistor` actor：
  ```
  func enqueueSave(draft, reason)  // debounce 500ms 内合并多次调用
  func flushNow(reason)            // scenePhase / onDisappear / 手动取消等关键节点
  func clear(scope)                // create / edit(UUID)
  ```
- ClothingEditView 的所有 `onChange(of:)`（每个文本/数字/日期/Tag/Accessory 字段）统一调用 `enqueueSave(reason: "field-change")`。
- scenePhase / didEnterBackground / onDisappear 改调 `flushNow`，并 `await` 完成后再 dismiss（在 onDisappear 用 `Task { await ... }` + 不阻塞 UI 的策略，最多等 200ms，超时记录 signpost）。
- `enqueueSave` 内部对 draft 做 `hasUserTouchedAnyField` 判定，避免空表单也写盘。

### 5.3 字段→草稿同步的统一入口

- 把所有 `@State var name / brandName / ...` 的 `onChange` 收拢到一个 `formObservationKey: some Hashable`（已有 `draftObservationKey` 的雏形，line 701）。
- 把现在散在三处的"image / chart / 普通字段"分支合并为一处，避免遗漏。

### 5.4 草稿与图片 GC（应对 H6）

- 引入 `DraftImageRefCounter`：草稿写盘时记录所引用的 `imagePaths`、`sizeChartImagePath`、`priceChartImagePath`、accessoryList 各自的图片。
- 草稿被显式 `clear` 时：从 ref counter 释放对应图片引用，由 ImageManager 统一回收（仅当无其它 Clothing/Draft 引用）。
- D1 起 App 启动时跑一次 `DraftGC.scan()`：清理"指向不存在的草稿"的孤儿图片 + "指向不存在的图片"的破草稿（破草稿先标记 broken，弹 toast 让用户决定 retry/discard）。

### 5.5 Combine debounce 替换 Task.sleep

- D0 的临时 `Task.sleep` 替换为 `PassthroughSubject<DraftSnapshot, Never>` + `.debounce(for: .milliseconds(500), scheduler: RunLoop.main)`。

### 5.6 D1 验收门槛

- §3 矩阵 **F1–F3 全部 cell 100% 恢复**（含强杀 30 分钟、低端 iOS 26 jetsam 杀）。
- F4 × 强杀 ≥ 95% 恢复（容忍最后一次未落盘的 500ms 内编辑）。
- 写盘 IO：
  - 文本连续输入（10 chars/sec），单次写盘频率 ≤ 2 次/秒（debounce 生效）。
  - 单次写盘耗时 P95 ≤ 8ms（低端 iOS 26）。
- 启动迁移成功率 100%（无草稿丢失，原 UserDefaults key 全清空）。
- 旧 UserDefaults 路径不再被任何代码访问（grep 兜底）。

### 5.7 不允许的 D1 偷懒

- 把 debounce 改成 `Timer.scheduledTimer(every: 1)` 全局轮询。
- 把"原子写"理解为"先 delete 再 write"。
- 把 `_index.json` 跟实际文件解耦（必须每次 create.json 写完同步更新索引，原子写入）。
- `DraftPersistor` 做成 `@MainActor` —— 必须独立 actor，避免主线程被 IO 阻塞。

---

## 6. D2 阶段：状态架构升级（治本，可独立排期）

> 目标：消灭"~30 个 `@State` 散落在 View 上 → view rebuild 即清零"的根本问题；增加 NSUserActivity 跨 scene 恢复。
> **D2 必须在 D1 通过验收后才启动**，否则架构改造和持久化改造同时进行，bug 归因复杂度爆炸。

### 6.1 ClothingEditModel：`@Observable` 表单状态容器

- 新建 `ClothingEditModel`（`@Observable`，iOS 17+ macro），把 `name / brandName / ... / selectedTags / accessoryList` 等所有表单字段搬进去。
- ClothingEditView 改用 `@State private var model = ClothingEditModel(...)` 持有，view rebuild 时 SwiftUI 不会重新 init `@State` 包裹的 reference type（这点要在文档里写明：参考 WWDC23 *Discover Observation in SwiftUI*）。
- 字段改 → `model.name = x` → DraftPersistor 订阅 model 的 `_$observationRegistrar`（或显式 didSet）触发 enqueueSave。

### 6.2 NSUserActivity 跨 scene 恢复

- 定义 `NSUserActivityType = "com.itemmanager.clothing.editing"`，typed payload = `ClothingEditDraft`（用 `setTypedPayload`）。
- ClothingEditView `.userActivity(...) { activity in activity.setTypedPayload(model.makeDraft()) }`。
- App 入口 `.onContinueUserActivity(...) { activity in 路由打开 ClothingEditView 并 restoreFromDraft }`。
- iPad 多窗口、Handoff、Spotlight Resume 都自动覆盖。

### 6.3 移除 `currentDraft` 内存层（条件性）

- 当 model 是 `@Observable` 单一来源后，"内存层"实际等价于 model 实例本身。`ClothingEditDraftManager.currentDraft` 字段可移除。
- 仅保留"持久化的草稿索引 + 文件读写"职责。

### 6.4 view rebuild 自检

- 在 `ClothingEditModel.init` 加 signpost。重跑 §3 矩阵的"多 sheet 反复开关 / 横竖屏切换 / iPadOS 分屏"等场景，期望 model 实例 == 1（D2 之前可能 ≥ 2）。

### 6.5 D2 验收门槛

- §3 矩阵全部 cell 100% 恢复（含 F4 × 强杀）。
- ClothingEditView 在所有交互序列中 `model.init` 调用次数 ≤ 1（每次"打开页面"算一次）。
- iPad Stage Manager 拆出第二个窗口编辑同一草稿时，能正确处理冲突（后写覆盖 + toast 提示）—— 此项可降级为"明确禁止双窗口同时编辑"。
- 移除 ClothingEditView 中所有冗余生命周期标志位（`hasProcessedDraft` / `didPersistForLifecycle`），由 model 状态机替代。

---

## 7. 跨阶段验收 / 回归

### 7.1 自动化 UI 测试（XCUITest，新增 `DraftReliabilityUITests` target）

- 用 `XCUIApplication.terminate()` + 重启模拟"系统强杀"。
- 用 `XCUIApplication().background(for:)`（自定义 helper，调 `XCUIDevice.shared.press(.home)` + 等待）模拟切后台。
- 每个 Tier × 每种"可自动化的"中断（≈ 8 种）跑一遍，断言"重新进入后字段相等"。
- 不可自动化的（PhotosPicker、控制中心、推送）保留人工脚本，§3.2 列表标 (M) for manual。

### 7.2 性能回归

- D1 之后写盘 IO 不应让"打字延迟" P95 > 16ms（一帧 60Hz）。用 Instruments → Time Profiler + Animation Hitches 观察。
- D2 之后 ClothingEditView body 重算次数较 D1 不应增加（用 `_printChanges()` 调试构建对比）。

### 7.3 数据完整性回归

- 把 §3 的所有 Tier 草稿 → 触发恢复 → 走"保存"流程 → 数据库读出，与原始字段做 deep equal。重点字段：JPY 汇率与原价币种 round-trip、accessoryList 排序、selectedTags 顺序。

### 7.4 回滚预案

- D0 的 6 条修复每条独立可回滚（提交粒度细）。
- D1 上线前，文件存储 Helper 加 feature flag `DRAFT_USE_FILESYSTEM`（默认 OFF，灰度 → 全量），两套实现并存 1 个版本，用户可双向迁移。
- D2 必须在 D1 稳定后开启另一 feature flag `DRAFT_USE_OBSERVABLE_MODEL`，至少 1 个版本灰度。
- 任何阶段一旦线上发现"草稿丢失率"上升，立刻关 flag，落回上一版本数据格式。

---

## 8. 文档与外部参考清单（PR 描述必须引用）

- WWDC23 — *Demystify SwiftUI performance* / *Discover Observation in SwiftUI*。
- WWDC22 — *The SwiftUI cookbook for navigation* §State restoration。
- Apple Developer：[Restoring your app's state with SwiftUI](https://developer.apple.com/documentation/swiftui/restoring-your-app-s-state-with-swiftui)、[NSUserActivity](https://developer.apple.com/documentation/foundation/nsuseractivity)、[applicationWillResignActive(_:)](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationwillresignactive(_:))、[Data.write(to:options:)](https://developer.apple.com/documentation/foundation/data/write(to:options:)) 中 `.atomic` 的语义。
- Vadim Bulavin — *iOS 13/iPadOS UIScene state restoration with NSUserActivity and SwiftUI*（https://www.vadimbulavin.com/ios13-ipados-uiscene-state-restoration-with-nsuseractivity-and-swiftui/ 多 scene 恢复模板，D2 直接参考）。
- Use Your Loaf — *SceneStorage for custom types*（说明 SceneStorage 的"scene 销毁即丢"边界，D 系列不选它的依据）。
- fatbobman — *Exploring SwiftUI Property Wrappers*（@AppStorage / @SceneStorage / @State 真实差异）。
- Apple HIG — Modality / Sheets（用户期望"中断后回来内容还在"的官方表述）。
- 本仓库已有的 `docs/iOS26_WARDROBE_MENU_PERFORMANCE_EXEC_PLAN.md` 和 `docs/WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md` 的 harness 章节排版（保持视觉一致，方便交叉评审）。

---

## 9. 出口准则

- D0 出口：§3.4 矩阵填满、§4.3 六条修复合入并跑过 §4.4 验收。
- D1 出口：UserDefaults 草稿路径全部退役、§5.6 验收全部达标、灰度 1 个版本。
- D2 出口：所有 form `@State` 收拢进 `ClothingEditModel`、NSUserActivity 落地、§6.5 验收全部达标、灰度 1 个版本。
- 每个阶段出口必须**有真机日志证据 + 录像**留档到 `temp/_drafts/release-<阶段>/`，不得用 simulator 数据交差（jetsam / 系统 kill 行为模拟器与真机不同）。
