# 尾款提醒体验 Harness

本 harness 用于“尾款提醒可读化”专项：把提醒页从记录式时间列表，调整为用户能理解的尾款时间线与支付期说明。

## 启动协议

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
FEATURE_ID="deposit_reminder_readability"
FEATURE_DIR="$PROJ/temp/尾款提醒体验"
ARTIFACT_ROOT="$FEATURE_DIR/_artifacts"
```

每次开发前确认：

```bash
cd "$PROJ"
git status --short
```

若存在无关改动，仅修改并 stage 本专项文件；不要执行 `git add .`。

## 目录

```text
temp/尾款提醒体验/
├── README.md
├── MANIFEST.yaml
├── EXEC_PLAN.md
├── ACCEPT_PLAN.md
└── _artifacts/
    ├── runs/<ts>/      # 开发侧截图 / 静态检查输出
    └── accept/<ts>/    # 验收 RESULT.md / 截图
```

## 小版本节奏

1. `v0-harness`：建立本目录与验收规范。
2. `v1-readable-ui`：提醒页增加尾款时间线概览，列表改为业务语义。
3. `v2-themed-cards`：提醒页卡片走主题容器和语义色。
4. `v3-notification-copy`：系统通知内容表达尾款日、支付期和提醒含义。
5. `v4-acceptance`：归档静态验收，记录未跑 Xcode 的边界。

## 硬约束

- 不新增 SwiftData 字段，不改 `DepositNotificationRecord` schema。
- 不改 `NotificationManager` 的 identifier、UserDefaults key、调度候选规则与 diff-based 刷新机制。
- 不改变尾款金额、定金/尾款语义、提醒天数默认值。
- iOS 默认不跑 `xcodebuild`，除非用户明确授权。
- 当前专项限定 iCloud Swift 工程，不写 `/Users/muniao/Downloads/Pink_House`。
