---
name: pink-house-daily-surface-gating
description: Pink_House 每日入口自动展示治理技能。用于处理“今日穿搭色 / 每日打卡 / 每日签到 / 每日问候”这类页面在启动、回前台或切页时重复自动出现的问题，并统一落实为“自动每天最多一次，手动入口不限”的规则。
---

# Pink House Daily Surface Gating

在 Pink_House 里处理“每天只自动出现一次”的入口问题时使用这个技能。

典型场景：

1. 每日打卡 sheet 一天内反复弹
2. 今日穿搭色今天已经看过，切后台回来又自动出现
3. 每日签到和每日打卡共用了一套混乱的弹出条件
4. 某个页面本来只想自动提醒一次，却变成了只允许今天打开一次

## 先读什么

1. 先读 [../../docs/DAILY_SURFACE_ONCE_PER_DAY_BEST_PRACTICES.md](../../docs/DAILY_SURFACE_ONCE_PER_DAY_BEST_PRACTICES.md)

## 优先看的代码

1. `ItemManager/ItemManagerApp.swift`
2. `ItemManager/Services/DailyCheckInManager.swift`
3. `ItemManager/Services/DailyGreetingManager.swift`
4. 相关入口页面，例如：
   - `ItemManager/Views/CheckIn/DailyCheckInView.swift`
   - `ItemManager/Views/WardrobeView.swift`
   - `ItemManager/Views/PetChat/PetChatView.swift`

## 固定判断原则

### 1. 先区分自动触发和手动触发

自动触发：

1. 启动完成后自动弹
2. 回前台自动弹
3. 定时或状态检查后自动弹

手动触发：

1. 用户点按钮
2. 用户点卡片
3. 用户点菜单入口

只对自动触发做“每天一次”限制。

### 2. 每个自动入口都要有自己的日级 key

不要把所有每日入口共用一个总开关。

也不要复用公告系统的已读/弹窗状态去做每日入口限流。

### 3. 去重判断要放在触发源头

不要把“每天一次”锁死在页面内部，否则手动入口也会被误伤。

### 4. 标记时机要早于真正展示

推荐顺序：

1. 判断今天是否已自动展示过
2. 如果还没有，先写入今天的展示标记
3. 再展示页面

## 推荐排查顺序

1. 先确认这是自动还是手动进入
2. 再确认当天展示 key 是否存在
3. 再确认冷启动和前后台是不是共用了同一套判断
4. 最后再查页面自己的状态

## 处理约束

1. 不要把“自动只一次”实现成“今天只能打开一次”
2. 不要只修冷启动，不修回前台
3. 不要只用内存变量，必须持久化到本地
4. 不要让一个每日入口的 key 误伤另一个入口
5. 在这个仓库里，默认不要跑 Xcode 编译；由用户自己编译并反馈报错

## 改完后至少确认的结果

1. 同一天自动只出现一次
2. 杀端重进也不会再次自动打断
3. 用户手动点入口时仍然能正常进入
4. 不同每日入口之间互不串扰
