# 3D 模型重构指南

## 概述

本文档记录了将 3D 模型从 Clothing 分类中独立出来的完整重构过程、修复的问题以及相关的最佳实践。

## 问题分析

### 原始问题
1. **3D 模型与 Clothing 耦合**：3D 模型被存储为 Clothing 对象，不符合业务逻辑
2. **素材库缺少独立分类**：3D 模型应该有独立的"模型"分类，而不是混在"服装"里
3. **老数据未迁移**：历史数据中的 3D 模型需要迁移到新的独立模型中
4. **保存时序问题**：保存后立即退出可能导致数据未持久化
5. **级联删除错误**：错误的删除规则导致书页被意外删除

## 重构方案

### 1. 数据模型设计

#### 新建 Model3D 模型
```swift
@Model
final class Model3D {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var types: String = ""
    var modelPath: String?
    var modelType: String = "usdz"
    var thumbnailPath: String?
    var sourceImagePaths: [String] = []
    
    // 时间戳管理
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // 软删除
    var isDeleted: Bool = false
    var deletedAt: Date?
    
    // 路径管理方法
    var resolvedModelPath: String? { ... }
    func setModelPath(_ absolutePath: String?) { ... }
}
```

### 2. 素材分类系统

#### AssetCategory 扩展
```swift
enum AssetCategory: String, CaseIterable, Identifiable {
    case models = "模型"      // 新增，放在第一位
    case clothing = "服装"
    case cutout = "抠图"
    case accessory = "配饰"
    case background = "背景"
}
```

### 3. 数据迁移服务

#### Model3DMigrationService
```swift
class Model3DMigrationService {
    static let shared = Model3DMigrationService()
    
    func migrateIfNeeded(modelContainer: ModelContainer) async {
        let migratedKey = "Model3DMigrationCompleted"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else {
            return
        }
        
        // 1. 查找所有包含 3D 模型的 Clothing
        // 2. 创建对应的 Model3D 对象
        // 3. 保留所有原始数据
        // 4. 标记迁移完成
    }
}
```

### 4. 路径管理系统

#### ModelPathManager
统一管理模型路径的存储和解析，避免 App 容器 UUID 变化导致文件找不到：
- **存储时**：将绝对路径转换为相对路径（以 `[RELATIVE]` 开头）
- **加载时**：将相对路径解析回绝对路径
- **兼容旧数据**：支持多种路径格式的自动识别

### 5. 保存流程优化

#### 带回调的保存方法
```swift
private func saveScene(completion: (() -> Void)? = nil) {
    // 保存逻辑...
    
    do {
        try modelContext.save()
        hasUnsavedChanges = false
        completion?()  // 保存成功后调用回调
    } catch {
        completion?()  // 即使失败也调用回调
    }
}
```

#### 保存并退出
```swift
Button("保存并返回") {
    if hasUnsavedChanges {
        saveScene {
            dismiss()  // 确保保存完成后再退出
        }
    } else {
        dismiss()
    }
}
```

## 关键问题修复

### 问题 1：级联删除导致书页被删

**错误代码**：
```swift
@Relationship(deleteRule: .cascade)
var spaceOutfit: SpaceOutfit?
```

**原因**：SceneObjectData 对 SpaceOutfit 使用 .cascade 删除规则，导致删除场景对象时级联删除了书页。

**修复**：
```swift
@Relationship  // 移除 .cascade
var spaceOutfit: SpaceOutfit?
```

### 问题 2：保存时序问题

**错误代码**：
```swift
saveScene()
dismiss()  // 立即调用，保存可能未完成
```

**修复**：
```swift
saveScene {
    dismiss()  // 在回调中调用
}
```

## 最佳实践

### 1. 数据模型设计

#### 路径管理模式
```swift
// 存储相对路径
var modelPath: String?

// 计算属性：解析后的绝对路径
var resolvedModelPath: String? {
    ModelPathManager.shared.resolvePath(modelPath)
}

// 方法：设置路径（自动转为相对路径）
func setModelPath(_ absolutePath: String?) {
    modelPath = ModelPathManager.shared.storePath(absolutePath)
}
```

#### 软删除模式
```swift
var isDeleted: Bool = false
var deletedAt: Date?

// 查询时过滤
@Query(filter: #Predicate<Model3D> { $0.isDeleted == false })
```

### 2. 关系设计

#### 避免反向级联删除
```swift
// ❌ 错误：子对象级联删除父对象
@Relationship(deleteRule: .cascade)
var parent: Parent?

// ✅ 正确：父对象级联删除子对象
@Relationship(deleteRule: .cascade)
var children: [Child]
```

### 3. 异步操作

#### 使用回调确保时序
```swift
func doSomethingAsync(completion: @escaping () -> Void) {
    Task {
        // 异步操作...
        await MainActor.run {
            completion()
        }
    }
}
```

### 4. 数据迁移

#### 幂等性设计
```swift
func migrateIfNeeded() {
    let key = "MigrationCompleted_v1"
    guard !UserDefaults.standard.bool(forKey: key) else {
        return  // 只执行一次
    }
    
    // 执行迁移...
    
    UserDefaults.standard.set(true, forKey: key)
}
```

### 5. 日志记录

#### 结构化日志
```swift
print("[Scene] 开始保存场景，对象数: \(sceneObjects.count)")
print("[Scene] 使用现有的 SpaceOutfit: \(outfit.id)")
print("[Scene] 场景保存成功，共 \(sceneObjects.count) 个对象")
```

## 文件清单

### 新增文件
- `ItemManager/Models/Model3D.swift` - 独立的 3D 模型数据模型
- `ItemManager/Services/Model3DMigrationService.swift` - 数据迁移服务

### 修改文件
- `ItemManager/Models/SceneObjectData.swift` - 修复级联删除规则
- `ItemManager/Views/SpatialCanvas/AssetPanel.swift` - 添加 Model3DAssetList
- `ItemManager/Views/SpatialCanvas/SpatialCanvasEditorView.swift` - 优化保存逻辑
- `ItemManager/Views/SpatialCanvas/SpatialCanvasTypes.swift` - 添加 models 分类
- `ItemManager/Services/SharedPersistence.swift` - 添加 Model3D 到 Schema
- `ItemManager/ItemManagerApp.swift` - 添加迁移服务调用

## 测试清单

- [ ] 新创建的 3D 模型保存为 Model3D，不出现在 Clothing 中
- [ ] 素材库"模型"分类显示所有 3D 模型
- [ ] 老数据中的 3D 模型自动迁移到 Model3D
- [ ] 保存场景后退出，书页不被删除
- [ ] 场景中的模型位置、旋转、缩放正确保存和加载
- [ ] 模型文件路径在 App 重装后仍能正确解析

## 总结

本次重构的核心收获：

1. **数据模型解耦**：将 3D 模型从 Clothing 中独立出来，更符合业务逻辑
2. **路径管理标准化**：使用相对路径存储，避免 App 容器 UUID 变化的问题
3. **关系设计谨慎**：级联删除规则要特别注意方向，避免误删数据
4. **异步操作安全**：使用回调机制确保异步操作完成后再执行后续逻辑
5. **数据迁移完善**：提供自动化的迁移服务，保证老数据平滑过渡
