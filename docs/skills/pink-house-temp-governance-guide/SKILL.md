---
name: pink-house-temp-governance-guide
description: Pink_House temp 目录治理、历史 harness 迁移、临时文档转正式 docs/tools/skills、删除 temp 前依赖扫描和 source-of-truth 降级工作流。用于用户要求整理 temp、删除 temp、迁移临时方案、沉淀最佳实践、把历史 harness 转正或核对临时目录是否还能删除时。
---

# Pink House Temp Governance Guide

在 Pink_House 中处理 `temp/`、历史 harness、临时方案、实验脚本、生成物、截图验收、删除前核对时使用本技能。

## 先读

1. `docs/TEMP_GOVERNANCE_AND_KNOWLEDGE_MIGRATION.md`
2. `docs/TEMP_CLEANUP_INVENTORY.md`（如果存在；作为当前迁移台账）
3. 相关领域正式文档，例如 ThemeSkin 读 `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md`
4. 相关正式工具，例如 `tools/theme_skin/theme_manifest.yaml`

## 核心原则

- `temp/` 默认不是 source of truth；它只是历史证据、临时输入或待迁移材料。
- 先读 temp 文档，建立它自己的声明；再读代码 / 工具 / 资源核对声明是否仍成立。
- 不把 PARTIAL 写成 PASS；未跑构建、未跑截图、未核对代码要明说。
- 删除前先迁移可复用知识，再扫描依赖，最后再删。
- 中文路径、日志、JSON、命令输出按 UTF-8 处理。

## 分类方法

把每个 temp 条目分到一个桶：

| 类型 | 迁移目标 |
|---|---|
| 当前状态 | `docs/*_STATUS.md` |
| 验收规则 | `docs/*_ACCEPTANCE_CHECKLIST.md` |
| 执行计划 | `docs/*_EXEC_PLAN.md` |
| 最佳实践 | `docs/*_BEST_PRACTICES.md` |
| 资产流水线 | `docs/*_PIPELINE.md` + `tools/<domain>/` |
| 可执行脚本 | `tools/` 或 `scripts/`，默认 dry-run |
| 测试矩阵 | `docs/*_TEST_MATRIX.md` |
| 历史过期记录 | inventory 中标为历史过期 |
| 删除候选 | 最后扫描后删除 |

## 默认工作流

1. 盘点 `temp`：列一级目录、文件数、体积。
2. 阅读 temp 文档：记录它声明的完成状态、代码路径、资源路径、RESULT、TODO。
3. 建或更新 inventory：不要直接删。
4. 读实际代码 / 工具 / 工程配置：确认 runtime 是否依赖 temp。
5. 把可复用内容迁入正式位置：`docs/`、`tools/`、`docs/skills/`。
6. 把旧 temp 引用降级为“历史参考 / 临时输入 / 删除前核对输入”。
7. 跑验证命令。
8. 汇总剩余 blocker，等待用户确认删除或由用户手动删除。

## 验证命令

```bash
git diff --check
rg -n "temp/" ItemManager ItemManager.xcodeproj docs scripts tools AGENTS.md --glob '!temp/**'
```

如迁移工具，还要跑对应语法检查和 dry-run，例如：

```bash
ruby -c tools/theme_skin/materialize_manual_image2_assets.rb
ruby tools/theme_skin/materialize_manual_image2_assets.rb --theme-id theme_skin.sky_concert --dry-run
```

## 输出要求

交付时必须说明：

- 迁出了什么：docs / tools / skills 路径。
- 哪些只是历史参考，哪些仍是临时输入。
- runtime / 构建配置是否仍依赖 temp。
- 跑过哪些验证，哪些没跑。
- 是否删除了文件；如果用户说不要删，就明确“未删除 temp”。
- 剩余 blocker 的优先级。

## 反模式

- 把 `temp/...` 写成长期 source of truth。
- 复制整份历史日志到正式文档。
- 把旧 RESULT 当作当前验收通过。
- 只迁文档不核对实际代码路径。
- 让工具默认读 temp，却在文档里说 temp 可删。
- 删除前不跑 `rg -n "temp/"`。
