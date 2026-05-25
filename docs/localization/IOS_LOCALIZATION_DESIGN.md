# iOS 多语言设计文档

> 适用范围：Pink_House iOS App、Widget、App Store Connect 多地区发布。
> 日期：2026-05-25
> 状态：设计文档。本文只做调研与落地设计，未修改业务代码，未运行构建。
> 背景材料：`docs/IOS_LOCALIZATION_AND_GLOBAL_RELEASE_RESEARCH.md`

## 1. 结论摘要

1. 技术主线采用 Xcode String Catalog：`Localizable.xcstrings` 承接 App 内 UI、toast、错误、通知正文等用户可见文案。
2. `Info.plist` 用户可见字段独立本地化：权限说明、App 名、Widget 名必须进入 `InfoPlist.strings` 或 Xcode build setting 的等价本地化配置。
3. App 内语言和 App Store 商品页语言分开治理：binary localization 不等于 metadata localization，发布矩阵必须同时记录两者。
4. 当前工程已有语言选择入口，但实现还不是完整多语言：`LanguageManager` 只写 `AppleLanguages`，没有全局 `.environment(\.locale, ...)` 注入，也没有成体系的资源文件。
5. 首轮不要全球全语言铺开。建议先做 `zh-Hans` + `en` 的 P0 风险层，再扩 `zh-Hant`，最后评估日、韩、欧盟语言。
6. 任何用户输入、衣物名、品牌、标签、宠物昵称、手帐内容不翻译；只翻译 UI 外壳、系统提示、业务状态和固定文案。

## 2. 官方依据

Apple 官方当前口径：

- Xcode 15 及以后推荐使用 String Catalog 管理本地化字符串。
- Xcode localization export 会生成 `.xcloc`，并从 SwiftUI `Text`、`NSLocalizedString` 等 API 提取可本地化字符串。
- App Store metadata localizations 是独立于 App binary 的商品页元数据；新增 metadata 语言不会自动让 App 内支持该语言。
- App availability 可以选择全部或指定国家/地区；用户 Apple Account 的国家/地区决定其 App Store storefront。

参考链接：

- https://developer.apple.com/documentation/xcode/localization
- https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog
- https://developer.apple.com/documentation/xcode/exporting-localizations/
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/
- https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store
- https://developer.apple.com/documentation/appstoreconnectapi/app-info-localizations

## 3. 当前工程基线

### 3.1 资源与工程配置

本地复核结果：

- `ItemManager` 主 App 未发现 `.xcstrings`、`.strings`、`.stringsdict`、`InfoPlist.strings`、App 自有 `.lproj`。
- `ItemManager.xcodeproj/project.pbxproj`：
  - `developmentRegion = en`
  - `knownRegions = (en, Base)`
  - App target Debug/Release 均有 `SWIFT_EMIT_LOC_STRINGS = YES`
  - App target Debug/Release 均有 `STRING_CATALOG_GENERATE_SYMBOLS = YES`
  - Widget target 也打开了 `SWIFT_EMIT_LOC_STRINGS`
- `ItemManager/Info.plist`：
  - `CFBundleDevelopmentRegion = zh_CN`
  - `CFBundleLocalizations = [zh_CN]`
  - 权限说明均为中文硬编码
  - `NSAllowsArbitraryLoads = true`
  - `ITSAppUsesNonExemptEncryption = false`
- `ItemManager.xcodeproj/project.pbxproj` 里还存在 build setting 级中文：
  - `INFOPLIST_KEY_CFBundleDisplayName = "少女心愿"`
  - `INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "需要访问您的相册以选择裙装图片"`
  - Widget `INFOPLIST_KEY_CFBundleDisplayName = "少女心愿衣橱"`

主要风险：project 的 `developmentRegion = en` 与 `Info.plist` 的 `zh_CN` 不一致；后续应统一为 BCP-47 风格 locale 标识，首选 `zh-Hans` 和 `en`。

### 3.2 语言管理现状

当前 `ItemManager/Services/LanguageManager.swift`：

- 支持 `zh-Hans`、`zh-Hant`、`en` 三个枚举值。
- 语言变更时写入 `UserDefaults.standard["AppleLanguages"]`。
- 默认值是 `.simplifiedChinese`。

当前设置页入口：

- `ItemManager/Views/Settings/GeneralSettingsView.swift`
- `ItemManager/Views/Settings/Refactored/SystemSettingsView.swift`

现有缺口：

- 没有 App 根节点统一注入 `.environment(\.locale, Locale(identifier: currentLanguage.rawValue))`。
- 写 `AppleLanguages` 通常需要重启才能完整影响 Bundle 查找，当前 UI 也提示“需要重启”，但设计文档需要明确这是 P0 策略还是过渡策略。
- 语言入口在旧设置页和重构设置页重复，后续迁移时要保留一个 source of truth。
- `displayName` 目前固定为中文/英文混合展示，后续应区分“本语言名称”和“当前界面语言下的名称”。

### 3.3 中文硬编码基线

复核命令：

```bash
rg '"[^"]*[\p{Han}][^"]*"' ItemManager --glob '*.swift' --files-with-matches | wc -l
rg -n '"[^"]*[\p{Han}][^"]*"' ItemManager --glob '*.swift' --count-matches | sort -t: -k2,2nr | sed -n '1,30p'
```

结果：

- 含中文字符串字面量的 Swift 文件：337 个。
- 高频文件前列：
  - `ItemManager/Services/AI/ClothingSemanticAnalyzer.swift`
  - `ItemManager/Views/PetChat/PetChatCoreHelpers.swift`
  - `ItemManager/Services/AI/OutfitSuggestionService.swift`
  - `ItemManager/Views/Settings/TestEffectsView.swift`
  - `ItemManager/Views/PetChat/PetChatIntentRouter.swift`
  - `ItemManager/Services/NewbieGuide/NewbieGuideSteps.swift`
  - `ItemManager/Views/PetChat/PetChatView.swift`
  - `ItemManager/Views/ClothingDetailView.swift`
  - `ItemManager/Views/WardrobeView.swift`
  - `ItemManager/Views/VIP/VIPCenterView.swift`

额外发现：

- 多处日期格式、DatePicker、展示逻辑硬编码 `Locale(identifier: "zh_CN")` 或 `zh_Hans_CN`。
- `AudioManager` 中 `SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))` 固定中文，语音能力需要和 App 语言或用户选择分开设计。
- AI prompt、宠物口癖、语义分析同样包含大量中文，但不能简单机械翻译；需要单独 glossary 和 prompt 风格策略。

## 4. 设计目标

### 4.1 用户目标

- 用户能在设置中选择界面语言，并理解是否需要重启。
- 权限弹窗、购买、VIP、协议、通知、错误提示不出现混语或 key 泄漏。
- 日期、金额、数量、列表在不同地区显示符合本地习惯。
- 英文长文本不会挤爆按钮、底栏、弹窗和卡片。

### 4.2 工程目标

- 新增文案默认进入统一本地化资源，不再散落中文硬编码。
- 交易、法律、权限、通知等高风险文案有 stable key 和 translator comment。
- 导出/导入 localization 可往返。
- 语言矩阵、术语表、验收截图和 App Store metadata 可追踪。

### 4.3 非目标

- 不翻译用户创建的数据。
- 不在 P0 翻译全部 AI 自由生成内容。
- 不把所有历史注释、日志、调试文案纳入首轮迁移。
- 不为了本地化重构主题皮肤、IAP、AI 等业务架构。

## 5. Locale 策略

### 5.1 App 内语言

| 阶段 | App 内 locale | 用途 |
|---|---|---|
| P0 | `zh-Hans` | 简体中文主语言 |
| P0 | `en` | 英文质量基线和 W2 发布基础 |
| P1 | `zh-Hant` | 港澳台与繁中用户 |
| P2 | `ja`、`ko`、欧盟重点语言 | 视发布 wave 和翻译资源决定 |

### 5.2 标识统一

推荐统一使用：

- 简体中文：`zh-Hans`
- 繁体中文：`zh-Hant`
- 英文：`en`
- 英文美国 metadata：`en-US`
- 英文英国 metadata：`en-GB`

设计要求：

- 代码、String Catalog、App Store metadata、文档矩阵都使用同一套标识。
- 避免继续扩散 `zh_CN`、`zh_Hans_CN`。
- 对 Foundation 兼容场景，可在边界处把 `zh-Hans` 转为 Foundation 可接受的 locale identifier，但业务文档仍以 BCP-47 为准。

## 6. 资源设计

### 6.1 文件布局

建议：

```text
ItemManager/
├── Resources/
│   └── Localization/
│       └── Localizable.xcstrings
├── zh-Hans.lproj/
│   └── InfoPlist.strings
├── en.lproj/
│   └── InfoPlist.strings
└── zh-Hant.lproj/
    └── InfoPlist.strings
```

Widget 如需独立 App 名和权限文案，单独放入 Widget target 的 `InfoPlist.strings` 或明确共用策略。

### 6.2 Key 命名

命名格式：

```text
<domain>.<screen-or-feature>.<element>.<state>
```

示例：

```text
settings.language.title
settings.language.restart_required.message
permission.camera.reason
iap.meow_coin.purchase_success
vip.exchange.confirmation.title
notification.deposit.due.body
guide.ootd.step1.title
theme_skin.store.apply_success
```

必须使用 stable key：

- 权限说明
- IAP/VIP/支付/退款/余额
- 法律协议与联系入口
- 通知 title/body/action
- 错误码、toast、业务状态
- 新手引导步骤
- AI 免责声明和安全提示
- App Store metadata 源稿

允许短期中文原文作为 key：

- 低风险、低复用 SwiftUI 静态短文案。
- 迁移过渡期尚未纳入 P0/P1 的页面。

### 6.3 Translator Comment

所有高风险 key 必须有 comment：

- 说明显示位置。
- 说明变量含义。
- 说明产品口径，例如“VIP 是喵币兑换权益，不是自动续费订阅”。
- 说明不能翻译的品牌词、币种名、功能名。

## 7. 代码设计

### 7.1 LanguageManager

建议职责：

- 持久化用户选择。
- 暴露 `localeIdentifier`、`locale`、`requiresRestartForBundleStrings`。
- 提供“跟随系统”选项时，区分 `.system` 与具体语言。
- 不直接承担翻译查找逻辑。

建议枚举：

```swift
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
}
```

P0 可保守保持“切换后提示重启”。如果要即时切换 SwiftUI 文案，需要在 App 根节点注入：

```swift
.environment(\.locale, languageManager.locale)
```

但必须承认：Bundle 级 `NSLocalizedString`、Info.plist 权限弹窗、部分系统组件不会因为 SwiftUI environment 即时刷新，因此“完整生效需重启”仍应保留。

### 7.2 SwiftUI 文案

推荐：

```swift
Text("settings.language.title")
Button("common.done") { ... }
```

服务层或 ViewModel 需要 String：

```swift
String(
    localized: "iap.meow_coin.purchase_success",
    defaultValue: "Purchase successful",
    comment: "Shown after a consumable meow coin purchase succeeds."
)
```

跨层延迟求值：

```swift
LocalizedStringResource("notification.deposit.due.body")
```

禁止：

```swift
"还剩 " + String(days) + " 天"
Text("共 \(count) 件")
String(format: "¥%.2f", amount)
```

替代：

- 整句进入 String Catalog，变量用插值。
- 复数用 String Catalog plural variation。
- 日期、金额、百分比使用 Foundation `FormatStyle`。
- 列表使用 `ListFormatStyle` 或 locale-aware join。

### 7.3 日期、金额、数量

日期：

```swift
date.formatted(.dateTime.year().month().day().locale(languageManager.locale))
```

金额：

```swift
amount.formatted(.currency(code: currencyCode).locale(languageManager.locale))
```

数量：

- 不手写“件/个/条”拼接。
- 用 plural variation 表达 `item_count`。

### 7.4 语音识别

语音识别语言不应简单等于 UI 语言。

设计建议：

- P0：继续默认中文，但文档登记为限制。
- P1：新增“语音识别语言”设置，默认跟随界面语言，允许单独选择。
- P1：对不支持的 locale fallback 到 `zh-Hans` 或 `en`，并给用户可见提示。

### 7.5 AI 与宠物口癖

分三层处理：

| 层 | 策略 |
|---|---|
| 固定 UI | 进入 String Catalog |
| prompt 模板 | 用 locale 分支模板，不逐字翻译 |
| 模型生成正文 | 由 prompt 指定输出语言，保留用户原始输入 |

要求：

- prompt 中明确输出语言。
- glossary 固定核心词：喵币、鱼币、VIP、心愿尾款、萌宠、穿搭手帐。
- 安全、免责声明、付费提示必须使用固定本地化文案，不依赖模型生成。

## 8. 迁移分层

### P0：审核和交易保护层

范围：

- `Info.plist` 权限说明、App 名、Widget 名。
- IAP 喵币购买、退款、失败、恢复、Offer Code。
- VIP 喵币兑换、权益、非订阅说明、协议确认。
- 隐私、用户协议、会员协议、联系入口。
- 本地通知 title/body/action。
- 设置里的语言、隐私权限、系统设置、协议中心。

通过标准：

- `Localizable.xcstrings` 创建并加入 App target。
- `InfoPlist.strings` 覆盖 `zh-Hans` 和 `en`。
- `zh-Hans`、`en` 可构建、可启动、无 key 泄漏。
- P0 页面截图留档。

### P1：核心产品体验层

范围：

- 主 Tab、导航、搜索、空状态。
- 衣橱、编辑、详情、筛选。
- 财富/尾款/账本。
- OOTD/穿搭手帐。
- 新手引导。
- 宠物聊天固定 UI、AI 免责声明。

通过标准：

- `zh-Hans`、`zh-Hant`、`en` 主路径可完整使用。
- 英文长文本、小屏、iPad 无核心遮挡。
- `Text(String变量)`、toast、ViewModel 字符串有专项清单。

### P2：全球化体验层

范围：

- 主题商店、分享卡、含文字图片。
- 宠物口癖和 AI prompt 风格。
- 日、韩、欧盟重点语言。
- RTL 伪语言、动态字体、iPad polish。

通过标准：

- 目标语言截图验收。
- 含文字素材无明显残留中文。
- RTL 不破坏主流程。

## 9. App Store 发布设计

### 9.1 四条线分开

| 线 | 说明 |
|---|---|
| App availability | 哪些国家/地区可下载/购买 |
| Metadata localization | App Store 商品页语言 |
| Binary localization | App 内实际支持语言 |
| Legal/payment/compliance | 税务、IAP、年龄、加密、地区许可、隐私 |

### 9.2 推荐 wave

| Wave | 地区 | 建议 |
|---|---|---|
| W1 | 香港、澳门、台湾、新加坡、马来西亚 | 中文近场灰度 |
| W1 候选高风险 | 中国大陆 | 先确认 ICP、主体、分类、游戏/内容许可 |
| W2 | 美国、加拿大、英国、澳大利亚、新西兰 | 英文质量基线 |
| W3 | 日本、韩国 | 专项翻译和分级确认 |
| W4 | 欧盟重点地区 | 隐私、DSA、客服、语言质量稳定后进入 |
| W5 | 巴西、越南等 | 单独法务/税务/地区监管 owner |

### 9.3 Metadata 字段

每个 locale 至少准备：

- App Name
- Subtitle
- Description
- Keywords
- Promotional Text
- What’s New
- Privacy Policy URL
- Support URL
- Screenshots / App Preview
- IAP display name / description
- Review Notes 中的 VIP 和 IAP 说明

注意：Apple 支持的 App Store metadata 语言列表会变化，文档不要手写成长期静态真相；提交前以 App Store Connect 当前页面/API 为准。

## 10. 验收设计

### 10.1 技术验收

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"

xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet build

xcodebuild -exportLocalizations \
  -project ItemManager.xcodeproj \
  -localizationPath /private/tmp/pink-house-localization-export \
  -exportLanguage en

find ItemManager \( -name '*.plist' -o -name '*.strings' -o -name '*.stringsdict' -o -name '*.xcstrings' -o -name '*.xcprivacy' \) -print0 | xargs -0 plutil -lint
```

### 10.2 UI 验收

| 维度 | 范围 |
|---|---|
| 语言 | `zh-Hans`、`en`，P1 加 `zh-Hant` |
| 设备 | iPhone 16 Pro、iPhone SE、iPad |
| 权限 | 相册、相机、通知、麦克风、语音、定位 |
| 交易 | IAP、VIP、余额不足、购买成功/失败 |
| 通知 | title、body、action |
| 长文本 | 英文、伪长文本 |
| 截图 | P0/P1 核心路径留档 |

### 10.3 Gate

| 级别 | 阻断条件 |
|---|---|
| P0 | 构建失败、启动崩溃、IAP/VIP 口径错误、权限说明缺失或误导、隐私/年龄/出口合规未确认 |
| P1 | 核心页混语、按钮遮挡、key 泄漏、metadata/IAP localization 缺失、截图证据不足 |
| P2 | 非核心文案不顺、低频页混语、截图命名不统一 |

## 11. 产物目录

建议建立：

```text
docs/localization/
├── IOS_LOCALIZATION_DESIGN.md
├── LOCALE_MATRIX.md
├── GLOSSARY.md
├── STRING_AUDIT.md
├── UI_ACCEPTANCE_MATRIX.md
├── APP_STORE_CONNECT_CHECKLIST.md
├── app-store-metadata/
└── runs/<yyyy-mm-dd>/
    ├── RESULT.md
    └── screenshots-index.md
```

纳入 git：

- `docs/localization/**`
- 最终导入工程的 `.xcstrings`、`.strings`、`.stringsdict`
- 本地化后的 asset catalog 资源
- 验收 `RESULT.md` 和截图索引

默认不入库：

- `LocalizationExports/**`
- 完整 `.xcloc` / `.xliff` 往返包
- 原始截图大包
- App Store Connect 临时导出表

## 12. 下一步执行清单

1. 新建 `docs/localization/GLOSSARY.md`，固定喵币、鱼币、VIP、心愿尾款、萌宠、穿搭手帐等术语。
2. 新建 `docs/localization/LOCALE_MATRIX.md`，记录 App 内语言、metadata 语言和发布 wave。
3. 新建 `docs/localization/STRING_AUDIT.md`，把 337 个 Swift 文件按 P0/P1/P2 分类。
4. 第一轮代码实施只做 P0：String Catalog、InfoPlist、IAP、VIP、协议、通知、设置语言入口。
5. 第一轮验收只跑 `zh-Hans` 和 `en`，确认链路稳定后再扩 `zh-Hant`。

