# House 洛可可左上悬浮菜单点击修复记录

## 目标

修复 `RococoSmallWorldView` 左上角悬浮视图菜单经常点不到、原生菜单打开后菜单项点击无反应的问题。范围只限洛可可 House 菜单页，不改法式复古、不改底部 House 长按轮盘、不改 ThemeSkin slot / manager / manifest。

## 实施策略

- 用 `RococoViewModeFloatingMenu` 替换原生 SwiftUI `Menu + Picker`，避免系统菜单弹层与房间缩放/拖拽、全局 overlay 的事件竞争。
- 悬浮按钮使用固定 56×56 命中区、`contentShape(Rectangle())`、`.buttonStyle(.plain)` 与稳定 `zIndex`。
- 菜单展开时给房间内容加 `.allowsHitTesting(false)`，并用透明全屏遮罩接管外部点击，确保点外部只关闭菜单、不透传给 House 热区。
- 菜单项全部为真实 `Button`：视图模式三项与 DEBUG 下热区/路径调试项，点选后立即关闭面板。
- 保留 `@AppStorage("rococoViewMode")` key 与现有 House 路由语义。

## 本地 harness 归档

本次任务按 harness 风格写入本地产物目录（`temp/*` 被 `.gitignore` 忽略，作为本地验收附件保留）：

- `temp/house_rococo_menu_interaction/_artifacts/runs/20260501-0118/RUN.md`
- `temp/house_rococo_menu_interaction/_artifacts/accept/20260501-0118/RESULT.md`

## 验收清单

- [x] `git diff --check -- ItemManager/Views/RococoSmallWorldView.swift temp/house_rococo_menu_interaction`
- [x] `xcrun --sdk iphonesimulator swiftc -parse -target arm64-apple-ios17.0-simulator -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" ItemManager/Views/RococoSmallWorldView.swift`
- [x] `RococoSmallWorldView.swift` 中无左上角原生 `Menu { ... }` 路径残留。
- [x] `rococoViewMode` key 保留。
- [ ] iOS 模拟器/真机运行验收：当前项目规则允许按需运行 `xcodebuild`；本历史任务当时未运行，后续复验时在 RESULT.md 补充构建/运行命令、结果和验证边界。
