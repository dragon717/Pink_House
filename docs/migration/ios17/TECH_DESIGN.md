# 少女心愿 · iOS 17 兼容版技术设计

> 文档版本：v1.0 · 最后更新：2026-04-20
> 上游：`docs/migration/ios17/PRD.md`
> 同级：`MIGRATION_PLAN.md`、`ACCEPTANCE_TESTS.md`

---

## 1. 设计目标

**核心诉求**：在不改变任何业务逻辑的前提下，让同一个 app 包支持 iOS 17.4 ~ iOS 26.x。

**技术约束**：
- 单一代码库（不 fork）
- 单一 Xcode target（不拆包）
- 视觉降级采用 `if #available` 分支实现
- 不引入任何第三方兼容层库
- 功能 100% 保留（含 AI、CloudKit、StoreKit 2、RealityKit）

**非目标**：
- 不做 iOS 16 支持（SwiftData 依赖 iOS 17+）
- 不做性能优化（如果 iOS 17 老机型卡，另案处理）
- 不做代码重构（保持现有架构）

---

## 2. iOS 版本特性支持矩阵

### 2.1 框架级 API 可用性

| 框架 / API | iOS 17.4 | iOS 18 | iOS 26 | 当前使用 | 处理策略 |
|---|---|---|---|---|---|
| SwiftData `@Model` | ✅ | ✅ | ✅ | 核心依赖 | 保持 |
| CloudKit（Private/Public DB） | ✅ | ✅ | ✅ | Notice CMS + 裙子股市 | 保持 |
| StoreKit 2 `Product` / `Transaction` | ✅ | ✅ | ✅ | IAP 核心 | 保持 |
| Vision Framework | ✅ | ✅ | ✅ | AI 图像分析 | 保持 |
| AVFoundation `AVPlayer` | ✅ | ✅ | ✅ | 宠物/小世界视频 | 保持 |
| RealityKit 基础 API | ✅ | ✅ | ✅ | OOTD 3D | 保持 |
| RealityKit `ModelSortGroup`、新粒子 | ❌ | ✅ | ✅ | 如未使用则无需降级 | 检查 |
| ObjectCapture | ✅（iOS 17+） | ✅ | ✅ | 物体扫描 | 保持 |
| WidgetKit 基础 | ✅ | ✅ | ✅ | 现有 widget | 保持 |
| **iOS 18 新特性** | | | | | |
| MeshGradient | ❌ | ✅ | ✅ | Wealth 页可能用 | `if #available(18)` → LinearGradient |
| `Image.frameRate` | ❌ | ✅ | ✅ | 未使用 | — |
| `ScrollView.onScrollGeometryChange` | ❌ | ✅ | ✅ | 未使用 | — |
| `@Animatable` macro | ❌ | ✅ | ✅ | 未使用 | — |
| **iOS 26 新特性** | | | | | |
| Liquid Glass `.glassEffect()` | ❌ | ❌ | ✅ | TabBar、卡片、设置 | 降级为 `.ultraThinMaterial` |
| Mica 材质 | ❌ | ❌ | ✅ | 小世界、财富页 | 降级为 Material + 半透明叠加 |
| 新浮动 TabBar | ❌ | ❌ | ✅ | MainTabView | 降级为自定义浮动实现（已有） |
| `subscriptionStoreControlStyle` | ❌ | ❌ | ✅ | 未使用 | — |
| `toolbarBackgroundVisibility` | ❌ | ❌ | ✅ | 可能 | 检查 |
| `concentricRectangle` 形状 | ❌ | ❌ | ✅ | 未使用 | — |

### 2.2 当前代码中 `if #available` 分布

**扫描结果**（已确认 30+ 个分支点）：

| 文件 | iOS 26 分支数 | iOS 18 分支数 | 当前 else 状态 |
|---|---|---|---|
| `ItemManagerApp.swift` | 2 | 0 | 待验证 |
| `Views/HomeView.swift` | 2 | 1 | 待验证 |
| `Views/MainTabView.swift` | 5 | 0 | 已有 else 实现 |
| `Views/FrenchRetroSmallWorldView.swift` | 5 | 0 | 已有 else 实现 |
| `Views/RococoSmallWorldView.swift` | 2 | 0 | 已有 else 实现 |
| `Views/Wealth/WealthView.swift` | 1 | 0 | 待验证 |
| `Views/GlobalSearchView.swift` | 0 | 1 | 待验证 |
| `Views/Calendar/DreamDressCalendarView.swift` | 1 | 0 | 待验证 |
| `Views/Settings/GeneralSettingsView.swift` | 1 | 0 | 待验证 |
| `Views/Settings/Components/AdaptiveSettingsComponents.swift` | 1 | 0 | 已有 else 实现 |
| `Views/Settings/Refactored/SmallWorldSettingsView.swift` | 2 | 0 | 待验证 |
| `Views/Settings/DataManagementView.swift` | 1 | 0 | 待验证 |
| `Views/SmallWorldMenuOverlay.swift` | 1 | 0 | 待验证 |
| `Views/PetChat/PetChatViewPreview.swift` | 0 | 1 | 仅 Preview，不影响运行时 |
| `Services/NewbieGuide/NewbieGuideAIAndWealth.swift` | 1 | 0 | 待验证 |

**M1 阶段任务**：对每一个"待验证" else 分支逐一走查，确保：
1. 无 iOS 18/26 专属 API 泄漏到 else 分支
2. else 分支视觉效果可接受（没有纯黑/空白等降级异常）
3. 编译通过（部署目标降到 17.4 后不再有对 iOS 18/26 API 的"未判断调用"）

---

## 3. 组件降级策略

### 3.1 Liquid Glass（iOS 26 核心视觉）

**现状**：`Components/LiquidGlassComponents.swift` 封装了玻璃效果组件，内部已用 `if #available(iOS 26.0)`。

**架构**：
```swift
// 伪代码示意，实际以现有实现为准
struct LiquidGlassCard<Content: View>: View {
    let content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) {
            content().background(.glassEffect(in: .capsule))
        } else if #available(iOS 18.0, *) {
            content().background(.ultraThinMaterial) // + MeshGradient overlay
        } else {
            content().background(.ultraThinMaterial)  // iOS 17.4
                     .overlay(LinearGradient(...).blendMode(.plusLighter))
        }
    }
}
```

**验收要求**：
- iOS 17.4 真机：玻璃质感"存在感" > 50%（不能看起来像纯白卡片）
- iOS 17.4 与 iOS 18 视觉差距 < 20%（肉眼可辨但不突兀）
- iOS 18 与 iOS 26 视觉差距 < 10%（接近）

### 3.2 MainTabView 浮动 TabBar

**现状**：`MainTabView.swift` 已有 5 处 `if #available(iOS 26.0)`，iOS 26 走系统浮动 TabBar，其余走**自定义浮动 overlay 实现**。

**iOS 17.4 降级方案**（沿用 iOS 18 分支）：
- 自定义浮动 Bar：ZStack 在页面底部 overlay 一个 HStack 五个按钮
- 背景：`.ultraThinMaterial` + 顶部细线 1px 分割
- 阴影：`.shadow(color: .black.opacity(0.08), radius: 12, y: -2)`
- 激活态：主色图标 + 小圆点

**风险**：
- 部分 iOS 26 使用的 `TabBarButton` 辅助能力（如长按菜单）在降级分支可能缺失 → 确认无功能性需求
- 旋转/横屏下浮动 Bar 位置 → 已有处理（`TabBarItemAnchorResolver`）

### 3.3 MeshGradient 降级

**使用点**：`Views/Wealth/WealthView.swift` 等可能用到（MeshGradient 是 iOS 18+）。

**降级方案**：
```swift
if #available(iOS 18.0, *) {
    MeshGradient(width: 3, height: 3, points: [...], colors: [...])
} else {
    // iOS 17.4 fallback
    LinearGradient(colors: [startColor, midColor, endColor],
                   startPoint: .topLeading,
                   endPoint: .bottomTrailing)
}
```

### 3.4 Mica 材质（iOS 26）

**使用点**：小世界背景、财富卡片等。

**降级方案**：
- iOS 17.4：`Color.backgroundTint.opacity(0.92)` + 模糊图层（通过 `Rectangle().blur(radius: 40)` 模拟）
- 若视觉差距过大，可以考虑预渲染一张带模糊效果的 PNG 作为背景图（资源代价）

### 3.5 RealityKit Spatial Scene

**使用点**：`FrenchRetroSmallWorldView.swift`、`RococoSmallWorldView.swift` 中 `isSpatialSceneEnabled` 分支（iOS 26 专属 3D 沉浸模式）。

**降级方案**：
- iOS 17.4：`isSpatialSceneEnabled == false`，不显示空间场景入口（产品 PRD 已确认**隐藏**）
- 不影响小世界 2D 版正常使用

### 3.6 iOS 18 专属点位

**已定位的 3 处 `if #available(iOS 18.0)`**：

| 位置 | 代码意图 | iOS 17.4 降级 |
|---|---|---|
| `HomeView.swift:362` | 可能是新 ScrollView API | 回退到 `ScrollView` + `@State offset` |
| `GlobalSearchView.swift:413` | 可能是新 Searchable | 回退到 iOS 17 `.searchable` |
| `PetChatViewPreview.swift:5` | 仅 `#Preview` 预览，不影响运行时 | 无需降级 |

---

## 4. Extension Target 降级

### 4.1 当前扩展 target（deployment target = 26.2）

从 `project.pbxproj` 扫描结果：
- 4 个扩展 target 的 deployment target 是 `26.2`
- 推测：Widget Extension、Share Extension、Intents Extension、可能的 App Clip

### 4.2 降级策略

全部 Extension target 一起改到 **iOS 17.4**。影响：

| Extension | iOS 17 可用性 | 需改动 |
|---|---|---|
| Widget Extension | ✅（基础 API 从 iOS 14 起） | 视觉可能有 iOS 26 新组件需 fallback |
| Share Extension | ✅ | 无 |
| Intents Extension | ✅ | 无 |
| App Clip（如有） | ✅ | 审视新 API |

### 4.3 Widget iOS 17 视觉

- 小号 Widget：内容可能有 iOS 26 `widgetAccentedRenderingMode` → 降级到基础渲染
- 锁屏 Widget：iOS 26 新 circular/rectangular 样式 → 沿用 iOS 17 旧样式
- **PRD 开放问题 3**：Widget 是否要出 iOS 17 设计稿 → 工程上默认"沿用 + 不崩"，不重新设计

---

## 5. 编译与构建

### 5.1 project.pbxproj 修改点

扫描结果：8 个位置有 `IPHONEOS_DEPLOYMENT_TARGET`，分布在 Debug/Release × 4 个 target。

**修改**：
```diff
- IPHONEOS_DEPLOYMENT_TARGET = 18;
+ IPHONEOS_DEPLOYMENT_TARGET = 17.4;

- IPHONEOS_DEPLOYMENT_TARGET = 26.2;
+ IPHONEOS_DEPLOYMENT_TARGET = 17.4;
```

**批量替换命令**（供参考，实际操作见 `MIGRATION_PLAN.md`）：
```bash
sed -i '' 's|IPHONEOS_DEPLOYMENT_TARGET = 18;|IPHONEOS_DEPLOYMENT_TARGET = 17.4;|g' \
  ItemManager.xcodeproj/project.pbxproj
sed -i '' 's|IPHONEOS_DEPLOYMENT_TARGET = 26.2;|IPHONEOS_DEPLOYMENT_TARGET = 17.4;|g' \
  ItemManager.xcodeproj/project.pbxproj
```

### 5.2 Swift Package Manager 依赖

**需审视的依赖**：
- 当前项目用的 SwiftPM 依赖（如有）可能有自己的 deployment target。
- 行动：打开 Xcode → Package Dependencies，检查每个 package 的 minimum deployment target ≥ 17.4。
- 若某依赖要求 iOS 18+ 且无法替代 → 降级该依赖或加 `#available` 包裹调用点。

### 5.3 Info.plist / entitlements

- `Info.plist`：无需改动
- `ItemManager.entitlements`：CloudKit、Push、iCloud Container 等能力均不限 iOS 版本，无需改动
- `PrivacyInfo.xcprivacy`：无需改动（不新增隐私行为）

### 5.4 SwiftData Schema 兼容

**关键风险**：SwiftData 在 iOS 17.0~17.3 有已知 migration 崩溃 bug（用户从老版本升级到新 schema 时崩溃）。

**规避**：
- deployment target = **17.4**（已确认）
- schema 版本控制必须显式管理（`VersionedSchema`、`SchemaMigrationPlan`）
- **不在 iOS 17 上做破坏性 migration**（即：新字段必须有默认值，删字段要走 lightweight migration）

### 5.5 编译警告治理

- deployment target 降级后 Xcode 会对 iOS 18/26 API 报"Availability required"警告
- 强制警告为错误：`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`（临时开启用于审计，确保没有漏网的新 API）
- 审计完成后关闭（避免第三方 SDK 的非我方警告也变成错误）

---

## 6. 测试策略

### 6.1 真机测试矩阵

| 机型 | iOS 版本 | 测试重点 | 优先级 |
|---|---|---|---|
| iPhone XS | 17.7 | 冷启动性能、SwiftData 稳定性 | P0 |
| iPhone 11 | 17.4 | 全功能回归（覆盖最低目标） | P0 |
| iPhone 13 | 18.7 | iOS 18 特性（MeshGradient）正常 | P1 |
| iPhone 14 Pro | 18.5 | 中间档 | P1 |
| iPhone 15 | 26.1 | 完整 iOS 26 视觉 | P0 |
| iPhone 17 Pro | 26.2 | 最新特性全开 | P1 |
| iPad Pro | 17.7 + 26.2 | iPad 布局适配 | P2 |

### 6.2 模拟器测试（次要）
- Xcode 可用 iOS 17.4 Simulator
- 但 3D 渲染、RealityKit、SwiftData、StoreKit 测试**必须真机**（模拟器偏差大）

### 6.3 自动化测试
- 项目有 `ItemManagerTests` 和 `ItemManagerUITests` 基础
- UITest 至少覆盖：启动、添加一件衣物、打开宠物页、充值流程
- 单测覆盖数据层（SwiftData 查询、BackupService 序列化/反序列化）

---

## 7. 发布策略

### 7.1 版本号
- 当前版本：查 `Info.plist` `CFBundleShortVersionString`
- iOS 17 兼容版版本建议：主版本号 + 0.1（例：4.2 → 4.3）
- build number 递增

### 7.2 App Store Connect 配置
- 最低系统要求下调至 **iOS 17.4**（App Store Connect 页面可直接设置）
- Release notes 中文+英文写明"**新增 iOS 17 支持，更多用户现在可以下载**"
- 截图：保留现有 iOS 26 截图，**无需重新拍摄**（可选择性增加 iOS 17 截图集，见 PRD 开放问题 1）

### 7.3 灰度
- TestFlight 先发 iOS 17 测试组（招募 iPhone XS/11/13 用户）
- 观察 1 周，无 crash 后全量上线

### 7.4 回滚预案
- 若 iOS 17 用户崩溃率 > 1%，App Store Connect 可**仅限 iOS 18+ 下载**作为紧急止血
- 主版本可继续，下个子版本修复

---

## 8. 风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|---|---|---|---|
| 某 iOS 26 API 未加 `#available` 导致 iOS 17 crash | 中 | 严重 | M1 开启 `SWIFT_TREAT_WARNINGS_AS_ERRORS` 强制审计 |
| SwiftPM 依赖要求 iOS 18+ | 中 | 中 | 换依赖或降级版本；最坏情况自己 vendored |
| SwiftData migration 在 iOS 17.4 真机崩溃 | 低 | 严重 | TestFlight 真机测试；保留老 App 版本作回退路径 |
| Liquid Glass 降级视觉过丑 | 中 | 中 | 设计 review；必要时引入静态资源图 |
| Widget 在 iOS 17 上显示异常 | 低 | 低 | Widget 非核心路径，发现问题单独修 |
| 某功能在 iOS 17 老机型（如 XS）性能不达标 | 中 | 中 | 性能监控，老机型自动降低动画精度 |
| 第三方 SDK（如 Qwen/DeepSeek）的 iOS 17 兼容问题 | 低 | 中 | 走 HTTPS API 不依赖 SDK，规避风险 |

---

## 9. 工作量估算

| 模块 | 工作量（人日） |
|---|---|
| M1 可用性审计（15+ 文件走查） | 3 天 |
| M2 deployment target 下调 + 编译修复 | 2 天 |
| M3 Liquid Glass / Mica / TabBar fallback 实装 | 5 天 |
| M4 MeshGradient 等 iOS 18 API 兜底 | 1 天 |
| M5 Widget / Extension target 适配 | 1 天 |
| M6 SwiftData schema 审计 | 1 天 |
| M7 真机回归（7 机型 × 1 天 = 按优先级并行） | 5 天 |
| M8 App Store 提审 + 灰度 | 2 天 |
| **合计** | **约 20 人日（4 周）** |

**人力**：1 名 iOS 工程师全职即可，可叠加半个 QA（M7 阶段）。

---

## 10. 代码改动清单（详见 MIGRATION_PLAN.md）

概要：
- `ItemManager.xcodeproj/project.pbxproj`：8 处 deployment target 改动
- `Components/LiquidGlassComponents.swift`：补 iOS 17.4 fallback
- `Views/MainTabView.swift`：验证 else 分支 5 处
- `Views/FrenchRetroSmallWorldView.swift`：验证 else 分支 5 处
- `Views/RococoSmallWorldView.swift`：验证 else 分支 2 处
- 其余 10+ 文件：逐一走查
- 删除：无文件需要删除
- 新增：无新增文件

---

**文档结束**。具体改动清单见 `MIGRATION_PLAN.md`，验收用例见 `ACCEPTANCE_TESTS.md`。
