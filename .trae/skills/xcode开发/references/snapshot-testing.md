# SwiftUI 快照测试（ImageRenderer）

读取时机：用 `ImageRenderer` 在单测里导出 PNG 做版式核对之前。

**坑 C 会直接崩掉整个测试进程**，表现为 `Restarting after unexpected exit, crash, or test timeout`，
重跑后 `Executed N tests, with 0 failures` 却仍报 `** TEST FAILED **`。

## 坑 A：`UIImage.size` 是「点」，不是像素

```swift
renderer.scale = 2
let image = renderer.uiImage!
image.size.width        // == frame 的 pt 值（如 393），不是 786
image.cgImage!.width    // 这才是像素（786）
```

断言用 `XCTAssertEqual(image.size.width, 393, accuracy: 4)`；用 `393 * 2` 去比会稳定失败。

## 坑 B：`ScrollView` / `Form` / `List` 渲染出来是空框架

这些容器只渲染可视区，`ImageRenderer` 拿到的是空白。
**解法：把要核对的区块抽成不含滚动容器的独立 View**，快照渲染那个 View。
（例：`MidsummerYearRail`（含 ScrollView）旁再拆一个 `MidsummerYearRailContent` 只给快照用。）

## 坑 C：视图带 `.task` / `.onAppear` 且会写状态 → 崩测试

```
SwiftUICore/Logging.swift:232: Fatal error: no current update to enqueue action to
```

触发条件：被渲染的视图里有 `.task { await … }` 或 `.onAppear { … }`，且回调会在渲染期写 `@State` / 发 `objectWillChange`。

- 实例：`MidsummerContributeView` 的 `.onAppear(perform: prefill)`、
  `MidsummerBrandView` 的 `.task { await store.refreshFromCloud() }`
- **不要**把这类页面整体丢进 `ImageRenderer`。规则用纯逻辑单测覆盖
  （把校验抽成 `nonisolated` 静态函数），别指望截图。

## 坑 D：`isOpaque = true` + 画布没铺满 → 黑边 + 内容垂直居中

```swift
// 正确写法：铺满白底 + 顶部对齐
ImageRenderer(content: view
  .frame(width: w, height: h, alignment: .top)
  .background(Color.white)
  .environment(\.colorScheme, .light))
renderer.scale = 2
renderer.isOpaque = true
```

## 坑 E：`Menu` / `Picker` 这类系统控件渲染成「禁止符号」

`Menu` 在 `ImageRenderer` 下无法栅格化，快照里会画出**红黄禁止标志**，看起来像真实 UI bug。

```swift
// ❌ 快照里变成禁止符号
Menu { Button("访问官网") { … } } label: { Image(systemName: "ellipsis") }

// ✅ 改成 Button + confirmationDialog：真机行为等价，快照可正常核对
Button { showsMenu = true } label: { Image(systemName: "ellipsis") }
  .confirmationDialog(title, isPresented: $showsMenu) { … }
```

判断：某控件真机正常、快照里变成占位图形 → 先怀疑是这个坑，别急着改业务逻辑。
同理适用于 `Picker`、`DatePicker` 等 AppKit/UIKit 承载的控件。

## 快照 PNG 落在模拟器沙盒里，不在宿主机 `/tmp`

```bash
SIM=$(xcrun simctl list devices | grep "iPhone 18 Pro" | grep -o "[0-9A-F-]\{36\}" | head -1)
# ⚠️ macOS 是 BSD find，-newermt 只认**绝对时间**，写 "10 minutes ago" 会静默匹配不到任何文件。
find ~/Library/Developer/CoreSimulator/Devices/$SIM/data/Containers/Data/Application \
  -path "*<你的目录名>*" -name "*.png" -newermt "$(date -v-10M '+%Y-%m-%d %H:%M:%S')" \
  -exec cp {} /tmp/snaps/ \;
```

同一个 `Application/<UUID>` 容器会被后续测试复用，删掉的测试留下的旧 PNG 仍在那里。
**务必按 mtime 过滤**（用上面的绝对时间写法），否则会把已经不生成的旧图当成新结果。
