# 多宠物管理最佳实践 (Multi-Pet Management Best Practices)

本文档总结了当前项目中多宠物管理系统的架构设计思路、数据流向及扩展最佳实践。

## 1. 核心设计理念：单状态，多形象 (Single State, Multiple Avatars)

当前项目采用 **"共享状态模型" (Shared Stats Model)** 来管理多只宠物。

### 设计思路
*   **用户视角**：用户扮演唯一的“饲养员”角色。
*   **数据视角**：
    *   **资源共享**：金币（喵币/鱼币）、背包物品归用户所有，所有宠物通用。
    *   **状态共享**：饱食度、清洁度、精力、心情反映的是用户的“养宠投入度”，而非单只宠物的生理指标。切换宠物时，这些数值**不会**重置或切换。
    *   **形象独立**：每只宠物（奶茶、毛毛等）仅作为一种“视觉皮肤”和“交互对象”存在。

### 优势
1.  **降低心智负担**：用户不需要同时照顾多只宠物，避免因宠物过多导致频繁的“上线打卡”压力。
2.  **简化数据管理**：无需处理后台多实例的数值衰减（Offline Decay），避免“切换回很久没看的宠物发现它饿死”的负面体验。
3.  **资源统一**：经济系统（金币）和道具系统统一，便于数值平衡。

---

## 2. 数据架构 (Data Architecture)

### 2.1 静态配置 (`PetCharacter`)
定义宠物的固有属性，通常硬编码在 `Enum` 中，便于编译期检查。

*   **文件**: `PetModel.swift`
*   **结构**:
    ```swift
    enum PetCharacter: String, CaseIterable, Identifiable {
        case naicha = "naicha"
        case maomao = "maomao"
        
        // 核心资产索引
        var portraitImageName: String { ... }
        var description: String { ... }
    }
    ```
*   **扩展方式**: 新增宠物只需在 `enum` 中增加 case，并提供相应的资源文件。

### 2.2 动态状态 (`PetStatus`)
用户的存档数据，包含所有动态变化的值。

*   **文件**: `PetModel.swift`
*   **结构**:
    ```swift
    struct PetStatus: Codable {
        // 身份标识
        var selectedPetId: String?  // 当前激活的宠物
        var ownedPetIds: [String]   // 已解锁的宠物列表
        var petName: String?        // 当前昵称 (共享或独立视需求而定，目前倾向于共享或随ID变动)
        
        // 核心数值 (共享)
        var hunger: Double
        var hygiene: Double
        var energy: Double
        var mood: Double
        
        // 经济系统 (共享)
        var fishCoin: Int
        var inventory: [String: Int]
    }
    ```

### 2.3 状态管理 (`PetViewModel`)
作为唯一的 Source of Truth，负责业务逻辑。

*   **切换逻辑 (`switchPet`)**:
    1.  验证 `ownedPetIds` 包含目标 ID。
    2.  更新 `status.selectedPetId`。
    3.  **关键点**：触发 UI 刷新，重置视频播放状态 (`currentVideoFileName`)，但**不**重置数值。
    4.  持久化保存。

---

## 3. 业务流程最佳实践

### 3.1 领养流程 (Adoption)
1.  **入口**: `PetAdoptionView`。
2.  **检查**: 判断 `status.ownedPetIds` 是否已包含该宠物。
3.  **操作**:
    *   将新 ID 加入 `ownedPetIds`。
    *   自动调用 `switchPet` 切换到新宠物。
    *   (可选) 触发“获得新宠物”的特效或奖励。

### 3.2 资源命名规范 (Asset Naming Convention)
为了支持动态切换，资源文件必须遵循严格的命名规范：

*   **视频/动画**: `[petId]_[action].mp4`
    *   例如: `naicha_idle.mp4`, `maomao_eating.mp4`
*   **逻辑映射**:
    *   ViewModel 根据 `currentPet.id` + `currentAction` 动态拼接文件名。
    *   代码示例:
        ```swift
        func getCharacterVideoName(action: String) -> String {
            return "\(currentPet.id)_\(action)"
        }
        ```

### 3.3 新增宠物步骤 (Checklist)
1.  **定义**: 在 `PetCharacter` 枚举中添加新 case (e.g., `case doge`).
2.  **资源**:
    *   准备对应的 `Assets.xcassets` 图片 (`doge_portrait`).
    *   准备动作视频文件 (`doge_idle.mp4`, `doge_eating.mp4`, etc.) 并放入 Bundle。
3.  **UI**: `PetAdoptionView` 会自动遍历 `allCases` 显示新宠物，无需修改 UI 代码。

---

## 4. 未来演进方向 (Future Considerations)

如果未来需要转变为 **"独立状态模型" (Individual Stats Model)**，即每只宠物有独立的饥饿度/等级，建议采取以下迁移策略：

1.  **数据结构升级**:
    *   在 `PetStatus` 中新增 `var petStates: [String: PetIndividualState]` 字典。
    *   `PetIndividualState` 包含 `hunger`, `mood` 等字段。
2.  **兼容性迁移**:
    *   `init(from decoder:)` 时，如果发现旧数据 (`hunger` 在根节点)，将其迁移到默认宠物 (naicha) 的 `petStates` 中。
3.  **ViewModel 改造**:
    *   所有的 `status.hunger` 访问改为 `status.petStates[currentPetId]?.hunger`。
4.  **后台计算**:
    *   需重写 `calculateOfflineDecay`，循环计算所有已拥有宠物的数值衰减。

## 5. 总结

当前 **Shared Stats Model** 是移动端轻量级宠物养成游戏的最佳实践选择。它在保证“收集乐趣”（多形象）的同时，最大程度降低了“维护成本”（单数值），非常适合碎片化时间的休闲游戏定位。
