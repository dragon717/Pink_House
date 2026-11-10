# App Store 截图采集指南 — 全球 metadata

> 配合 [app-store-metadata/](./app-store-metadata/) 各语言 metadata
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
| 3 | 时光馆 | 底部导航 → 时光馆 → 裙款目录 |
| 4 | 喵币商店 | 我 → 喵币商店 |
| 5 | VIP 中心 | 我 → VIP |

## 本次上传尺寸与采集

主对话统一采集 iPhone 12、当前大屏 iPhone 和 iPad 素材并套框。按目标语言复用同一场景与设备，在当次运行索引中记录文件、语言、设备、像素和构建。Apple 要求的设备槽位以版本页和[官方规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)为准。

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
| 时光馆 | ☐ | ☐ |
| 喵币商店 | ☐ | ☐ |
| VIP | ☐ | ☐ |
| 已上传 ASC | ☐ | ☐ |
