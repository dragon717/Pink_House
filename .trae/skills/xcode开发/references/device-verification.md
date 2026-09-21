# 模拟器验收

读取时机：要在模拟器上看效果、截图、核对文案或点击时。

## 铁律顺序

Computer Use 只能证明「当前 Simulator 窗口显示了什么」，不能证明它来自新代码。顺序必须是：

1. 锁定用户正在看的模拟器 destination（名字或 UDID）；
2. 对**同一个** destination 重新编译；
3. 安装新产物；
4. `simctl terminate` 旧进程，再 `simctl launch`；
5. **最后**才读取页面或点击核验。

```bash
PRODUCT=build/sym/Debug-iphonesimulator/ItemManager.app
xcrun simctl install booted "$PRODUCT"
xcrun simctl terminate booted bugod2.ItemManager   # "found nothing to terminate" 不是失败
xcrun simctl launch    booted bugod2.ItemManager
```

看到旧文案时，先假设是**旧进程 / 旧构建 / 装错模拟器 / 页面缓存**，不要先怀疑代码没改对。

## 文案类改动可先查产物

```bash
rg -a -n "新文案|旧文案" build/sym/Debug-iphonesimulator/ItemManager.app
```

## 「真交互」只有 XCUITest 这一条可靠路径

`xcrun simctl io screenshot` 能看画面，但**点不动**。本机实测过的死路：

| 尝试 | 结果 |
|---|---|
| `xcrun simctl privacy booted grant location <bundle>` | exit 0，但首启位置权限弹窗**照样出现** |
| `osascript` + System Events 点击 | `execution error: 权限违例 (-10004)`，沙箱里被拒 |
| `cliclick` / `idb` | 本机未安装 |

可行做法：写 XCUITest 驱动，自己处理权限弹窗、自己导航、自己截图。见 `uitest-pitfalls.md`。

```swift
// 关掉首启权限弹窗（App 自己的 alert 或 springboard 上都要试）
let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
for label in ["不允许", "Don't Allow", "好", "OK"] {
  for container in [app, springboard] where container.buttons[label].isHittable {
    container.buttons[label].tap()
  }
}
```

跑法（`-resultBundlePath` 必需，否则拿不到附件）：

```bash
scripts/build.sh test -o ItemManagerUITests/<你的类> -r /tmp/ph_ui.xcresult
```

取附件（**Xcode 27 写法**，旧版 `xcresulttool get` 已不适用）：

```bash
xcrun xcresulttool export attachments --path /tmp/ph_ui.xcresult --output-path /tmp/ph_ui_attach
# 得到 manifest.json + 以 UUID 命名的 png/txt/mp4；对应关系看 manifest.json 的 suggestedHumanReadableName
```

## 假绿检测：TEST SUCCEEDED 也可能跑的是旧产物

改完源码跑 test，构建数据库（XCBuildData）可能误判产物最新 → **完全不重编**，
用旧 App + 旧测试二进制跑出全绿。`strings` 查中文串会失效（UTF-8 高字节不可见）。

防御三步：

1. 跑完用 `scripts/verify_fresh_build.sh <起点时间戳>` 校验产物 mtime；
2. 截图里的状态栏时间 = 运行时刻，与版式对不上就是旧产物；
3. 发现不重编 → `touch` 改过的源文件再 build 一次，真有编译错误会立刻暴露。

## 结果记录口径

必须写清：跑过的命令与 destination、PASS/FAIL、是否完成安装与进程重启、实际观察到的关键 UI 文案或状态，
以及未覆盖边界（未跑构建 / 未跑模拟器 / 未跑真机 / 仅静态检查）。

**不要把「Simulator 里有一个页面」写成完整验收通过。**
缺少重新编译或进程重启时，必须明确标注验收不完整。
