# Pink_House Android 持续复刻 Harness

> 本文是 SwiftUI → Jetpack Compose 复刻工作的 **harness 工程规范**。任何 session（人或 AI）在动 `android/app/src/main/java/com/pinkhouse/android/feature/**` 之前必须先读完它。配套：
> - 复刻经验：`docs/ANDROID_COMPOSE_PORTING_NOTES.md`
> - 跨端 PRD：`docs/migration/android/PRD.md`
> - 进度看板：`android/docs/PORT_BACKLOG.md`
> - 全局技能：`~/.claude/skills/android-compose-port/SKILL.md`

---

## 一、六条不可越过的红线

| # | 红线 | 落地约束 | 检查点 |
|---|---|---|---|
| R1 | **每批 ≤ 2 业务文件** | PR 标题写出文件清单；超出必须拆 | code review 时 grep 文件数 |
| R2 | **`build.gradle.kts` / `libs.versions.toml` / `AndroidManifest.xml` 单独成批** | 与业务 diff 不共 PR | git diff 头判断 |
| R3 | **每批必过两道闸** | `./gradlew :app:assembleDebug` + 装机截图 | 失败即 `git revert` |
| R4 | **token 单一真源** | 新增 Composable 内 grep `0xFF[0-9A-F]{6}` / `\d+\.sp` 必须 = 0 | 提交前自动检查 |
| R5 | **不接 GMS / 不开 dynamicColor / API 31+ 必须降级** | grep `Firebase` / `dynamicColor` = 0；`Modifier.blur` 必须有 `Build.VERSION.SDK_INT >= 31` 包裹 | 同上 |
| R6 | **用户可见文案 = 产品文案，无开发侧泄漏** | 新增 .kt / strings.xml 内 grep `BATCH-` / `阶段 [A-Z]` / `复刻` / `占位` / `待接入` / `下一批` / `后续` / `未完成` / `F-\d+` / `W-\d+` 必须 = 0；硬编码 sample 列表条目不得在生产路径 | 提交前 grep + 装机截图人工对照 iOS 文案 |

> R6 的代价记录：[BATCH-UX-COPY-01A](PORT_BACKLOG.md) 因通知中心样例公告 + House 菜单 "复刻 / 已接入 / 下一批 / 后续" 等内部进度术语进了用户 UI，被迫单独拉一批清理。要在写第一行 Composable 之前就封掉。

---

## 二、Task Card 模版（每批一张）

每个批次开工前先写一张 Task Card；写不全说明范围没收敛，**不要**直接动手。

```
ID:        BATCH-{阶段}-{序号}    例：BATCH-M3-02
PR_NAME:   feat(petchat): 复刻萌宠对话首屏与意图按钮
SCOPE:     2 文件
  - android/app/src/main/java/com/pinkhouse/android/feature/petchat/PetChatRoute.kt (新建)
  - android/app/src/main/java/com/pinkhouse/android/core/navigation/AppDestination.kt (改 1 处)

UPSTREAM_iOS:
  - ItemManager/Views/PetChat/PetChatView.swift:1-300        (首屏 body)
  - ItemManager/Views/PetChat/PetChatBubbleView.swift:1-180  (气泡组件)
  - 完整 3022 行；本批仅取首屏 + 3 个意图按钮 + 兜底文案池

PRD_REFS:  F-19, F-20, W-03, W-04, W-05
DEGRADE:   无 LLM / 无 TTS；输入 → 立即随机抽兜底文案池

DEPENDENCIES:
  - 已有: PinkHouseDesignTokens, PinkSurfaceScaffold, PinkSegmentedTabs
  - 缺资源: 橘猫对话姿态 webp（本批用粉色圆形占位 + "缺素材" 标签）

SUCCESS_GATES:
  G1 ./gradlew :app:assembleDebug 通过
  G2 装机截图: 进入 💬 Tab 看到欢迎气泡 + 3 个意图按钮 + 底部输入；逐区对照 iOS 文案
  G3 grep "0xFF[0-9A-F]\{6\}" 在新增文件 = 0
  G4 grep "Modifier.blur\|Firebase\|dynamicColor" 在新增文件 = 0
  G5 @Preview 渲染通过
  G6 grep "BATCH-\|阶段 [A-Z]\|复刻\|占位\|待接入\|下一批\|后续\|未完成\|F-[0-9]\+\|W-[0-9]\+" 在新增 .kt / strings.xml = 0；UI 字面量已对照 iOS

ROLLBACK: git revert HEAD
```

---

## 三、Subagent 分工合约

**主线程 = 建筑师 + 写代码者；subagent 只做"重读、轻摘要"。**
不让 subagent 写业务代码——避免上下文断裂导致 token 漂移、modifier 顺序错位。

### 角色 1 · `Explore-iOS-Digest`（subagent_type: Explore）

**职责**：读 1 个 SwiftUI 源文件，输出结构化摘要。

**冷启动 Prompt 模板**：

```
任务: 给 Compose 工程师做 SwiftUI 源页面摘要，他要把它复刻到 Android。
输入文件: ItemManager/Views/<PATH>.swift（仅这一个，不要追到子组件）
读取范围: 全文（行 1 - 文件末）

输出格式（必须严格按此结构，否则报告作废）:
1. **顶级容器**（NavigationStack / ScrollView / ZStack ...）
2. **分区列表**：依 body 自上而下，每节给 [标题/布局类型/列数/子项数/iOS文件:行号]
3. **颜色与渐变**：每个 Color(...) / LinearGradient 的色值 + 用途
4. **字号/圆角/阴影**：所有 .font / .cornerRadius / .shadow 数值
5. **状态变量**：所有 @State / @Binding / @ObservedObject / @Environment
6. **异步与副作用**：所有 .task / .onAppear / .onChange / NotificationCenter
7. **iOS 平台依赖**：UIKit / SF Symbols / Haptics / SwiftData / CloudKit
8. **PRD 降级标注**：根据 docs/migration/android/PRD.md W-XX 标出本页该砍的功能

约束:
- 不要给 Compose 代码建议
- 不要读其他文件
- 全文 ≤ 1000 字
- 找不到的字段写 "不存在"，不要瞎编
```

### 角色 2 · `Plan-Compose-Tree`（subagent_type: Plan）

**职责**：拿 Explore 摘要 + 项目 token 文档，输出 Compose 组件树骨架。

**冷启动 Prompt 模板**：

```
任务: 设计一个 Composable 的树结构 + Modifier 链方案。不要写实现，只给骨架。
输入:
  - SwiftUI 摘要 (粘下面)
  - Token 列表 (粘下面，来自 PinkHouseDesignTokens.kt)
  - 复刻硬规则 (粘下面，来自 docs/ANDROID_COMPOSE_PORTING_NOTES.md §二、§三)

输出:
  1. 顶级 Composable 签名: fun XxxRoute(modifier: Modifier = Modifier, ...)
  2. 组件树（markdown 缩进），每节标 token 引用
  3. Modifier 链: 严格按 size→background→border→padding→clickable 顺序
  4. State hoisting 方案: ViewModel 用 StateFlow 还是 Composable 用 remember
  5. 已知陷阱清单（照 §四响应式、§五组件级）
  6. @Preview 用 PreviewParameter 还是固定数据

约束:
- 不写函数体
- 不引第三方依赖（除非已在 libs.versions.toml）
- 报告 ≤ 600 字
```

### 角色 3 · 主线程 — 写代码 + 验证

根据 Explore 摘要 + Plan 骨架，调 `Edit/Write` 落地；调 `Bash` 跑闸；调 `computer-use` 截图。**不能委托**——理解必须留在主线程。

### 角色 4（可选）· `Code-Reviewer`

仅在改 **主题 token / Room schema / Manifest** 这类高 blast-radius 文件时启用。Prompt 强调：与 PRD 红线一致、与鸿蒙侧 schema 是否同构。

---

## 四、跑批回合（每批一个回合）

```
回合开始
├─ ① 主线程: 写出 Task Card → 用户 confirm
├─ ② 主线程: 调 Agent(Explore-iOS-Digest)            ← SwiftUI 源 > 500 LOC 才需要
│      ↓ 拿回 ≤ 1000 字摘要
├─ ③ 主线程: 调 Agent(Plan-Compose-Tree)             ← 骨架 ≥ 5 组件才需要
│      ↓ 拿回 ≤ 600 字骨架
├─ ④ 主线程: Edit/Write 业务文件 (≤ 2 个)
├─ ⑤ Bash: ./gradlew :app:assembleDebug
│      ↓ 失败 → 修同回合 / 还失败 → revert → 报告
├─ ⑥ Bash: grep 红线 (0xFF / Firebase / blur 无降级 / R6 文案泄漏)
│      ↓ 命中 → 修同回合
├─ ⑦ computer-use: 装机截图 → 双端对照（视觉 + UI 文案逐区对照 iOS）
│      ↓ 不一致 → 报告差异，等用户裁定
├─ ⑧ Edit: 追加一段到 android/docs/android_migration_<page>.md
│      "本批改了什么 / 验证结果 / 待办"
├─ ⑨ Edit: 更新 android/docs/PORT_BACKLOG.md，把当前批移到 ## Done
├─ ⑩ git commit — 主线程在所有闸全过后**自行 commit**（用户已对小阶段 commit 永久授权），一批一 commit，message 带 BATCH-ID + Co-Authored-By
└─ 回合结束 → Task Card 状态置 ✅，进入下一批
```

**关键点**：
- 步骤 ① 之前**必须**有用户 confirm 当批 Task Card（除非 Task Card 已在 PORT_BACKLOG.md `Ready` 段且无歧义）。
- 步骤 ⑩ 小阶段 commit 已永久授权——**单批所有闸（G1~G5）全过**才允许 commit；任意一闸失败 → 不 commit，修同回合或 revert 后报告。
- 跨阶段（ARCH→M3 / M3→M4）切换或动到高 blast-radius 文件（gradle / Manifest / Room schema）时仍需要用户 confirm。

---

## 五、上下文卫生

| 数据 | 留主线程 | 委托 subagent | 写盘 |
|---|---|---|---|
| 当前批 Task Card | ✅ | — | — |
| SwiftUI 源 (>500 LOC) | ❌ | ✅ Explore | — |
| 摘要（≤1000 字） | ✅ | — | — |
| Compose 骨架（≤600 字） | ✅ | — | — |
| 完整 PRD（1000+ 行） | ❌ 只引相关 F-XX | — | 已在 git |
| 已完成批次记录 | ❌ | — | ✅ `android/docs/android_migration_*.md` |
| 跨 session 进度看板 | ❌ | — | ✅ `android/docs/PORT_BACKLOG.md` |

**回收节奏**：每完成 3 批主动检查上下文占用；逼近 100k token 时把"已完成批次记录"全部下沉到磁盘，主线程只留 backlog 表。

---

## 六、失败恢复矩阵

| ID | 触发条件 | 动作 |
|---|---|---|
| F1 | `assembleDebug` 非 0 | 同回合修；修不掉 → `git reset --hard HEAD~1` 后报告 |
| F2 | 装机截图 vs iOS 偏差 > 30% | **不要猜**，报告差异，等用户裁定 |
| F3 | 红线 grep 命中（含 R6 文案泄漏） | 同回合修，不允许下批继续 |
| F4 | 单批文件超 2 | 拆成两张卡，第二张进 backlog |
| F5 | SwiftUI 源 > 1500 LOC | 让 Explore **只读首屏 + 用户指定的子区**，多张卡分次摘 |
| F6 | 资源缺失 | **不找替代**，用粉色渐变占位 + `// TODO(asset): xxx`，向用户报清单 |
| F7 | 跨 session 失忆 | 新 session 先读 `PORT_BACKLOG.md` + 最近 2 个 commit |

---

## 七、跨 session 协议

**新 session 接手时必读三件**：
1. `android/docs/PORT_HARNESS.md`（本文）
2. `android/docs/PORT_BACKLOG.md`（看板）
3. `git log --oneline -5`（最近 5 个 commit）

**绝不**：
- 跨 batch 改文件（一个批的 diff 必须自洽）
- 跳过装机验证（@Preview 一定会骗人）
- 用 destructive commands（`git reset --hard` / `--no-verify`）

---

## 八、Backlog 看板规范

`android/docs/PORT_BACKLOG.md` 用四段：

```
## In Progress     最多 1 项，谁在做就标在后面
## Ready           按优先级倒序，下个回合从顶端取
## Blocked         注明 blocker
## Done            commit 后追加，最近的在顶
```

每完成一批，主线程在同一回合内把它从 In Progress 移到 Done。

---

**End of harness**.
