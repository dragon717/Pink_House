# SwiftData 数据恢复与复杂关系同步最佳实践复盘

本文档记录了在 `ItemManager` 项目中，针对 SwiftData 数据恢复、软删除处理以及 OOTD 复杂对象图同步过程中遇到的技术挑战与解决方案。

## 一、 软删除与数据恢复 (Soft Delete Recovery)

### 问题背景
用户将物品放入回收站（软删除），执行云端备份。恢复时，该物品被错误识别为新物品并重新创建，导致“顽固复活”。

### 核心原则
1.  **信任本地状态 (Trust Local State)**：在恢复逻辑中，如果本地对象已存在且处于删除状态，无论备份数据如何，必须强制保持其删除状态。
2.  **属性遮蔽风险**：SwiftData 的 `PersistentModel` 可能包含系统级 `isDeleted`。自定义软删除属性建议使用明确命名（如 `deletedAt`）并进行双重检查。

### 最佳实践代码
```swift
// 强制同步本地删除状态
if isLocalDeleted {
    clothingBack.isDeleted = true
    if clothingBack.deletedAt == nil { clothingBack.deletedAt = Date() }
}
```

---

## 二、 OOTD 复杂关系数据的备份与恢复

在 OOTD（穿搭画布）场景中，一个 `Outfit` 包含多个 `OutfitItem`，每个 `Item` 又关联一个 `CutoutItem`（贴纸）。这种多层级关系在恢复时极易出错。

### 1. 跨生命周期的关系重建 (Re-linking via Content)
**问题**：备份中的 UUID 在异地恢复时可能无意义，或者本地贴纸已重新生成（ID 改变），导致关联丢失。
**解决方案**：不依赖 UUID 硬关联，而是建立基于**内容特征**（如图片文件名、Hash）的反向查找表。

**代码模式**：
```swift
// 1. 建立反向查找表 (FileName -> CutoutItem)
var cutoutFileMap: [String: CutoutItem] = [:]
for cutout in existingCutouts {
    let fileName = (cutout.imagePath as NSString).lastPathComponent
    cutoutFileMap[fileName] = cutout
}

// 2. 恢复时通过文件名查找关联
for itemDTO in dto.items {
    guard let cutout = cutoutFileMap[itemDTO.imageReference] else {
        print("Warning: Cutout missing for \(itemDTO.imageReference)")
        continue
    }
    // 重建关联
    item.cutout = cutout
}
```

### 2. 对象图的一致性与 ID 冲突 (Upsert Strategy)
**问题**：直接 `context.insert(item)` 一个数据库中已存在的 ID（即使它是游离的/未关联的），会导致严重的上下文状态错误或崩溃。
**解决方案**：采用 **Upsert（更新或插入）** 策略，并维护全局对象缓存。

**最佳实践**：
1.  **全局预取**：恢复前一次性获取所有 `OutfitItem`，建立 `[ID: Item]` 映射。
2.  **存在即更新**：如果 ID 已存在，更新其属性（x, y, scale 等）并重新挂载到 `Outfit`。
3.  **不存在才插入**：只有 ID 不存在时才执行 `insert`。

```swift
// 全局查找表防止 ID 冲突
if let existingItem = globalItemMap[itemDTO.id] {
    // Update existing
    existingItem.x = itemDTO.x
    // ...
    item = existingItem
} else {
    // Insert new
    item = OutfitItem(...)
    context.insert(item)
}
// 重新挂载
outfit.items.append(item) 
```

### 3. 避免访问失效对象 (Accessing Invalidated Objects)
**问题**：尝试检查旧关系 `if item.outfit?.id != outfit.id` 时崩溃。
**原因**：`item.outfit` 可能指向一个已被物理删除但内存中仍有残余引用的对象（Fault Object）。访问其属性会触发 CoreData/SwiftData 的 `Fatal Error`。
**对策**：**不信任旧关系**。直接通过 `outfit.items.append(item)` 建立新关系，SwiftData 会自动处理旧关系的断开。

---

## 三、 SwiftData 线程安全 (Thread Safety)

### 致命错误：EXC_BREAKPOINT in save()
**现象**：在云同步回调中调用 `context.save()` 导致崩溃。
**原因**：`ModelContext` 是线程受限的（Thread-Confined）。如果在后台线程（如 CloudKit Operation Queue）中直接操作绑定在 `@MainActor` 的 Context，属于违规操作。

**修复方案**：
必须使用 `MainActor.run` 或 `Task { @MainActor in ... }` 将执行流强制切回 Context 所在的线程。

```swift
// CloudSyncManager.swift
// 错误做法：直接在回调中调用
// try BackupService.shared.restore(...) 

// 正确做法：
try await MainActor.run {
    try BackupService.shared.restoreFromManifest(..., context: mainContext)
}
```

---

## 四、 UI 状态与数据持久化的同步

### 画布缩略图刷新
**问题**：修改数据后，列表页的缩略图未更新。
**原因**：数据层（SwiftData）更新了，但视图层（SwiftUI View -> Renderer）未及时生成新的快照文件。
**解决方案**：
1.  **回调机制**：在 Canvas View 中暴露 `onCanvasChange` 回调。
2.  **渲染延时**：在触发截图保存前，增加微小延时（如 `0.1s`），等待 SwiftUI 完成视图层级的布局更新（Layout Pass），确保截图内容是最新的。

```swift
onUpdate: {
    if let outfit = currentOutfit {
        Task { @MainActor in
            // 等待视图渲染更新
            try? await Task.sleep(nanoseconds: 100_000_000) 
            saveSnapshot(for: outfit)
        }
    }
}
```
