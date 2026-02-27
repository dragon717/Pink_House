# 全屏视频转场与无缝切换最佳实践

本文档记录了在 少女心愿 项目中实现“House衣橱开门动画”时总结的沉浸式全屏视频转场技术方案。该方案解决了系统原生转场生硬、视频播放结束黑屏、界面切换突兀等常见问题。

## 1. 场景描述

用户在“House”界面点击“衣橱”热区时，需要执行以下流程：
1.  **触发**：立即全屏播放一段“打开衣橱”的过场动画（视频）。
2.  **播放**：视频覆盖全屏，隐藏所有 UI 元素（包括 TabBar）。
3.  **结束**：视频播放完毕后，**无缝**过渡到“衣橱”主界面。

## 2. 遇到的问题

### 2.1 原生 `fullScreenCover` 的局限性
*   **问题**：使用 SwiftUI 的 `.fullScreenCover` 会强制伴随从底部滑入/滑出的系统动画。
*   **影响**：破坏了沉浸感，用户体验像是“打开了一个新页面”而不是“进入了衣橱”。

### 2.2 视频播放结束后的“黑屏闪烁”
*   **问题**：`AVPlayer` 播放完最后一帧后，默认行为可能导致画面变黑或清空，或者在销毁播放器瞬间露出底色。
*   **影响**：在视频消失和新界面出现之间存在明显的视觉断层。

### 2.3 界面切换的突兀感
*   **问题**：如果等视频彻底播完消失后，再切换 Tab，用户会看到一瞬间的界面跳变。

## 3. 解决方案架构

### 3.1 核心策略：状态提升与 ZStack 顶层覆盖

不使用模态跳转，而是将视频播放器作为一个**全屏覆盖层 (Overlay)**，置于应用的最顶层（`MainTabView` 级别）。

*   **状态提升**：控制视频播放的 `Bool` 状态（如 `isPlayingOpeningAnimation`）不应局限在子视图（`SmallWorldView`），而应提升到根视图（`MainTabView`）。
*   **ZStack 布局**：在 `MainTabView` 的 `ZStack` 中，将视频层放在最上层（`zIndex` 高于所有内容）。

```swift
// MainTabView.swift
ZStack {
    // 1. 主内容层
    TabView(selection: $selectedTab) { ... }
    
    // 2. 视频播放覆盖层 (最顶层)
    if isPlayingOpeningAnimation {
        PetVideoPlayer(...)
            .zIndex(200) // 确保覆盖一切
            .transition(.opacity) // 使用渐变过渡
    }
}
```

### 3.2 防黑屏关键技术：定格最后一帧

为了防止视频播完变黑，必须修改 `AVPlayer` 的默认行为。

*   **关键代码**：`player.actionAtItemEnd = .pause`
*   **原理**：告诉播放器在播放完当前 Item 后，保持暂停在最后一帧，而不是尝试推进到下一个 Item（会导致黑屏）或停止。

```swift
// PetVideoPlayer.swift
if isLooping {
    player.actionAtItemEnd = .advance
} else {
    // 单次播放关键设置：暂停在最后一帧
    player.actionAtItemEnd = .pause 
    context.coordinator.setupObserver(item: newItem, onFinished: onFinished)
}
```

### 3.3 无缝过渡技巧：后台切换 + 淡出

利用视频层遮挡视线的机会，在后台完成界面切换，然后优雅地淡出视频层。

*   **步骤 1**：视频播放结束回调触发。
*   **步骤 2**：立即修改 Tab 状态，切换到底层的目标界面（此时用户看不见，因为被视频挡住了）。
*   **步骤 3**：使用 `withAnimation` 让顶层视频层 `opacity` 变为 0。

```swift
PetVideoPlayer(..., onFinished: {
    // 1. 幕后切换：此时画面仍定格在视频最后一帧
    homeTabSelection = .wardrobe
    selectedTab = 0
    
    // 2. 视觉过渡：视频层淡出，露出已经渲染好的衣橱界面
    withAnimation(.easeOut(duration: 0.8)) {
        isPlayingOpeningAnimation = false
    }
})
```

## 4. 最佳实践总结

1.  **沉浸式转场**：优先使用 `ZStack` + `Overlay` + `Transition`，避免使用系统模态跳转（Sheet/FullScreenCover）。
2.  **视频定格**：非循环视频播放务必设置 `player.actionAtItemEnd = .pause` 以防止结束时黑屏。
3.  **预加载/幕后切换**：在全屏遮罩存在时进行耗时的界面切换或数据加载，给用户“零加载”的错觉。
4.  **状态管理**：涉及跨页面/全屏效果的状态，应尽早提升到足以覆盖整个屏幕的父视图层级。

## 5. 相关文件引用

*   `MainTabView.swift`: 顶层布局与状态管理。
*   `SmallWorldView.swift`: 触发入口。
*   `PetVideoPlayer.swift`: 封装的 AVPlayer 播放器逻辑。
