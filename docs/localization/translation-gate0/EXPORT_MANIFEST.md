# Localization export manifest — Gate-0

> 生成日期：2026-07-03  
> **注意**：完整 `en.xcloc` 体积较大，默认不提交 git；在本机保留或交给翻译方。

## 已导出包

| 文件 | 路径 | 内容 |
|------|------|------|
| en.xcloc | `export-manifest/en.xcloc/` | Localizable.xcstrings、InfoPlist、Assets 的 en 导出 |

## 重新生成

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -exportLocalizations \
  -project ItemManager.xcodeproj \
  -localizationPath docs/localization/translation-gate0/export-manifest \
  -exportLanguage en
```

## 导入译稿

```bash
xcodebuild -importLocalizations \
  -project ItemManager.xcodeproj \
  -localizationPath docs/localization/translation-gate0/export-manifest/en.xcloc
```

（实施阶段、翻译完成后执行）

## 包含的主要 XLIFF 源

- `ItemManager/Resources/Localization/Localizable.xcstrings` → Localizable.xliff  
- `ItemManager/en.lproj/InfoPlist.strings`  
- Widget `少女心愿衣橱/Localizable.xcstrings`  
- Asset catalog 字符串（如有）

## 配套交付

- [p0-literal-audit.csv](./p0-literal-audit.csv) — 158 条 candidate（未进 catalog 的硬编码）  
- [p0-literal-audit-summary.md](./p0-literal-audit-summary.md)  
- [infoplist-*.strings.template](./infoplist-ja.strings.template) — 六语权限模板  
- [GLOSSARY.md](../GLOSSARY.md)
