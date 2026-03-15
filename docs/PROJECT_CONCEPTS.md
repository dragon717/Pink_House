# 项目概念与专有词汇指南 (Project Concepts & Terminology)

本文档旨在总结 "少女心愿" (ItemManager) 项目中的核心场景、专有词汇及其在系统中的含义，帮助 AI 助手和开发者快速理解业务逻辑。

## 1. 核心场景 (Core Scenarios)

### 1.1 少女衣橱 (Wardrobe Management)
用户管理 Lolita 服饰的核心模块。
- **场景描述**: 用户录入裙装的详细信息（价格、日期、分类），系统提供统计、筛选和“尾款天使”提醒服务。
- **关键流程**:
    - **录入**: 添加裙装，记录定金、尾款、排期。
    - **尾款天使 (Deposit Plan)**: 针对预售款裙装的资金规划功能，帮助用户计算未来需要支付的尾款总额。
    - **裙装广场**: (预留) 分享和展示裙装的公共区域。

### 1.2 萌宠互动 (Pet Interaction)
不仅是电子宠物，更是用户的“衣橱管家”和“贴心闺蜜”。
- **角色**:
    - **奶茶 (Naicha)**: 一只傲娇、贪吃的小橘猫。
    - **毛毛 (Maomao)**: 一只热情、憨厚的金毛犬。
- **互动方式**:
    - **点击**: 触发动作反馈（如蹭蹭、叫声）。
    - **拖拽 (Drag-to-Analyze)**: 将宠物拖拽到屏幕上的裙装图片上，触发视觉识别，宠物会点评裙装（基于 AI）。
    - **对话**: 通过文字或语音与宠物交流，宠物会以“闺蜜”口吻回应。
    - **打工**: 派遣宠物去打工（如服务员、安保、主播）赚取喵币。

### 1.3 House (Small World)
宠物的虚拟生活空间，提供不同的视觉风格。
- **风格**: 洛可可 (Rococo)、法式复古 (French Retro)。
- **功能**: 宠物在此场景中自由活动（Idle, Walking, Sleeping）。

### 1.4 财富管理 (Wealth)
展示用户资产的模块，支持多货币换算。
- **场景**: 用户查看自己衣橱的总价值，并可以切换不同货币单位（如日元、黄金）来获得心理满足感。

### 1.5 VIP 会员体系
- **场景**: 提供高级 AI 功能的订阅服务。
- **权益**: 解锁基于 DeepSeek 的智能对话（普通用户只能使用复读机模式）。

---

## 2. 专有词汇表 (Terminology)

### 2.1 服饰与交易 (Clothing & Transaction)

| 词汇 | 英文 Key | 含义 | 备注 |
| :--- | :--- | :--- | :--- |
| **JSK** | `types` | Jumper Skirt | 无袖连衣裙，Lolita 常见款式，通常需要搭配内搭。 |
| **OP** | `types` | One-piece | 有袖连衣裙。 |
| **SK** | `types` | Skirt | 半身裙。 |
| **定金** | `deposit` | Deposit | 预售时支付的部分金额。 |
| **尾款** | `balance` | Balance | 发货前需补齐的剩余金额。 |
| **排期/工期** | `finalPaymentDate` | Schedule | 预计补款和发货的时间段。 |
| **截团** | - | Group Close | 团购结束的时间点。 |
| **小物** | `accessories` | Accessories | 搭配用的发带、袜子、手袖等配件。 |
| **掉落** | - | Spot Goods | 现货掉落，指预售结束后多余的现货。 |
| **H价/L价** | - | High/Low Price | 二手交易中的高价或低价。 |

### 2.2 萌宠系统 (Pet System)

| 词汇 | 英文 Key | 含义 | 备注 |
| :--- | :--- | :--- | :--- |
| **喵币** | `MeowCoin` | 基础货币 | 游戏内主要流通货币，用于购买道具、开通 VIP。 |
| **鱼币** | `FishCoin` | 高级货币 | 稀有货币（预留）。 |
| **骨头币** | `BoneCoin` | 特殊货币 | 狗狗专属或特殊活动产出。 |
| **打工** | `Job` | Work | 宠物挂机赚取喵币的状态。职业包括：服务员、保安、主播。 |
| **饥饿度** | `hunger` | Hunger | 影响宠物状态的数值，需要喂食。 |
| **心情** | `mood` | Mood | 影响宠物互动反馈的数值。 |

### 2.3 技术与 AI (Technology)

| 词汇 | 含义 | 备注 |
| :--- | :--- | :--- |
| **Vision Analysis** | 视觉分析 | 使用 Apple Vision 或 Qwen-VL 对屏幕截图进行分析，识别裙装信息。 |
| **Wardrobe Context** | 衣橱上下文 | 将用户的衣橱数据（最贵的裙装、最近买的裙装）注入 AI Prompt，让 AI 具备记忆。 |
| **Echo Mode** | 模仿复述 | 非 VIP 模式下的语音互动，宠物单纯变声复述用户的话。 |
| **Smart Chat** | 智能对话 | VIP 模式下的语音互动，接入 LLM (DeepSeek) 进行角色扮演对话。 |

### 2.4 界面与视觉 (UI/UX)

| 词汇 | 含义 | 备注 |
| :--- | :--- | :--- |
| **黑金卡** | Black Gold Card | VIP 会员的身份象征，卡面设计为黑金渐变，带有光泽感。 |
| **靓号** | Lucky Number | VIP 编号，算法倾向于生成含 6, 8, 9, 0 的数字。 |
| **液态数字** | Liquid Number | 财富界面中数字滚动的特效，带有粘滞感和玻璃光泽。 |
| **拖拽吸附** | Snap | 宠物被拖拽到屏幕边缘或线条上时，会自动吸附并改变姿态（如趴在横线上）。 |

---

## 3. 数据模型简述 (Data Models)

### Clothing (Model)
*   `originalPrice` (原价) vs `price` (购入价/总价)
*   `deposit` (定金) + `balance` (尾款) = 总支出
*   `status`: 上架/下架 (OnShelf/OffShelf)

### PetStatus (Model)
*   `vipStatus`: 包含 `isActive`, `expireDate`, `vipNumber`。
*   `currentJob`: 当前正在进行的打工任务。

### WealthViewModel (ViewModel)
*   支持汇率换算：CNY -> JPY (Lolita 日牌常用)。
*   实物等价物：黄金 (Gold)、白银 (Silver) 的克重换算。
