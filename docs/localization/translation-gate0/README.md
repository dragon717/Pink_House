# Gate-0 翻译包交付说明

> P0 模块：IAP / VIP / 权限 / 法律 / 通知 / 设置  
> 目标语言：en、zh-Hans、zh-Hant（完整）；ja/ko/fr/de/es/pt-BR（InfoPlist 六语模板）  
> 更新：2026-07-03

---

## 1. 字符串资源基线

| 资产 | 路径 | Keys | 缺口 |
|------|------|------|------|
| 主 App String Catalog | `ItemManager/Resources/Localization/Localizable.xcstrings` | ~3305 | en/zh-Hans/zh-Hant 各 ~20；扩展六语各 ~1467 |
| InfoPlist | `ItemManager/{locale}.lproj/InfoPlist.strings` | 9 权限 + 显示名 | ja–pt-BR 现为英文副本 |
| Widget | `少女心愿衣橱/Localizable.xcstrings` | 小 | 仅 3 语 |

---

## 2. 导出命令（实施阶段 Import 前执行）

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"
EXPORT="/private/tmp/pink-house-localization-export-$(date +%Y%m%d)"
mkdir -p "$EXPORT"

# 导出 Xcode 本地化包（含 String Catalog）
xcodebuild -exportLocalizations \
  -project ItemManager.xcodeproj \
  -localizationPath "$EXPORT" \
  -exportLanguage en

# 语法检查
find ItemManager \( -name '*.xcstrings' -o -name '*.strings' \) -print0 | xargs -0 plutil -lint
```

**注意**：`LocalizationExports/` 与 `/private/tmp/` 导出物 **不入库**；译后通过 Import 或手动合并进 `Localizable.xcstrings`。

Import：

```bash
xcodebuild -importLocalizations \
  -project ItemManager.xcodeproj \
  -localizationPath "<translated.xcloc-or-catalog>"
```

---

## 3. Gate-0 范围（P0 模块文件清单）

翻译优先级 P0 — 必须 en + zh-Hant + zh-Hans 无混语：

| 模块 | 文件 |
|------|------|
| IAP | `ItemManager/Views/IAP/MeowCoinStoreView.swift`, `ItemManager/Services/IAP/*` |
| VIP | `ItemManager/Views/VIP/VIPCenterView.swift`, `ItemManager/Services/VIP/VIPManager.swift` |
| 法律链接 | `ItemManager/Utilities/SharedTypes.swift` |
| 设置/语言 | `ItemManager/Views/Settings/Refactored/SystemSettingsView.swift` |
| 通知 | `ItemManager/Services/NotificationManager.swift` |
| Info.plist 权限 | `ItemManager/*/InfoPlist.strings` |

完整 P1 列表见 [IOS_LOCALIZATION_AND_GLOBAL_RELEASE_RESEARCH.md](../IOS_LOCALIZATION_AND_GLOBAL_RELEASE_RESEARCH.md) §5。

---

## 4. 硬编码审计（P0 候选）

```bash
cd "$PROJ"
python3 tools/localization/audit_swift_literals.py \
  --roots ItemManager/Views/IAP ItemManager/Views/VIP ItemManager/Views/Settings \
  --output docs/localization/translation-gate0/p0-literal-audit.txt
```

将 `candidate` 类条目纳入 Gate-0 翻译或后续 `.appLocalized` 改造（改造属代码任务，本包仅列清单）。

---

## 5. InfoPlist 六语翻译模板

源英文见 `ItemManager/en.lproj/InfoPlist.strings`。扩展语言翻译稿见：

- [infoplist-ja.strings.template](./infoplist-ja.strings.template)
- [infoplist-ko.strings.template](./infoplist-ko.strings.template)
- [infoplist-fr.strings.template](./infoplist-fr.strings.template)
- [infoplist-de.strings.template](./infoplist-de.strings.template)
- [infoplist-es.strings.template](./infoplist-es.strings.template)
- [infoplist-pt-BR.strings.template](./infoplist-pt-BR.strings.template)

译后 **实施阶段** 覆盖对应 `ItemManager/{locale}.lproj/InfoPlist.strings`（本方案不改代码则仅交付模板）。

---

## 6. 外包交付物 checklist

| # | 交付物 | 格式 |
|---|--------|------|
| 6.1 | P0 字符串翻译 | XLIFF / 填好的 xcstrings 片段 |
| 6.2 | Glossary 遵守确认 | [GLOSSARY.md](../GLOSSARY.md) |
| 6.3 | InfoPlist 六语 | .strings 文件 |
| 6.4 | IAP ASC 文案（可选，与 metadata 重复） | [iap-localizations.md](../app-store-metadata/iap-localizations.md) |
| 6.5 | 禁止翻译用户内容声明 | 签字 |

---

## 7. Gate-0 完成标准

1. en / zh-Hans / zh-Hant 在 P0 模块无空 key、无 key 泄漏  
2. InfoPlist 九语权限文案为母语（非英文 copy-paste）  
3. `plutil -lint` 通过  
4. en 系统语言截图：IAP、VIP、权限弹窗、协议入口  
5. 与 [GLOBAL_SUBMISSION_GATE.md](../GLOBAL_SUBMISSION_GATE.md) P1.6 对齐  

---

## 8. 当前状态（2026-07-03）

| 项 | 状态 |
|----|------|
| 导出命令与范围文档 | ✅ 本文 |
| InfoPlist 模板 | ✅ translation-gate0/*.template |
| P0 硬编码审计 | ✅ p0-literal-audit.csv（158 candidate） |
| Xcode export | ✅ `export-manifest/en.xcloc`（见 [EXPORT_MANIFEST.md](./EXPORT_MANIFEST.md)；.gitignore 不入库） |
