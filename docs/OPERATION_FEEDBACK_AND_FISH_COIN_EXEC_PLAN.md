# 操作反馈与鱼币统一执行计划

2026-10-11；用户已授权当前本机工作区实现。正式规则入口：[使用指南](OPERATION_FEEDBACK_AND_FISH_COIN_GUIDE.md)。

## 本期目标与完成项

- [x] 时光馆单件入橱、批量入橱、加入心愿：图片/记录成功保存后提示添加成功，同时按既有新增衣物规则奖励鱼币。
- [x] 普通成功/错误/复制/奖励统一队列、卡片、生命周期和可访问性，不依赖页面订阅奖励事件。
- [x] 手动新建衣物改为保存成功后发奖；尾款付清的成功和鱼币合并，以支付流水 ID 防重。
- [x] 萌宠购物、搭配保存、贴纸添加/删除/移动、IAP 普通结果提示使用同一队列。
- [x] 时光馆图片保存移除本地气泡；等待系统相册保存完成，失败时不报成功。
- [x] 实际到账回执、每日上限、稳定业务标识、旧钱包快照兼容；鱼币与充值喵币职责分离。
- [x] 入橱联动通知、魔法任务数量、小组件；原有图片持久化/云同步保留。
- [x] 任务解锁交互与系统确认弹窗职责写入指南；任务卡片在普通提示展示期间暂缓显示。
- [x] 指南写入 docs，并在 MEMORY、工作记忆、Agent.md、AGENTS.md、店家上新计划建立唯一入口索引。

## 验证记录

第一轮：Xcode 27 / iOS 27 SDK 编译及 15 项定向单测通过，运行设备 iPhone 17 Pro 模拟器，实际运行系统 iOS 26.3.1。

结果包：`/private/tmp/pink-house-feedback-20261011.xcresult`；日志：`/private/tmp/pink-house-feedback-20261011.log`。

最终源码回归：**通过**。18 项单测 + 1 项原生底栏 UI 回归，共 19 项，通过 19、失败 0、跳过 0。编译 SDK 为 iOS 27；实际运行是 iPhone 17 Pro / iOS 26.3.1 模拟器。

结果包：`/private/tmp/pink-house-feedback-delivery-20261011.xcresult`；日志：`/private/tmp/pink-house-feedback-delivery-20261011.log`。

最终命令（已执行）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /private/tmp/pink-house-detail-layout-20261011 \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/RewardManagerTests \
  -only-testing:ItemManagerTests/OperationFeedbackTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests \
  -only-testing:ItemManagerTests/PetStatusCodableTests \
  -only-testing:ItemManagerUITests/NativeTabNavigationUITests \
  -resultBundlePath /private/tmp/pink-house-feedback-delivery-20261011.xcresult test
```

界面夹具截图已导出并核对：`/private/tmp/pink-house-feedback-delivery-images/B3A52D75-8A99-44A6-834C-5BA5A48C60E1.png`。真实 scene 中验证辅助窗口位于 sheet 上方、卡片只占自身范围、卡片外触摸透传、不夺取 key window、暂停不丢消息。截图为 UI 测试夹具渲染，不冒充用户真实商品入橱截图。原生底栏 UI 测试验证衣橱、心愿尾款、时光馆和“我”可正常切换。

验证中修复了两处问题：卡片区域改用 SDK 的 `onGeometryChange` 测量，并显式设置辅助窗口/宿主视图为透明、卡片保留系统语义背景以保证对比；旧运行时上 UIKit 释放反馈模型时曾在 `swift_task_deinitOnExecutorMainActorBackDeploy / TaskLocal::StopLookupScope` 崩溃，无 UI 析构清理的反馈模型和协调器改为 `nonisolated deinit` 后完整回归通过。崩溃诊断：`/Users/sangyu/Library/Logs/DiagnosticReports/ItemManager-2026-10-11-040218.ips`。

奖励与导入测试使用独立 UserDefaults、临时/内存数据与媒体夹具，不向真实用户钱包发测试奖励。源码已通过 `git diff --check`。


## 后续接入清单

1. 确认“用户操作成功”的保存/系统完成回执，先解决假成功问题。
2. 普通提示走 Toast/Copy 适配入口；有既定奖励的操作走合并入口。
3. 标识用持久化业务记录 ID，批量按真正保存的记录数计算。
4. 业务拥有者完成任务/通知/小组件收尾；展示层禁止承担记账或重复收尾。
5. 校验失败、取消、保存失败不发奖励；每日上限不撤销已成功业务。
6. 按指南验证并更新这份执行记录；不要新增独立气泡与隐藏计时器。

## 验证边界

本期不改既有奖励金额、IAP 到账与权益算法、主题 slot 持久化或旧衣物图片回填规则。正式充值、系统相册真实写入及 Duo 真机体验需独立场景验收，不通过单元测试宣称已验证。

## 既有大文件拆分计划

本期新增服务、队列、卡片和 scene 宿主均独立成小文件，既有大页面只调整调用与移除旧气泡。后续按以下边界拆分，避免把业务逻辑重新堆回 View：先把 ClothingEditView 的保存及通知收尾抽成服务；再把 PetChatView/Legacy 的搭配保存、购物收尾与动作覆盖层分别抽出；最后把 ShopCatalogProductDetailView 的大图查看器和入橱 sheet 拆成独立文件。新增文件继续遵守 ≤500 行。

2026-10-11 默认规则补充：入橱主衣物默认入选、小物主动勾选；运营新录入币种默认 CNY。具体实现、历史币种边界与回归命令见 `docs/SHOP_CATALOG_ENTRY_DEFAULTS_2026-10-11.md`。

2026-10-11 用户截图确认：入橱方式只保留确认页内单选，点击确认直接按已选方式保存，删除右侧重复选择弹窗及其状态/分支；取代 2026-09-27 二次弹窗旧要求。成功后仍统一提示与发放实际到账鱼币。

运营存量币种已按用户确认实际修复：开发库 seq 21，26 件商品涉及 38 条销售记录与 3 份价格修正补填 CNY；独立回读确认 0 条未明确币种。见 `docs/SHOP_CATALOG_OPERATOR_CURRENCY_REPAIR_2026-10-11.md`。
