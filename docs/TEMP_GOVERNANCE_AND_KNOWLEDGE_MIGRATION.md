# temp 治理与知识资产迁移规范

> 更新时间：2026-05-25
> 适用范围：Pink_House 仓库内 `temp/`、历史 harness、一次性验证目录、临时计划稿、生成物、验收截图与可复用工具的转正 / 归档 / 删除。

## 1. 设计哲学

`temp/` 只允许承载探索期的不确定性，不允许承载项目长期记忆。

探索期可以混乱，因为它服务速度；沉淀期必须清晰，因为它服务未来。一次好的清理，不是把目录删干净，而是把临时材料里的判断、证据、规则和工具迁移到它们真正属于的位置，让后来的人不需要再翻废墟。

本项目的治理原则是：

- 代码是行为事实，文档是解释事实，工具是可重复事实，截图 / RESULT 是验收事实。
- `temp` 里的内容默认不是 source of truth；它最多是历史证据和迁移输入。
- 未验证的“已完成”不进入正式口径；只能写成 PARTIAL、历史声明或待核对。
- 删除前先降级：先从 source of truth 降为历史参考，再从历史参考降为可删除候选。
- 不为删除而删除。能复用的变成 docs / tools / skills；不能复用的写清楚为什么不保留。

## 2. Source Of Truth 层级

从高到低：

| 层级 | 位置 | 用途 |
|---|---|---|
| Runtime source | `ItemManager/`、`ItemManager.xcodeproj/`、`Assets.xcassets/` | App 真实行为、构建配置、资源入口 |
| Formal tools | `tools/`、`scripts/` | 可重复执行的导入、审计、生成、验证工具 |
| Formal docs | `docs/` | 方案、状态、验收、设计哲学、迁移结论 |
| Project skills | `docs/skills/<skill>/SKILL.md` | 可复用的 agent 工作流与硬约束 |
| Historical evidence | 历史 RESULT、截图、旧 harness 摘要 | 只解释“当时发生过什么” |
| Temporary input | `temp/` | 探索材料、临时产物、待迁移输入 |

如果两个来源冲突，优先级按上表处理。历史文档声称已完成，但代码不存在时，以代码为准，并把历史文档标为过期口径。

## 3. temp 内容分类

清理前先分类，不要一把扫。

| 类型 | 典型内容 | 处理方式 |
|---|---|---|
| 已落地状态 | RESULT、PASS、已实现说明 | 迁到 `docs/*_STATUS.md` 或正式验收文档 |
| 未闭环计划 | PARTIAL、待跑验收、待实现功能 | 迁到 backlog / exec plan，不能写成完成 |
| 可复用规则 | 验收点、命名规则、素材 pipeline、测试矩阵 | 迁到 `docs/*_CHECKLIST.md`、`docs/*_BEST_PRACTICES.md` |
| 可执行工具 | 生成脚本、审计脚本、导入脚本 | 迁到 `tools/` 或 `scripts/`，默认不依赖 temp |
| 资产输入 | PSD、PNG、手动 image2、设计基准图 | 迁到正式资产输入目录，或记录替代来源 |
| 大体积生成物 | 截图成品、node_modules、外部 checkout | 迁到发布素材目录 / tools，或只保留最终成品 |
| 过期证据 | 代码路径已不存在、方案已被替代 | 标记历史过期，必要时只保留摘要 |
| 删除候选 | 空文件、无业务 prompt、重复中间物 | 删除前做最后一次 `rg` 和路径核对 |

## 4. 迁移流程

### 4.1 先读文档，再读代码

当目标是“整理 temp 文档”时，第一阶段只读 temp 文档，先建立它自己的声明：

- 它说自己完成了吗？
- 它指向哪些代码、资源、截图和 RESULT？
- 它还有哪些 PARTIAL / TODO / 待验收？
- 它是否把自己写成 source of truth？

第二阶段再读代码，核对这些声明是否仍成立。

### 4.2 建迁移索引

正式索引应至少包含：

- temp 路径
- 文档声明状态
- 对应代码 / 工具 / 资源
- 当前核对结论
- 删除前动作

Pink_House 的当前样板是 `docs/TEMP_CLEANUP_INVENTORY.md`。

### 4.3 转正四件套

能复用的临时内容，优先落到这四类正式资产：

- 状态文档：`docs/<FEATURE>_STATUS.md`
- 验收清单：`docs/<FEATURE>_ACCEPTANCE_CHECKLIST.md`
- 工具 / manifest：`tools/<domain>/...`
- 技能：`docs/skills/<skill-name>/SKILL.md`

不要把执行日志整篇搬进正式文档。正式文档只保留结论、规则、入口、验证边界和下一步。

### 4.4 旧路径降级

文档里允许保留旧路径，但必须写清楚身份：

- 历史引用路径
- 临时 artifact 输入
- 删除前核对输入
- 非 runtime 依赖
- 已过期口径

禁止继续使用这些表述：

- “以 `temp/...` 为准”
- “`temp/...` 是唯一 source of truth”
- “长期流程见 `temp/...`”
- “默认从 `temp/...` 读取”，除非工具当前事实确实如此，并且写明迁移计划

## 5. 架构组织规则

### 5.1 docs 组织

| 文档类型 | 命名建议 | 内容边界 |
|---|---|---|
| 当前状态 | `*_STATUS.md` | 事实、代码路径、完成 / 未完成 |
| 执行计划 | `*_EXEC_PLAN.md` | 待做步骤、风险、验证命令 |
| 验收清单 | `*_ACCEPTANCE_CHECKLIST.md` | PASS / PARTIAL / FAIL 标准 |
| 最佳实践 | `*_BEST_PRACTICES.md` | 可复用原则和反模式 |
| 流水线规则 | `*_PIPELINE.md` | 资产 / 数据 / 工具输入输出 |
| 总索引 | `*_INVENTORY.md` | 迁移台账和删除前动作 |

一个文档只做一件事。不要让 `STATUS` 变成计划书，也不要让 `EXEC_PLAN` 混入历史日志。

### 5.2 tools 组织

工具进入 `tools/<domain>/` 后要满足：

- 能从仓库根目录执行。
- 默认输入不应依赖 `temp`；若仍依赖，必须在 help / docs 中声明。
- 支持 dry-run 或只读审计模式。
- 输出能被验收：例如 `missing=0`、`placeholder_suspect=0`、`ok=true`。
- 中文路径按 UTF-8 处理。

### 5.3 skills 组织

技能只写 agent 下次需要遵守的工作流，不写冗长复盘。

技能应包含：

- 什么时候触发。
- 先读哪些正式文档。
- 哪些路径不能作为 source of truth。
- 哪些验证命令必须跑。
- 输出时必须说明哪些边界。

## 6. 验证标准

删除 `temp` 前至少要有三类验证：

### 6.1 路径扫描

```bash
rg -n "temp/" ItemManager ItemManager.xcodeproj docs scripts tools AGENTS.md --glob '!temp/**'
```

扫描结果按身份分类：runtime、工具输入、历史说明、删除前检查。只有 runtime / 构建配置 / 默认工具输入为零或已替代，才能进入删除阶段。

### 6.2 工具验证

对迁出的工具跑：

```bash
git diff --check
ruby -c tools/theme_skin/materialize_manual_image2_assets.rb
ruby tools/theme_skin/materialize_manual_image2_assets.rb --theme-id theme_skin.sky_concert --dry-run
```

其他语言工具按对应语法检查和 dry-run 执行。

### 6.3 事实验证

对每个“已完成”结论至少确认一项真实证据：

- 代码路径存在。
- 构建配置存在。
- 资源在 Asset Catalog。
- 工具 dry-run 通过。
- RESULT / 截图 / 验收记录存在。

没有证据的完成，只能写“文档声明完成，待代码核对”。

## 7. 协作方式

大规模清理适合拆给 subagent，但必须拆写入边界：

- 一个 agent 迁工具。
- 一个 agent 迁验收清单。
- 一个 agent 迁状态文档。
- 一个 explorer 只读核对 runtime 和工程配置。

主 agent 负责监督和验收，不重复 worker 的工作。验收时重点看：

- 是否误删或回滚他人改动。
- 是否把历史路径继续写成 source of truth。
- 是否把 PARTIAL 写成 PASS。
- 是否有工具默认输入仍指向 temp。
- 是否有新生成的副产物未记录。

## 8. 设计哲学沉淀

这次 temp 清理形成的更大共识：

1. **临时目录不是垃圾桶，是孵化器。** 它可以快速聚合想法，但成熟后必须分流到 docs、tools、skills 或代码。
2. **文档不是仓库的注释，而是协作界面。** 好文档让人知道下一步该做什么，而不是只知道过去发生过什么。
3. **验收证据要能离开作者存在。** RESULT、截图、dry-run 输出、代码路径都应该能让后来的 agent 独立判断。
4. **架构组织的本质是减少误会。** source of truth 层级清晰，比文件名漂亮更重要。
5. **删除动作应当无戏剧性。** 真正好的删除，是删除时大家已经不再需要它。
6. **未完成也有价值。** 只要写清楚边界、风险和下一步，PARTIAL 就是资产；伪装成 PASS 才是债务。

## 9. 收尾清单

删除临时目录前逐项确认：

- [ ] `rg -n "temp/"` 已跑并分类。
- [ ] runtime / 构建配置没有默认依赖 temp。
- [ ] 正式工具默认输入不再指向 temp。
- [ ] 可复用规则已迁入 docs。
- [ ] 可复用工具已迁入 tools / scripts。
- [ ] 可复用工作流已迁入 docs/skills。
- [ ] 未完成事项已进入 STATUS / EXEC_PLAN / backlog。
- [ ] 大体积生成物已确认保留位置或删除理由。
- [ ] 空文件 / `.DS_Store` / 缓存副产物已作为最后清理项处理。
- [ ] 最终报告写明删了什么、没删什么、为什么。
