# CloudKit 公告同步配置指南

## 概述

本应用使用 CloudKit Public Database 实现公告的跨用户同步。所有用户都可以读取公告，但只有管理员可以发布/编辑/删除公告。

---

## 第一步：获取你的 iCloud ID

在配置 CloudKit Dashboard 之前，你需要先获取自己的 iCloud ID。

### 方法：通过应用获取

1. **临时修改代码**（已添加辅助方法），在 `NoticeTestView.swift` 中添加一个测试按钮：

```swift
// 在 NoticeTestView 的 body 中添加一个按钮
Button {
    Task {
        await NoticeCloudKitService.shared.getCurrentUserID()
    }
} label: {
    LabActionCard(
        icon: "person.badge.key",
        title: "获取我的 iCloud ID",
        subtitle: "用于配置管理员权限",
        color: .orange
    )
}
.padding(.horizontal)
```

2. **运行应用**，进入 **我的 → 实验室 → 公告管理**

3. **点击"获取我的 iCloud ID"按钮**

4. **查看控制台输出**，你会看到类似：
   ```
   🔑 当前用户 iCloud ID: _d2a5e8f3a1b2c3d4e5f6...
   📋 请复制上面的 ID 添加到 adminIDs 数组中
   ```

5. **复制这个 ID**，稍后需要添加到代码中

---

## 第二步：配置 CloudKit Dashboard

### 1. 访问 CloudKit Dashboard

打开 [CloudKit Dashboard](https://icloud.developer.apple.com/) 并登录你的 Apple ID

### 2. 选择容器

点击你的容器：`iCloud.bugod2.ItemManager`

### 3. 创建 Notice Record Type

1. 点击左侧菜单 **Schema** → **Record Types**
2. 点击右上角 **+** 按钮创建新类型
3. **Record Type Name**: 输入 `Notice`
4. 添加以下字段：

| Field Name | Type | Index | 说明 |
|-----------|------|-------|------|
| `id` | String | ✓ Query | 公告唯一标识 |
| `title` | String | ✓ Query | 公告标题 |
| `content` | String | ✓ Query | 公告内容 |
| `mediaType` | String | ✓ Query | 媒体类型: none/image/video |
| `priority` | Int | ✓ Query | 优先级，数字越大越靠前 |
| `isActive` | Int | ✓ Query | 是否显示 (1=true, 0=false) |
| `createdAt` | Date/Time | ✓ Query | 创建时间 |
| `updatedAt` | Date/Time | ✓ Query | 更新时间 |
| `version` | Int | | 版本号 |

**操作步骤**：
- 点击 **Add Field...**
- 输入 Field Name
- 选择 Type
- 勾选 Queryable（除了 version）
- 点击 **Add**

5. 完成后点击右上角 **Save**

### 4. 配置 Security Roles

1. 点击左侧菜单 **Schema** → **Security Roles**

2. 配置 **World**（所有用户）：
   - **Read**: ✓ 勾选
   - **Write**: ✗ 不勾选

3. 配置 **Authenticated**（已认证用户）：
   - **Read**: ✓ 勾选
   - **Write**: ✗ 不勾选

4. 配置 **Creator**（记录创建者）：
   - **Read**: ✓ 勾选
   - **Write**: ✓ 勾选

5. 点击 **Save**

### 5. 部署到 Production（发布前必须做）

**⚠️ 重要提示**：Development 和 Production 是两个完全独立的环境！

- **Development**：Xcode 调试运行时使用
- **Production**：TestFlight 和 App Store 版本使用

**如果不部署到 Production，TestFlight 和 App Store 用户将看不到任何公告！**

#### 部署步骤：

1. 在 **Schema** 页面，点击右上角 **Deploy to Production...**
2. 确认要部署的 Record Types 包含 `Notice`
3. 点击 **Deploy**

#### 部署后需要在 Production 环境重复配置：

部署完成后，切换到 Production 环境，重复以下配置：

1. 点击页面顶部的环境切换器，选择 **Production**
2. 进入 **Schema** → **Record Types**
3. 确认 `Notice` Record Type 已存在
4. 进入 **Schema** → **Security Roles**，确认权限配置正确
5. 如果需要在 Production 环境发布测试公告，需要先在 Production 环境发布一条公告

#### 环境验证方法：

在代码中添加了环境检测，查看控制台输出：
```
📢 当前运行环境: Development (调试版)  // Xcode 运行
📢 当前运行环境: Production (发布版)   // TestFlight/App Store
```

---

## 第三步：配置管理员权限

### 1. 编辑代码添加管理员 ID

打开 `NoticeCloudKitService.swift`，找到：

```swift
// 管理员 iCloud IDs - 只有这些用户可以发布公告
private let adminIDs: [String] = [
    // 在这里添加管理员 iCloud ID
    // 例如: "_d2a5e8f3..."
]
```

添加你的 iCloud ID：

```swift
private let adminIDs: [String] = [
    "_d2a5e8f3a1b2c3d4e5f6...",  // 你的 iCloud ID（第一步获取的）
]
```

### 2. 重新编译运行

---

## 第四步：测试公告功能

### 测试管理员发布

1. 打开应用 → 我的 → 实验室 → 公告管理
2. 应该能看到管理界面（如果不是管理员会显示"需要管理员权限"）
3. 填写标题和内容
4. 点击"发布公告"
5. 查看控制台，确认发布成功

### 测试普通用户接收

1. 在另一台设备或模拟器上安装应用
2. 使用不同的 iCloud 账户登录
3. 打开应用，进入实验室 → 公告管理
4. 点击"手动同步公告"
5. 应该能看到管理员发布的公告

---

## 注意事项

1. **媒体资源**：公告图片使用应用内置资源，不通过 CloudKit 传输
2. **软删除**：删除公告时只是标记 `isActive=false`，不会真正删除
3. **过期机制**：只拉取最近30天的公告，过期公告自动隐藏
4. **频率限制**：发布/更新公告有1分钟的客户端频率限制
5. **环境隔离**：Development 和 Production 数据完全隔离

---

## 故障排查

### 公告无法同步

1. 检查 iCloud 账户是否登录（设置 → Apple ID → iCloud）
2. 检查网络连接
3. 查看控制台日志中的错误信息
4. 确认 CloudKit Dashboard 中 Record Type 配置正确
5. 确认已部署到正确的环境（Development/Production）

### 无法发布公告（提示"只有管理员可以发布公告"）

1. 确认 iCloud ID 已正确添加到 `adminIDs` 数组
2. 确认代码已重新编译
3. 在控制台查看输出的 iCloud ID 是否与添加的一致

### 沙盒环境 vs 生产环境

| 环境 | 用途 | 数据 |
|------|------|------|
| Development | 开发、Xcode 运行 | 独立 |
| Production | TestFlight、App Store | 独立 |

**重要**：TestFlight 和 App Store 版本使用 Production 环境，需要在 CloudKit Dashboard 中将 Schema 部署到 Production。

---

## 相关文件

- `ItemManager/Models/Notice.swift` - 公告数据模型
- `ItemManager/Services/NoticeCloudKitService.swift` - CloudKit 同步服务
- `ItemManager/Services/NoticeService.swift` - 公告业务逻辑
- `ItemManager/Views/Notice/NoticeAdminView.swift` - 公告管理界面
