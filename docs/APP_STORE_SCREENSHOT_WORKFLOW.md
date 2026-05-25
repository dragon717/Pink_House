# App Store 商品图工作流迁移说明

> 状态：2026-05-25 梳理。本文只记录 `temp/商品图/` 的工具和生成作业归属，不要求本轮移动或删除目录。

## 当前目录性质

- `temp/商品图/appshot/` 是外部 `appshot-cli` 工具 checkout，包含 `.git`、`node_modules`、CI、skill、frames、fonts 等工具资产。它不是 Pink_House app runtime 依赖，也不应作为 app 构建、启动或 Swift 代码读取路径。
- `temp/商品图/appshot-job/` 是 Pink_House 商品图生成作业，主要放输入/输出目录配置、截图 captions、富文案 overlay 配置等发布物料生产上下文。它也不是 app runtime 依赖。
- 衣橱性能压测样例不再以 `temp/商品图/` 为默认输入。压测图片建议放到 `tools/perf-samples/wardrobe-images/`，或由执行者通过 `--image-dir <absolute-path>` 显式传入。

## 后续迁移建议

| 当前路径 | 建议迁移位置 | 说明 |
|---|---|---|
| `temp/商品图/appshot/` | `tools/appshot/` 或全局安装 `appshot-cli` | 如果需要固定工具版本，可迁入 `tools/appshot/` 并在 README 记录安装和运行命令；如果只需要通用 CLI，优先记录全局安装方式，避免把 `node_modules` 长期留在仓库临时目录。 |
| `temp/商品图/appshot-job/` | `tools/appshot-job/` 或发布素材文档 | 如果作业配置需要可重复执行，迁到 `tools/appshot-job/`；如果只保留成品截图、尺寸、文案和验收记录，迁入发布素材文档即可。 |
| 最终商品截图 | 正式发布素材目录 | 保留可提交 App Store 的最终成品和必要源配置，避免只在 `temp/` 中保存唯一副本。 |

## 删除 temp 前检查

1. 确认 Swift / Xcode runtime 没有读取 `temp/商品图/`。
2. 确认性能压测命令改用 `tools/perf-samples/wardrobe-images/` 或显式 `--image-dir`。
3. 确认商品图工具的安装方式、作业配置和最终成品截图已有正式位置。
4. 确认 `appshot/` 内的外部 `.git`、`node_modules` 不再作为 `temp/` 保留理由。
