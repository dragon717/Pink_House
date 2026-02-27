# 2D/3D OOTD 重构与功能设计文档

## 1. 概述

本文档旨在阐述将原有的 OOTD（穿搭手帐）模块重构为"手帐本"层级结构，并引入 3D 试衣间功能的技术与交互设计方案。

### 核心目标
1.  **情感化升级**：从"列表"变为"手帐"，增强整理与记录的仪式感。
2.  **层级管理**：引入 `BookGroup`（手帐本）-> `Outfit`（书页）的两级结构。
3.  **技术前瞻**：引入 3D 试衣间，使用 Apple Object Capture API 实现 iOS 原生 3D 建模。

---

## 2. 2D OOTD 重构：手帐系统

### 2.1 数据模型变更

在 `Clothing.swift` 中引入新模型并更新现有模型关系。

*   **BookGroup (手帐本)**
    *   `id`: UUID
    *   `title`: String (如"2026春季"、"旅行穿搭")
    *   `coverImage`: String? (预留，封面图)
    *   `createdAt`: Date
    *   `isDeleted`: Bool (软删除标记)
    *   `deletedAt`: Date?
    *   `pages`: [Outfit] (一对多关系)

*   **Outfit (书页/搭配)**
    *   新增 `book`: BookGroup? (所属手帐)
    *   新增 `isDeleted`: Bool
    *   新增 `deletedAt`: Date?
    *   **迁移策略**：旧版本 `book` 为空的 `Outfit`，在应用启动时自动归档至系统自动创建的"默认手帐"。

### 2.2 交互逻辑

#### 侧边栏 (OOTDSidebarView)
*   **层级展示**：
    *   最外层为 `BookGroup` 列表。
    *   点击手帐本标题展开/折叠，显示其下的 `Outfit` 书页列表。
    *   **视觉隐喻**：手帐本采用文件夹或书脊样式，书页保留缩略图卡片样式。
*   **管理操作**：
    *   **新增手帐**：侧边栏顶部提供"新建手帐"入口。
    *   **手帐操作**：支持重命名、删除（软删除，连带删除书页）。
    *   **书页操作**：
        *   **移动**：长按书页或点击菜单，选择"移动到..."，可转移至其他手帐。
        *   **删除**：软删除，进入回收站。

#### 主画布 (OOTDView)
*   **新建逻辑**：新建书页时，默认添加到当前选中的手帐本；若无选中，则添加到"默认手帐"。
*   **背景图**：支持自定义背景，模拟"手帐纸张"质感。

#### 回收站 (RecycleBinView)
*   **分组显示**：
    *   **已删除手帐**：以文件夹形式显示，点击可展开查看包含的书页。支持"整本恢复"或"彻底删除"。
    *   **孤立书页**：单独删除的书页显示在"单独删除的书页"分组下。
*   **恢复逻辑**：
    *   恢复手帐时，其包含的所有书页一并恢复。
    *   恢复单独书页时，若原手帐仍存在，则放回原手帐；若原手帐已彻底删除，则提示移动到"默认手帐"或新建手帐。

---

## 3. 3D OOTD：三维试衣间

### 3.1 功能入口
*   **位置**：集成在"House (Small World)"模块中。
*   **方式**：
    1.  底部 Tab "House" -> 长按呼出菜单 -> 选择 **"3D试衣"** (青色图标)。
    2.  House主菜单模式下直接点击入口。

### 3.2 技术方案 (SpatialCanvasEditorView)

#### 渲染引擎
*   使用 **RealityKit** 作为 3D 渲染引擎（Apple 原生、高性能、AR 集成）。
*   通过 **Object Capture API** 实现 iOS 设备端 3D 建模。

#### 核心功能
1.  **场景漫游**：
    *   支持单指旋转 (Orbit Control)。
    *   支持双指缩放 (Zoom) 和平移 (Pan)。
    *   支持点击选择对象。

2.  **3D 模型生成 (Object Capture)**：
    *   **设备要求**：需要 LiDAR 设备（iPhone 12 Pro 及以上）。
    *   **输入方式**：
        - **相机扫描**：引导用户围绕物体拍摄多角度照片。
        - **图库选择**：从相册选择已有照片（建议 20+ 张）。
    *   **处理流程**：图片预处理 -> PhotogrammetrySession -> 生成 USDZ 模型。
    *   **输出格式**：USDZ（Apple 通用 3D 格式）。

3.  **非 LiDAR 设备处理**：
    *   检测设备是否支持 Object Capture。
    *   不支持时显示友好提示："您的设备不支持 3D 建模功能，需要 iPhone 12 Pro 及以上机型"。
    *   不创建占位模型，直接返回错误信息。

4.  **环境控制**：
    *   预留环境光 (IBL) 切换接口，模拟不同光照下的材质表现。

### 3.3 数据模型

#### SceneObject (场景对象)
```swift
public enum SceneObjectType {
    case usdzModel   // Object Capture 生成的模型
    case primitive   // 基本几何体
}

public struct SceneObject {
    let id: UUID
    var type: SceneObjectType
    var position: SIMD3<Float>
    var rotation: SIMD3<Float>
    var scale: SIMD3<Float>
    var usdzModelPath: String?
    var color: SIMD4<Float>
}
```

#### SceneObjectData (持久化模型)
*   使用 SwiftData 持久化场景对象。
*   支持与 `SpaceOutfit` 关联。

### 3.4 关键服务

#### ObjectCaptureService
*   封装 Object Capture API 调用。
*   管理图片预处理和模型生成。
*   处理设备兼容性检查。

#### ObjectCaptureSessionManager
*   管理相机扫描会话状态。
*   处理扫描引导和进度反馈。

---

## 4. 数据迁移与兼容性

### 4.1 迁移策略 (Migration)
*   **时机**：`OOTDView` 的 `onAppear`。
*   **逻辑**：
    1.  检测是否存在 `book == nil` 的 `Outfit`（孤儿数据）。
    2.  若存在，检查是否存在名为"默认手帐"的 `BookGroup`。
    3.  若不存在"默认手帐"，则自动创建。
    4.  将所有孤儿数据关联到该手帐。
    5.  执行 `modelContext.save()`。
*   **安全性**：仅修改关系指针，不修改用户内容数据。

---

## 5. UI/UX 细节

*   **图标体系**：
    *   手帐：`book.closed.fill` / `book.fill`
    *   书页：`doc.text` / `tshirt`
    *   3D：`cube.transparent`
    *   相机扫描：`camera.fill`
    *   图库选择：`photo.on.rectangle`
*   **动效**：
    *   侧边栏展开/折叠使用 `withAnimation`。
    *   3D 视图加载使用进度遮罩。
    *   模型处理阶段动画（准备中 -> 处理中 -> 上传中）。
*   **反馈**：
    *   保存、删除等操作增加 Haptic Feedback (触感反馈)。
    *   非支持设备显示友好错误提示。

---

## 6. 后续规划 (Roadmap)

1.  **AR 预览**：利用 RealityKit 的 AR 能力，在真实环境中预览 3D 模型。
2.  **手帐贴纸系统**：在 2D 手帐中增加胶带、贴纸等装饰元素。
3.  **2D/3D 联动**：在 3D 试衣间截图，自动生成透明背景图导入 2D 手帐。
4.  **模型优化**：提供模型简化、纹理优化等后处理选项。
5.  **云端同步**：支持 iCloud 同步 3D 模型数据。

---

## 7. 技术架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    SpatialCanvasEditorView                   │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ CanvasToolbar│  │RealityKit  │  │  AssetPanel/        │  │
│  │             │  │SceneView    │  │  ObjectCapture      │  │
│  │ • 选择      │  │             │  │                     │  │
│  │ • 相机      │  │ • USDZ渲染  │  │ • 相机扫描          │  │
│  │ • 图库      │  │ • 手势交互  │  │ • 图库选择          │  │
│  │ • 3D模型   │  │ • 对象管理  │  │ • 处理进度          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                    ObjectCaptureService                      │
│  • 设备兼容性检查                                            │
│  • 图片预处理                                                │
│  • PhotogrammetrySession 管理                                │
│  • USDZ 模型生成                                             │
├─────────────────────────────────────────────────────────────┤
│                    SwiftData Persistence                     │
│  • SceneObjectData                                           │
│  • SpaceOutfit                                               │
└─────────────────────────────────────────────────────────────┘
```
