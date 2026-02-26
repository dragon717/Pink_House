# 萌宠视频资源文档

## 目录结构

```
asserts/
├── README.md                      # 本文档
├── naicha_*.mp4                   # 奶茶(橘猫)视频资源
├── maomao_*.mp4                   # 毛毛(金毛犬)视频资源
└── open_dress.mp4                 # 通用开场动画
```

---

## 命名规范

视频文件名格式：`{角色名}_{动作名}.mp4`

- **角色名**: `naicha`(奶茶) / `maomao`(毛毛)
- **动作名**: 见下方动作映射表

代码中通过 `getCharacterVideoName(action:)` 自动生成完整文件名：
```swift
return "\(currentPet.rawValue)_\(action)"
// 例如: naicha_idle, maomao_eating
```

---

## 角色介绍

### 🐱 奶茶 (Naicha)
- **角色ID**: `naicha`
- **品种**: 橘猫
- **性格**: 温顺、爱撒娇、喜欢喝奶茶
- **专属行为**: NaichaBehavior（含登基彩蛋、打工结果视频等）

### 🐕 毛毛 (Maomao)
- **角色ID**: `maomao`
- **品种**: 金毛犬
- **性格**: 活泼、忠诚、精力充沛
- **专属行为**: DefaultPetBehavior（通用行为）

---

## 视频资源清单

### 基础状态视频

| 动作名 | 说明 | 奶茶 | 毛毛 | 循环 |
|--------|------|:----:|:----:|:----:|
| `idle` | 待机/空闲状态 | ✅ | ✅ | 是 |
| `sleeping` | 睡觉 | ✅ | ✅ | 是 |
| `listening` | 倾听/期待 | ✅ | ✅ | 是 |
| `talking` | 说话/复述 | ✅ | ✅ | 是 |

### 互动视频

| 动作名 | 说明 | 奶茶 | 毛毛 | 循环 |
|--------|------|:----:|:----:|:----:|
| `enjoy_click` | 点击头部-享受 | ✅ | ✅ | 否 |
| `angry_click` | 点击肚子-生气 | ✅ | ✅ | 否 |
| `rolling` | 翻滚 | ✅ | ✅ | 否 |
| `playing` | 玩耍 | ✅ | ✅ | 是 |
| `grooming` | 洗脸/梳理 | ✅ | ❌ | 否 |
| `attention` | 吸引注意 | ✅ | ❌ | 否 |

### 喂食视频

| 动作名 | 说明 | 奶茶 | 毛毛 | 循环 |
|--------|------|:----:|:----:|:----:|
| `eating_catFood` | 吃猫粮 | ✅ | ✅ | 否 |
| `eating_cannedFood` | 吃罐头 | ✅ | ✅ | 否 |
| `drinking_glass` | 喝水 | ✅ | ✅ | 否 |

### 清洁视频

| 动作名 | 说明 | 奶茶 | 毛毛 | 循环 |
|--------|------|:----:|:----:|:----:|
| `bathing_happy` | 开心洗澡 | ✅ | ✅ | 否 |
| `bathing_boring` | 不情愿洗澡 | ✅ | ✅ | 否 |

### 工作相关视频

| 动作名 | 说明 | 奶茶 | 毛毛 | 循环 |
|--------|------|:----:|:----:|:----:|
| `dressing_work` | 换装准备工作 | ✅ | ✅ | 否 |
| `work_success` | 打工成功 | ✅ | ❌ | 否 |
| `work_exhausted` | 打工累瘫 | ✅ | ❌ | 否 |

### 彩蛋视频（奶茶专属）

| 动作名 | 说明 | 触发条件 |
|--------|------|----------|
| `coronation` | 登基仪式 | 语音包含"登基/登记/等级/登机/灯基" |
| `eat_rush` | 快速吃饭 | 喂食时5%概率触发 |

---

## 代码中的视频路径定义

### PetVideoPaths (PetViewModel.swift)

```swift
struct PetVideoPaths {
    static let angry = "angry_click"
    static let rolling = "rolling"
    static let bathingBoring = "bathing_boring"
    static let bathingHappy = "bathing_happy"
    static let drinking = "drinking_glass"
    static let eatingCanned = "eating_cannedFood"
    static let eatingCatFood = "eating_catFood"
    static let enjoy = "enjoy_click"
    static let grooming = "grooming"
    static let listening = "listening"
    static let playing = "playing"
    static let sleeping = "sleeping"
    
    static let attention = "attention"
    static let talking = "talking"
    static let dressingWork = "dressing_work"
    static let coronation = "coronation"
}
```

---

## 视频加载机制

### 加载优先级 (PetVideoPlayer.swift)

1. 绝对路径 (`/Users/.../video.mp4`)
2. Bundle 根目录 (`videoName.mp4`)
3. asserts 子目录 (`asserts/videoName.mp4`)
4. 回退机制：找不到时回退到 `idle` 状态

### 回退逻辑

```
目标视频不存在 → 尝试 {角色}_idle → 尝试 naicha_idle → 尝试 idle
```

---

## 角色行为差异

### 奶茶 (NaichaBehavior)

```swift
struct NaichaBehavior: PetBehavior {
    func getWorkFinishResult(job: PetJob, status: PetStatus) -> (video, message, success) {
        if status.energy > 50 {
            return ("work_success", "打工赚了 \(earned) 鱼币!", true)
        } else {
            return ("work_exhausted", "累死宝宝了...", false)
        }
    }
    
    func getEchoEgg(text: String) -> String? {
        // 登基关键词触发
        if text.contains("登基/登记/等级/登机/灯基") {
            return "coronation"
        }
    }
    
    func getFeedingEgg(item: PetItemDefinition) -> String? {
        // 5%概率触发
        if Int.random(in: 1...100) <= 5 {
            return "eat_rush"
        }
    }
}
```

### 毛毛 (DefaultPetBehavior)

```swift
struct DefaultPetBehavior: PetBehavior {
    func getWorkFinishResult(...) -> ("idle", "打工结束", true)
    func getEchoEgg(...) -> nil  // 无彩蛋
    func getFeedingEgg(...) -> nil  // 无彩蛋
}
```

---

## 资源缺失清单

### 毛毛缺失的视频

| 缺失视频 | 影响 | 临时回退 |
|----------|------|----------|
| `maomao_grooming` | 无法播放洗脸动画 | 回退到 `maomao_idle` |
| `maomao_attention` | 无法播放吸引注意动画 | 回退到 `maomao_idle` |
| `maomao_work_success` | 打工成功无特殊视频 | 回退到 `maomao_idle` |
| `maomao_work_exhausted` | 打工失败无特殊视频 | 回退到 `maomao_idle` |
| `maomao_coronation` | 无登基彩蛋 | 无彩蛋触发 |
| `maomao_eat_rush` | 无快速吃饭彩蛋 | 无彩蛋触发 |

---

## 添加新视频步骤

1. **准备视频文件**
   - 格式: MP4
   - 命名: `{角色}_{动作}.mp4`
   - 建议: 去除水印，首尾帧一致（循环视频）

2. **放入目录**
   ```bash
   cp new_video.mp4 asserts/naicha_newaction.mp4
   ```

3. **代码中引用**
   - 在 `PetVideoPaths` 中添加静态常量
   - 在对应 State 类中设置 `videoName`
   - 如需彩蛋，在 Behavior 中实现逻辑

4. **测试验证**
   - 检查视频是否正常加载
   - 检查循环/单次播放设置
   - 检查回退逻辑

---

## 相关代码文件

- `PetVideoPlayer.swift` - 视频播放器实现
- `PetViewModel.swift` - 视频状态管理
- `PetModel.swift` - 角色定义和行为
- `PetVideoPaths` - 视频路径常量
- `NaichaBehavior` - 奶茶专属行为

---

*文档生成时间: 2026-02-17*
*版本: v1.0*
