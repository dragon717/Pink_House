# 少女心愿 · Pink House

一款面向 Lolita / JK / 汉服「三坑」用户的**衣橱管理 + 轻养成** App。
主线是「把裙子记下来、把钱算清楚、把穿搭玩出花」，并配一只会点评、会打工、会聊天的电子宠物作为情感载体。

| 项 | 值 |
| :-- | :-- |
| 主工程 | `ItemManager/`（iOS，SwiftUI） |
| Bundle ID | `bugod2.ItemManager` |
| 最低系统 | iOS 17.4 |
| Xcode Scheme | `ItemManager` |
| 主分支 | `main` |
| 远端 | `git@github.com:dragon717/Pink_House.git` |
| iOS 源码规模 | 约 450 个 `.swift` 文件（含扩展 Target），主 Target `ItemManager/` 下约 400 个 |

---

## 一、技术栈

| 层 | 技术 | 说明 |
| :-- | :-- | :-- |
| UI | SwiftUI + UIKit 互操作 | 主容器 `MainTabView`，底部为自绘异形 TabBar |
| 数据 | SwiftData（`@Model` + `@Query`） | 主模型 `Clothing` / `Item` / `Tag` / `Brand` / `Model3D` / `Notice` / `SceneObjectData`；迁移走 `SwiftDataMigrationManager` |
| 云同步 | CloudKit（Public DB + 私有库） | 公告 CMS、时光馆上传、图片同步；`iCloudSyncManager` / `NoticeCloudKitService` |
| 备份 | 本地归档 + iCloud | `BackupService`（导出/导入 zip 归档） |
| AI | Vision + DeepSeek / LLM | `Services/AI/`；衣橱上下文注入、穿搭建议、宠物人格对话 |
| 支付 | StoreKit 2 | `Services/IAP/`，喵币 + VIP 订阅 |
| 3D / 空间 | RealityKit / Metal / Gaussian Splatting | `Views/ThreeD`、`Views/SpatialCanvas`、`Services/GaussianSplatting` |
| 动效资源 | 视频 + 序列帧 | `asserts/`（不入库的体积资源已在 `.gitignore` 屏蔽） |
| 多语言 | 9 个 `.lproj` + `LanguageManager` | 中简 / 中繁 / 英 / 日 / 韩 / 德 / 法 / 西 / 葡(巴西) |
| 其他端 | Android（Kotlin + Compose）、HarmonyOS Next（ArkTS）、Godot(C#) 实验 | 详见 [目录结构说明](docs/目录结构说明.md) |

---

## 二、业务模块地图

App 底部 Tab 采用「单一容器 + 动态目标」设计：`MainTabView` 承载五个固定入口，House 页签的内容由 `SmallWorldDestination` 动态切换。

| 入口 | 目录 | 一句话职责 |
| :-- | :-- | :-- |
| 衣橱 | `Views/Wardrobe`、`Views/ClothingEditView` 等 | 录入/筛选/统计裙子与小物 |
| OOTD 穿搭手帐 | `Views/OOTD/`（36 文件） | 手帐式排版、抠图贴纸、空间书 |
| House | `Views/SmallWorldView` + 动态目标 | 日历 / 来财 / 萌宠 / 手帐 / 心愿尾款 / 回收站 |
| 萌宠对话 | `Views/PetChat/`（22 文件） | 与奶茶/毛毛聊天、穿搭点评、打工 |
| 我的 | `Views/MeView`、`Views/Settings/`（34 文件） | 设置、数据管理、VIP、主题商店 |

支撑体系：主题皮肤 `ThemeSkin/`（18 slot）、新手引导 `NewbieGuide/`、公告 CMS `Notice/`、`Wealth/`（财富与多币种）、`TimeHall/`（品牌图鉴）、`VIP/`、`IAP/`。

---

## 三、快速上手

### 3.1 打开工程

```bash
open ItemManager.xcodeproj
# 选 ItemManager scheme → iPhone 16 Pro 模拟器 → ⌘R
```

### 3.2 命令行构建（CI / Agent 验收）

```bash
xcodebuild -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -quiet build
```

使用 Xcode beta 时显式指定：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet build
```

### 3.3 跑测试

```bash
xcodebuild -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

单测位于 `ItemManagerTests/`（16 个文件），覆盖备份还原、汇率、宠物状态、公告逻辑、时光馆目录校验等。

### 3.4 模拟器视觉验收

先编译 → 安装 → 冷启动新进程，再读画面（详见 `docs/XCODE_SIMULATOR_COMPUTER_USE_ACCEPTANCE.md`）：

```bash
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
xcrun simctl install booted "$PWD/build/Debug-iphonesimulator/ItemManager.app"
xcrun simctl launch booted bugod2.ItemManager
```

> 注：`.trae/rules/my.md` 里有一条「不使用命令行编译 Xcode，让用户自行编译」的历史约定。
> **现行口径**：人工开发时由你在 Xcode 里编译；Agent 需要自证编译通过或做模拟器验收时，才用上面的命令行方式。两者以本 README 为准。

---

## 四、文档地图

| 文档 | 用途 |
| :-- | :-- |
| **[Agent.md](Agent.md)** | **Agent / 开发者总规范：架构分层、业务开发规范、硬性约束、阶段审查与提交流程** |
| **[MEMORY.md](MEMORY.md)** | 项目长期记忆与踩坑索引 |
| **[docs/目录结构说明.md](docs/目录结构说明.md)** | 每个目录放什么、不能放什么 |
| **[docs/业务拆解方法.md](docs/业务拆解方法.md)** | 面向初级 PM / 需求同学的需求拆解方法论 |
| **[docs/阶段审查清单.md](docs/阶段审查清单.md)** | 每阶段结束派子代理审查的 Checklist |
| `docs/PROJECT_CONCEPTS.md` | 业务概念与黑话词典（JSK/OP/定金/尾款/掉落…） |
| `docs/BUSINESS_PROCESS.md` | 现有业务流程（录入、定金尾款、状态流转） |
| `docs/DATA_ARCHITECTURE.md` | Swift ↔ Godot(C#) 数据交互（历史方案，Godot 已非主线） |
| `docs/少女衣橱主题皮肤重构方案.md` | ThemeSkin 架构 |
| `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md` | 主题复刻最佳实践 |
| `docs/TEMP_GOVERNANCE_AND_KNOWLEDGE_MIGRATION.md` | `temp/` 治理与知识迁移 |

> ⚠️ `docs/` 下 120+ 篇历史文档中，部分（如 Godot 引擎方案、早期 CoreData 描述）已被现网代码取代。
> **以代码为第一事实来源**，文档与代码冲突时先信代码，并顺手修订文档。

---

## 五、开发约定速查

- **写代码前**先读 [Agent.md](Agent.md)。
- **不懂就联网搜索**，不允许凭记忆猜 API / 框架行为（Agent.md 硬约束第 0 条）。
- **单文件 ≤ 500 行**，超了就拆（当前有 105 个文件超限，见 Agent.md 技术债清单）。
- **注释写中文，讲「为什么」**，不是复述代码。
- **提交信息用中文，一句话说清楚**，例如：`feat: 心愿尾款新增按月汇总视图`。
- **禁止** `git push --force`、**禁止** `--no-verify` 跳 hook。

---

## 六、当前技术债（一图看懂）

| 债 | 现状 | 处置原则 |
| :-- | :-- | :-- |
| 超大文件 | 39 个 > 1000 行，66 个 500~1000 行；最大 `NewbieGuideManager.swift` 4162 行 | 新增代码不得加剧；改动该文件时顺手拆出一块 |
| 根目录散落模型 | `Item.swift` / `Clothing.swift` / `Tag.swift` / `Brand.swift` 在 `ItemManager/` 根 | 新模型一律进 `Models/`，旧文件不批量迁移 |
| 新旧并存 | `PetChatView.swift` 与 `PetChatViewLegacy.swift` | 新功能只改新版，Legacy 仅修 bug |
| 多套同步 | `CloudSyncManager` 与 `iCloudSyncManager` 并存 | 改动前先确认用哪个，别两个都写 |
| 历史文档过期 | Godot/CoreData 相关描述已失效 | 见第四节告警 |
