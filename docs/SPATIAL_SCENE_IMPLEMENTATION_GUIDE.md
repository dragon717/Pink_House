# iOS 26 Spatial Scene (空间场景) 实现与最佳实践指南

## 1. 概述

本项目旨在利用 iOS 26 引入的 `RealityKit` 新特性（`Spatial3DImage`），将普通的 2D 背景图转化为具有深度信息的 3D 空间场景（Spatial Scene）。同时，为了在当前开发环境（Xcode 26.2 / iOS 18+）下保证项目可运行且具备演示效果，我们设计了一套完整的 **Mock（模拟）+ Fallback（降级）** 架构。

## 2. 核心架构设计

我们采用了 **"资源预加载 + 双渲染路径"** 的架构模式。

### 2.1 模块职责

*   **`SpatialAssetManager` (Service)**
    *   **单例管理**：全局管理空间资源的生命周期。
    *   **异步预加载**：在 App 启动阶段（Splash Screen）即开始在后台线程进行资源的 I/O 读取和 AI 生成（模拟耗时）。
    *   **缓存机制**：避免重复生成，提升二次进入的体验。
    *   **线程安全**：使用 `Task.detached` 将繁重的图片编解码和文件写入操作移出主线程，杜绝 UI 卡顿。

*   **`SmallWorldView` (Container)**
    *   **状态监听**：监听 `assetManager` 的加载状态，展示加载进度或最终视图。
    *   **交互分发**：管理顶层的点击事件（OOTD、衣橱、日历等），并将其传递给渲染层。

*   **`SpatialBackgroundView` (Renderer)**
    *   **双路径渲染**：
        *   **Path A (iOS 26 Native)**: 使用 `RealityView` 和 `ImagePresentationComponent`，由系统接管渲染和视差。
        *   **Path B (Mock/Fallback)**: 使用 SwiftUI `Image` + `CoreMotion`，手动模拟陀螺仪视差效果。

### 2.2 数据流向

```mermaid
[App Launch] -> [SpatialAssetManager.preload()] -> (Background Thread: I/O & AI Gen) -> [MainActor: isReady = true]
                                                                                                |
[SmallWorldView] <---------------------------------(Observes)-----------------------------------+
       |
       v
(if iOS 26 && Real Device) -> [RealityView (Spatial3DImage)]
(else) -> [Image + CoreMotion Parallax]
```

## 3. 关键技术实现与最佳实践

### 3.1 性能优化：拒绝主线程 I/O

**问题**：在 `GeometryReader` 或 `body` 中直接调用 `UIImage(contentsOfFile:)` 会导致每一帧重绘时都进行文件读取和解码，造成严重的 FPS 下降和卡顿。

**最佳实践**：
1.  **后台预处理**：将图片从 Asset Catalog 导出到临时文件的操作完全放在后台线程 (`Task.detached`)。
2.  **内存缓存**：在 View 的 `onAppear` 中异步加载一次图片并存储在 `@State` 变量中，后续渲染直接使用内存对象。

```swift
// ❌ 错误示范：每一帧都在解码
Image(uiImage: UIImage(contentsOfFile: path)!)

// ✅ 正确示范：一次加载，多次渲染
@State private var cachedImage: UIImage?
// ...
if let image = cachedImage {
    Image(uiImage: image)
}
```

### 3.2 交互体验：消除“双重视差”与“白线”

**问题 1**：iOS 26 原生 `Spatial3DImage` 自带视差效果，如果外部再叠加 `offset`，会导致背景“乱晃”甚至眩晕。
**解决**：在真实渲染路径下，完全禁用手动的 `CoreMotion` 偏移，将渲染管线交给系统。

**问题 2**：交互热区（Hotspots）如果只是简单的 2D 叠加，在手机倾斜时会与 3D 背景错位（漂移）。
**解决**：
*   **原生环境**：将热区作为不可见的 `ModelEntity` 挂载到 RealityKit 的 3D 坐标系中，使其随背景一同产生深度位移。
*   **消除白线**：设置热区材质为 `UnlitMaterial(color: .clear)` 并强制 `OpacityComponent(opacity: 0.0)`，防止产生高光或边框伪影。

### 3.3 稳定性：Mock 环境的优雅降级

**问题**：在不支持的模拟器或旧系统上强行调用 `RealityView` 会导致大量底层渲染错误日志（`engine:throttleGhosted`, `Video texture allocator`），甚至崩溃。

**解决**：
1.  **条件编译/运行**：使用 `if #available(iOS 26, *)` 严格隔离代码。
2.  **Mock 回退**：在当前 Mock 阶段，暂时注释掉 `RealityView` 代码，仅启用 `Image` + `CoreMotion` 的高保真模拟。这既保证了开发时的日志干净，又提供了足够逼真的演示效果。
3.  **权限声明**：使用 `CoreMotion` 必须在 `Info.plist` 中添加 `NSMotionUsageDescription`，否则会导致权限错误。

### 3.4 视觉微调：Mock 视差参数

为了让 Mock 效果接近真实的 Spatial Scene，我们调整了以下参数：
*   **Scale**: 1.15x (防止位移时露出黑边)
*   **Parallax**: Roll * 30pt, Pitch * 30pt (收敛的移动范围，避免过度夸张)
*   **Animation**: `interactiveSpring(response: 0.2, dampingFraction: 0.8)` (弹性跟手，模拟物理惯性)

## 4. 未来迁移指南 (To iOS 26)

当 iOS 26 SDK 正式发布且项目准备迁移时，请执行以下步骤：

1.  **移除 Shadow Types**：删除 `SpatialAssetManager.swift` 中 `#if os(iOS)` 包裹的 `ImagePresentationComponent` 模拟定义。
2.  **启用 RealityView**：在 `SmallWorldView.swift` 中取消对 `RealityView` 代码块的注释。
3.  **验证热区坐标**：在真实设备上调试 `addSpatialHotspot` 的 `position` (x, y, z)，确保与背景图中的物体精确对齐。
4.  **移除 Mock 逻辑**：可以逐步移除 `CMMotionManager` 相关的回退代码，完全依赖系统渲染。

## 5. 总结

通过这一套架构，我们成功地在**“未来的 API”**与**“现在的开发环境”**之间架起了一座桥梁。既实现了对未来特性的探索和布局，又保证了当前版本的稳定性和流畅度。
