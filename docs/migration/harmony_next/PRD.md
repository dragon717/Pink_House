# 少女心愿 · HarmonyOS Next 5 版 PRD

> 文档版本：v1.0 · 最后更新：2026-04-20
> 上游：`docs/migration/00_PRODUCT_SPEC_CROSS_PLATFORM.md`
> 同级：`TECH_DESIGN.md`、`MIGRATION_PLAN.md`、`ACCEPTANCE_TESTS.md`
> 姊妹参考：`docs/migration/android/PRD.md`（产品决策高度复用）

---

## 1. 版本定位

**一句话**：HarmonyOS Next 5.0 原生 HAP 包（纯鸿蒙，不兼容 Android 运行时）。功能集与 Android 版一致，但**原生接入鸿蒙生态能力**（HMS IAP、分布式能力预留、服务卡片等）。

### 1.1 兼容目标
- **最低支持**：HarmonyOS Next API 12（2024 Q4 首个正式版）
- **Target API**：HarmonyOS Next API 14（截至 2026-04）
- **DevEco Studio**：5.0+
- **ArkTS**：严格模式
- **测试重点设备**：华为 Mate 70 / Pura 70 / MatePad 13.2 / 折叠屏 Mate X6

### 1.2 HarmonyOS 3/4 不在此包范围
HarmonyOS 3/4 设备走 **Android 版 APK**（见 `android/PRD.md`），因为鸿蒙 3/4 仍兼容 Android 运行时。本文档只描述 **鸿蒙 Next 5.0 及以上** 的纯鸿蒙实现。

### 1.3 发行渠道
华为 AppGallery（鸿蒙 Next 分区）。**无其他渠道**，因鸿蒙 Next HAP 包格式仅 AppGallery 分发。

---

## 2. 与 Android 版的差异（仅列差异项）

> 产品决策 **95% 同步 Android**，本节只列不一致的点。未列入差异项的功能，行为与 Android 版完全一致。

### 2.1 支付通道
- Android：微信支付 + 支付宝
- **鸿蒙 Next：HMS IAP（华为应用内支付）**
  - 单一通道，无需多支付聚合
  - 华为 AGC 已提供订单签名校验，本地验证签名即可
  - 不做微信/支付宝（鸿蒙 Next 上微信支付 SDK 稳定性尚在观察）

### 2.2 服务卡片（类 Widget）
- Android：**不做** Widget
- **鸿蒙 Next：Should 级别做 Service Card**
  - 2x2 卡片：显示宠物头像 + 饱食度 + 今日签到入口
  - 2x4 卡片：显示衣橱总资产 + 最近一件衣物
  - 卡片点击跳转应用内对应页面
  - 实现：ArkTS Card 组件 + `formExtensionAbility`

### 2.3 分布式能力（v1.1+ Should，v1.0 不做）
鸿蒙 Next 特性：跨设备流转。v1.0 不做；v1.1 可考虑：
- 手机衣橱数据**一键流转**到平板
- 平板编辑同步回手机

### 2.4 意图框架 / HMS AI Engine（**不使用**）
用户确认 Android/鸿蒙 Next 不接 AI。即使 HMS 提供 AI 引擎（HiAI、图像识别等），**本版本也不接入**。

### 2.5 推送（本地提醒机制差异）
- Android：`AlarmManager` + `BroadcastReceiver`
- **鸿蒙 Next：`@ohos.reminderAgentManager`**
  - 鸿蒙原生提醒代理，系统托管，后台生存率更高
  - 三类提醒渠道：`reminderType_Alarm`（签到）、`reminderType_Calendar`（尾款）、`reminderType_Timer`（宠物）

### 2.6 视频播放（宠物动画）
- Android：ExoPlayer，HEVC Alpha 需验证
- **鸿蒙 Next：`@ohos.multimedia.media`（AVPlayer）**
  - 鸿蒙 Next AVPlayer 对透明视频支持**有限**，**建议降级为序列帧 PNG 动画**
  - 宠物动画文件需重出序列帧版本（与 Android 一致）

### 2.7 拖拽
- Android：Compose `DragAndDropTarget`
- **鸿蒙 Next：`@ohos.multimodalInput` + ArkUI `DragEvent`**
- 鸿蒙 Next 拖拽 API 相对新，需原型验证

### 2.8 字体
- Android：打包 `res/font/` 字体资源
- **鸿蒙 Next：`resources/rawfile/fonts/` + `@ohos.font.registerFont`**

### 2.9 隐私与合规
- Android：启动时弹隐私政策（国内合规）
- **鸿蒙 Next：同样需要**，且 AppGallery 对隐私声明格式要求更严格
- 需提供 **"个人信息收集清单"** 和 **"第三方 SDK 清单"**（鸿蒙 Next 无第三方 SDK 的话就明示）

### 2.10 分享
- Android：`Intent.ACTION_SEND`
- **鸿蒙 Next：`@ohos.systemShare`** 或 **碰一碰分享**
  - 首版只做系统分享 Sheet
  - v1.1 可考虑一碰分享（鸿蒙特色）

---

## 3. 功能范围（与 Android 对齐）

### 3.1 Must（MVP v1.0）
与 Android 完全一致，F-01 ~ F-53 全部做。**支付改为 HMS IAP**。

### 3.2 Should（v1.1+）
- S-01 鸿蒙 Service Card（2x2 + 2x4）
- S-02 **分布式流转（跨设备衣橱流转）** — 产品侧确认 v1.1 做
- S-03 备份压缩（zip 含图片）
- S-04 一碰分享
- S-05 大屏适配（平板 / 折叠屏展开态）

### 3.2-天气 F-55 天气集成（一期做，联网）
- **API**：**和风天气免费版**（与 Android 同一供应商，**共享 API key**，两端调用总量统一计费）
- **认证**：JWT 签名
- **权限**：`ohos.permission.APPROXIMATELY_LOCATION`（粗略位置），用户拒绝则用 IP 定位
- **调用方式**：ArkTS `@ohos.net.http` 发 HTTPS 请求
- **集成位置与降级策略**：同 Android（小世界右上角组件，失败隐藏，缓存 6h）
- **免费额度**：1000 次/天共享，Android + 鸿蒙合计 DAU 50 以内免费可覆盖，超出同 Android 方案

### 3.3 Won't
与 Android 一致的 Won't 列表，外加：
- W-14 **不接入 HMS AI 引擎**（用户要求无 AI）
- W-15 **不做纯鸿蒙 3/4 HAP**（走 Android 包）

---

## 4. HMS IAP 详细流程

### 4.1 开通与充值
1. 用户点击"开通 VIP"或"充值喵币"
2. 本 App 调用 `@hms.core.iap.pay`，传入 `productId`（对应 HMS 后台创建的商品 ID）
3. HMS 拉起华为支付页
4. 支付完成 → HMS 回调返回订单 `InAppPurchaseData` + `InAppDataSignature`
5. 本地用 HMS 公钥验签（`@hms.core.iap.Iap.verifySignature`）
6. 验签通过 → 本地订单表入库 + 发放喵币/VIP 权益
7. 调用 `@hms.core.iap.consumeOwnedPurchase`（消耗型商品，喵币）或 `acknowledgePurchase`（非消耗型，VIP）

### 4.2 异常处理
- 支付中断（用户取消）→ 仅记录 pending 订单，不加币
- 验签失败 → 弹错误 toast "订单验证失败，请联系客服"，不加币
- 订单已消耗再次回调 → 幂等判断，直接返回成功
- 恢复购买：VIP 会员 App 重装时支持 `queryOwnedPurchases` 拉取历史订单恢复权益

### 4.3 商品 ID 命名规范（6 档喵币，与 iOS / Android 对齐）

| 档位 | iOS 商品 ID | HMS ProductID | 类型 | 价格 |
|---|---|---|---|---|
| 60 喵币 | `com.pinkhouse.app.meowcoin_60` | `meowcoin_60` | 消耗型 | ¥6 |
| 120 喵币 | `com.pinkhouse.app.meowcoin_120` | `meowcoin_120` | 消耗型 | ¥12 |
| 300 喵币 | `com.pinkhouse.app.meowcoin_300` | `meowcoin_300` | 消耗型 | ¥30 |
| 500 喵币（热门） | `com.pinkhouse.app.meowcoin_500` | `meowcoin_500` | 消耗型 | ¥50 |
| 1280 喵币（最划算） | `com.pinkhouse.app.mcoin_1280` | `mcoin_1280` | 消耗型 | ¥128 |
| 3280 喵币 | `com.pinkhouse.app.mcoin_3280` | `mcoin_3280` | 消耗型 | ¥328 |

**注意**：
- **VIP 不是 IAP 商品**，无需在 HMS 后台创建 VIP 相关 productId
- VIP 开通通过**花喵币实现**（月卡 66 喵币、季卡 188 喵币），与 iOS/Android 一致
- 赠送策略（首充双倍、非首充 +10%~+35%）完全沿用 iOS 实现，无需在 HMS 后台配置，由 App 内逻辑计算

---

## 5. 非功能需求（差异点）

### 5.1 性能
- 冷启动 < 2.0 秒（鸿蒙 Next 启动管理较严，时间更短）
- 应用不活跃 5 分钟后进入冻结态是鸿蒙特性，需确保冻结前保存所有用户数据

### 5.2 设备覆盖
- 主要手机：Mate 70、Pura 70、Nova 12
- 平板（MatePad）：v1.0 保证能运行，v1.1 做大屏适配
- 折叠屏（Mate X5/X6）：展开态 v1.0 不专门适配（与平板类似）
- 智慧屏 / 手表：v1.0 **明确不支持**

### 5.3 AppGallery 合规要求
- 必须提供**隐私政策**和**用户协议**（含具体 URL）
- 必须通过华为 AGC 的**隐私扫描**
- IAP 必须用 HMS IAP，**不可跳转外部网页支付**（否则拒审）
- 启动页广告：一律不做
- 儿童保护：若面向全年龄段需声明年龄分级（本应用定位 12+）

---

## 6. 数据迁移

### 6.1 从 iOS / Android 迁移到鸿蒙 Next
JSON 备份格式三端统一（见 `00_PRODUCT_SPEC_CROSS_PLATFORM.md` 第 6 节）。

鸿蒙 Next 端导入步骤：
1. 文件通过华为分享 / 一碰 / 微信 / 邮件传输到鸿蒙 Next 设备
2. 设置 → 数据管理 → 导入 → 选文件（`@ohos.filePicker`）
3. 解析 JSON，识别版本号，应用对应策略
4. 导入完成提示

### 6.2 鸿蒙 Next 之间迁移
- v1.0：走 JSON 导出导入
- v1.1（Should）：分布式流转一键迁移

---

## 7. 交付里程碑

| 阶段 | 范围 | 周数 |
|---|---|---|
| M1 环境搭建 + 数据层 | DevEco Studio 环境、RDB Store 建模、ArkUI 脚手架 | 2 周 |
| M2 衣橱核心 | F-01 ~ F-10 | 3 周 |
| M3 宠物 + 小世界 | F-11 ~ F-25 | 3 周 |
| M4 签到/日历/尾款/通知 | F-26 ~ F-29 + F-36 ~ F-38（含 reminderAgent） | 2 周 |
| M5 财富 + 拼豆 + OOTD | F-30 ~ F-31 + F-39 ~ F-41 + F-50 ~ F-53 | 2 周 |
| M6 VIP + HMS IAP | F-32 ~ F-35 | 2 周 |
| M7 备份 + 设置 + 分享 + 引导 | F-42 ~ F-49 | 1.5 周 |
| M8 联调 + 全量 QA | ACCEPTANCE_TESTS 全跑 | 2 周 |
| M9 AGC 送审 | 隐私扫描、合规整改 | 1.5 周 |

**总计：约 19 周**（与 Android 持平），建议在 Android 进入 M5 时启动鸿蒙 Next 的 M1，**功能对齐周期可压缩 4-6 周**（复用 Android 产品决策与视觉稿）。

---

## 8. 成功指标

同 Android，额外关注：
- AGC 审核通过率（首次送审通过率 > 70%）
- 鸿蒙 Next 设备崩溃率 < 0.5%
- 分布式流转使用率（v1.1 后观察）

---

## 9. 开放问题

1. **HMS IAP 开发者账号**：是否已注册？个人开发者 vs 企业开发者权益差异？
2. **鸿蒙 Next 支付商品 ID 命名** 是否与 iOS StoreKit 保持一致（便于运营统一管理）？
3. **分布式能力优先级**：v1.1 要不要冲？鸿蒙 Next 的差异化卖点就是这个，产品侧评估。
4. **HEVC Alpha 视频**在鸿蒙 Next AVPlayer 上能跑吗？需先做原型验证，否则动画需全改序列帧。

---

**文档结束**。
