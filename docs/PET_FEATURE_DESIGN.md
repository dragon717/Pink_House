# 萌宠功能设计文档

## 1. 概述
在应用底部导航栏中间位置新增“萌宠”入口。用户可以与虚拟小猫互动，照顾其饮食起居。
核心玩法参考 Talking Tom，包含状态机驱动的动画播放系统和属性养成系统。

## 2. 核心系统

### 2.1 状态机 (State Machine)
萌宠的行为由有限状态机 (FSM) 控制。

**状态定义 (PetState):**
- **Idle (默认)**: 空闲状态，循环播放待机动画。
- **Eating**: 进食状态，播放进食动画，结束后自动切回 Idle。
- **Cleaning**: 清洁状态，播放洗澡/清洁动画，结束后自动切回 Idle。
- **Sleeping**: (可选) 睡眠状态。
- **Playing**: (可选) 玩耍状态。

**状态转换规则:**
- `Any` -> `Eating`: 用户点击“喂食”按钮。
- `Any` -> `Cleaning`: 用户点击“清洁”按钮。
- `Eating` -> `Idle`: 进食动画播放结束。
- `Cleaning` -> `Idle`: 清洁动画播放结束。

### 2.2 动画树 (Animation Tree)
基于当前状态播放对应的 MP4 视频资源。

**资源映射:**
- `Idle` -> `idle.mp4` (Loop)
- `Eating` -> `eat.mp4` (One-shot)
- `Cleaning` -> `clean.mp4` (One-shot)

**技术实现:**
- 使用 `AVPlayer` + `AVPlayerLayer` (或 SwiftUI `VideoPlayer`)。
- **Idle** 状态下启用 `AVPlayerLooper` 实现无缝循环。
- **Action** 状态下播放一次，监听 `.AVPlayerItemDidPlayToEndTime` 通知以切换回 Idle 状态。
- **注意**: 视频背景需与 UI 背景融合，或者使用 HEVC with Alpha 通道视频（如果源文件支持），否则需保证视频背景色与 App 背景一致。

### 2.3 属性系统 (Attributes)
小猫拥有随时间变化的属性。

**属性定义 (PetStatus):**
- **Hunger (饱食度)**: 0-100。随时间自然降低。进食增加。
- **Hygiene (清洁度)**: 0-100。随时间自然降低。清洁增加。
- **Mood (心情)**: (可选) 0-100。随时间/交互变化。

**衰减逻辑:**
- 使用 `Timer` 每分钟/每小时减少一定数值。
- 应用进入后台时记录时间戳，再次回到前台时计算离线期间的衰减量。

## 3. UI/UX 设计

### 3.1 导航栏
- 位置：底部 TabBar Index 2 (中间)。
- 图标：猫咪头像或类似图标 (e.g., `pawprint.fill`)。

### 3.2 萌宠主页
- **中央区域**: 显示小猫动画 (Video Player)。
- **顶部区域**: 状态条显示 (饱食度、清洁度进度条)。
- **底部区域**: 交互按钮 (喂食、清洁)。

## 4. 数据持久化
- 使用 `UserDefaults` 或 `AppStorage` 存储:
  - 当前属性值 (Hunger, Hygiene)。
  - 上次更新时间戳 (LastUpdateTime)。
  - 宠物名称/等级 (如果有)。

## 5. 开发计划
1. **Model**: 定义 `PetState`, `PetStatus`。
2. **ViewModel**: 实现 `PetViewModel`，处理状态切换、计时器、属性计算。
3. **View**: 实现 `PetVideoPlayer` (封装 AVPlayer) 和 `PetHomeView`。
4. **Integration**: 修改 `MainTabView` 加入入口。
