# MEMORY — 少女心愿（Pink House）长期记忆索引

> 长期事实写这里；每日工作流水写 `.workbuddy/memory/YYYY-MM-DD.md`。
> 与 `Agent.md` 的分工：`Agent.md` 是**规范**（该怎么做），本文件是**记忆**（已经发生过什么、踩过什么坑）。

---

## 一、项目身份（长期不变）

| 项 | 值 |
| :-- | :-- |
| 产品 | 少女心愿 —— Lolita / JK / 汉服「三坑」衣橱管理 + 轻养成 App |
| 主工程 | `ItemManager/`（iOS，SwiftUI，iOS 17.4+，Bundle ID `bugod2.ItemManager`） |
| 主分支 / 远端 | `main` / `git@github.com:dragon717/Pink_House.git` |
| 数据 | SwiftData 为主；CloudKit 做公告与图片同步；`BackupService` 做本地归档 |
| AI | DeepSeek / LLM + Apple Vision，衣橱上下文注入 |
| 其他端 | `android/`（Kotlin+Compose 骨架）、`harmony_next/`（ArkTS MVP）、`godot_project/`（实验，已非主线） |

---

## 二、仓库 source of truth（⚠️ 待确认，动工前必问）

- `AGENTS.md` 声明 Swift/Xcode 源仓库在 iCloud：`/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House`
- 本工作区实际路径：`/Users/sangyu/develop/Pink_House`
- **两者谁是本次开发目标仓库尚未确认**，已在 `Agent.md` 顶部标为"动工前必须先问用户"。确认后请把结论写回这里并删掉本条告警。

---

## 三、踩过的坑（按主题）

### 3.1 子代理 / Agent

- 完整上下文 fork 会**继承父 agent 类型**，不能再指定 `explorer`；需要 explorer 就不要 fork，改为显式传路径 + 任务边界。
- 子代理看不到当前对话，prompt 必须自包含（仓库路径、做了什么、需求原文、要它做什么、输出格式）。

### 3.2 Xcode / 构建

- 本机 `xcode-select -p` 指向 CommandLineTools；用 Xcode beta 时显式 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`。
- 历史口径冲突：`.trae/rules/my.md` 说"不用命令行编译"，`AGENTS.md` 说可以跑 `xcodebuild`。**现行口径**：人工开发在 Xcode 里编译；Agent 自证编译或做模拟器验收时才用命令行（见 README 第三节）。
- 模拟器验收必须先编译 → 安装 → **重启新进程**，再读画面，否则读到旧进程。
- iCloud 同步锁文件：`find "$PROJ" -name "*.icloud"` 或 `brctl download "$PROJ"`。
- 模拟器键盘不响应：用 `xcrun simctl io booted setText`。

### 3.3 主题皮肤 ThemeSkin

- imageset 加了 Xcode 找不到 → 检查 target membership + namespace 文件夹 `provides-namespace: false`。
- PSD 图层导出全空 → `psd-tools` 默认只导可见层，先 `layer.visible = True`。
- 素材入库走正式入口 `tools/theme_skin/materialize_manual_image2_assets.rb`（读 `tools/theme_skin/theme_manifest.yaml`）。

### 3.4 数据与同步

- `CloudSyncManager` 与 `iCloudSyncManager` **两套并存**，改动前先确认该模块用的是哪个，不要两边都写。
- 改 `@Model` 字段必须写迁移并过 `SwiftDataMigrationManager`。

---

## 四、约定与偏好（用户级）

- **交流语言**：中文。
- **提交信息**：中文，言简意赅，一句话说清楚（`.trae/rules/git-commit-message.md` 同口径）。
- **注释**：中文，写「为什么」。
- **文件长度**：≤ 500 行，超限拆分。
- **静态参数**：策划会调整的数值一律提取为具名常量，保持全局一致。
- **不确定就联网搜索**，不允许凭记忆编造 API（`Agent.md` H1）。

---

## 五、技术债台账

| 债 | 现状（2026-09-13 统计） | 原则 |
| :-- | :-- | :-- |
| 超大文件 | 39 个 Swift 文件 > 1000 行，66 个 500~1000 行 | 新增不加剧，改动时顺手拆 |
| 最大文件 | `NewbieGuideManager.swift` 4162 行 | 拆 |
| 根目录散落模型 | `Item/Clothing/Tag/Brand.swift` 在 `ItemManager/` 根 | 新模型进 `Models/`，旧的不批量迁移 |
| 新旧并存 | `PetChatView` / `PetChatViewLegacy` | 新功能只改新版 |
| 双同步实现 | 见 3.4 | 确认后再动 |
| 历史文档过期 | Godot / CoreData 描述已失效 | 代码第一事实 |
| 已跟踪的调试残留 | `ItemManager/Views/ClothingEditView.swift.backup` 在版本库里 | 清理前先确认无人引用 |

---

## 六、调研索引

- [主题皮肤详情页预览与组件开关 UX 调研](project_theme_detail_preview_research.md)
- [Xcode 27 beta、iOS 27 规范与 Apple agent skills 调研](xcode27_ios27_agent_skills_research.md)

---

## 七、待裁决

- （空）审查中出现争议且用户未裁决时，在这里登记一行，格式：`YYYY-MM-DD | 议题 | 选项A / 选项B`。
