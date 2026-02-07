# 萌宠功能设计文档

## 1. 概述
在应用底部导航栏中间位置新增“萌宠”入口。用户可以与虚拟小猫互动，照顾其饮食起居。
引入双货币系统（喵币、鱼币）和道具背包系统，支持拖拽喂食/饮水交互。

## 2. 核心系统

### 2.1 状态机 (State Machine)
萌宠的行为由有限状态机 (FSM) 控制。

**状态定义 (PetState):**
- **Idle (默认)**: 空闲状态，循环播放待机动画。
- **Eating**: 进食状态，播放进食动画。
- **Drinking**: 饮水状态，播放饮水动画（如无专用动画可复用进食或特定动画）。
- **Cleaning**: 清洁状态，播放洗澡/清洁动画。
- **Expecting**: (新增) 期待状态。当用户拖拽物品靠近小猫时触发，播放期待动画或显示 UI 提示。

### 2.2 经济系统 (Economy System)

**喵币 (Meow Coin):**
- **质地**: 闪亮的黄金质地 3D 圆形薄币。
- **获取**: 充值获得，汇率 1:10 (CNY)。
- **用途**: 购买 App Store 商品或兑换鱼币（可选）。
- **类型**: 充值货币 (Premium Currency)。

**鱼币 (Fish Coin):**
- **质地**: 黄铜质地 3D 圆形薄币。
- **获取**: 游戏内行为获取（每日登录、任务等），**每日上限 10,000**。
- **用途**: 购买食物、水碗等基础道具。
- **类型**: 游戏货币 (Soft Currency)。

### 2.3 道具系统 (Item System)

**道具类型 (PetItemType):**
1.  **Food (食物)**:
    *   猫饭 (Cat Rice)
    *   猫罐头 (Canned Food)
    *   猫条 (Cat Strip)
    *   冻干 (Freeze-dried)
    *   鸡胸肉 (Chicken Breast)
2.  **Water (饮水)**:
    *   温水 (Warm Water) - 容器：陶瓷高碗
    *   白开水 (Boiled Water) - 容器：不锈钢碗

**道具属性:**
- 名称
- 价格 (鱼币)
- 恢复属性值 (饱食度/清洁度/心情)
- 对应动画触发

### 2.4 交互系统 (Interaction)

**背包 (Inventory):**
- 用户购买的道具存放于背包。
- 界面底部显示背包栏/抽屉。
- 支持拖拽操作。

**拖拽交互 (Drag & Drop):**
1.  **Drag Start**: 用户按住背包中的物品。
2.  **Dragging**: 拖动过程中，小猫进入 **Expecting** 状态（UI 反馈/动画）。
3.  **Drop**:
    *   **On Pet**: 如果释放位置在小猫判定范围内 -> 消耗物品 -> 增加对应属性 -> 播放 Eating/Drinking 动画。
    *   **Outside**: 物品飞回背包，不消耗。

## 3. UI/UX 设计

### 3.1 萌宠主页
- **顶部区域**:
    *   状态条 (饱食度、清洁度)。
    *   **货币栏**: 显示喵币和鱼币数量，支持点击“+”号跳转充值/获取。
- **中央区域**:
    *   PetVideoPlayer。
    *   支持拖拽释放区域 (Drop Destination)。
- **底部区域**:
    *   **操作面板**:
        *   背包 (默认显示，横向滚动)。
        *   商店 (点击切换，购买物品)。
        *   清洁/其他互动按钮。

## 4. 数据持久化
- **PetStatus**: 增加 `meowCoin`, `fishCoin`, `dailyFishCoinEarned`, `lastDailyResetDate`。
- **Inventory**: 存储用户拥有的物品列表 `[ItemID: Count]`。

## 5. 开发计划
1.  **Model**: 更新 `PetStatus` 添加货币字段；定义 `PetItem` 和 `Inventory`。
2.  **ViewModel**: 实现购买、每日上限重置、背包管理、拖拽逻辑。
3.  **View**:
    *   实现货币显示组件。
    *   实现可拖拽的物品图标 (`.draggable`)。
    *   实现小猫区域的接收逻辑 (`.dropDestination`)。
    *   更新主界面布局。
