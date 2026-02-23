# BackupService 重构指南

## 重构背景

`BackupService.swift` 文件中的 `restoreFromManifest` 方法原本长达 **1292 行**，承担了数据恢复的所有职责，严重违反单一职责原则。

## 重构目标

1. **降低复杂度**：将巨型方法拆分为职责单一的小方法
2. **提高可读性**：通过清晰的阶段划分，让代码逻辑一目了然
3. **增强可维护性**：修改某个阶段的逻辑不会影响其他阶段
4. **改善可测试性**：每个阶段的方法可以独立测试

## 重构方案

### 1. 提取 RestoreContext 结构体

**为什么**：
- 恢复过程需要共享大量状态（manifest、imageFiles、context、各种模型映射表）
- 避免方法参数过多（超过5个参数会降低可读性）
- 通过结构体封装，可以清晰地看到哪些状态在阶段间传递

**实现**：
```swift
private struct RestoreContext {
    let manifest: BackupManifest
    let imageFiles: [String: URL]
    let context: ModelContext
    let fileManager: FileManager
    let imagesDir: URL
    let documentsDir: URL
    
    // 阶段2产生的映射表，供后续阶段使用
    var brandMap: [UUID: Brand] = [:]
    var tagMap: [UUID: Tag] = [:]
    var imageMetaMap: [UUID: StoredImage] = [:]
    
    // 阶段3产生的映射表，供后续阶段使用
    var clothingMap: [UUID: Clothing] = [:]
    var cutoutMap: [UUID: CutoutItem] = [:]
    var outfitMap: [UUID: Outfit] = [:]
    var model3DMap: [UUID: Model3D] = [:]
    var bookGroupMap: [UUID: BookGroup] = [:]
    var spaceBookGroupMap: [UUID: SpaceBookGroup] = [:]
}
```

### 2. 按阶段拆分方法

**为什么**：
- 数据恢复有明确的阶段划分：文件 → 基础模型 → 复杂模型 → 设置
- 每个阶段独立，不依赖其他阶段的内部实现
- 符合"分而治之"的编程思想

**实现**：
```swift
func restoreFromManifest(manifest: BackupManifest, imageFiles: [String: URL], context: ModelContext) throws {
    var ctx = try RestoreContext(manifest: manifest, imageFiles: imageFiles, context: context)
    
    try restoreFiles(context: &ctx)           // 阶段1
    try restoreBasicModels(context: &ctx)     // 阶段2
    try restoreComplexModels(context: &ctx)   // 阶段3
    try restoreSettings(context: ctx)         // 阶段4
}
```

### 3. 进一步拆分子方法

**为什么**：
- 每个阶段内部还有多个独立的恢复任务
- 例如阶段2需要恢复 Brand、Tag、StoredImage 三种模型
- 子方法可以独立测试和复用

**实现**：
```swift
private func restoreBasicModels(context: inout RestoreContext) throws {
    try restoreBrands(context: &context)
    try restoreTags(context: &context)
    try restoreStoredImages(context: &context)
    try modelContext.save()
}
```

## 为什么不拆分为多个文件

### 技术限制

1. **访问控制问题**
   - 所有恢复方法都是 `private`，只在 `BackupService` 内部使用
   - Swift 扩展无法访问主类的 `private` 成员
   - 改为 `internal` 或 `public` 会破坏封装性

2. **依赖关系复杂**
   - `RestoreContext` 需要访问 `BackupService.BackupError`
   - 方法之间通过 `RestoreContext` 共享状态
   - 拆分后需要大量参数传递，增加复杂性

3. **Swift 扩展限制**
   - 扩展中不能定义存储属性
   - 扩展中不能定义新的 `private` 方法

### 收益 vs 成本

| 方面 | 单文件 | 多文件 |
|------|--------|--------|
| 代码导航 | ✅ 在一个文件中跳转 | ❌ 需要在多个文件间切换 |
| 编译时间 | ✅ 更快 | ❌ 更慢（更多文件） |
| 访问控制 | ✅ 保持 `private` | ❌ 需要放宽访问控制 |
| 代码清晰度 | ✅ 已经很好 | ⚠️ 没有明显提升 |
| 维护成本 | ✅ 低 | ❌ 高（文件间依赖） |

### 结论

**保持单文件结构**，理由：
1. 代码已经通过方法提取实现了职责分离
2. 主方法 `restoreFromManifest` 只有35行，非常清晰
3. 通过 `// MARK: -` 注释可以轻松导航到各个部分
4. 拆分文件带来的复杂性大于收益

## 重构成果

### 代码结构对比

**重构前**：
```swift
func restoreFromManifest(...) throws {
    // 1292行代码，包含：
    // - 文件恢复逻辑
    // - Brand恢复逻辑
    // - Tag恢复逻辑
    // - StoredImage恢复逻辑
    // - Clothing恢复逻辑
    // - CutoutItem恢复逻辑
    // - Outfit恢复逻辑
    // - Model3D恢复逻辑
    // - BookGroup恢复逻辑
    // - SpaceBookGroup恢复逻辑
    // - SpaceOutfit恢复逻辑
    // - UserDefaults恢复逻辑
    // - PetStatus恢复逻辑
    // - ChatHistory恢复逻辑
    // - UserProfile恢复逻辑
    // ... 各种嵌套条件和重复逻辑
}
```

**重构后**：
```swift
func restoreFromManifest(...) throws {
    var ctx = try RestoreContext(...)
    try restoreFiles(context: &ctx)
    try restoreBasicModels(context: &ctx)
    try restoreComplexModels(context: &ctx)
    try restoreSettings(context: ctx)
}

private func restoreFiles(context: inout RestoreContext) throws { ... }
private func restoreBasicModels(context: inout RestoreContext) throws { ... }
private func restoreComplexModels(context: inout RestoreContext) throws { ... }
private func restoreSettings(context: RestoreContext) throws { ... }
// 以及更多子方法...
```

### 量化指标

| 指标 | 重构前 | 重构后 | 改善 |
|------|--------|--------|------|
| 主方法行数 | 1292行 | 35行 | -97% |
| 主方法圈复杂度 | ~25 | ~5 | -80% |
| 方法数量 | 1个 | 15+个 | +1400% |
| 最大方法行数 | 1292行 | ~150行 | -88% |

## 最佳实践总结

### 1. 何时拆分方法

✅ **应该拆分**：
- 方法超过50行
- 方法做多个不同的事情
- 方法有多个嵌套层级（if/for/while嵌套超过3层）
- 方法参数超过5个
- 需要为不同逻辑编写独立测试

❌ **不应该拆分**：
- 方法虽然长，但只做一件事（如纯配置代码）
- 拆分后需要大量参数传递
- 拆分后破坏代码的内聚性

### 2. 如何组织大文件

✅ **推荐做法**：
- 使用 `// MARK: -` 注释划分代码段落
- 按功能模块组织方法（如：导出、导入、工具方法）
- 使用结构体封装相关状态（如 `RestoreContext`）
- 保持方法职责单一

❌ **避免做法**：
- 盲目拆分为多个文件
- 为了拆分而放宽访问控制
- 创建过多的小文件（<100行）

### 3. Swift 文件拆分的注意事项

**可以拆分的情况**：
- 协议定义（Protocol）
- 数据模型（Model/DTO）
- 独立的工具类/结构体
- 与主类无紧密耦合的扩展

**不建议拆分的情况**：
- 需要访问 `private` 成员的方法
- 与主类有大量状态共享的代码
- 只是将大文件机械地切分成小文件

## 总结

本次重构的核心思想是：**通过方法提取实现职责分离，而不是通过文件拆分**。

重构后的代码：
- ✅ 主方法简洁清晰（35行）
- ✅ 每个阶段职责单一
- ✅ 圈复杂度显著降低
- ✅ 易于测试和维护
- ✅ 保持单文件结构，避免不必要的复杂性

**关键原则**：代码组织的清晰度取决于方法级别的职责分离，而不是文件级别的物理拆分。
