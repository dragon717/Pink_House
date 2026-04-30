# ACCEPT_PLAN — 尾款提醒可读化验收

## 0. 启动协议

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
FEATURE_ID="deposit_reminder_readability"
DIR="$PROJ/temp/尾款提醒体验/_artifacts/accept/$(date +%Y%m%d-%H%M)"
mkdir -p "$DIR"
```

默认不运行 Xcode 编译；如用户明确允许，再执行模拟器构建和截图。

## 1. P0 静态验收

- `DepositNotificationRecord` 字段未变。
- `NotificationManager.Keys`、通知 identifier、调度候选规则未变。
- 提醒页主信息不再以裸 `MM/dd HH:mm` 为标题。
- 提醒页核心卡片走 `ThemeSkinSectionCardContainer` / 语义色。
- `git diff --check` 通过。

## 2. 场景验收

1. 未开启提醒：顶部能说明提醒关闭，列表不出现误导性“待系统通知”。
2. 无通知权限：保留权限提示，文案仍解释为什么收不到系统提醒。
3. 无尾款记录：空态说明需要先创建心愿尾款。
4. 未来尾款：显示尾款日、还有几天、将提前几天提醒。
5. 当天尾款：显示今天开始付尾款，行动提示明确。
6. 支付期范围：显示起止日期而非单个模糊时间。
7. 已过期：显示已过期/请处理，但不改数据状态。
8. 系统通知 / 仅站内：角标能解释“系统通知”与“站内排队”。
9. 已读 / 未读：未读圆点、批量已读、清除已读仍可用。
10. 衣物被删除后的历史记录：至少能用记录内裙名和时间回退展示，不崩溃。

## 3. 截图归档建议

```text
A_overview_card.png
B_pending_list.png
C_history_list.png
D_settings_expanded.png
E_dark_mode.png
RESULT.md
```

`RESULT.md` 必须记录：PASS/PARTIAL/FAIL、残留问题、未执行项、是否运行构建。
