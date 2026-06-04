# 多语言文本审计与验收记录

> 日期：2026-06-04
> 范围：Pink_House iOS 主 App、Widget、本地化资源、用户可见 SwiftUI/服务层文案。
> 方式：主代理本地静态扫描 + 3 个 subagent 只读分区审计。

## 1. 当前结论

1. 主 App 当前声明 9 个 locale：`en`、`zh-Hans`、`zh-Hant`、`ja`、`ko`、`fr`、`de`、`es`、`pt-BR`。
2. 当前真实完成线仍应按 `en`、`zh-Hans`、`zh-Hant` 管理。新增 6 个 locale 已开放入口和部分资源，但不是完整翻译完成。
3. `String.appLocalized` 是现阶段统一入口，定义在 `ItemManager/Services/LanguageManager.swift`。App 根节点已经注入 `.environment(\.locale, languageManager.locale)`。
4. `Localizable.xcstrings` 当前有 3090 个 key：`en`、`zh-Hans`、`zh-Hant` 全覆盖；`ja`、`ko`、`fr`、`de`、`es`、`pt-BR` 各缺 1744 个 key。
5. 主 App `InfoPlist.strings` 9 个 `.lproj` 都存在；其中 `de`、`es`、`fr`、`ja`、`ko`、`pt-BR` 权限文案当前复用英文，需要按 P2 全球化阶段补齐。
6. Widget 本地化落后于主 App，目前只看到 `en`、`zh-Hans`、`zh-Hant` 覆盖。
7. `Localizable.xcstrings` 有大量 `stale` key。后续清理 stale 前必须先确认是否仍被动态 `.appLocalized`、通知、服务层或旧页面引用，不能机械删除。

## 2. 本轮验证命令

```bash
ruby -rjson -e 'JSON.parse(File.read("ItemManager/Resources/Localization/Localizable.xcstrings")); puts "JSON OK"'
find ItemManager -name '*.lproj' -type d -maxdepth 3 -print
rg -n "developmentRegion|knownRegions|SWIFT_EMIT_LOC_STRINGS|STRING_CATALOG_GENERATE_SYMBOLS" ItemManager.xcodeproj/project.pbxproj
python3 tools/localization/audit_swift_literals.py ItemManager/Views/PetChat/PetChatViewLegacy.swift --show candidate
```

说明：`plutil -lint` 对当前 `.xcstrings` JSON 文件会报 `Unexpected character { at line 1`，本轮使用 Ruby JSON parse 校验 catalog 结构。后续验收脚本应把 `.xcstrings` 和 `.strings` 分开校验。

## 3. 覆盖统计

| 项目 | 当前结果 |
|---|---:|
| `Localizable.xcstrings` key 总数 | 3090 |
| `en` 缺失 | 0 |
| `zh-Hans` 缺失 | 0 |
| `zh-Hant` 缺失 | 0 |
| `ja` 缺失 | 1744 |
| `ko` 缺失 | 1744 |
| `fr` 缺失 | 1744 |
| `de` 缺失 | 1744 |
| `es` 缺失 | 1744 |
| `pt-BR` 缺失 | 1744 |
| 全 9 语言都有值的 key | 1346 |
| 至少一个语言缺值的 key | 1744 |

## 4. Subagent 分工与结论

| Subagent | 分工 | 结论 |
|---|---|---|
| Archimedes | 资源与文档审计 | 9 个 locale 已声明；`en/zh-Hans/zh-Hant` 资源完整，新增 6 语言仅部分覆盖；Widget 和 InfoPlist 非英语翻译需后续补齐；文档中的旧基线需按当前状态更新。 |
| Hypatia | SwiftUI 视图层审计 | 视图层仍有大量未走 `.appLocalized` 的候选。高优先级集中在新手引导、Me/iCloud、Notice、OOTD cutout、拼豆、同步状态共享组件。 |
| Huygens | 服务/模型层审计 | 服务层用户可见错误、toast、通知、引导、IAP/登录/备份恢复仍有硬编码风险。尾款通知主流程已 9 语言覆盖完整。 |

## 5. 高优先级风险池

### P1 主路径和高影响操作

| 模块 | 代表文件 | 风险 |
|---|---|---|
| 新手引导 | `ItemManager/Services/NewbieGuide/*` | 首次启动、跨页面引导、跳过确认、下一步提示仍有多处中文直出。 |
| Me/iCloud/备份恢复 | `ItemManager/Views/MeView.swift`、`ItemManager/Services/BackupService.swift`、`ItemManager/Services/CloudSyncManager.swift` | 恢复覆盖、导入结果、iCloud 错误、同步设置变更属于高影响用户操作。 |
| Notice | `ItemManager/Views/Notice/*`、`ItemManager/Services/NoticeService.swift` | 用户公告按钮、管理员表单、公告状态和动作校验多处硬编码；公告 `locale` 字段尚未形成显示过滤策略。 |
| OOTD cutout | `ItemManager/Views/OOTD/OOTDCutoutListView.swift` | 搜索、删除确认、插值按钮需格式化 key。 |
| 拼豆 | `ItemManager/Views/PerlerBeads*` | 功能首页、搜索、批量删除、空态仍需统一本地化。 |
| Object Capture | `ItemManager/Services/ObjectCaptureService.swift` | 设备不支持、准备进度、失败/完成状态会直接展示。 |
| 奖励与打卡 | `ItemManager/Services/RewardManager.swift`、`ItemManager/Services/DailyCheckInManager.swift` | reward publisher、打卡成功/失败、天气失败提示有中文直出。 |
| 登录/IAP 服务层 | `ItemManager/Services/AuthenticationManager.swift`、`ItemManager/Services/IAP/IAPServerManager.swift` | 登录错误、余额不足、未知商品类型等会进入 UI。 |

### P2 全球扩展

| 模块 | 风险 |
|---|---|
| `ja/ko/fr/de/es/pt-BR` catalog | 1744 个 key 缺翻译，当前依赖英文 fallback。 |
| 非英语 `InfoPlist.strings` | 权限弹窗仍是英文，全球发布前需本地化。 |
| Widget | 语言覆盖落后主 App。 |
| App Store/IAP metadata | binary localization 不等于商品页和 IAP 展示名本地化。 |
| 金额、日期、语音、AI prompt | 需要独立 locale/formatter/prompt 策略，不能和静态 UI 文案混改。 |

## 6. 验收口径

每个代码小阶段提交前执行：

1. `git diff --check`
2. 对触达文件运行 `python3 tools/localization/audit_swift_literals.py <files> --show candidate`
3. 校验 `Localizable.xcstrings` JSON 可解析
4. 对 `.strings` 文件运行 `plutil -lint`
5. 运行 `xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /private/tmp/pink-house-build-<stage> -clonedSourcePackagesDirPath build/SourcePackages -quiet build`
6. UI 文案阶段需要安装、terminate、launch 到同一模拟器后再用 Computer Use 读取关键页面

文档或只读审计阶段可以不跑模拟器，但必须说明未覆盖构建和 UI 观察。

## 7. 下一阶段建议

1. 先提交本审计文档，作为调研与验收口径阶段。
2. 单独处理当前已暂存的 `PetChatViewLegacy.swift` 菜单按钮本地化切片，确认资源配套和构建后提交。
3. 下一批代码修复建议优先选择一个窄范围高收益模块：`NewbieGuide` 或 `Me/iCloud`，不要一次性混改 Notice、OOTD、拼豆和服务层。
4. 后续新增 `LOCALE_MATRIX.md`、`STRING_AUDIT.md`、`UI_ACCEPTANCE_MATRIX.md` 时，应以本文件统计作为 2026-06-04 基线。
