# 本期 SwiftUI 官方技能更新

本期范围：系统底部导航、开屏、衣橱与时光馆详情主图。代码更新依据本机 Xcode 27.0 正式版（27A266a）最新导出的 Apple 官方技能；导出目录仅是本次读取输入，不作为长期技能源。

## 官方来源

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun agent skills export \
  --output-dir /private/tmp/pink-house-official-swiftui-20261011 --replace-existing
```

已读取 `swiftui-specialist`（structure、dataflow、environment、foreach、soft-deprecation 与相关 API 清单）和 `swiftui-whats-new-27`（State macro、toolbar、AsyncImage）。新 API 的签名和可用系统版本再对照当前 SwiftUI SDK interface 核验。

## 实现

- 系统导航在 iOS 18 及以上采用 `Tab(value:content:label:)`，使用稳定的 `AppFeatureID` 选择入口；iOS 17.4 仅保留同一系统 TabView 的旧声明形式。最低部署版本未改变。`.tabBarOnly` 使用系统导航样式，不恢复主题底栏、私有控件探测或固定高度避让。
- 每个入口的内容拆为 `NativeTabPage`，主题观察留在页面内。路由的 400ms 冷却改为 `.task(id:)` 与 `Task.sleep(for:)`，快速切换取消旧任务，离开视图时不遗留 DispatchWorkItem 回调。
- 时光馆商品主图和信息卡拆为独立 `View`，信息卡只接收显示字段。翻页状态由 `ShopCatalogProductGallery` 持有，不再使详情父视图随每次翻页重新计算表格和价格信息。此处未进行性能基准测量。
- 主图页面用资产 ID 标识，移除位置 ID 和每次渲染创建的 enumerated Array。选择也按资产 ID 存储：调换顺序、刷新 URL 保留所选资产；所选资产移除后回到首张，空图集清空选择。重复资产 ID 在组装图集时去重。
- 两个详情页共用 `DetailImageLayout`，从 GeometryReader 的当前可用高度计算主图高度。短窗口、横屏和分屏限制主图占用，正常手机竖屏继续采用 400pt。主图与信息卡保持 16pt 正常排版间距。
- 开屏采用原生 Button，图片内容拆为独立视图；保留整页点按进入、原图文字和原图元素。移除手动附加按钮 trait 和重复 accessibilityAction，让系统提供按钮交互语义。

`@State` 的 SDK 27 初始化规则已核对：本次新增状态无“声明初值后又在 init 中赋值”模式。现有大图查看器采用无声明初值、init 提供初值的方式。入橱仍使用 ImageManager 的持久文件与引用计数；官方 AsyncImage 的 HTTP 缓存行为不能替代衣橱图片持有与持久保存。

## 验证

本期验证命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /private/tmp/pink-house-detail-layout-20261011 \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/SwiftUIModernizationTests \
  -only-testing:ItemManagerTests/SplashArtworkLayoutTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests \
  -only-testing:ItemManagerUITests/NativeTabNavigationUITests \
  -resultBundlePath /private/tmp/pink-house-swiftui27-final.xcresult test
```

最终结果：**PASS**。SDK 27 编译成功；12 项单元测试 + 1 项四入口系统导航 UI 用例，0 失败；`git diff --check` PASS。日志 `/private/tmp/pink-house-swiftui27-final.log`，结果 `/private/tmp/pink-house-swiftui27-final.xcresult`，开屏与底栏截图 `/private/tmp/pink-house-swiftui27-final-previews/`。首次执行中 12 项单元测试通过，导航用例在一次切换后即时读取选中态失败；诊断复测确认四个入口和路由一致并通过。最终 UI 用例在点击后等待预期选中态，仍要求四个入口逐一正确切换。临时路由日志已移除。运行目标为 iOS 26.3；SDK 27 编译不能代替 iOS 27 外观验收，也未使用特定折叠／双屏真机。

上一轮的详情遮挡、图片所有权和兼容清理验证见 [修复记录](界面元素遮挡全量排查与修复_需求实现说明.md)。
