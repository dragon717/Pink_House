# iOS 多语言与全球发布调研计划

> 适用范围：Pink_House iOS App、Widget、App Store Connect 发布准备。
> 仓库：`/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House`
> 更新时间：2026-05-25
> 状态：调研与计划文档。未修改业务代码，未运行构建，未登录 App Store Connect 后台。

## 1. 目标

1. 建立 Pink_House 的 iOS 多语言技术路线，避免后续只靠零散翻译补丁。
2. 把 Apple App Store 的国家/地区发布拆成可执行矩阵，而不是一次性全量开放。
3. 明确当前仓库的本地化、隐私、IAP、合规风险基线。
4. 定义实施后的验收 gate，让后续每轮多语言迁移都有可复查证据。

## 2. 子任务分工与验收结论

| 子任务 | 输出内容 | 验收结论 | 主代理修正 |
|---|---|---|---|
| Swift / Xcode 多语言技术迁移 | String Catalog、SwiftUI、本地化 API、分阶段路线 | 采纳 | `SWIFT_EMIT_LOC_STRINGS = YES` 已由本地复核确认；动态字符串、IAP、AI 话术列入专项风险 |
| App Store 国家/地区发布矩阵 | 国家/地区可用性、metadata、本体多语言、合规矩阵 | 采纳 | 中国大陆从“W1 默认首发”调整为“W1 候选但高风险”，需要 ICP/许可/分类确认 |
| 当前仓库现状审计 | 本地化资源、中文硬编码、合规文件、优先迁移文件 | 部分采纳 | 统计口径拆成“含中文行数”和“中文字符串字面量”；以本地复核的 337 个 Swift 文件作为字符串字面量基线 |
| 验收计划 | 技术验收、UI 验收、App Store Connect gate | 采纳 | `LocalizationExports/` 定义为临时产物，默认不入库；截图与结果摘要入 `docs/localization/` |

## 3. 当前仓库基线

### 3.1 本地化资源

本地复核命令：

```bash
find . -path './build' -prune -o -path './.build' -prune -o -path './harmony_next/build' -prune -o -name '*.lproj' -type d -print
rg --files -g '*.xcstrings' -g '*.strings' -g '*.stringsdict' -g '*InfoPlist*' -g '*Localizable*' -g '*.lproj/**' ItemManager ItemManager.xcodeproj ops docs
rg -n "SWIFT_EMIT_LOC_STRINGS|developmentRegion|knownRegions|INFOPLIST_FILE|CFBundleDisplayName|NSPhotoLibraryUsageDescription" ItemManager.xcodeproj/project.pbxproj ItemManager/Info.plist
plutil -p ItemManager/Info.plist
```

结果：

1. 主 App 未发现 `.xcstrings`、`.strings`、`.stringsdict`、`InfoPlist.strings`、App 自有 `.lproj`。
2. 仓库中发现的 `.lproj` 仅在 `code/ScanningObjectsUsingObjectCapture/...` 示例目录，不属于主 App 资源。
3. `ItemManager.xcodeproj/project.pbxproj` 的项目级配置为 `developmentRegion = en`，`knownRegions = (en, Base)`。
4. `ItemManager/Info.plist` 写入 `CFBundleDevelopmentRegion = zh_CN`，`CFBundleLocalizations = [zh_CN]`。
5. App target Debug / Release 均有 `SWIFT_EMIT_LOC_STRINGS = YES` 和 `STRING_CATALOG_GENERATE_SYMBOLS = YES`，但当前没有 String Catalog 承接资源。
6. Widget target 也有 `SWIFT_EMIT_LOC_STRINGS = YES`，并使用中文 `INFOPLIST_KEY_CFBundleDisplayName = "少女心愿衣橱"`。

关键文件：

- `ItemManager.xcodeproj/project.pbxproj`
- `ItemManager/Info.plist`
- `ItemManager/Services/LanguageManager.swift`

### 3.2 中文硬编码分布

存在两种统计口径：

1. 中文字符串字面量扫描：`rg "\"[^\"]*[\p{Han}][^\"]*\"" ItemManager --glob '*.swift' --count-matches`
   - 含中文字符串字面量的 Swift 文件：337 个。
   - 典型高频模块：`PetChat`、`AI/OutfitSuggestionService`、`ClothingSemanticAnalyzer`、新手引导、IAP、设置、通知。
2. 任意中文字符行扫描：`rg -n -P "[\p{Han}]" ItemManager --glob '*.swift'`
   - 覆盖代码、注释、日志、文案、prompt，口径更宽。
   - 子任务扫描曾得到约 18,845 行、409 个 Swift 文件，适合作为“大体量中文资产”警示，不适合作为迁移任务量精确值。

后续迁移时必须把中文内容分层：

| 层级 | 是否 P0 迁移 | 示例 |
|---|---|---|
| 用户可见交易/权限/法律文案 | 是 | IAP、VIP、权限弹窗、隐私协议、通知 |
| 用户可见主流程 UI | 是，P1 完成 | 底栏、设置、衣橱、财富、手帐、空状态 |
| AI prompt / 角色语气 / 宠物口癖 | 分阶段 | 先迁系统提示和结构化 UI，不机械翻译生成正文 |
| 用户自定义内容 | 否 | 衣服名、品牌、标签、宠物昵称、手帐标题 |
| 开发日志/注释 | 否，后置 | `print`、调试注释、内部诊断 |

### 3.3 发布合规相关现状

1. `ItemManager/Info.plist` 目前直接写中文权限说明：
   - 相机、定位、麦克风、运动、相册写入、相册读取、语音识别、世界感知。
   - 这些必须进入 `InfoPlist.strings` 或等价本地化策略。
2. `ItemManager/Info.plist` 中 `NSAllowsArbitraryLoads = true`，后续需要确认能否收敛为特定域名例外。
3. `ItemManager/Info.plist` 中 `ITSAppUsesNonExemptEncryption = false`，但 App 使用 HTTPS、CloudKit、AI 服务时仍需和 App Store Connect 出口合规问卷口径一致。
4. `ItemManager/PrivacyInfo.xcprivacy` 中：
   - `NSPrivacyTracking = true`。
   - 文件里 `NSPrivacyTrackingDomains` 出现两次，`plutil` 解析后最终保留 AI 域名列表：`api.deepseek.com`、`api.minimaxi.com`、`dashscope.aliyuncs.com`。
   - 需要确认这是否真是 Apple 定义下的 tracking，而不是把 AI 服务域名误放到 tracking domains。
5. 协议与联系入口集中在 `ItemManager/Utilities/SharedTypes.swift`，线上协议站点在 `ops/legal-site/`。
6. IAP 商品定义在 `ItemManager/Services/IAP/IAPProduct.swift`，当前为 6 个 consumable 喵币档位，并包含 offer code 兑换逻辑。
7. VIP 是喵币兑换型权益，不是自动续费订阅。这个口径必须在 App 内、协议、IAP 页面、App Review Notes 中一致。

## 4. 官方技术路线

### 4.1 推荐技术栈

| 能力 | 推荐方案 | 使用边界 |
|---|---|---|
| App 内 UI 文案 | `Localizable.xcstrings` | 主字符串资产，覆盖按钮、标题、空状态、弹窗、错误、引导、通知 |
| SwiftUI 字面量 | `Text("...")` / `LocalizedStringKey` | 静态短文案可先让 Xcode 提取；跨模块、含业务语义时改 stable key |
| 服务层字符串 | `String(localized:defaultValue:comment:)` | 通知、ViewModel、Manager、错误信息、toast 等最终需要 `String` 的场景 |
| 跨层延迟求值 | `LocalizedStringResource` | 自定义组件参数、模型层、App Intents、异步任务 |
| 数字/日期/货币 | Foundation `FormatStyle` | 日期、时间、金额、百分比、列表，不手拼格式 |
| 权限和 App 名 | `InfoPlist.strings` | `NS*UsageDescription`、`CFBundleDisplayName` 等用户可见 Info.plist 字段 |
| 图片/资源本地化 | Asset Catalog localization | 含文字图片、文化相关图、方向相关图标、主题商店预览 |

Apple 官方参考：

- [Xcode Localization](https://developer.apple.com/documentation/xcode/localization)
- [Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [LocalizedStringResource](https://developer.apple.com/documentation/foundation/localizedstringresource)
- [LocalizedStringKey](https://developer.apple.com/documentation/swiftui/localizedstringkey)
- [FormatStyle](https://developer.apple.com/documentation/foundation/formatstyle)
- [Localizing assets in a catalog](https://developer.apple.com/documentation/xcode/localizing-assets-in-a-catalog)

### 4.2 Stable key 策略

允许短期保留中文原文作为 key 的场景：

1. SwiftUI 静态短文案。
2. 临时迁移阶段的低风险页面。
3. 不参与跨模块复用、不会被外包翻译长期维护的文案。

必须使用 stable key 的场景：

1. 权限说明：`permission.camera.reason`。
2. 通知：`notification.deposit.due.body`。
3. IAP / VIP：`iap.meow_coin.purchase_success`、`vip.exchange.confirmation`。
4. 法律协议：`legal.privacy.title`、`legal.vip_agreement.title`。
5. 设置项：`settings.system.language.title`。
6. 错误码和业务状态：`cloud.restore.no_backup`。
7. 新手引导步骤：`guide.ootd.step1.title`。
8. 主题商品和商店文案：`theme_skin.store.apply_success`。

### 4.3 动态字符串准则

禁止：

```swift
"还剩 " + String(days) + " 天"
Text("共 \(count) 件")
String(format: "¥%.2f", amount)
```

推荐：

1. 把整句作为一个本地化单元，使用插值和 translator comment。
2. 数量用 String Catalog plural variation。
3. 金额用业务货币 code + `FormatStyle`。
4. 日期/时间用 `.formatted(...)` 或 SwiftUI `Text(date, format:)`。
5. 不翻译用户输入内容，只翻译外围说明。

## 5. 分阶段迁移路线

### P0：发布与审核保护层

目标：先把上架、支付、权限、隐私、通知这些高风险文案从中文硬编码中剥出来。

| 模块 | 范围 | 关键文件 |
|---|---|---|
| Info.plist 权限 | `NS*UsageDescription`、App 名、Widget 名 | `ItemManager/Info.plist`、`少女心愿衣橱/Info.plist` |
| IAP / StoreKit | 喵币、Offer Code、购买成功/失败、退款说明、余额不足 | `ItemManager/Views/IAP/MeowCoinStoreView.swift`、`ItemManager/Services/IAP/*` |
| VIP | 喵币兑换、非订阅、权益、协议确认 | `ItemManager/Views/VIP/VIPCenterView.swift`、`ItemManager/Services/VIP/VIPManager.swift` |
| 法律入口 | 隐私政策、用户协议、会员协议、联系入口 | `ItemManager/Utilities/SharedTypes.swift`、`ops/legal-site/` |
| 通知 | 本地通知 title/body/action | `ItemManager/Services/NotificationManager.swift` |
| 设置基础页 | 语言、隐私权限、备份恢复、系统设置 | `ItemManager/Views/Settings/Refactored/SystemSettingsView.swift` |

P0 完成标准：

1. 创建并入包 `Localizable.xcstrings`。
2. 创建 `InfoPlist.strings` 或明确替代策略。
3. 中英文至少覆盖 P0 文案。
4. `plutil -lint` 通过。
5. `xcodebuild -scheme ItemManager ... build` 通过。
6. IAP 页面、权限弹窗、通知、协议入口有截图或运行证据。

### P1：核心产品体验层

目标：保证 App 主路径在首发语言下可完整使用。

| 模块 | 范围 |
|---|---|
| 底栏/导航 | `MainTabView`、功能名、导航标题、搜索、入口文案 |
| 衣橱/筛选/编辑 | 卡片、筛选、批量编辑、空状态、错误 |
| 财富/尾款 | 金额、统计、尾款、账本、提醒 |
| 手帐/OOTD | 书架、画布、分享、导出 |
| 新手引导 | 标题、步骤、toast、跨页面提示 |
| AI / 萌宠聊天固定 UI | 按钮、菜单、卡片、系统提示、免责声明、fallback |

P1 完成标准：

1. 简中、英文跑通核心主流程。
2. 伪本地化 Double-Length 无核心按钮遮挡。
3. `Text(String变量)`、通知正文、toast 等非自动提取点有专项清单。
4. App Store metadata 英文源稿可与 App 内术语对齐。

### P2：长尾与全球化体验层

目标：提高海外质量，处理语言风格、素材和地区差异。

| 模块 | 范围 |
|---|---|
| 主题皮肤 | 主题名、slot 名、商店预览、购买说明、素材本地化 |
| 宠物口癖/角色 | 角色语气、情绪反馈、AI prompt 风格 |
| 拼豆/大世界/空间 | 低频工具页、导出、错误和空状态 |
| 分享卡/图片 | 有文字图片、多语言截图、Asset Catalog 变体 |
| RTL / iPad / 小屏 | 方向、布局、动态字体、长文本 |

P2 完成标准：

1. 目标二线语言通过截图验收。
2. 含文字素材不存在明显残留中文。
3. RTL 伪语言不会破坏主流程。
4. 翻译 glossary 和品牌语气文档稳定。

## 6. App Store 国家/地区发布矩阵

### 6.1 四条线分开判断

| 线 | 判断问题 | 查证入口 |
|---|---|---|
| App Store 国家/地区可用性 | 用户能否在该 storefront 下载或购买 | App Store Connect availability |
| App Store metadata localization | 商品页名称、副标题、描述、关键词、截图、隐私 URL 是否本地化 | App Store Connect app information |
| App binary localization | App 内字符串、权限、IAP、通知、资源是否支持该语言 | Xcode localization |
| 法律/支付/税务/内容可用性 | 是否满足税务、IAP、年龄、加密、内容权利、地区许可 | App Store Connect compliance / business |

Apple 官方参考：

- [Manage availability for your app on the App Store](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/)
- [Localize app information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information/)
- [App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)

### 6.2 推荐 launch waves

| Wave | 区域 | 建议 | 原因 |
|---|---|---|---|
| W1 中文近场 | 香港、澳门、台湾、新加坡、马来西亚，中国大陆作为候选高风险项 | 先做中文近场灰度 | 繁中/简中/英文组合可覆盖；中国大陆需额外确认 ICP、内容分类、许可和主体信息 |
| W2 英语基线 | 美国、加拿大、英国、澳大利亚、新西兰 | 建立全球默认英文质量线 | 英文 metadata、客服、IAP、隐私表达可复用到更多地区 |
| W3 日韩 | 日本、韩国 | 第二波专项 | 消费能力强，但翻译质量、本地客服、韩国分级/监管需确认 |
| W4 欧盟 | 德国、法国、意大利、西班牙、荷兰、爱尔兰等 | 隐私合规稳定后进入 | GDPR/DSA、客服展示、隐私解释、语言本地化要求更高 |
| W5 专项高风险地区 | 巴西、越南等 | 单独 owner 确认 | 税务、游戏许可、地区监管可能导致 blocked |

### 6.3 发布矩阵字段

| 字段 | 用途 |
|---|---|
| `storefront` / `storefront_name` | Apple storefront 或国家/地区名称 |
| `launch_wave` | W1/W2/W3/W4/W5 |
| `availability_decision` | Available / Not Available / Wait Legal / Blocked |
| `metadata_languages` | App Store 商品页语言 |
| `binary_languages` | App 内实际支持语言 |
| `screenshots_previews` | 截图和 App Preview 覆盖 |
| `price_tax` | 价格、税务、Paid Apps Agreement、银行/税表 |
| `iap_availability` | IAP/offer code 在该地区是否可售 |
| `iap_localization` | IAP display name / description / review screenshot |
| `privacy` | 隐私政策 URL、数据标签、SDK、账号删除 |
| `age_rating` | 全球年龄问卷和地区分级 |
| `export_encryption` | 加密问卷、文档、Info.plist 口径 |
| `content_rights` | 字体、主题、AI 图、音乐、第三方素材授权 |
| `regional_permits` | ICP、版号、DSA、GRAC、越南游戏许可等 |
| `review_notes` | 测试账号、IAP/VIP 说明、权限说明 |
| `support` | 客服语言、Support URL、退款和隐私请求流程 |
| `risk_level` | Low / Medium / High / Blocked |
| `owner` | Product / Legal / Finance / iOS / Localization / Support |
| `last_checked` | 最近确认日期 |

### 6.4 App Store Connect 人工确认清单

1. Privacy Policy URL 是否覆盖目标语言，并说明 CloudKit、IAP、AI、数据删除。
2. Support URL 是否可公开访问，至少中文/英文可用。
3. 6 个喵币 IAP 商品是否有本地化名称、描述、审核截图、审核备注。
4. App screenshot / preview 是否与目标 storefront 语言匹配。
5. 年龄问卷是否重新确认宠物、虚拟货币、AI/聊天、外链、购买等选项。
6. 出口合规问卷是否与 `ITSAppUsesNonExemptEncryption` 和实际网络/云同步行为一致。
7. Paid Apps Agreement、银行信息、美国税表、区域税务是否完成。
8. App availability 和 IAP availability 是否一致。
9. Review Notes 是否明确 VIP 为喵币兑换型权益，非自动续费订阅。
10. 中国大陆、韩国、欧盟、巴西、越南等是否有地区专项 owner。

## 7. 高优先迁移文件

| 优先级 | 文件 | 原因 |
|---|---|---|
| P0 | `ItemManager/Info.plist` | 权限文案、ATS、加密、本地化区域配置 |
| P0 | `ItemManager/PrivacyInfo.xcprivacy` | tracking、AI 域名、隐私标签一致性 |
| P0 | `ItemManager/Views/IAP/MeowCoinStoreView.swift` | 购买、退款、协议、优惠码、错误提示 |
| P0 | `ItemManager/Services/IAP/IAPProduct.swift` | 商品 ID、档位、首充、Offer Code 成功文案 |
| P0 | `ItemManager/Views/VIP/VIPCenterView.swift` | VIP 兑换、协议确认、权益解释 |
| P0 | `ItemManager/Services/VIP/VIPManager.swift` | VIP 计划、价格、成功/失败消息 |
| P0 | `ItemManager/Utilities/SharedTypes.swift` | LegalLinks、备案、版权、联系信息 |
| P1 | `ItemManager/Views/Settings/Refactored/SystemSettingsView.swift` | 语言、隐私权限、协议中心、系统设置 |
| P1 | `ItemManager/Services/NotificationManager.swift` | 通知 title/body/action |
| P1 | `ItemManager/Services/NewbieGuide/NewbieGuideSteps.swift` | 新手引导步骤集中 |
| P1 | `ItemManager/Services/NewbieGuideManager.swift` | 引导、奖励、状态提示 |
| P1 | `ItemManager/Views/PetChat/PetChatView.swift` | 宠物聊天、充值、VIP 升级、互动文案 |

## 8. 验收计划

### 8.1 技术验收

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"

xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet build

xcodebuild -exportLocalizations \
  -project ItemManager.xcodeproj \
  -localizationPath /private/tmp/pink-house-localization-export \
  -exportLanguage en

xcodebuild -importLocalizations \
  -project ItemManager.xcodeproj \
  -localizationPath "<translated-localization-file-or-catalog>"

find ItemManager \( -name '*.plist' -o -name '*.strings' -o -name '*.stringsdict' -o -name '*.xcstrings' -o -name '*.xcprivacy' \) -print0 | xargs -0 plutil -lint
```

验收点：

1. 构建通过并记录命令、Xcode 版本、模拟器版本。
2. export/import localization 可往返。
3. `Localizable.xcstrings` 不存在未解释的 `New`、`Needs Review`、`Stale`、空翻译、占位符损坏。
4. `InfoPlist.strings`、`.stringsdict`、`.xcstrings`、`PrivacyInfo.xcprivacy` 语法有效。
5. 代码中的中文硬编码有白名单或迁移计划。

### 8.2 UI 验收

| 维度 | 必测范围 | 通过标准 |
|---|---|---|
| 语言 | `zh-Hans`、`zh-Hant`、`en-US`、`ja-JP` | 核心页无混语、无 key 泄漏 |
| 长文本 | 英文、日文、Double-Length 伪语言 | 不遮挡金额/按钮/图标 |
| RTL | Right-to-Left 伪语言 | 布局不破主流程，不误镜像服装/品牌/插画 |
| 设备 | iPhone 16 Pro、iPhone SE、iPad | 小屏按钮、底栏、弹窗、iPad 宽度正常 |
| 系统弹窗 | 相册、通知、相机、麦克风、语音、定位 | 权限理由本地化且真实 |
| 通知 | 本地通知、通知动作 | title/body/action 本地化 |
| 截图 | 每个目标语言核心流程 | 记录语言、设备、系统版本、构建号 |

### 8.3 App Store Connect 验收

1. Metadata localization：App Name、Subtitle、Description、Keywords、Promotional Text、What's New、Privacy Policy URL、截图/App Preview。
2. IAP 商品：Display Name、Description、价格、可用国家、审核截图、审核备注、状态。
3. 隐私标签：App Privacy、`PrivacyInfo.xcprivacy`、权限弹窗、实际数据采集一致。
4. 年龄分级：AI/聊天、虚拟货币、购买、外链、UGC 等问卷答案复核。
5. 出口合规：加密使用、Info.plist、App Store Connect 问卷一致。
6. 价格/税务/可用国家：Paid Apps Agreement、税务类别、App 与 IAP 可用国家一致。

### 8.4 发布 Gate

| 级别 | 定义 | Gate |
|---|---|---|
| P0 | 构建失败、启动崩溃、IAP 无法购买/发放、权限弹窗缺失或误导、隐私/出口/年龄未确认、目标语言大量缺失 | 禁止外部 TestFlight，禁止提交审核，禁止全球发布 |
| P1 | 核心页面混语、长文本遮挡、RTL 破坏主流程、App Store/IAP metadata 缺失、截图证据不足 | 可内部验证，禁止全球发布，可缩小国家/语言灰度 |
| P2 | 非核心页面文案不顺、截图命名不统一、少量 UI polish | 可发布，但必须登记 owner、截止日期和回归方式 |

## 9. 推荐产物目录

```text
docs/localization/
├── README.md
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

建议纳入 git：

1. `docs/localization/**`
2. 最终导入工程的 `.xcstrings`、`.strings`、`.stringsdict`、`InfoPlist.strings`
3. 本地化后的 asset catalog 资源
4. 验收 `RESULT.md` 和截图索引

建议默认不入库：

1. `LocalizationExports/**`
2. 完整 `.xcloc` / `.xliff` 往返包
3. 原始截图大包
4. App Store Connect 临时导出表

如需审计留档，提交 hash、摘要、语言矩阵和结果索引，大文件放外部归档或 Git LFS。

## 10. 未决问题

1. 主语言资源目录使用 `zh-Hans` 还是继续沿用 `zh_CN`，需要和 App Store metadata、Xcode `developmentRegion` 统一。
2. 是否创建 `Localizable.xcstrings` 与 `InfoPlist.strings`，还是先保守使用传统 `.strings`。建议主线采用 String Catalog。
3. `NSAllowsArbitraryLoads = true` 是否仍有必要。
4. `NSPrivacyTracking = true` 是否符合实际业务，AI 域名是否应作为 tracking domains。
5. 麦克风、语音识别、定位、运动、世界感知权限是否都有当前可达功能入口。
6. 线上协议内容、日期、备案号、主体名称是否与 App Store Connect 元数据一致。
7. VIP “喵币兑换型权益、非订阅、非自动续费”的表达是否在 App 内、协议、商店页、审核备注中完全一致。
8. 6 个 IAP 商品 ID、价格、展示文案、Offer Code 规则是否与 App Store Connect 当前配置一致。
9. Pink_House 在各国家/地区是否会被归类为 game，以及这对中国大陆、韩国、越南、年龄分级的影响。
10. 英文、繁中、日文的品牌语气、宠物口癖、AI prompt 是否需要人工翻译规范和 glossary。

## 11. 下一步建议

1. 建 `docs/localization/LOCALE_MATRIX.md`，先列 W1/W2 候选地区与语言决策。
2. 建 `docs/localization/GLOSSARY.md`，固定“喵币、鱼币、VIP、心愿尾款、萌宠、穿搭手帐”等术语。
3. 建 `docs/localization/STRING_AUDIT.md`，用脚本生成 P0/P1 文件迁移清单。
4. 第一轮代码只做 P0：`Localizable.xcstrings`、`InfoPlist.strings`、IAP/VIP/协议/通知。
5. 第一轮验收只跑简中和英文，确认框架可用后再扩繁中、日文。
