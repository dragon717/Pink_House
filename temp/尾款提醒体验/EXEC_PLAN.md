# EXEC_PLAN — 尾款提醒可读化

## 0. 启动协议

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
FEATURE_ID="deposit_reminder_readability"
FEATURE_DIR="$PROJ/temp/尾款提醒体验"
ARTIFACT_ROOT="$FEATURE_DIR/_artifacts"
```

执行前必须：

```bash
cd "$PROJ"
git status --short
```

如存在无关改动，只 stage 本专项文件，禁止 `git add .`。

## 1. 必读上下文

1. `ItemManager/Views/DepositPlan/DepositNotificationView.swift`
2. `ItemManager/Services/NotificationManager.swift`
3. `ItemManager/Views/ThemeSkin/ThemeSkinSharedComponents.swift`
4. `ItemManager/Views/DepositPlanView.swift`
5. `ItemManager/Views/DepositItemRow.swift`

## 2. 实施顺序

### v0 — Harness
- 建立 `README.md`、`MANIFEST.yaml`、`EXEC_PLAN.md`、`ACCEPT_PLAN.md`。
- 明确 artifact 目录、不可变更项和静态检查命令。

### v1 — 可读语义 UI
- 在提醒页顶部增加“尾款时间线”概览：下次提醒、最近支付期、待付总额、提醒状态。
- 待提醒行显示裙名、尾款日/支付期、还有几天/已进入支付期、待付金额、提醒方式。
- 已发送行显示“已在 xx 提醒”、原计划提醒日、提前几天/当天、是否未读。
- 原始时间只能作为次要辅助文案，不作为主标题。

### v2 — 主题与视觉
- `settingsSummarySection`、`historySection`、`pendingSection`、已发送组卡、待提醒行、已发送行统一使用 `ThemeSkinSectionCardContainer` 或语义色容器。
- 默认皮肤仍使用 `CardBackgroundView` 回退；主题未启用时不得出现主题装饰。

### v3 — 系统通知文案
- `makeReminderContent` 输出包含裙名、尾款日/支付期、提醒含义和行动提示。
- 保持 `identifier`、`PayloadKeys`、UserDefaults key、调度候选逻辑不变。

### v4 — 验收
- 运行静态检查并写入 `_artifacts/accept/<ts>/RESULT.md`。
- 默认不运行 Xcode 编译；若未跑，必须在 RESULT 中说明。

## 3. 静态检查

```bash
cd "$PROJ"
git diff --check
rg -n 'scheduledDate|actualDate|MM/dd HH:mm|HH:mm 发送' ItemManager/Views/DepositPlan/DepositNotificationView.swift
rg -n 'ThemeSkinSectionCardContainer' ItemManager/Views/DepositPlan/DepositNotificationView.swift
```
