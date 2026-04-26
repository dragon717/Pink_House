# 少女心愿 HarmonyOS Next 工程骨架

这是 `docs/migration/harmony_next/PRD.md` 对应的 HarmonyOS Next 5 原生首批工程。当前已从基础骨架推进到衣橱核心 MVP 第一轮：衣橱页接入 RDB/Repository/usecase 链路，具备列表、空态、按名称搜索、添加示例衣物和软删除能力。

## 技术选择

- 应用模型：Stage 模型，入口 Ability 为 `EntryAbility`。
- 语言/UI：ArkTS 严格模式预留 + ArkUI 声明式 UI。
- 最低 API：HarmonyOS Next API 12；目标 API：API 14。
- 本地存储：`@ohos.data.relationalStore` 预留 RDB schema，`@ohos.data.preferences` 预留轻量设置。
- 产品分层：`core`、`domain`、`data`、`feature`，feature 首批包含 `wardrobe`、`pet`、`smallworld`、`wealth`、`vip`、`settings`。
- 生态能力预留：HMS IAP、`reminderAgentManager`、和风天气 HTTPS/JWT、系统分享、字体注册、Service Card 数据源。

## 衣橱 MVP 第一轮

- 领域层：新增 `WardrobeItem` / `NewWardrobeItem` 模型、`WardrobeRepository` 接口，以及获取列表、搜索、添加示例衣物、软删除用例。
- 数据层：新增 `WardrobeItemDao` 和 `RdbWardrobeRepository`，基于 `wardrobe_items` 支持未删除列表查询、插入示例数据、按名称 `LIKE` 搜索、`is_deleted` 软删除。
- UI 层：`WardrobePage` 已替换占位壳，显示 RDB 列表、搜索输入框、空态、加载/错误状态、添加示例衣物按钮和单项移除按钮。
- 当前策略：示例衣物先写入基础字段，图片导入、分类筛选、详情页、资产统计和备份兼容留到后续迭代。

## 目录说明

```text
harmony_next/
├── AppScope/                         # 应用级配置与资源
├── entry/                            # 主 HAP entry 模块
│   └── src/main/
│       ├── module.json5              # Stage 模块配置
│       ├── ets/
│       │   ├── entryability/          # EntryAbility
│       │   ├── pages/                 # 首页入口
│       │   ├── core/                  # 常量、主题、导航、日志
│       │   ├── domain/                # 领域模型、仓储接口、用例
│       │   ├── data/                  # RDB、Preferences、服务占位
│       │   └── feature/               # 业务 feature 占位
│       └── resources/                 # 字符串、颜色、图标、profile
├── build-profile.json5
├── hvigorfile.ts
└── oh-package.json5
```

## macOS + DevEco Studio 开发

1. 安装 DevEco Studio 5.0+，并安装 HarmonyOS Next API 12/14 SDK。
2. 使用 DevEco Studio 打开 `harmony_next/` 目录。
3. 首次打开后让 IDE 同步 Hvigor/SDK 配置；如 IDE 提示升级 `modelVersion` 或补充 wrapper 文件，以 DevEco 生成结果为准。
4. 在 `File > Project Structure` 中确认 `entry` 模块为 Stage 模型，设备类型包含 phone/tablet/2in1。
5. 不要把本机签名文件、证书、密钥、AGC 私有配置提交到仓库。

## 模拟器/真机调试

- 模拟器：在 Device Manager 创建 HarmonyOS Next API 12+ 手机或平板模拟器，选择 `entry` 模块运行。
- 真机：开启开发者模式和 USB 调试，使用华为账号/AGC 关联的调试 Profile。
- 设备重点：Mate 70、Pura 70、MatePad 13.2、Mate X6 展开态。
- 首批验证重点：冷启动、首页渲染、feature 切换、RDB 初始化、Preferences 读写、权限弹窗文案。

## HAP/.app 打包

- Debug：DevEco Studio 选择 `Build Hap(s)/APP(s) > Build Hap(s)` 生成调试 HAP。
- Release：完成签名配置后选择 `Build Hap(s)/APP(s) > Build App(s)` 生成 AppGallery 上传用 `.app`。
- 多模块/服务卡片加入后，需要确认 `entry` 与 card/form extension 的 bundle、module、ability 配置一致。

## 签名、Profile 与 AGC 上架注意事项

- 在 AGC 创建 HarmonyOS Next 应用，bundleName 暂定为 `com.pinkhouse.harmony`，正式上架前需与 AGC 保持一致。
- Debug 使用调试证书和调试 Profile；Release 使用发布证书和发布 Profile。
- HMS IAP 商品 ID 按 PRD：`meowcoin_60`、`meowcoin_120`、`meowcoin_300`、`meowcoin_500`、`mcoin_1280`、`mcoin_3280`。
- VIP 不是 HMS IAP 商品，VIP 通过喵币兑换实现。
- 上架前必须补齐隐私政策 URL、用户协议 URL、个人信息收集清单、第三方 SDK 清单。
- 仓库禁止提交 `.p12`、`.cer`、`.p7b`、Profile、AGC 私钥、和风天气 API key/JWT 私钥。

## 当前未完成项

- 未接入真实 HMS IAP SDK；`HmsIapService` 仅保留接口与异常占位。
- 未实现 `@ohos.reminderAgentManager`，当前只保留提醒通道枚举。
- 未实现通用 RDB 迁移器；当前先以 `CREATE TABLE IF NOT EXISTS` 确保首批表结构，并为衣橱补齐 DAO。
- 未实现 Service Card/formExtensionAbility；当前只在 README 和 feature 页面预留数据源方向。
- 未实现和风天气 JWT、定位降级、系统分享、字体注册和备份导入导出。
- 衣橱尚未接入真实图片 URI、分类筛选、详情路由、批量导入和 iOS 备份字段映射。

## 本地构建状态

当前机器未确认安装 DevEco Studio/Hvigor，按任务要求未强行执行构建。请在 DevEco Studio 5.0+ 中打开 `harmony_next/` 后完成 SDK 同步、签名配置和首次编译校验。
