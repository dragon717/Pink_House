# HarmonyOS Next 首批工程初始化记录

> 日期：2026-04-20

## 已落地

- 在仓库根目录新增 `harmony_next/`，作为 HarmonyOS Next 原生工程根目录。
- 创建 Stage 模型基础配置：`AppScope/app.json5`、`entry/src/main/module.json5`、`EntryAbility`、`pages/Index`。
- 创建 ArkTS/ArkUI 首页壳，包含 feature 切换占位和里程碑占位。
- 创建首批 feature 包目录：`wardrobe`、`pet`、`smallworld`、`wealth`、`vip`、`settings`。
- 创建 `core/domain/data` 分层，预留 RDB、Preferences、HMS IAP、提醒和天气服务接口。
- 新增 `harmony_next/README.md`，记录 DevEco Studio 开发、调试、打包、签名/Profile/AGC 注意事项。

## 边界

- 未修改 iOS 文件。
- 未修改 `android/`。
- 未提交任何证书、密钥、Profile 或 AGC 私有配置。
- 未在缺少 DevEco Studio/Hvigor 确认的情况下强制执行构建。

## 后续建议

- 用 DevEco Studio 5.0+ 打开 `harmony_next/` 并让 IDE 同步/补齐 Hvigor wrapper。
- 完成首次编译后，根据实际 SDK API 校正 `build-profile.json5` 和 ArkTS import 细节。
- M1 阶段优先补齐 RDB migration、DAO、Preferences repository 和隐私弹窗。
