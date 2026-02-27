# 裙子股市 - 快捷指令集成指南

## 概述

本指南帮助你配置App以支持从快捷指令导入商品数据。虽然不能直接在App内静默创建快捷指令，但我们可以提供**一键引导安装**功能。

## 配置步骤

### 1. 配置Info.plist

在你的 `Info.plist` 中添加以下配置：

```xml
<!-- URL Scheme配置 -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.yourapp.skirtmarket</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>skirtmarket</string>
        </array>
    </dict>
</array>

<!-- 快捷指令支持 -->
<key>NSUserActivityTypes</key>
<array>
    <string>INSendMessageIntent</string>
</array>

<!-- 后台获取（用于分布式任务） -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.yourapp.skirtmarket.fetch</string>
</array>
```

### 2. 配置App入口

在 `@main` App结构中添加URL处理：

```swift
@main
struct YourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    URLSchemeHandler.shared.handleURL(url)
                }
        }
        .modelContainer(SkirtMarketPersistence.shared.publicContainer ?? SharedPersistence.shared.sharedModelContainer)
    }
}
```

### 3. 配置AppDelegate

```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 配置裙子股市
        Task {
            await SkirtMarketPersistence.shared.configure()
            await TaskDispatcher.shared.start()
        }
        
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // 调度后台任务
        TaskDispatcher.shared.scheduleBackgroundTask()
    }
    
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // 处理URL Scheme
        return URLSchemeHandler.shared.handleURL(url)
    }
}
```

### 4. 添加快捷指令安装入口

在你的设置页面中添加：

```swift
struct SettingsView: View {
    var body: some View {
        List {
            Section("快捷指令") {
                if ShortcutSetupService.shared.isShortcutInstalled() {
                    Label("快捷指令已安装", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button("安装快捷指令") {
                        presentShortcutSetup()
                    }
                }
                
                NavigationLink("查看使用指南") {
                    ShortcutSetupGuideView()
                }
            }
        }
    }
    
    private func presentShortcutSetup() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        ShortcutSetupService.shared.installShortcut(from: rootVC)
    }
}
```

## 快捷指令配置

### 方式1：iCloud链接安装（推荐）

1. 在快捷指令App中创建快捷指令
2. 配置如下动作：

```
动作1: 获取网页内容
   - 输入: 快捷指令输入

动作2: 在网页上运行JavaScript
   - 输入: 网页内容
   - 脚本: (见下方JavaScript代码)

动作3: URL编码
   - 输入: JavaScript的结果
   - 模式: 编码

动作4: 打开URL
   - URL: skirtmarket://import?data={{URL编码的文本}}
   - 在App中打开: 是
```

3. JavaScript代码：

```javascript
var result = {
    platform: "",
    title: document.title,
    price: "",
    url: window.location.href,
    image: "",
    seller: ""
};

var hostname = window.location.hostname;
if (hostname.includes("2.taobao.com") || hostname.includes("xianyu")) {
    result.platform = "xianyu";
    result.title = document.querySelector('h1')?.textContent?.trim() || document.title;
    result.price = document.querySelector('.price')?.textContent?.trim() || '';
    result.image = document.querySelector('.item-img img')?.src || '';
    result.seller = document.querySelector('.seller-name')?.textContent?.trim() || '';
} else if (hostname.includes("xiaohongshu")) {
    result.platform = "xiaohongshu";
    result.title = document.querySelector('.title')?.textContent?.trim() || document.title;
} else if (hostname.includes("taobao")) {
    result.platform = "taobao";
    result.title = document.querySelector('h3')?.textContent?.trim() || document.title;
    result.price = document.querySelector('.price')?.textContent?.trim() || '';
}

completion(JSON.stringify(result));
```

4. 长按快捷指令 -> 分享 -> 复制iCloud链接
5. 将链接填入 `ShortcutSetupService.swift` 中的 `iCloudLink` 变量

### 方式2：手动创建

用户可以按照App内的「手动安装指南」一步步创建。

## 使用流程

### 用户端流程

1. **首次使用**
   - 打开App，进入设置
   - 点击「安装快捷指令」
   - 选择安装方式（推荐iCloud一键安装）
   - 按提示完成快捷指令安装

2. **分享商品**
   - 在闲鱼/小红书/淘宝中浏览商品
   - 点击分享按钮
   - 选择「分享商品到裙子股市」
   - 自动跳转到App并导入商品

3. **查看导入结果**
   - App自动保存商品到数据库
   - 显示导入成功提示
   - 可以在「裙子股市」界面查看

### 开发者端流程

1. **接收数据**
   - 快捷指令抓取网页内容
   - 提取商品信息
   - 通过URL Scheme发送到App

2. **处理数据**
   - `URLSchemeHandler` 解析URL
   - 创建 `LolitaItem` 对象
   - 保存到SwiftData
   - 触发AI去重处理

3. **分布式同步**
   - 数据自动同步到CloudKit Public DB
   - 所有设备可见
   - 触发股市指标更新

## 测试检查清单

- [ ] Info.plist已配置URL Scheme
- [ ] App能正确处理 `skirtmarket://` 链接
- [ ] 快捷指令能正确提取商品信息
- [ ] 数据能正确保存到数据库
- [ ] 导入成功后显示提示
- [ ] 多设备间数据同步正常

## 故障排除

### 快捷指令无法打开App
- 检查Info.plist中的CFBundleURLSchemes配置
- 确保URL格式正确：`skirtmarket://import?data=xxx`

### 数据解析失败
- 检查JavaScript代码是否正确执行
- 确认返回的是有效的JSON格式
- 检查URL编码/解码是否正确

### 数据未保存
- 检查CloudKit配置
- 确认SwiftData上下文正确
- 查看控制台日志获取错误信息

## 注意事项

1. **隐私合规**：确保用户知情同意数据收集
2. **平台规则**：遵守各电商平台的服务条款
3. **数据安全**：不要收集敏感个人信息
4. **用户体验**：提供清晰的操作引导

## 进阶功能

### 批量导入
可以扩展快捷指令支持批量导入：
- 在网页上运行JavaScript获取多个商品
- 返回JSON数组
- App端批量处理

### 智能识别
利用AI自动识别商品信息：
- 使用MiniMax分析标题
- 使用Qwen-VL分析图片
- 自动填充品牌、类型、颜色等字段

### 价格监控
导入商品后自动监控价格变化：
- 创建后台任务定期抓取
- 价格变化时推送通知
- 生成价格走势图
