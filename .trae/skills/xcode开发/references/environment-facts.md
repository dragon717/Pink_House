# 本机环境事实

读取时机：任何命令里出现写死的 Xcode 路径、仓库路径、模拟器名之前。

**这些值会漂移。** 每次开工先跑 `scripts/detect_environment.sh`，把输出当作本次会话的唯一真值。
下面记的是 2026-09-21 在 `sangyu` 机器上的实测快照。

## 快查表

| 项 | 实测值 | 怎么验 |
|---|---|---|
| 仓库根 | `/Users/sangyu/develop/Pink_House` | `git rev-parse --show-toplevel` |
| Xcode | `/Applications/Xcode.app`，27.0 (27A266a) | `xcodebuild -version` |
| 是否有 Xcode-beta | **没有**（`/Applications/Xcode-beta.app` 不存在） | `ls -d /Applications/Xcode-beta.app` |
| 主 scheme | `ItemManager` | `ls ItemManager.xcodeproj/xcshareddata/xcschemes/` |
| bundle id | `bugod2.ItemManager` | `scripts/detect_environment.sh` |
| 可用模拟器 | **iOS 27.0**：iPhone 18 Pro / 18 Pro Max · iOS 26.3：iPhone 17 Pro / 17 Pro Max / 17 / 17e / Air / 16e | `xcrun simctl list devices available` |
| 推荐 destination | **iPhone 18 Pro**（iOS 27.0） | `scripts/detect_environment.sh --sim-name` |
| pbxproj objectVersion | 77，用 `PBXFileSystemSynchronizedRootGroup` | `grep -m1 objectVersion ItemManager.xcodeproj/project.pbxproj` |
| 默认 actor 隔离 | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` | `grep SWIFT_DEFAULT_ACTOR_ISOLATION ItemManager.xcodeproj/project.pbxproj` |

## AGENTS.md 里已失效、不要照抄的三条

1. **仓库路径**写的是 `/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House`。
   那是**另一台机器**的路径，本机不存在。本机真值见上表。
   （AGENTS.md 自身已在开头注明这点，但里面的命令块仍带着旧路径。）

2. **Xcode-beta**：AGENTS.md 要求显式设 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`。
   本机没有该 app，照抄会直接报 `missing DEVELOPER_DIR path`。**不要设，用默认 `xcodebuild`。**

3. **模拟器名**写的是 `iPhone 16 Pro`，本机模拟器列表里没有这个名字。
   用 `xcrun simctl list devices available` 里真实存在的名字，或用 UDID。

### 比"名字存在"更严的约束：runtime 必须匹配

`iPhone 17 Pro` **名字存在但不能用**：它是 iOS 26.3 runtime，本工程 scheme 只认 iOS 27 runtime，
用它做 destination 会直接 `exit 70`。必须用 **iPhone 18 Pro / 18 Pro Max（iOS 27.0）**。

`detect_environment.sh` 的推荐逻辑就是按"取最后一个 runtime 分组"实现的，别改成"取列表里第一台"。
不确定时用 UDID：`-destination 'platform=iOS Simulator,id=<UDID>'`。

同理，`docs/skills/pink-house-xcode27-cli-build` 与 `tools/xcode/stable_cli_build_and_run.sh`
默认指向 `/Applications/Xcode-beta.app` 且默认 `SIM_NAME="Codex iPhone 17 Pro"`（本机无此设备）。
要用它们必须显式覆盖：

```bash
XCODE_APP=/Applications/Xcode.app SIM_NAME="iPhone 18 Pro" tools/xcode/stable_cli_build_and_run.sh
```

## 新文件自动进 target，不用改 pbxproj

`objectVersion = 77` + `PBXFileSystemSynchronizedRootGroup`：新增 `.swift` 会自动纳入主 target。

**例外**：小组件扩展 `少女心愿衣橱Extension` 有
`PBXFileSystemSynchronizedBuildFileExceptionSet`，只编译固定的几个文件
（`Brand.swift` / `Clothing.swift` / `Item.swift` / `Tag.swift` 等）。
新文件不会进扩展 target；要在扩展里用新代码，必须手动加进例外集。

## 默认 MainActor 隔离的推论

类型默认 MainActor 隔离 ⇒ `nonisolated` 上下文里**不能**调用依赖 MainActor 状态的本地化入口
（如 `String.appLocalized`，背后是 `LanguageManager.shared`），否则报
`call to main actor-isolated ... in a synchronous nonisolated context`。

切开「纯逻辑」和「本地化文案」：

```swift
nonisolated struct Row { let count: Int }        // 纯数据/匹配 → 可单测
@MainActor extension Row {                        // 文案 → 跟随默认隔离
  var text: String { "\(count)" + "件".appLocalized }
}
```

## 跨模块成员要显式 import

SDK 27 / Swift 6.4 下，间接依赖里的类型不再"顺带可见"。症状极易误判成"类型没定义"：

| 报错 | 真因 | 修法 |
|---|---|---|
| `type 'X' does not conform to protocol 'ObservableObject'`（X 确实写了 `: ObservableObject`） | `ObservableObject` / `@Published` 属 **Combine**，只 `import SwiftUI` 不够 | 服务层加 `import Combine`（项目惯例：`import Combine` + `import Foundation`） |
| `property 'modelContext' is not available due to missing import of defining module 'SwiftData'` | `@Environment(\.modelContext)` 属 SwiftData | 视图加 `import SwiftData` |

## 测试数据隔离硬规则（落盘测试必读）

单测宿主是**主 App**（`bugod2.ItemManager`），测试进程里的 `FileManager.default` 就是**用户真实沙盒**。
`tearDown` 里删 Application Support 文件 = 删用户数据。

落盘测试一律用注入目录，不准指向真实路径。既有防线测试：`ItemManagerTests/ShopCatalogStorageIsolationTests`。
