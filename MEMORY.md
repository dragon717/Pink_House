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

## 二、仓库 source of truth（本机已确认）

- 本机 Swift/Xcode 开发目录：`/Users/sangyu/develop/Pink_House`，由用户明确确认。
- muniao 的 iCloud 路径属于另一台机器，在本机不读写，不重复询问。
- 2026-10-11 核验：`/Applications/Xcode.app` 为 Xcode 27 正式版；构建显式设置 `DEVELOPER_DIR`，不改全局 xcode-select。

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

## 八、操作反馈与鱼币（2026-10-11）

- 已统一普通提示、复制与奖励队列；时光馆单件/批量/心愿确认入橱保存成功后显示一次成功及实际到账鱼币。
- 根因：时光馆部分成功入口没有反馈；旧奖励发布计划金额，额度不足也显示全额；手动新建在保存前发奖；页面订阅在导航切换时可能丢奖励。
- 现在使用持久化业务 ID 防重，余额/日计数/领取标识同钱包快照保存；每日上限 10000，新增记录既有奖励 50，尾款付清 200；这些是鱼币，不是充值喵币。
- 新操作如何选弹窗、哪些系统联动，先读 [使用指南](docs/OPERATION_FEEDBACK_AND_FISH_COIN_GUIDE.md)；验证见 [执行计划](docs/OPERATION_FEEDBACK_AND_FISH_COIN_EXEC_PLAN.md)。不要再写本地 Toast 或按弹窗自动加币。

## 时光馆入橱与运营默认值（2026-10-11）

入橱默认主衣物，小物由用户主动勾选；重复出现不得重置用户取消结果。运营新草稿/新价格录入默认人民币（CNY），保留明确币种与历史来源。正式规则与验证见 `docs/SHOP_CATALOG_ENTRY_DEFAULTS_2026-10-11.md`。

2026-10-11 用户截图确认：入橱方式只保留确认页内单选，点击确认直接按已选方式保存，删除右侧重复选择弹窗及其状态/分支；取代 2026-09-27 二次弹窗旧要求。成功后仍统一提示与发放实际到账鱼币。

2026-10-11 用户明确确认：运营已上传商品的未明确币种全部补为人民币，不能仅修改新录入默认值。Development 存量已修复发布 seq 21：26 件商品、38 条销售记录及 3 份价格修正；明确币种与金额保持原值。正式规则与证据：`docs/SHOP_CATALOG_OPERATOR_CURRENCY_REPAIR_2026-10-11.md`。
