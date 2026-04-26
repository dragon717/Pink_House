# 少女心愿 · iOS 17 兼容版 PRD

> 文档版本：v1.0 · 最后更新：2026-04-20
> 上游：`docs/migration/00_PRODUCT_SPEC_CROSS_PLATFORM.md`
> 同级：`TECH_DESIGN.md`、`MIGRATION_PLAN.md`、`ACCEPTANCE_TESTS.md`

---

## 1. 版本定位

**一句话**：**不是新 App，是现有 iOS App 的 deployment target 下放**。目标：**同一个 app 包同时支持 iOS 17.0 ~ iOS 26.x**，扩大用户覆盖到 iOS 17 用户（约占 App Store 总流量的 12-15%）。

### 1.1 核心原则
- **功能不减**：所有功能（含 AI、裙子股市、CloudKit、3D 穿搭）在 iOS 17 上仍然可用
- **视觉分级**：iOS 26 专属视觉（Liquid Glass、Mica、新 TabBar 浮动样式等）在 iOS 17/18 上**自动 fallback 到同等设计意图的替代实现**
- **单一代码库**：用 `if #available(iOS X, *)` 分支实现降级，不 fork 代码库
- **单一 target**：不拆成多个 app target，不维护"精简版"

### 1.2 改造范围
- 主 App target：`IPHONEOS_DEPLOYMENT_TARGET` 从 `18` → **`17.4`**（**已确认**，规避 SwiftData 17.0~17.1 migration bug）
- 扩展 target（Widget、Share、Intents 等）：从 `26.2` → **`17.4`**（与主 target 对齐）
- Swift 版本：保持 5.0

---

## 2. iOS 版本矩阵

| iOS 版本 | 覆盖率（App Store 数据估计） | 支持状态 | 视觉体验 |
|---|---|---|---|
| iOS 17.0 ~ 17.3 | ~2% | ❌ **不支持**（SwiftData 有已知崩溃 bug） | — |
| iOS 17.4 ~ 17.7 | ~10% | ✅ 完整功能 | 旧版视觉（Material / Shadow） |
| iOS 18.0 ~ 18.x | ~35% | ✅ 完整功能 | 中间态（含 MeshGradient 等 iOS 18 特性） |
| iOS 26.0 ~ 26.x | ~45% | ✅ 完整功能 + iOS 26 专属视觉 | Liquid Glass / Mica / 新 TabBar |
| iOS 16 及以下 | ~8% | ❌ 不支持（SwiftData 要求 iOS 17+） | — |

---

## 3. 功能影响分析（按模块）

> 核心判断：**功能逻辑不受影响，只有视觉表现层可能 fallback**。

### 3.1 无影响模块（直接兼容）
以下模块全部用 iOS 17 基础 API，降级后零改动：

- 衣橱管理（`@Model`、SwiftData 查询、筛选）
- 品牌/标签管理
- 签到、日历、尾款规划
- 拼豆
- 备份恢复
- 设置（除部分 iOS 26 新组件）
- 分享
- 全局搜索
- 多语言

### 3.2 需适配模块（有 iOS 18/26 代码）

**基于代码扫描，以下文件含 `if #available(iOS 18/26, *)` 分支**（共 30+ 处）：

| 文件 | 可用性分支 | 降级策略 |
|---|---|---|
| `ItemManagerApp.swift` | iOS 26.0 | 已有 else 分支 |
| `Views/HomeView.swift` | iOS 26.0 × 2 / iOS 18.0 | 检查 else 分支完整性 |
| `Views/MainTabView.swift` | iOS 26.0 × 5 | 新 TabBar 降级到旧 TabBar 样式 |
| `Views/FrenchRetroSmallWorldView.swift` | iOS 26.0 × 5 | Liquid Glass 降级到 Mica fallback |
| `Views/RococoSmallWorldView.swift` | iOS 26.0 × 2 | 同上 |
| `Views/Wealth/WealthView.swift` | iOS 26.0 | 视觉降级 |
| `Views/GlobalSearchView.swift` | iOS 18.0 | 新搜索控件降级 |
| `Views/Calendar/DreamDressCalendarView.swift` | iOS 26.0 | 视觉降级 |
| `Views/Settings/GeneralSettingsView.swift` | iOS 26.0 | 视觉降级 |
| `Views/Settings/Components/AdaptiveSettingsComponents.swift` | iOS 26.0 | 视觉降级 |
| `Views/Settings/Refactored/SmallWorldSettingsView.swift` | iOS 26.0 × 2 | 视觉降级 |
| `Views/Settings/DataManagementView.swift` | iOS 26.0 | 视觉降级 |
| `Views/SmallWorldMenuOverlay.swift` | iOS 26.0 | 视觉降级 |
| `Views/PetChat/PetChatViewPreview.swift` | iOS 18.0 | 检查 else 分支 |
| `Views/SpatialCanvas/MultiImagePicker.swift` | iOS 16.0 | 已覆盖 iOS 17 |
| `Views/Pet/PetComponents.swift` | iOS 16.0 | 已覆盖 iOS 17 |
| `Services/NewbieGuide/NewbieGuideAIAndWealth.swift` | iOS 26.0 | 视觉降级 |

**结论**：代码里已有较完整的 `if #available` 覆盖，**iOS 17 兼容的主要工作是审计每一个分支的 else 是否完整可运行**。

### 3.3 组件库降级

#### 3.3.1 `LiquidGlassComponents.swift`
- iOS 26：使用原生 Liquid Glass 材质（`.glassEffect()` 新 API）
- iOS 18：使用 `.ultraThinMaterial` + 自定义 MeshGradient
- iOS 17：使用 `.ultraThinMaterial` + LinearGradient（无 MeshGradient）
- **验收标准**：iOS 17 上玻璃感弱化但不突兀；iOS 18 上接近 iOS 26 体验

#### 3.3.2 MainTabView 浮动 TabBar
- iOS 26：原生浮动 TabBar + Liquid Glass 背景
- iOS 17/18：自定义浮动 TabBar（通过 overlay 实现），背景用 Material
- **代码参考**：现有 `MainTabView.swift:30` 已有 `if #available(iOS 26.0, *)` 分支

#### 3.3.3 Adaptive 设置组件
- iOS 26：新 Form 样式
- iOS 17/18：旧 Form 样式 + 手动圆角
- **文件**：`Views/Settings/Components/AdaptiveSettingsComponents.swift` 已覆盖

### 3.4 iOS 专属功能（仍保留）

以下功能在 iOS 17 上**保持完整**，无需降级：

| 功能 | iOS 最低要求 | iOS 17 可用 | 备注 |
|---|---|---|---|
| SwiftData | iOS 17+ | ✅ | 项目基础 |
| CloudKit 同步 | iOS 13+ | ✅ | 包括 Private DB + Public DB |
| StoreKit 2 | iOS 15+ | ✅ | IAP 和订阅 |
| Vision Framework | iOS 13+ | ✅ | AI 图像分析 |
| AVFoundation | 长期支持 | ✅ | 视频/音频 |
| RealityKit（3D 穿搭） | iOS 13+ | ✅ | 但部分新 API 仅 iOS 18+ |
| ObjectCapture | iOS 17+ | ✅ | 刚好 iOS 17 起 |
| WidgetKit | iOS 14+ | ✅ | 视觉需降级 |
| 裙子股市（CloudKit Public） | iOS 15+ | ✅ | |
| AI 云 API 调用（Qwen/DeepSeek） | 无限制 | ✅ | |

### 3.5 需要特别验证的 iOS 17 限制

- **SwiftData 在 iOS 17 某些版本有稳定性 bug**（如 17.0 ~ 17.1 的 migration 崩溃）。产品要求最低支持 iOS 17.2 或 17.4 规避已知 bug。→ **建议改 deployment target 为 17.4**，留出 buffer。
- **@Observable 宏在 iOS 17.0 首版有编译 bug**，17.2+ 稳定。
- **RealityKit 部分 API 在 iOS 17 不完整**（如 Spatial Canvas 可能需要额外 `#available` 判断）。
- **ObjectCapture for Object** 要求 iOS 17+ 但需要 LiDAR 设备（仅 iPhone Pro 系列），与 deployment target 无关。

---

## 4. 功能清单（与现有 iOS 版本完全一致）

不单独列出 F-XX 编号，**所有功能沿用现有 iOS 版**。iOS 17 版本的产品承诺就是一句话：

> **iOS 17 用户得到的功能集 = iOS 26 用户的功能集，视觉细节可能略有差异**

以下是对照表：

| 模块 | iOS 17 行为 | iOS 18 行为 | iOS 26 行为 |
|---|---|---|---|
| 衣橱 | 完整 | 完整 | 完整 |
| OOTD 2D | 完整 | 完整 | 完整 |
| OOTD 3D (RealityKit) | 完整 | 完整 | 完整 |
| 宠物互动 | 完整 | 完整 | 完整 |
| 宠物聊天（AI） | 完整 | 完整 | 完整 |
| 小世界（2D） | 完整 | 完整 | 完整 |
| 小世界（iOS 26 空间场景） | ❌（按钮灰/隐藏） | ❌ | ✅ |
| BigWorld 沉浸飞行 | 2D 版 | 2D 版 | 3D 沉浸 |
| 财富液态数字 | SpriteKit 正常 | SpriteKit 正常 | + Liquid Glass 背景 |
| VIP 中心 | 完整 | 完整 | + Liquid Glass 卡片 |
| VIP App Icon 切换 | 完整 | 完整 | 完整 |
| IAP | StoreKit 2 | StoreKit 2 | StoreKit 2 |
| 裙子股市 | 完整 | 完整 | 完整 |
| AI 服务（7 个） | 完整 | 完整 | 完整 |
| iCloud 同步 | 完整 | 完整 | 完整 |
| Widget | iOS 17 样式（老配色） | iOS 18 样式 | iOS 26 样式 |
| 通知中心（Notice CMS） | 完整 | 完整 | 完整 |
| 新手引导 | 完整 | 完整 | 完整 |

---

## 5. 非功能需求

### 5.1 性能
- iOS 17 设备覆盖：iPhone XS 及以上（SwiftData 硬性要求）
- 冷启动 < 2 秒（iPhone 11 / XS）
- 衣橱列表 1000 件滚动 60fps（与 iOS 26 机型相比可能有 5-10% 性能退化，可接受）
- 内存峰值 < 400MB

### 5.2 测试设备矩阵
必须覆盖：
- **iOS 17.5 / 17.7**：iPhone XS、iPhone 11、iPhone 13（常见老机型）
- **iOS 18.5 / 18.7**：iPhone 14 Pro、iPhone 15
- **iOS 26.1 / 26.2**：iPhone 16 Pro、iPhone 17 Pro（最新视觉效果）
- **iPad 17/18/26**：至少一台 iPad Pro

### 5.3 合规
- App Store 隐私标签保持现有
- CloudKit 的用户隐私声明不变
- AI 调用的第三方服务（Qwen、DeepSeek）已在隐私政策声明

### 5.4 App Store 发布
- 统一一个 version，不拆 build
- Release notes 中**明确说明**"本版本新增 iOS 17 支持"
- 最低系统要求从 **iOS 18.0** 改为 **iOS 17.4**（或 17.2）

---

## 6. 与 Android / 鸿蒙 Next 的关系

- **代码层无关**：三端独立代码库，iOS 17 兼容改造仅影响 iOS 包
- **产品层弱关联**：用户跨端迁移时，iOS 17 导出的 JSON 格式仍标版本 `3.0`（完整版），Android/鸿蒙端按兼容规则导入
- **视觉层参考**：iOS 17 fallback 时某些组件的实现思路可供 Android/鸿蒙 设计参考（例如"非 Liquid Glass 场景下如何做玻璃感"）

---

## 7. 交付里程碑

iOS 17 改造是**轻量任务**（代码修改集中在 ≈ 30 个文件、主要是补 else 分支和视觉回归测试）：

| 阶段 | 范围 | 周数 |
|---|---|---|
| M1 可用性审计 | 扫描所有 `if #available` 分支，补齐 else 逻辑 | 0.5 周 |
| M2 deployment target 下调 | 改 project.pbxproj，解决编译错误 | 0.5 周 |
| M3 视觉 fallback 实现 | Liquid Glass / 新 TabBar 等组件补 iOS 17/18 路径 | 1.5 周 |
| M4 iOS 17 机型实机测试 | 全量功能回归（用 ACCEPTANCE_TESTS.md） | 1.5 周 |
| M5 App Store 送审 | Release notes、截图（iOS 17 机型重新截）| 0.5 周 |

**总计：约 4.5 周**，1 名 iOS 工程师即可完成。

---

## 8. 成功指标

- 编译通过 + 在 iOS 17.4 / 17.7 真机无闪退 = 最低交付标准
- **iOS 17 用户装机率**：发布后 30 天，iOS 17 用户占总新增下载 > 10%（说明新开放市场生效）
- **iOS 17 用户崩溃率**：< 0.3%（不得显著高于 iOS 26 用户）
- **App Store 评分**：保持 > 4.5（不因 iOS 17 适配引入新差评）
- **跨版本 bug 报告**：iOS 17 专属 bug 数 < 10 / 月

---

## 9. 风险与对策

| 风险 | 概率 | 影响 | 对策 |
|---|---|---|---|
| iOS 17 上 SwiftData migration 崩溃 | 中 | 高 | deployment target 定到 17.4+ 规避；严格 migration 测试 |
| Liquid Glass fallback 视觉违和 | 中 | 中 | Design review by 产品，不能出现"老 iOS 用户看起来像廉价 App"的观感 |
| RealityKit 某 API iOS 17 不存在导致编译失败 | 低 | 中 | 编译器会报错，加 `if #available(iOS 18)` 包 |
| Widget iOS 17 样式过时 | 低 | 低 | iOS 17 用户可接受老样式 |
| AI 服务在老机型（iPhone XS）卡顿 | 中 | 中 | 老机型降级为纯云 API（不做本地 Vision 推理），保持体验 |
| 某个 iOS 26 独有 API 被用在非 #available 分支导致 iOS 17 crash | 高 | 高 | **M1 审计必须 100% 覆盖** |

---

## 10. 已确认决策 & 遗留开放问题

### 10.1 已确认（2026-04-20）
- ✅ deployment target 定 **iOS 17.4**（规避 SwiftData 17.0/17.1 migration bug）
- ✅ 扩展 target（Widget 等）同步降级到 17.4

### 10.2 遗留开放问题
1. **Store 截图**：要不要为 iOS 17 重新拍一组？Apple 允许多套截图。建议拍 1 套 iOS 17 视觉版 + 保留 1 套 iOS 26 Liquid Glass 版。
2. **RealityKit 空间场景入口**（`FrenchRetroSmallWorldView` 中 `isSpatialSceneEnabled` 分支）在 iOS 17 上是显示入口但灰掉，还是直接**隐藏入口**？建议**隐藏**避免用户困惑，与 Android/鸿蒙 Next 对齐。
3. **Widget 在 iOS 17 上的视觉**：iOS 17 的 Widget 没有 accessoryRectangular 的新字体等，是否需要单独出 iOS 17 Widget 设计稿？或者沿用现有设计接受轻微退化？

---

**文档结束**。相比 Android/鸿蒙 Next 的长产品文档，本文档短小，因为本质上是**同一产品的兼容性扩展**而非新产品。
