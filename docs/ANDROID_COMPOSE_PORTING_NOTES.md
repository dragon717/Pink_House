# iOS → Android Jetpack Compose 复刻经验

> 来源：从 `HARMONY_ARKUI_PORTING_NOTES.md`（鸿蒙 ArkUI 首轮复盘）迁移而来的知识资产，结合 Android 侧 PRD（`docs/migration/android/PRD.md`）与当前脚手架（`android/`）的约束重写。适用于把 `ItemManager/Views/**.swift`（SwiftUI / iOS 18–26）复刻到 `android/app/src/main/java/com/pinkhouse/android/feature/**`（Kotlin + Jetpack Compose + Material 3）。

---

## 一、工作流（硬约束，与鸿蒙侧同构）

1. **先读对应 SwiftUI View 的 body**，画组件树，再动 Compose。
   - 用鸿蒙首轮"衣橱统计误写 2 列（应为 3 列）、action 应为 3 个大 tile 而非 chips"的教训：**只看设计图或只看产品文案，容易错分区数、错列数、错 action 形态**。第一版必须先贴 `ItemManager/Views/Wardrobe/WardrobeView.swift:1441-1524` 的 body，再写 Compose。
2. **取色走纯色 + 渐变近似**；水彩/园林底图等富素材留占位，进资源清单。
3. **增量编译**：`PinkHouseTheme` → 最小 `PinkHouseApp` shell → 单屏 stub → 扩展。一次改 5 个 Composable 会让 `Modifier` 链、State hoisting、recomposition 三类问题同时爆。
4. **每轮交付一个可 Android Studio Sync + `./gradlew :app:assembleDebug` 的最小 diff**，按用户贴的编译报错迭代。
5. **每批 ≤ 2 文件 diff**；Android 侧多一条：改了 `build.gradle.kts` / `libs.versions.toml` / `AndroidManifest.xml` 的那一轮，单独走一次 Sync 再动业务代码，避免"依赖换版"和"Composable 重构"冲突爆栈。

---

## 二、Compose 命名 / 参数反模式（对标 ArkTS `@Prop` 同名冲突）

鸿蒙 ArkTS 侧禁止 `@Prop` 和基类 `CustomComponent` 的属性方法同名（`padding` / `size` 等）。Compose 没有同样强的编译期冲突，但有一组**语义陷阱**，同名参数会把"修饰"和"布局"搞混：

| 危险命名 | 为什么危险 | 改用 |
|---|---|---|
| `fun Foo(padding: Dp)` | 调用方会以为 Composable 内部有边距，实则还得传 `Modifier.padding`，两者经常冲突 | `innerPadding: PaddingValues` 并只在组件内部的 `Column` / `Row` 上消费 |
| `fun Foo(size: Dp)` | `Modifier.size` 和参数 `size` 谁优先不明确 | `diameter: Dp`（圆形头像）或 `iconSize: Dp`（图标） |
| `fun Foo(color: Color)` | 与 `MaterialTheme.colorScheme` 语义冲突，主题切换时容易漏改 | `tintColor: Color = MaterialTheme.colorScheme.primary`，默认走主题 |
| `fun Foo(background: Color)` | `Modifier.background` 同名 | `surfaceColor` / `bgColor` |
| `modifier: Modifier` 同时又有 `padding` / `size` 参数 | 双重布局入口 → Compose Preview 里看不出来，真机跑才翻车 | **布局一律走 `modifier`**，组件内只暴露 `contentPadding` / `iconSize` 这种语义明确的语法糖 |
| `fun Foo(...)` 组件内部首行不是 `modifier: Modifier = Modifier` | 违反 [Compose API 指南](https://developer.android.com/jetpack/compose/api-guidelines) | 把 `modifier` 作为第一个可选参数，默认值 `Modifier` |

**硬规则**：所有自定义 `@Composable` 必须把 `modifier: Modifier = Modifier` 放在**必填参数之后、其它可选参数之前**。这是 Compose 官方 API 约定，也是 IDE 模板的默认形状。

---

## 三、布局套路（对标鸿蒙 `@BuilderParam` 链式陷阱）

鸿蒙那边坑在"自定义组件 + 尾随块之后不能 `.chain()` 属性"。Compose 的对应坑是 **Modifier 顺序敏感**：

### 3.1 Modifier 顺序决定语义，不是交换律

```kotlin
// ❌ 错：padding 在 background 之前 → 外面留白有色，内容区还有 padding
Modifier
  .padding(16.dp)
  .background(Color.Pink)
  .fillMaxWidth()

// ✅ 对：先 fillMaxWidth → 再 background → 最后 padding
Modifier
  .fillMaxWidth()
  .background(Color.Pink)
  .padding(16.dp)
```

**记忆法**：`size → background → border → padding → clickable → content` 是 98% 场景下的正确顺序。任何时候想不明白，按这个顺序过一遍。

### 3.2 自定义 Composable 的 `modifier` 参数必须应用在**根 layout** 上

```kotlin
// ❌ 根 Box 没接 modifier → 外部传的 Modifier.weight(1f) / Modifier.padding 全部失效
@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
  Box { content() }   // modifier 丢了
}

// ✅
@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
  Box(modifier = modifier) { content() }
}
```

这条是"鸿蒙 `@BuilderParam` 尾随块后不能 `.chain()`" 的 Compose 版：**modifier 只能挂在根 layout，不能挂在 Composable 调用的外层**（因为 Composable 本身不是表达式，没有返回值链）。

### 3.3 `weight` / `matchParentSize` 只在正确的 scope 里有效

- `Modifier.weight(1f)` 只在 `RowScope` / `ColumnScope` 内有效；拿出 scope 就是编译错或 runtime 忽略。
- `Modifier.matchParentSize()` 只在 `BoxScope` 内有效。
- 做"可拆分的行/列单元"组件时，签名写成 `fun RowScope.MyCell(...)`，把 scope 显式暴露给调用方。

---

## 四、响应式注意（对标 TS `get` 访问器不响应式）

鸿蒙侧：`get` 访问器不在 ArkUI 响应式系统里，模板会拿到 undefined。Compose 侧对应两类：

### 4.1 `State<T>` 必须在 `@Composable` 范围内读取

```kotlin
// ❌ viewModel 里直接 .value 赋给普通字段，字段变化不会触发 recomposition
class VM : ViewModel() {
  val count = mutableStateOf(0)
  val doubled = count.value * 2   // 只在 init 跑一次
}

// ✅ 派生状态用 derivedStateOf，或 Flow
class VM : ViewModel() {
  private val _count = MutableStateFlow(0)
  val count = _count.asStateFlow()
  val doubled = count.map { it * 2 }.stateIn(viewModelScope, SharingStarted.Eagerly, 0)
}
```

### 4.2 非 `@Composable` 函数里读 State 不会订阅

```kotlin
// ❌ 这个 remember 拿的是当时的值，之后 state 变了也不刷新
val label = remember { buildLabel(uiState) }

// ✅
val label by remember(uiState) { derivedStateOf { buildLabel(uiState) } }
```

### 4.3 原始类型别用 `mutableStateOf`

Compose 1.4+ 提供 `mutableIntStateOf` / `mutableLongStateOf` / `mutableFloatStateOf`，装箱开销 = 0。大型列表里 `mutableStateOf(0)` 每秒重建 1000 次会 GC 抖。

### 4.4 列表 reassign 优于 mutate

鸿蒙那条"数组 reassign 不要原地 push/splice"，Compose 完全一样：

```kotlin
// ❌ SnapshotStateList 之外的 MutableList
var items: List<Item> by remember { mutableStateOf(emptyList()) }
items.add(x)   // 不触发 recomposition

// ✅
items = items + x
// 或者从一开始就用
val items = remember { mutableStateListOf<Item>() }
items.add(x)   // SnapshotStateList 会触发
```

---

## 五、组件级坑点（对标鸿蒙 `bindSheet` / `Divider.vertical`）

| 场景 | 鸿蒙实现 | Compose 实现 | 坑 |
|---|---|---|---|
| 模态底部 Sheet | `bindSheet($$this.isOpen, ...)` | `ModalBottomSheet(onDismissRequest = ...)` | Compose 的 `sheetState.hide()` 是 suspend，要在 `rememberCoroutineScope` 里调；直接置 `showSheet=false` 会闪 |
| 垂直分隔线 | `Divider().vertical(true)` | `VerticalDivider()`（Material3 1.2+）或 `Box(Modifier.width(1.dp).fillMaxHeight().background(...))` | Material3 1.1 以下没有 `VerticalDivider`，手写 Box 更稳 |
| 图标 | `SymbolGlyph($r('sys.symbol.xxx'))` | `Icon(imageVector = Icons.Default.Xxx)` + Material Icons Extended 依赖 | Material Icons Extended 会让 APK 膨胀 ~10MB，按需引入单个 `ic_*.xml` 更好 |
| 真实照片 | `Image().objectFit(ImageFit.Cover)` | **Coil** `AsyncImage(model = uri, contentScale = ContentScale.Crop)` | 不要用 `Image(painter = rememberAsyncImagePainter(...))` 的旧写法，`AsyncImage` 支持占位/错误图 |
| 毛玻璃 | `BlurStyle.BACKGROUND_THIN` | `Modifier.blur(radius)`（API 31+）或 `RenderEffect` | API 26–30 降级成 `background + alpha` 伪毛玻璃，MVP 阶段不要硬上 |
| 长按拖拽排序 | `Grid.editMode + onItemDragStart/onItemDrop` | `LazyColumn` + `Modifier.draggable` + 第三方 `reorderable` 库，或官方 `DragAndDropModifier`（1.6+） | 1000 项衣橱默认不开拖拽（性能），进入"调整顺序"模式才开 |
| Emoji ≠ 图标 | 禁止 | 禁止 | 真实项目必须用 vector drawable 或 PNG |

---

## 六、Pink_House 专属资源缺口（与鸿蒙侧同构）

| 缺口 | 用途 | 来源 | Android 落地位置 |
|---|---|---|---|
| 浅粉水彩 + 国风园林底图 | 所有页面背景 | `temp/design` 切图或 iOS `WealthContainerBackground.imageset` | `app/src/main/res/drawable-nodpi/bg_*.webp`（WebP 比 PNG 省 60% 包体） |
| 橘猫陪伴（多姿态） | 底部悬浮、聊天主角 | iOS `maomao_*.imageset`、`happy_cat.imageset` | `res/drawable-xxhdpi/pet_*.webp` + 帧动画走 `AnimationDrawable` 或 Lottie |
| 商品/衣物图标 | 宠物商店 / 衣橱网格 | iOS `catFood`/`catRice` 等 + 真实衣物 imageUri | 商品用 `drawable-*`；衣物用户图走 Room + 私有目录 URI |
| 金币/银币/纸币 | 财富三段 | iOS `mcoin_*` | 金币动画用 Lottie 或 Compose 粒子，**不引入物理引擎**（PRD F-31） |

**硬规则**：所有色值 / 字号 / 圆角 / 阴影必须从 `core/ui/theme/PinkHouseTheme.kt` 的 token 取，不在 Composable 里硬编码 `0xFFFF69B4.toColor()` 或 `16.sp`。`MaterialTheme.colorScheme` / `MaterialTheme.typography` / 自定义 `LocalPinkTokens` 三级。

---

## 六点五、用户侧文案卫生（R6 配套）

复刻 SwiftUI 时要做的不只是搬布局/取色，**所有用户可见 string 必须复刻成 iOS 用户实际看到的产品文案**。开发侧术语任何一种漏到 UI 都算脏 PR：

| 禁出现在 user-visible string | 改用 |
|---|---|
| `BATCH-M3-04`、`BATCH-` 标识 | （删；只在文档/commit/PR title 出现） |
| `阶段 ARCH`、`阶段 M3` 等开发阶段 | （删） |
| `复刻`、`复刻中`、`已接入`、`待接入`、`下一批`、`后续`、`未完成`、`占位` | 写产品级标题/空状态文案，例如 "暂无公告" / "建设中" / "敬请期待" |
| 英文级别码（`WARNING` / `ERROR` / `CRITICAL`）直接渲染 | 中文等价文案，由本地化 string 资源提供 |
| PRD / 产品文档编号（`F-19` / `W-03`） | （删；只在 Task Card / 文档出现） |
| 文件路径、Composable 名字、Tab key | （删） |
| 硬编码 sample 公告 / 占位列表条目残留生产路径 | 真实数据源 + 产品级空状态 |

**Why**：[BATCH-UX-COPY-01A](../android/docs/PORT_BACKLOG.md) 已经因为通知中心样例公告 + House 菜单"复刻、已接入、下一批、后续"等内部文案进了用户 UI 而单独拉了一批清理——这是真实代价。要在写第一行 Composable 之前就避开。

**How to apply**：

1. 写 Composable 字面量前先定位 iOS 上同位置的 `Text("...")` / `LocalizedStringKey`，原文搬运。找不到对应文案的位置（比如新增的中间态、Android 独有的 Snackbar），用产品级降级文案，**绝不写"开发进度"**。
2. 凡是 `stringResource` / `pluralStringResource` / `string-array` 都要 round-trip 走 `res/values*/strings.xml`，不要在 Composable 里 inline 中文字面量。inline 字面量在 UX-COPY 清理时漏检率最高。
3. 提交前 grep（在新增/修改文件作用域内）：
   ```bash
   rg -n '"(.*?)(BATCH-|阶段 [A-Z]|复刻|占位|待接入|下一批|后续|未完成)' \
     android/app/src/main/java/com/pinkhouse/android/feature/<本批新文件>
   rg -n 'F-\d+|W-\d+' android/app/src/main/res/values*/<本批新 strings.xml>
   ```
   命中即同回合修，不允许带进 commit。
4. 装机截图（PORT_HARNESS G2）必须人工对照 iOS：进入同一页，逐区核对标题/按钮/空态/错误提示/通知/确认弹窗，发现夹带开发侧文字立即报告。
5. `@Preview` 内的占位字面量绝不复制到非 Preview 的 Composable；Preview 用 `@PreviewParameter` 或局部 `val previewData = ...`。

---

## 七、Android 专属坑（鸿蒙侧没有的）

1. **Min SDK 26 的底线**：PRD 要求兼容 HarmonyOS 3/4（AOSP 兼容层）。这意味着：
   - 任何 API 31+ 特性（`Modifier.blur`、`SplashScreen` 新 API、`DynamicColors` monet）都要 `if (Build.VERSION.SDK_INT >= 31) { ... } else { 降级 }`。
   - `DynamicColors` 彻底关掉：一是 PRD 要求粉色主题一致性，二是低版本没有。
2. **不接 GMS**：Firebase Crashlytics / Analytics / Messaging / Play Billing **全部禁止**，替换成：
   - 崩溃 → Bugly（腾讯）或 Sentry 自建实例（PRD 5.5）
   - 推送 → 系统 `NotificationManager` + `AlarmManager` 本地（PRD F-37）
   - 支付 → 微信支付 SDK + 支付宝 SDK，不走 Play Billing
3. **Scoped Storage**：Android 10+ 强制，用户图片必须走 `MediaStore` 或 App 私有目录 `context.filesDir`。不要用 `Environment.getExternalStorageDirectory()`。
4. **通知渠道**：Android 8+ 强制 `NotificationChannel`，PRD 已定义三条（`channel_deposit` / `channel_checkin` / `channel_pet`），每条必须在首次启动时注册。
5. **精准闹钟权限**：Android 12+ 的 `SCHEDULE_EXACT_ALARM` 是危险权限，尾款 T-3/T-1/T 提醒需要它；要补运行时请求，拒绝场景降级为 `setWindow`。
6. **冷启动 < 2.5s**（PRD 5.1）：Compose 首帧慢，必要时开 **Baseline Profile**。Room + Coil 首次 init 要在 `Application.onCreate` 里用协程后台预热。
7. **HarmonyOS 3/4 on APK 侧的坑**：华为设备跑 APK 时 `WindowInsets` 和 `statusBar` 偶尔返回 0，导航栏覆盖内容；要用 `WindowCompat.setDecorFitsSystemWindows(window, false)` + `Modifier.safeDrawingPadding()` 兜底。
8. **Room schema 版本管理**：`app/schemas/` 必须纳入 git（`exportSchema = true`）；schema 升级必须写 `Migration`，禁止 `fallbackToDestructiveMigration()`——鸿蒙 MVP 那条"DROP 重建老用户丢数据"教训在 Android 更严重（Android 用户基数大）。
9. **Compose Preview ≠ 真机**：`@Preview` 渲染跟真机行为能差 30% 常见（字体、主题、WindowInsets、Dialog）。每个页面至少一次装机验证才能交付。
10. **Gradle Sync 成本**：改 `build.gradle.kts` 的一轮单独交付，不要和业务 diff 混在一起。

---

## 八、工具优先级（Android 侧）

| 需要 | 工具 | 备注 |
|---|---|---|
| 看 iOS 真实交互 | `computer-use` 跑 Xcode Simulator 截图 | 需用户授权 Xcode + Simulator |
| 取色 | `Read` 工具读 `.png/.PNG`（支持图像），或 macOS Digital Color Meter | 鸿蒙同款 |
| Android API 查文档 | `WebFetch https://developer.android.com/**` | Compose API 官方 |
| Compose Material3 查组件 | `WebFetch https://developer.android.com/jetpack/compose/**` | 官方 |
| 编译反馈 | 用户 Android Studio Sync / `./gradlew :app:assembleDebug`，贴报错 | 和鸿蒙 DevEco 同构 |
| 预览 UI | `@Preview` 注解 + Android Studio 预览面板 | 注意与真机差异（第 7.9 条） |
| 真机/模拟器 | `adb` 装 Debug APK，或 Android Studio Run | 真机验证必做 |

---

## 九、里程碑节奏（对齐 PRD 第 7 节）

| 阶段 | 范围 | 本文档关注点 |
|---|---|---|
| **M1** 数据层 + 基础框架 | Room 建模、Compose 脚手架、主题/多语言 | §二命名规则、§四响应式、§六资源清单建立 |
| **M2** 衣橱核心 F-01~F-10 | 第一波大规模 SwiftUI → Compose 迁移 | §一工作流、§三 Modifier 陷阱高发期 |
| **M3** 宠物 + 小世界 F-11~F-25 | 帧动画、Lottie、拖拽交互 | §五组件级坑、§七第 6 条冷启动 |
| **M6** VIP + IAP F-32~F-35 | 微信/支付宝、幂等订单 | §七第 2 条 GMS 禁令 |
| **M9** 国内渠道打包 + 合规 | 隐私弹窗、Baseline Profile、多渠道 | §七第 6、7 条 |

---

## 十、下次改进清单（对齐鸿蒙的）

1. 写 Composable 前先把布局用注释 tree 画出来（对齐 SwiftUI body 顺序），让用户先 review 布局再开写。
2. 接 `@Preview` + 装机截图双验证再交付（Preview 一定会骗人）。
3. 把色值 / 字号 / 圆角 / 阴影放 `PinkHouseTheme` 单一真源，禁止 inline 硬编码（除非覆写特殊情况）。
4. 宠物陪伴层放进 `Scaffold` 的 Box overlay 先占位，素材到位再显示。
5. 每改 1 个页面 / 1 个共享 Composable 就让用户跑一次 `./gradlew :app:assembleDebug` + 真机，别堆积。
6. 每次 schema 变动强制写 `Migration` 并跑一次 "老数据 → 新版本" 本地脚本，避免 MVP 期 `fallbackToDestructiveMigration` 偷懒。
7. 每次新增权限先更新 `AndroidManifest.xml` + 隐私政策两处，合规弹窗必须同步。

---

## 十一、与其他文档的关系

- **上游 PRD**：`docs/migration/android/PRD.md`
- **工程初始化记录**：`docs/migration/android/ANDROID_PROJECT_BOOTSTRAP.md`
- **跨端产品规格**：`docs/migration/00_PRODUCT_SPEC_CROSS_PLATFORM.md`
- **鸿蒙对标笔记**：`docs/HARMONY_ARKUI_PORTING_NOTES.md`（本文档的原型）
- **衣橱迁移记录（Android 侧，待填）**：`android/docs/android_migration_wardrobe.md`
- **全局技能**：`~/.claude/skills/android-compose-port/SKILL.md`（启用时机 + 硬约束精简版）
