# 技术设计文档：衣橱管理与轻养成APP

## 1. 概述
本项目旨在开发一款基于 iOS 平台的衣橱管理与轻养成应用。技术架构采用 **SwiftUI** 作为应用容器，**Godot (C#)** 作为 2D 交互核心引擎，通过 **SwiftGodotKit** 实现两者的高效集成。

## 2. 数据持久化方案 (Task 2 & 4)

### 2.1 存储路径
所有用户数据存储在 iOS 应用沙盒的 `Documents` 目录下，Godot 中通过 `user://` 协议访问。

### 2.2 数据结构
采用 JSON 格式存储元数据，配合哈希值实现增量更新。

**JSON 结构定义 (Metadata):**
```json
{
  "version": "1.0",
  "last_updated": 1715000000,
  "items": {
    "item_id_001": {
      "id": "item_id_001",
      "category": "top", // 上衣, 下装, 鞋履等
      "tags": ["summer", "casual"],
      "image_path": "images/item_id_001.webp",
      "image_hash": "a1b2c3d4...", // 图片内容的 SHA256 哈希
      "created_at": 1715000000
    }
  }
}
```

### 2.3 增量更新机制 (Hash)
为了优化性能，避免重复写入未修改的数据：
1.  **读取**: 启动时加载 `metadata.json` 到内存字典。
2.  **写入**:
    -   当物品属性或图片发生变更时，计算新数据的哈希值。
    -   对比内存中原有哈希，若不同则执行写入操作并更新 `last_updated`。
    -   保存时仅重写 JSON 文件，图片文件仅在哈希变化时重写。

### 2.4 C# 实现接口设计
```csharp
public interface IDataStore {
    void SaveItem(WardrobeItem item);
    WardrobeItem LoadItem(string id);
    void DeleteItem(string id);
    List<WardrobeItem> GetAllItems();
}
```

## 3. 图片压缩与存储策略 (Task 3 & 4)

### 3.1 压缩方案
-   **格式**: **WebP**
    -   *理由*: WebP 在同等质量下比 JPEG 小 25-34%，支持透明通道 (Alpha)，非常适合衣橱单品（通常需要透明背景抠图）。
-   **库引用**: Godot Native API (`Image.SaveWebp`)。
-   **质量设置**:
    -   **Lossy (有损)**: 质量系数 0.8 (80%)。
    -   *平衡*: 在手机屏幕上肉眼几乎无法区分，但体积显著减小。

### 3.2 读写流程
1.  **输入**: 原始图片 (`Image` 对象，可能来自 iOS 相册或相机)。
2.  **处理**:
    -   调整尺寸 (Resize): 限制最大边长为 1024px (视网膜屏幕足够清晰)。
    -   压缩 (Compress): 转换为 WebP 格式。
3.  **存储**:
    -   路径: `user://images/{uuid}.webp`
    -   映射: 在 `metadata.json` 中记录 UUID 与文件路径的对应关系。

### 3.3 参考代码逻辑
```csharp
// 伪代码示例
public void SaveCompressedImage(Image img, string id) {
    // 1. Resize if needed
    if (img.GetWidth() > 1024 || img.GetHeight() > 1024) {
        var aspect = (float)img.GetWidth() / img.GetHeight();
        int newW = 1024, newH = (int)(1024 / aspect);
        if (img.GetWidth() < img.GetHeight()) { // Portrait
            newH = 1024; newW = (int)(1024 * aspect);
        }
        img.Resize(newW, newH, Image.Interpolation.Cubic);
    }
    
    // 2. Save as WebP
    string path = $"user://images/{id}.webp";
    var error = img.SaveWebp(path, true, 0.8f); // lossy, quality 0.8
    
    if (error != Error.Ok) {
        GD.PrintErr($"Failed to save image: {error}");
    }
}
```

## 4. iOS 手势支持 (Task 5)

### 4.1 需求分析
衣橱整理需要频繁的拖拽 (Drag)、缩放 (Pinch) 和点击 (Tap) 操作。由于 Godot 运行在子视图中，需要一套健壮的手势识别系统。

### 4.2 实现方案
采用 **Godot 内部手势识别** 方案，通过监听 `InputEventScreenTouch` 和 `InputEventScreenDrag` 来模拟高级手势。这种方式比从 iOS 传递手势更流畅，且逻辑自包含。

### 4.3 接口设计
```csharp
public interface IGestureHandler {
    event Action<Vector2> OnTap;
    event Action<Vector2, Vector2> OnPan; // Delta, Position
    event Action<float, Vector2> OnPinch; // ScaleFactor, Center
}
```

### 4.4 核心逻辑
-   **单指**: 视为点击 (Tap) 或 拖拽 (Pan)。
-   **双指**: 计算两指间距变化，映射为缩放 (Pinch)。
-   **状态机**:
    -   `Idle` -> `TouchDown` (1 finger) -> `Dragging` / `Tapping`
    -   `Idle` -> `TouchDown` (2 fingers) -> `Pinching`

## 5. 测试与验证 (Task 6)
构建一个简单的 Godot 场景 `TestBench.tscn`：
1.  **UI 区域**: 包含 "Add Item", "Delete", "Simulate Gesture" 按钮。
2.  **展示区域**: 显示加载的图片网格。
3.  **验证点**:
    -   添加图片后，检查 `user://` 目录文件大小 (验证压缩)。
    -   重启应用，检查图片是否自动加载 (验证持久化)。
    -   双指捏合，检查图片网格缩放 (验证手势)。
