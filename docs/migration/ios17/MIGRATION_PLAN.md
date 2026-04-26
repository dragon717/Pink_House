# 少女心愿 · iOS 17 兼容版迁移计划

> 文档版本：v1.0 · 最后更新：2026-04-20
> 上游：`docs/migration/ios17/TECH_DESIGN.md`

---

## 1. 里程碑总览

| 里程碑 | 周数 | 产出 | 关键指标 |
|---|---|---|---|
| **M1 可用性审计** | 第 1 周上半 | 审计报告 + 待修复清单 | 100% `#available` 分支覆盖 |
| **M2 Target 下调** | 第 1 周下半 | 项目编译通过 | iOS 17.4 Simulator 冷启动 OK |
| **M3 视觉 fallback** | 第 2-3 周 | Liquid Glass / Mica / TabBar iOS 17 路径 | 设计 review 通过 |
| **M4 SwiftPM + Extension** | 第 3 周下半 | 所有 target 编译通过 | Extension 真机启动 OK |
| **M5 真机回归** | 第 4 周 | 全量验收测试报告 | ACCEPTANCE_TESTS 通过率 ≥ 95% |
| **M6 提审 + 灰度** | 第 5 周 | App Store 新版本上线 | iOS 17 用户崩溃率 < 0.3% |

**总周期**：5 周，1 名 iOS 工程师全职。

---

## 2. M1 可用性审计（T+0 ~ T+3 天）

### 2.1 步骤 1：自动扫描

**命令**：
```bash
cd ItemManager
grep -rn "if #available(iOS" . --include="*.swift" > /tmp/availability_sites.txt
grep -rn "@available(iOS" . --include="*.swift" >> /tmp/availability_sites.txt
wc -l /tmp/availability_sites.txt
```

**产出**：`availability_sites.txt`，记录所有 `#available` / `@available` 位置。当前预估 30+ 条。

### 2.2 步骤 2：逐个走查

对每个位置验证以下 checklist：

- [ ] `if` 分支用的 API 是否真的仅 iOS 18/26 可用？（可能有误加的）
- [ ] `else` 分支是否有对应实现？不能只写 `EmptyView()` 或注释 TODO
- [ ] `else` 分支是否又隐式调用了 iOS 18/26 API？（嵌套调用）
- [ ] 视觉差距是否 < 设计容忍度？
- [ ] 是否会编译警告？

**产出**：Excel 表格 `ios17_availability_audit.xlsx`，字段：文件、行号、API、当前 else、状态、修复建议。

### 2.3 步骤 3：已知位置清单

按 `TECH_DESIGN.md` 表 2.2 定位的 15 个文件逐一走查：

| # | 文件 | 行号（大致） | 预期工作 |
|---|---|---|---|
| 1 | `ItemManagerApp.swift` | 23, 350 | 验证 else 分支（App 入口、可能是窗口样式） |
| 2 | `Views/HomeView.swift` | 50, 362, 508 | 验证 3 处分支 |
| 3 | `Views/MainTabView.swift` | 30, 39, 150, 217, 1467 | 验证 5 处，重点是浮动 TabBar fallback |
| 4 | `Views/FrenchRetroSmallWorldView.swift` | 53, 72, 94, 133, 143 | 5 处 spatial scene 判断，iOS 17 一律 false |
| 5 | `Views/RococoSmallWorldView.swift` | 284, 411 | 2 处 spatial scene 判断，同上 |
| 6 | `Views/Wealth/WealthView.swift` | 370 | 1 处，可能是 MeshGradient 或 glassEffect |
| 7 | `Views/GlobalSearchView.swift` | 413 | 1 处 iOS 18 API |
| 8 | `Views/Calendar/DreamDressCalendarView.swift` | 173 | 1 处 |
| 9 | `Views/Settings/GeneralSettingsView.swift` | 476 | 1 处 |
| 10 | `Views/Settings/Components/AdaptiveSettingsComponents.swift` | 38 | 1 处，适配组件 |
| 11 | `Views/Settings/Refactored/SmallWorldSettingsView.swift` | 86, 147 | 2 处 |
| 12 | `Views/Settings/DataManagementView.swift` | 123 | 1 处 |
| 13 | `Views/SmallWorldMenuOverlay.swift` | 102 | 1 处 |
| 14 | `Views/PetChat/PetChatViewPreview.swift` | 5 | Preview 只读，跳过 |
| 15 | `Services/NewbieGuide/NewbieGuideAIAndWealth.swift` | 381 | 1 处 |

### 2.4 产出
- 审计报告（Excel + Markdown 摘要）
- 被发现有问题的条目进入 M3 修复队列

---

## 3. M2 Target 下调（T+3 ~ T+5 天）

### 3.1 步骤

**Step 1**：备份当前 `project.pbxproj`（git 已有版本控制，这里不需额外备份）。

**Step 2**：替换 deployment target。

打开 `ItemManager.xcodeproj/project.pbxproj`，搜索 `IPHONEOS_DEPLOYMENT_TARGET`，全部改为 `17.4`：

```diff
# 主 App target（Debug + Release）
- IPHONEOS_DEPLOYMENT_TARGET = 18;
+ IPHONEOS_DEPLOYMENT_TARGET = 17.4;

# Extension targets（4 个 × 2 = 8 处）
- IPHONEOS_DEPLOYMENT_TARGET = 26.2;
+ IPHONEOS_DEPLOYMENT_TARGET = 17.4;
```

或命令行（需在 Xcode 关闭状态下执行）：

```bash
cd "/path/to/project"
sed -i '' 's|IPHONEOS_DEPLOYMENT_TARGET = 18;|IPHONEOS_DEPLOYMENT_TARGET = 17.4;|g' \
  ItemManager.xcodeproj/project.pbxproj
sed -i '' 's|IPHONEOS_DEPLOYMENT_TARGET = 26.2;|IPHONEOS_DEPLOYMENT_TARGET = 17.4;|g' \
  ItemManager.xcodeproj/project.pbxproj
```

**Step 3**：打开 Xcode，Clean Build Folder（`Cmd+Shift+K`）。

**Step 4**：选择 iOS 17.4 Simulator，编译。

**Step 5**：**处理所有编译错误/警告**。典型错误类型：
- `'glassEffect' is only available in iOS 26.0 or newer` → 用 `if #available(iOS 26.0, *)` 包裹
- `'MeshGradient' is only available in iOS 18.0 or newer` → 同上
- `'ObjectCapture...' is only available in iOS 17.0 or newer` → 已满足，无需改

**Step 6**：SwiftPM 依赖检查。
- Xcode → File → Packages → Update to Latest Package Versions
- 检查 Package 的 Tools Version / minimum iOS
- 若某依赖要求 iOS 18+：
  - 选项 A：降级该依赖到支持 iOS 17 的旧版本
  - 选项 B：换等价依赖
  - 选项 C：若该依赖可选，用 `#if canImport(...)` 条件导入

**Step 7**：`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` 开启审计模式，重新编译确保无任何警告。

### 3.2 验收
- Xcode 无红（编译通过）
- iOS 17.4 Simulator 启动到首页不崩
- iOS 26 真机仍可编译运行

---

## 4. M3 视觉 Fallback 实装（T+6 ~ T+17 天）

### 4.1 任务 3.1：LiquidGlassComponents 补全

**文件**：`ItemManager/Components/LiquidGlassComponents.swift`

**改动**：
- 为每个 Liquid Glass 组件添加 iOS 17.4 分支
- 使用 `.ultraThinMaterial` + 自定义渐变 overlay 模拟玻璃感

**验收**：
- 在 iOS 17.4 Simulator 查看 Wealth 页、VIP 卡片、Settings 卡片
- 有"玻璃感"视觉存在（非纯色卡片）

### 4.2 任务 3.2：MainTabView 浮动 TabBar

**文件**：`ItemManager/Views/MainTabView.swift`

**现状**：已有 5 处 `if #available(iOS 26.0)` 分支，else 已有自定义浮动实现。

**改动**：
- 走查 else 分支代码，确保：
  - 布局在 iPhone XS / 11 / 13 上正确（浮动位置、圆角、阴影）
  - 横屏切换正常
  - iPad 布局不破坏

**验收**：
- 5 个 tab 项正常切换
- 浮动 Bar 位置居中、圆角饱满
- iOS 17.4 视觉接近 iOS 18 的 fallback 分支

### 4.3 任务 3.3：小世界 Spatial Scene 降级

**文件**：
- `ItemManager/Views/FrenchRetroSmallWorldView.swift`
- `ItemManager/Views/RococoSmallWorldView.swift`
- `ItemManager/Views/Settings/Refactored/SmallWorldSettingsView.swift`
- `ItemManager/Views/SmallWorldMenuOverlay.swift`

**逻辑**：
- iOS 17.4 上 `isSpatialSceneEnabled == false`，不显示空间场景切换入口
- 设置页中对应开关隐藏（不是置灰）

**验收**：
- iOS 17.4 小世界正常 2D 显示
- 找不到空间场景入口（避免用户困惑）

### 4.4 任务 3.4：Calendar / Settings / NewbieGuide 等细节点

每个文件单独开一个 commit，保证可追溯：
- `DreamDressCalendarView.swift` 的 iOS 26 分支 → 走 else 视觉（已有实现时验证，无时补）
- `GeneralSettingsView.swift` 的 iOS 26 分支 → 同上
- `DataManagementView.swift` 的 iOS 26 分支 → 同上
- `NewbieGuideAIAndWealth.swift` 的 iOS 26 分支 → 同上

### 4.5 任务 3.5：MeshGradient fallback（HomeView）

**文件**：`ItemManager/Views/HomeView.swift` 第 362 行

**改动**：
```swift
if #available(iOS 18.0, *) {
    MeshGradient(...)
} else {
    LinearGradient(colors: [...], startPoint: .topLeading, endPoint: .bottomTrailing)
}
```

**验收**：iOS 17.4 首页背景渐变自然，无突兀色块

### 4.6 任务 3.6：GlobalSearchView iOS 18 API

**文件**：`ItemManager/Views/GlobalSearchView.swift` 第 413 行

**改动**：审视代码意图，加 iOS 18 分支保护或重写为 iOS 17 兼容实现。

---

## 5. M4 SwiftPM + Extension（T+18 ~ T+20 天）

### 5.1 Extension Target 审视

对每个 Extension target（Widget、Share、Intents）：
1. 单独编译验证（Xcode → Scheme 选择 Extension → Build）
2. 真机运行验证（iPhone 11 iOS 17.4 上能看到 Widget 列表）
3. 视觉走查（Widget 渲染、Share 弹窗、Intents 执行）

### 5.2 SwiftPM 依赖稳定性

- 记录每个 Package 的最终版本到 `Package.resolved`
- `Package.resolved` 提交到 git，避免不同开发机版本漂移

---

## 6. M5 真机回归（T+21 ~ T+27 天）

### 6.1 设备分配

| 工程师/QA | 设备 | iOS 版本 | 测试重点 |
|---|---|---|---|
| QA-A | iPhone XS | 17.7 | 老机型稳定性、SwiftData |
| QA-A | iPhone 11 | 17.4 | 最低目标全功能 |
| QA-B | iPhone 13 | 18.7 | 中间档 |
| QA-B | iPhone 15 | 26.1 | 确保 iOS 26 未破坏 |
| DEV | iPhone 14 Pro | 18.5 | 开发联调 |

### 6.2 执行
- 严格按 `ACCEPTANCE_TESTS.md` 每条用例打钩
- 发现 bug 开 GitHub Issue，标签 `ios17-migration`
- 严重 bug（crash/功能不可用）必须 M5 内修复
- 次要 bug（视觉瑕疵）可进入 M6 后续迭代

### 6.3 性能基准
- 冷启动时间（iPhone 11）：目标 < 2 秒
- 衣橱列表 500 件滚动帧率：目标 60fps
- 内存峰值（正常使用）：< 400MB

---

## 7. M6 提审 + 灰度（T+28 ~ T+35 天）

### 7.1 App Store Connect 配置

- 新建 App Version（例如从 4.2 → 4.3）
- 最低系统要求：**iOS 17.4**
- What's New：
  ```
  新增 iOS 17 支持，更多用户现在可以使用少女心愿 💕
  优化部分界面在 iOS 17/18 上的显示效果。
  修复了若干问题。
  ```
- 截图：暂不更新（沿用现有 iOS 26 截图）
- 隐私声明：无变化

### 7.2 TestFlight 内测

**Group 1 - iOS 17 专属**：
- 邀请持有 iPhone XS/11/12/13 的已知用户（约 50 人）
- 反馈期 3 天
- 重点关注：冷启动崩溃、SwiftData migration 崩溃、视觉瑕疵

**Group 2 - 全量验证**：
- 正常 TestFlight 公测组
- 反馈期 4 天
- 观察 crash-free users 比例

### 7.3 上线

- 审核通过后，选择"**手动发布**"
- iOS 17 崩溃率 < 0.5% 且无 P0 bug → 发布全量
- 上线后 48 小时密切监控 App Store Connect Crashlytics

### 7.4 回滚预案

若上线 48 小时内 crash 率异常：
- Plan A：App Store Connect → 版本下架（从新用户下载中撤回，已下载用户保留）
- Plan B：提交热修 build，抢审"紧急修复"通道
- Plan C：把最低版本改回 iOS 18（只影响 iOS 17 用户下载不到，不影响已装用户）

---

## 8. 任务分解表（按天）

### Week 1
| 日 | 任务 | 负责人 |
|---|---|---|
| D1 | 扫描 + 生成 audit 表 | DEV |
| D2 | 走查 15 个文件的 else 分支 | DEV |
| D3 | 审计报告定稿 | DEV |
| D4 | pbxproj target 下调 | DEV |
| D5 | 处理编译错误、SwiftPM 检查 | DEV |

### Week 2
| 日 | 任务 | 负责人 |
|---|---|---|
| D6-D7 | LiquidGlassComponents 补全 iOS 17.4 分支 | DEV |
| D8-D9 | MainTabView fallback 验证 + 修复 | DEV |
| D10 | 小世界 Spatial Scene 降级 | DEV |

### Week 3
| 日 | 任务 | 负责人 |
|---|---|---|
| D11 | Calendar / Settings 细节点 | DEV |
| D12 | MeshGradient / GlobalSearch 修复 | DEV |
| D13 | Extension target 验证 | DEV |
| D14-D15 | 联调 + 自测 | DEV |

### Week 4
| 日 | 任务 | 负责人 |
|---|---|---|
| D16-D20 | 真机回归测试（按用例走） | QA × 2 |

### Week 5
| 日 | 任务 | 负责人 |
|---|---|---|
| D21-D22 | TestFlight 内测 Group 1 | PM + DEV |
| D23-D24 | TestFlight Group 2 | PM |
| D25 | App Store 送审 | DEV |
| (T+35) | 审核通过后全量发布 | PM |

---

## 9. 关键交付物 checklist

- [ ] M1 审计报告（Excel + .md 摘要）
- [ ] M2 `project.pbxproj` git diff（只有 deployment target 改动）
- [ ] M3 各视觉 fallback 的 iOS 17 / iOS 18 / iOS 26 三版截图对比
- [ ] M4 Extension target 真机截图
- [ ] M5 全量测试报告（用例通过率）
- [ ] M5 性能基准数据（冷启动、滚动帧率、内存）
- [ ] M6 TestFlight 反馈汇总
- [ ] M6 上线后 48 小时监控日报

---

## 10. 不做项（明确不在本计划范围）

- ❌ 新功能开发（本阶段纯兼容改造）
- ❌ 代码重构（除非编译必须）
- ❌ UI 视觉重设计（iOS 17 沿用 iOS 18 的 fallback 视觉）
- ❌ 性能优化（除非发现严重退化）
- ❌ 跨端数据迁移的代码实现（那是 Android/鸿蒙 PRD 的事）

---

**文档结束**。验收用例见 `ACCEPTANCE_TESTS.md`。
