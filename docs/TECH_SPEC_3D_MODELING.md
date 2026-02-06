# 技术规格书：基于 ml-sharp 的端侧 3D 衣物建模方案

## 1. 概述 (Overview)

本项目旨在为 **ItemManager (少女心愿衣橱)** 引入端侧 3D 建模能力。通过集成 Apple 最新的 `ml-sharp` 技术，实现用户只需提供一张衣物抠图（2D），即可在设备本地实时生成可交互的 3D 高斯泼溅（3D Gaussian Splats）模型，从而提升用户的衣物管理体验，实现从“平面照片”到“立体展示”的质的飞跃。

## 2. 核心技术选型 (Technology Stack)

*   **源模型架构**: [ml-sharp](https://github.com/apple/ml-sharp) (Sparse High-resolution Architecture for Real-time Point cloud generation)
    *   *优势*：专为从单张图像生成高质量 3D 内容设计，Apple 官方出品，适合移动端部署。
*   **推理框架 (Inference)**: **Core ML**
    *   利用 Apple Silicon (A系列/M系列芯片) 的 Neural Engine (ANE) 进行硬件加速。
    *   使用 fp16 精度以平衡性能与模型体积。
*   **渲染引擎 (Rendering)**: **Metal**
    *   采用自定义的 Gaussian Splatting Rasterizer（高斯泼溅光栅化器）。
    *   集成 `MetalKit` 与 `SwiftUI` 进行展示。
*   **开发语言**: Python (模型转换), Swift (iOS 业务逻辑 & 渲染)。

## 3. 系统架构 (System Architecture)

整个链路分为 **离线准备阶段** 和 **在线运行阶段 (iOS)**。

### 3.1 离线准备阶段 (Model Engineering)
*此阶段在开发环境中完成，产物随 App 发布或在线下发。*

1.  **环境搭建**: 配置 PyTorch, `coremltools`, `ml-sharp` 依赖。
2.  **模型转换**:
    *   输入: `ml-sharp` 预训练 PyTorch 模型 (`.pth`)。
    *   处理: Trace 模型结构 -> `coremltools.convert` -> 量化 (Float16) -> 优化计算图。
    *   输出: `SharpModel.mlpackage` (Core ML 模型包)。
3.  **验证**: 使用 Python 脚本对比 Core ML 模型与原始 PyTorch 模型的输出误差。

### 3.2 在线运行阶段 (iOS App Runtime)

#### A. 输入预处理 (Preprocessing)
*   **输入**: 用户上传/抠图后的 `UIImage` (RGBA)。
*   **处理**:
    *   Resize: 调整为模型输入分辨率 (如 512x512)。
    *   Normalize: 归一化像素值到 [-1, 1] 或 [0, 1]。
    *   Tensor Conversion: 转换为 `MLMultiArray`。

#### B. 核心推理 (Inference Service)
*   **模块**: `SharpGenerationService`
*   **职责**:
    *   管理 `MLModel` 的加载与释放 (利用 LRU 缓存策略)。
    *   执行推理预测 (`model.prediction(input: ...)`).
    *   **输出解析**: 解析模型输出的 MultiArray，提取以下分量：
        *   `Position` (x, y, z): 粒子位置。
        *   `Scale` (sx, sy, sz): 粒子缩放。
        *   `Rotation` (quaternions): 粒子旋转四元数。
        *   `Opacity` (alpha): 透明度。
        *   `Color/SH`: 颜色或球谐系数。

#### C. 后处理与优化 (Post-processing)
*   **剪枝 (Pruning)**: 移除 Opacity 低于阈值 (如 0.05) 的点，减少渲染压力。
*   **格式转换**: 将分散的数据组装为 GPU 友好的 `MTLBuffer` 结构 (`GaussianSplat` struct)。

#### D. 渲染展示 (Rendering)
*   **模块**: `GaussianSplatView` (UIViewRepresentable)
*   **管线**:
    1.  **Sort**: 在 GPU (Compute Shader) 或 CPU 上对高斯点按深度排序 (Back-to-Front)。
    2.  **Vertex Shader**: 计算高斯球在屏幕空间的投影 (2D 协方差, 边界框)。
    3.  **Fragment Shader**: 执行高斯混合 (Gaussian Blending) 绘制像素。
*   **交互**: 支持单指旋转 (Orbit)、双指缩放 (Zoom)。

## 4. 详细实施计划 (Implementation Plan)

### 阶段一：模型工程 (Model Engineering)
- [ ] 编写 Python 转换脚本 `convert_sharp.py`。
- [ ] 运行转换，生成 `SharpModel.mlpackage`。
- [ ] 验证模型在 macOS 上的推理结果。

### 阶段二：iOS 基础集成 (iOS Integration)
- [ ] 将 `.mlpackage` 导入 Xcode 项目。
- [ ] 创建 `SharpGenerationService` 类。
- [ ] 实现 `Preprocess` (图片转 Tensor) 和 `Postprocess` (Tensor 转高斯数据结构) 逻辑。

### 阶段三：渲染器开发 (Renderer Implementation)
- [ ] 创建 `GaussianShader.metal` 文件，实现顶点和片元着色器。
- [ ] 创建 `GaussianSplatRenderer` (Swift/Metal)，管理 `MTKView` 和渲染循环。
- [ ] 实现高斯点排序算法 (这对透明度混合至关重要)。

### 阶段四：UI 业务整合 (UI Integration)
- [ ] 在 `DepositItemRow` 或详情页添加“生成 3D 模型”按钮。
- [ ] 设计加载状态 UI (Loading Indicator)。
- [ ] 实现 3D 预览视图 `OOTD3DView`。

## 5. 性能指标与风险控制 (KPIs & Risks)

| 指标 | 目标值 | 风险应对 |
| :--- | :--- | :--- |
| **模型体积** | < 100MB | 使用 iOS 16+ 的模型压缩技术；考虑云端下发。 |
| **推理时间** | < 3s (iPhone 14 Pro) | 异步执行；提供进度提示；降级分辨率。 |
| **渲染帧率** | 60 FPS | 动态调整渲染点数；优化 Shader 混合算法。 |
| **内存占用** | < 200MB (峰值) | 及时释放中间 Tensor；使用 `mmap` 加载模型。 |

## 6. 数据结构定义 (Draft)

```swift
struct GaussianSplat {
    var position: SIMD3<Float>
    var scale: SIMD3<Float>
    var rotation: SIMD4<Float> // Quaternion
    var color: SIMD3<Float>    // RGB
    var opacity: Float
}

// 对应 Metal 中的结构
struct GaussianUniforms {
    var viewMatrix: float4x4;
    var projectionMatrix: float4x4;
    var screenSize: SIMD2<Float>;
};
```

## 7. 思路总结（实施与排查）

### 7.1 关键问题与定位路径

1. **点击“生成 3D 模型”后卡住**
   * 结论：主线程被模型加载与推理阻塞。
   * 处理：将模型加载与推理迁移到后台任务，UI 先进入预览页并显示加载态。

2. **预览白屏或黑屏闪烁**
   * 结论：SwiftUI 视图层级被遮挡或重建导致闪烁。
   * 处理：使用顶层 `ZStack` 管理 3D 预览覆盖层，减少 `.overlay` 的层级冲突。

3. **模型不可见或缩放过小**
   * 结论：点云坐标范围过大或过小，视锥内不可见。
   * 处理：加入点云包围盒计算与自动缩放逻辑，使模型稳定进入视锥。

4. **手势不顺畅或不可缩放**
   * 结论：交互控制模式与手势绑定不完整。
   * 处理：明确旋转与缩放的手势路径，采用更稳定的轨道式旋转控制。

5. **CoreML 转换“卡在 100%”**
   * 结论：终端输出缓冲导致“假卡住”，模型已生成。
   * 处理：以文件生成结果为准，避免被日志进度误导。

### 7.2 性能与稳定性策略

1. **模型体积过大导致 OOM**
   * 结论：原始模型体积过大，加载时触发内存峰值。
   * 处理：引入 8-bit 线性量化，体积约减少一半。

2. **量化后只显示“一个点”**
   * 结论：模型输出形状与解析假设不一致。
   * 处理：输出解析改为动态识别形状（如 1×N×14 与 N×14），并增加安全校验。

3. **渲染稳定性**
   * 结论：加载态与错误态未统一管理会导致状态错乱。
   * 处理：预览页先进入加载态，加载失败显示错误信息并允许退出。

### 7.3 实施要点沉淀

* 先让 UI “可进入”，再做模型推理，避免用户感知卡住。
* 3D 预览层必须保持顶层稳定结构，避免 SwiftUI 结构性重建。
* 任何模型输出解析都不要假设固定 shape，优先动态分支。
* 模型体积与内存峰值是移动端最大风险点，量化是必要手段。
