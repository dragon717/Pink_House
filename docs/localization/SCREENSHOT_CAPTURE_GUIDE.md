# App Store 截图采集指南 — 全球 metadata

> 配合 [app-store-metadata/](../app-store-metadata/) 各语言 metadata  
> 更新：2026-07-03

## 原则

1. **截图 UI 语言 = metadata 语言**（en 页配 en 描述）  
2. 使用 **真机或 Simulator** 同一设备尺寸系列  
3. 关闭调试 overlay；`IAPTestManager` 测试模式 **关闭**  
4. 扩区提交前对 **en** 与 **zh-Hant** 至少各一套完整截图  

## 语言切换

App → 设置 → 系统设置 → 界面语言 → 选择目标语言 → **重启 App**（LanguageManager 要求）

| Metadata | App 语言设置 |
|----------|-------------|
| en | English |
| zh-Hant | 繁體中文 |
| ja | 日本語 |
| ko | 한국어 |
| fr/de/es/pt-BR | 对应语言（部分 UI 可能 fallback en） |

## 必截页面（5 张 narrative）

| # | 页面 | 导航路径 |
|---|------|----------|
| 1 | 衣橱主页 | Tab 衣橱 |
| 2 | 财富/尾款 | Tab 财富 |
| 3 | 大世界 House | Tab House / 小世界 |
| 4 | 喵币商店 | 我 → 喵币商店 |
| 5 | VIP 中心 | 我 → VIP |

## ASC 尺寸（以 Connect 当前必填为准）

- iPhone 6.7"（例如 iPhone 15 Pro Max / 16 Pro Max）  
- iPhone 6.1"（例如 iPhone 15 Pro / 16 Pro）  

验证路径：App Store Connect → 版本 → Screenshots → 查看 Required sizes

## Simulator 命令参考

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
xcrun simctl boot "iPhone 16 Pro Max" 2>/dev/null || true
# 构建安装见 AGENTS.md / xcode-development skill
xcrun simctl io booted screenshot "/tmp/pink-house-screenshot-01-wardrobe.png"
```

## 归档

| 语言 | 目录建议 |
|------|----------|
| en | `docs/localization/runs/2026-07-03/screenshots/en/`（大图可选不入库，仅 index） |
| zh-Hant | `.../screenshots/zh-Hant/` |

索引文件：`screenshots-index.md` 记录文件名、语言、设备、build。

## en + zh-Hant checklist

| # | en | zh-Hant |
|---|-----|---------|
| 衣橱 | ☐ | ☐ |
| 财富 | ☐ | ☐ |
| House | ☐ | ☐ |
| 喵币商店 | ☐ | ☐ |
| VIP | ☐ | ☐ |
| 已上传 ASC | ☐ | ☐ |
