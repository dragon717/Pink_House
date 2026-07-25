# 裙装编辑：点选主路径（Chip + Sheet）

> ponytail ultra。模型逗号串不动。只改编辑页裙装信息卡。

## 目标

`ClothingField` 全部：行内约两行常用 tag（点选切换：选中粉 / 未选灰），末尾「更多」进 `SimpleStringSelectionView`（不是选中态）。手输只留在 sheet「添加新选项」。

## 不动

- `Clothing` 字段类型与存档
- 草稿 / 保存 / 筛选 / 备份
- 价格、购买、标签区
- Android / 鸿蒙
- 名称、品牌（仍 AutoComplete + 品牌库）

## 改动面

| 文件 | 做什么 |
|---|---|
| `ClothingEditSections.swift` | 全部动态字段 chip 行；尺码表图在标题右；`CommaSeparatedTokens` |
| `SimpleStringSelectionView.swift` | 搜索、保序写回、共用 parse |
| `ClothingEditView.swift` | `getAllOptions` = 历史 ∪ 预设；小物含「类型含小物」品名 |
| `SuggestionManager.swift` | `getAllTypes` / `getAllConditions` |
| `ItemManagerTests/CommaSeparatedTokensTests.swift` | parse / 保序 |

## 数据流

```
chip UI / sheet  ↔  Binding<String>（逗号串）  ↔  Clothing.*
```

## 状态

- [x] 骨架
- [x] 业务完整迁移（含衣长/状态、sheet 搜索与保序、小物品名选项）

## 验收

- 冷库 sheet 可见 JSK / 粉色 / 均码 / 全新 / 90cm 等
- 多选写回保序；单选「更改」替换
- 详情与筛选仍认原逗号字段
- `CommaSeparatedTokensTests` 通过
