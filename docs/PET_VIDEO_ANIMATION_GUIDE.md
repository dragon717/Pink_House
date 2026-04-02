# 萌宠视频动画新增与替换指南

本文档详细说明了在 `ItemManager` 项目中新增或替换萌宠视频动画的完整流程、技术细节及最佳实践。

## Rococo House 专项说明

Rococo House（小世界路径行走 + 等轴方向 + turn 过渡）的专项最佳实践请参考：

- `docs/ROCOCO_PET_ISOMETRIC_VIDEO_BEST_PRACTICES.md`
- `.trae/skills/swiftui-rococo-pet-isometric-video/SKILL.md`

## 1. 核心流程概览

新增一个动画通常涉及以下三个步骤：
1.  **资源准备**：导入视频文件。
2.  **常量定义**：在代码中注册视频名称。
3.  **状态绑定**：将视频关联到具体的宠物状态（State）或触发逻辑。

---

## 2. 详细操作步骤

### 第一步：资源准备 (Resource Preparation)

1.  **文件格式**：
    *   推荐格式：`.mp4` (H.264 编码兼容性最好)。
    *   建议移除音轨（除非视频包含必须的同步音效），以避免与 BGM 混音问题。
2.  **导入 Xcode**：
    *   将视频文件拖入 Xcode 项目导航栏的 `ItemManager/asserts/` 目录下。
    *   **重要检查**：在弹出的对话框中，务必勾选 **"Copy items if needed"** 以及 **"Add to targets: ItemManager"**。
    *   如果文件已存在但无法加载，点击文件，在右侧 Inspector 面板检查 **Target Membership** 是否已勾选。

### 第二步：代码配置 (Code Configuration)

打开 `ItemManager/Views/Pet/PetViewModel.swift`，在 `PetVideoPaths` 结构体中添加常量。

```swift
// PetViewModel.swift

struct PetVideoPaths {
    // 现有常量...
    static let listening = "listening"
    
    // [新增] 定义新视频常量
    // 这里的字符串应与文件名（不含后缀）一致
    // 系统会自动在 Bundle 根目录及 asserts 子目录下查找
    static let myNewAction = "my_new_video_file_name"
}
```

> **注意**：推荐使用相对路径（文件名），系统已适配自动查找逻辑。仅在调试或特殊需求时使用绝对路径。

### 第三步：状态绑定与触发 (State Binding & Trigger)

根据业务需求，视频可以绑定到**固定状态**，或者**动态触发**。

#### 场景 A：修改固定状态的视频（如：工作、睡觉）

打开 `ItemManager/Views/Pet/States/PetConcreteStates.swift`，找到对应的状态类。

```swift
// PetConcreteStates.swift

class WorkingState: PetVideoState {
    override var videoName: String {
        // 修改此处返回的常量
        return PetViewModel.PetVideoPaths.myNewAction
    }
    
    // 确保设置为循环播放
    override var isLooping: Bool { true }
}
```

#### 场景 B：动态触发特定视频（如：拖拽、交互）

在 `PetViewModel.swift` 的业务逻辑中，使用 `changeState` 方法。

```swift
// PetViewModel.swift

func onSomeEvent() {
    // 切换到 expecting 状态，并指定播放新视频
    changeState(to: .expecting, videoName: PetVideoPaths.myNewAction)
}
```

若状态类支持动态设置（如 `ExpectingState` 已修改支持 `setVideoName`），上述代码即可生效。

---

## 3. 关键机制与排查心得 (Key Insights & Troubleshooting)

### 3.1 视频资源查找机制
`SeamlessVideoPlayer` 实现了智能查找逻辑，优先级如下：
1.  **绝对路径**（`verify exists`）。
2.  **Bundle 根目录** (`Bundle.main.url(forResource: name...)`)。
3.  **`asserts` 子目录** (`subdirectory: "asserts"`)。
4.  **兼容路径** (`asserts/name`)。

**心得**：只要文件名正确且文件在 Target 中，通常无需关心具体路径。

### 3.2 循环播放 (Looping) 的控制权
循环播放由 `isLooping` 属性控制，其优先级（由高到低）：
1.  **`changeState` 的 `forceLoop` 参数**：最高优先级，强制覆盖。
2.  **State 类的 `isLooping` 属性**：默认行为。

**常见问题：只播放一遍就停止或切回 Idle**
*   **现象**：视频播放完一次后，画面卡住或变成 Idle 状态，即使 `isLooping` 设置为 `true`。
*   **原因**：可能是 `onAnimationFinished` 被误触发（播放器认为播放结束），或者状态机逻辑在播放结束时自动重置。
*   **解决方案**：
    在 `PetViewModel.swift` 的 `onAnimationFinished` 方法中添加**状态保护**：

    ```swift
    func onAnimationFinished() {
        // 保护：如果是工作或睡觉状态，忽略结束信号，强制保持当前状态
        if currentState == .working || currentState == .sleeping {
            return 
        }
        
        // 正常逻辑：切回 idle
        if !isCurrentLooping && currentState != .idle {
            changeState(to: .idle)
        }
    }
    ```

### 3.3 状态机设计模式
*   每个 `PetVideoState` 子类对应一个逻辑状态。
*   `didEnter` 方法负责通知 ViewModel 更新视频 (`updateVideoState`)。
*   这种**解耦设计**使得新增状态非常容易，只需继承 `PetVideoState` 并重写 `videoName` 和 `isLooping`。

---

## 4. 快速查阅清单

- [ ] 视频文件放入 `asserts` 目录了吗？
- [ ] 视频文件勾选 Target Membership 了吗？
- [ ] `PetVideoPaths` 添加常量了吗？
- [ ] 状态类 (`PetConcreteStates.swift`) 更新视频引用了吗？
- [ ] 如果是长动画/背景动画，`isLooping` 设为 `true` 了吗？
- [ ] `onAnimationFinished` 里有防止自动切回 Idle 的保护吗？
