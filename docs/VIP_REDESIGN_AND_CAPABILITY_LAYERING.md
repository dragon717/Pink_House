# VIP 页面重构与能力分层说明

更新时间：2026-04-03

## 1. 目标

本轮改造统一落地以下内容：

- VIP 页面改造成深色玻璃质感的权益页
- 试用期弹窗与 VIP 页面使用同源视觉风格
- 会员套餐改为 `1个月 66喵币 / 3个月 188喵币`
- 萌宠商店落地 VIP `6折`
- 主题皮肤商店预留 VIP `9折` 折扣接口
- 萌宠智能对话改为“入口不拦截，但第三方模型/API 能力引导升级 VIP”
- 魔法配色纳入 VIP 权益，但已单独永久解锁的用户不受 VIP 到期影响

---

## 2. 视觉主题

### 2.1 页面主题

首批提供三套同源 VIP 视觉主题：

- `black`
  - 黑色背景
  - 亮黑色玻璃卡
  - 白灰柔光描边
- `deepBlue`
  - 深蓝背景
  - 冰蓝玻璃卡
  - 冰蓝柔光描边
- `monicaPink`
  - 莫妮卡粉背景
  - 亮粉色玻璃卡
  - 亮粉柔光描边

### 2.2 主题映射

- 未开通 VIP：默认 `deepBlue`
- 已开通 VIP 且卡皮肤为 `blackGold`：使用 `black`
- 已开通 VIP 且卡皮肤为 `monicaPink`：使用 `monicaPink`

---

## 3. 页面结构

VIP 页面采用以下结构：

1. 顶部品牌栏
2. Hero 标语区
3. 会员权益宫格
4. 套餐选择区
5. 主 CTA
6. 协议说明区

### 3.1 权益宫格映射

- 智能统计
  - 复用本地衣橱统计能力
- 多模态智能
  - 入口统一，免费用户使用本地识别，VIP 解锁完整第三方分析
- VIP身份
  - 映射当前 VIP 身份、靓号、卡片皮肤
- 付费内容优惠
  - 首批落地萌宠商店 `-40% OFF`
- 会员周报
  - 待做，占位展示
- 魔法配色
  - 作为 VIP 权益之一
- 个性图标
  - 规划纳入 `少女心愿logo.icon`
- 持续更新
  - 作为宽卡提示后续权益持续补充

---

## 4. 套餐与折扣

### 4.1 VIP 套餐

- 一个月：`66喵币`
- 三个月：`188喵币`
- 三个月折扣展示：`-5% OFF`

说明：

- 精确优惠约为 `5.05%`
- UI 统一展示为 `-5% OFF`

### 4.2 商店折扣

- 萌宠商店：`6折`
  - 展示文案：`-40% OFF`
- 主题皮肤商店：`9折`
  - 先预留接口
  - 展示文案：`-10% OFF`

---

## 5. 能力分层

### 5.1 免费可用

- 纯本地能力
- 调本地模型的能力
- 衣橱统计
- 萌宠状态 / 背包 / 商店 / 货币面板
- 本地图片识别的第一层结果

### 5.2 VIP 专属

- 所有会调第三方模型/API 的能力
- 萌宠智能对话
- AI 穿搭建议
- 天气穿搭的完整智能建议
- 多模态图片分析的完整版本

### 5.3 交互原则

- 不拦截聊天入口
- 用户进入聊天页后，免费能力正常使用
- 用户触发第三方模型/API 能力时，展示“撒娇式升级引导”
- 升级引导支持跳转 VIP 页面和喵币商店

---

## 6. 魔法配色规则

魔法配色已纳入 VIP 权益，但需兼容历史永久解锁用户：

- 若用户已花喵币永久解锁 `themeCustomize`
  - 即使 VIP 到期，也不能关闭
- 若用户未单独解锁，但当前为 VIP
  - VIP 期间可直接使用

因此需要区分：

- `永久解锁`
- `VIP 临时可用`

---

## 7. 个性图标一期

个性图标功能一期计划纳入以下资源：

- 当前默认 App Icon
- `ItemManager/少女心愿logo.icon`

其中 `少女心愿logo.icon` 资源已在 git 历史中经历多轮更新，当前版本使用 `logo-new.png`。

---

## 8. 首批落地文件

- `ItemManager/Views/VIP/VIPVisualSystem.swift`
  - VIP 视觉主题、玻璃卡样式、套餐与权益模型
- `ItemManager/Services/VIP/VIPManager.swift`
  - 套餐价格、折扣文本、视觉主题来源
- `ItemManager/Views/VIP/VIPCenterView.swift`
  - 新 VIP 权益页
- `ItemManager/Views/VIP/VIPTrialPopupView.swift`
  - 同源试用期弹窗
- `ItemManager/Services/FeatureUnlockManager.swift`
  - 魔法配色的 VIP 临时访问桥接
- `ItemManager/Views/Settings/MagicColorSettingsView.swift`
  - 改用有效访问判定
- `ItemManager/Views/PetChat/PetChatVIPAccessSupport.swift`
  - 聊天升级引导文案与快捷按钮
- `ItemManager/Views/PetChat/PetChatView.swift`
  - 新聊天页 VIP 分层
- `ItemManager/Views/PetChat/PetChatViewLegacy.swift`
  - 旧聊天页 VIP 分层
- `ItemManager/Views/Pet/AI/ChatView.swift`
  - 独立宠物 AI 聊天页也统一改为发送前升级引导
- `ItemManager/Views/Pet/Components/AIAnalysisResultView.swift`
  - 图片分析结果页的“继续问问”改为 VIP 引导
- `ItemManager/Views/Pet/Components/PetAIAnalysisService.swift`
  - 免费用户保留本地识别结果，远程分析改为升级引导
- `ItemManager/Views/Pet/PetViewModel.swift`
  - 萌宠商店结算使用 VIP 折扣价，并补齐语音 AI 的 VIP 分层
- `ItemManager/Views/Pet/PetBottomPanel.swift`
  - 萌宠商店显示会员价
- `ItemManager/Views/Pet/PetComponents.swift`
  - 商店商品卡显示原价/折扣信息
- `ItemManager/Views/Pet/PetHomeView.swift`
  - 萌宠语音聊天入口改为允许进入模式，远程请求时再引导升级
- `ItemManager/Services/VIP/VIPAppIconManager.swift`
  - 应用图标配置、当前图标状态与系统切换封装
- `ItemManager/Views/VIP/VIPAppIconSelectionView.swift`
  - VIP 个性图标库页面

## 10. 个性图标二期前的首版实现

首版已经落地：

- 主图标：`少女心愿立体`
  - 资源来源：`8b9cf4d`
  - 对应 asset：`少女心愿logo.appiconset`
- 备选图标：`经典图标`
  - 对应 asset：`ClassicAppIcon.appiconset`

接入方式：

- VIP 用户可在 VIP 中心进入“个性图标库”
- 图标切换使用系统 alternate icon 能力
- 图标预览和图标资源分开维护，便于后续扩容

---

## 9. 后续待做

- 会员周报真实数据结构与生成逻辑
- 个性图标切换的系统级实现
- 主题皮肤商店的实体页面与 9 折结算
- 更细的“本地能力 / 本地模型 / 第三方模型”能力注册表
