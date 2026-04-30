# 主题皮肤详情页预览与组件开关 UX 调研

- 归档正文：`docs/THEME_SKIN_DETAIL_PREVIEW_BEST_PRACTICES.md`
- 状态：仅调研归档；主题详情页预览、实时组件预览、18 个 slot 开关的 UX 最佳实践已沉淀到正文文档。
- 摘要：后续实现优先按 V1「真渲染缩略图 + 分块图解 + 默认/主题对照」推进；V2/V3 再考虑 iPhone 框 Live 预览和双向锚点。
- 边界：不增减 18 个 slot；不改 `ThemeSkinSlot.rawValue`；不改 `ThemeSkinManager` API / 持久化 key；不改现有 Swift 代码；不动 `temp/_harness/`；不把本文当作 harness 执行计划。
- 实施时机：排在天空音乐会 / 天鹅入梦 harness 验收完成之后，避免与 `ThemeSkinDetailView.swift` 的主题复刻工作产生冲突。
