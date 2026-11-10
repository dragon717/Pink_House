# 衣橱筛选同步与店家排序

更新：2026-11-09。

## 行为

- 首页选中的标签、店家、类型、颜色、尺码、长度、品相、小物与预约状态，一并传入收纳柜抽屉与柜内页面。抽屉数量、状态数量和柜内展示使用相同的筛选结果。
- 切换柜子保留首页筛选，柜内搜索继续在该结果内收窄。没有匹配项时显示筛选空状态，可返回衣橱调整条件；取消首页筛选后恢复展示。
- 排序菜单新增「店家排序」。通过「优先显示的店家」点选店家即优先展示该店家；「按店家名称」恢复店家名称顺序。其他店家按名称排列，同店家按添加时间从晚到早排列，未填写店家的物品排最后。
- 首页、收纳柜和待付尾款共用店家比较规则。店家选择使用 UUID，改名不会丢失优先级；已删除的优先店家自动不再命中。
- `UserPreference_SortOption` 保持原有存储兼容，新增 `UserPreference_PreferredBrandID` 保存优先店家，重进首页或重启应用后继续使用。

## 验证

`WardrobeStorageInventoryTests` 新增组合标签/店家筛选、清除筛选恢复、店家分组、优先级、无店家与失效店家、首页异步排序与模型排序一致性覆盖。原有收纳分柜与预约状态测试继续保留。

构建与测试使用 Xcode 27.1（27A9275），显式指定：

```sh
export DEVELOPER_DIR=/Users/sangyu/Applications/Xcode-27.1.app/Contents/Developer
xcodebuild -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /tmp/PinkHouseWardrobeBuild -quiet build
xcodebuild -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /tmp/PinkHouseWardrobeBuild -jobs 2 \
  -only-testing:ItemManagerTests/WardrobeStorageInventoryTests \
  -only-testing:ItemManagerTests/WardrobeOwnershipFilterTests \
  -only-testing:ItemManagerTests/WardrobeStorageSettingsTests test
```

已通过：改动的 7 个 Swift 文件执行 `swiftc -frontend -parse`；`git diff --check`；新增 4 条文案的 JSON 解析及 9 语言完整性检查。语法解析不代表类型检查或完整构建通过。

首次默认并发构建因资源压力及 Xcode 编译任务异常信息中断，改为两个并发任务重试。低并发重试完成应用和测试目标编译，但 iOS 27.0 模拟器启动数分钟未进入 XCTest 执行，因此中断；使用 iOS 26.3 的 `test-without-building` 重试仍停留在运行时启动，亦中断，不能视为 XCTest 通过。

排序比较器从实际服务源码提取，使用 `xcrun swift /tmp/pink-wardrobe-brand-order-check.swift` 独立运行：通过。覆盖优先店家、其他店家分组、同店家新建优先、无店家置后、无优先店家、已删除的优先店家以及切换优先店家。

后续仅构建检查命令与首次相同，改用 `-jobs 2 build`：**通过（BUILD SUCCEEDED，退出码 0）**，输出 `/tmp/pink-wardrobe-build-final.log`。未做真机或界面视觉验收。

测试启动重试命令：

```sh
DEVELOPER_DIR=/Users/sangyu/Applications/Xcode-27.1.app/Contents/Developer \
xcodebuild -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /tmp/PinkHouseWardrobeBuild -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/WardrobeStorageInventoryTests \
  -only-testing:ItemManagerTests/WardrobeOwnershipFilterTests \
  -only-testing:ItemManagerTests/WardrobeStorageSettingsTests test-without-building
```
