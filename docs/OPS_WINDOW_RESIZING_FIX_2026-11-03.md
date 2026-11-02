# 运营 App 缩小窗口后按钮不可见修复（2026-11-03）

## 根因与修改

- S3 类型选项区原来是不能滚动的长 VStack，与款式 List 争用有限高度。窗口变矮后，内容的固有最小高度把向导导航挤出窗口；原生分栏还可能按历史/理想尺寸向两侧溢出。
- 主详情区和向导内容区现在明确接收父容器的实际可用尺寸。导航栏独立保留高度，长内容在内部滚动，不再决定整页最小高度。
- 类型选项最多占左列一半高度，选项和款式列表分别滚动；录入、商品管理和店家与系列三处按实际可用宽度自动分配列宽，取代原有可拖动分栏及其历史尺寸约束。
- 顶部业务/同步反馈使用按实际内容高度收敛、并有最大高度限制的滚动区域，长错误详情不会占满编辑区。
- 公共表单的滚动区由固定高度改为可收缩高度；批量配图窗口也允许缩小。取消、保存和确定操作位于独立底栏。
- 主窗口沿用最小内容尺寸 980×620，没有通过提高最小窗口尺寸规避问题。DEBUG 布局探针记录导航按钮实际 CGRect；Release 不包含记录或探针回调。

## 自动验证

环境：Xcode 27.0（27A266a），macOS arm64。以下命令均设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/chart-units-debug \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
python3 tools/testing/run_ops_catalog_editor_regressions.py --derived-data build/chart-units-debug \
  --window-layout-snapshot-dir /private/tmp/pink-layout-snapshots
SPM_CACHE=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  tools/xcode/build_mac_release.sh
```

`TEST BUILD SUCCEEDED`、Release `BUILD SUCCEEDED`，101 项工作区 XCTest 通过、0 失败，10 个布局场景生成完成，严格签名验证通过。工作区 XCTest 与布局夹具使用临时 SwiftData 数据，不触碰正式草稿、不发送网络发布。

布局夹具入口：`tools/testing/OpsWindowLayoutSnapshots.swift`。共 10 个截图场景：S3 的 980×620、1120×720、1600×900，最小尺寸下的店家与系列、商品管理、本地预览、发布草稿箱、长错误提示，以及 560×400 公共表单、760×440 批量配图。4 个 S3 场景均检查两个导航按钮具有正尺寸且完全位于根视图边界内。截图已目视检查类型列、表单和配图操作栏。

980×620 夹具中：上一步 CGRect 为 `(820, 582, 64, 27)`，下一步为 `(896, 581, 68, 29)`；长错误提示场景的导航位置相同。

修正了既有图片缓存测试对对象身份的过强假设：NSCache 允许内存压力下回收，测试改为检查重新请求后的图像尺寸及替换/删除行为，不要求两次 CGImage 必须是同一个对象。未改变缓存实现。

构建日志 `/private/tmp/pink-layout-build.log`、`build/mac-release/build.log`；测试和快照日志 `/private/tmp/pink-layout-tests.log`；导航位置证据位于截图目录的 `wizard-*.txt`。

## 本机安装与实际操作

已正常退出旧进程、更新并启动 `/Applications/少女心愿运营.app`。新旧应用 bundle ID、签名团队及全部 entitlement 相同；旧版保留在 `/Applications/.codex-window-layout-backup-20261103-032925/少女心愿运营.app`。签名、安装和验收记录：`/private/tmp/pink-house-window-layout-install-20261103.json`。

电脑控制确认系统缩放前后页面正常；恢复原窗口尺寸并返回 S3 后，类型选择区、款式列表、保存草稿、上一步和下一步均在实际画面中可见。原草稿第 3578 版、4 店家 / 14 系列 / 431 商品 / 656 图片保持不变；原价格表含 BNT 的 16×5 数据仍识别成功。

验证边界：最小精确内容尺寸由真实 NSHostingView/AppKit 布局夹具覆盖；日常安装 App 通过系统缩放与截图验收。未对正式业务字段执行保存修改或云端发布。

## 后续现场恢复：系统菜单追踪残留

用户随后反馈窗口完全无法操作。旧进程 PID 67862 的 CPU 接近 0%，5 秒采样显示主线程位于 `NSMenuItem(Accessibility) accessibilityPerformAction` → `NSMenuTrackingSession startRunningMenuEventLoop` 的嵌套菜单事件循环，点击商品管理未切页。这与前次窗口菜单自动化操作相关，不能将此前 AX 控件可读或截图正常等同于普通鼠标交互正常。

已用 Cmd-Q 正常退出旧进程，重新启动同一已安装版本（PID 70432），没有改代码、强杀、清空或迁移草稿。恢复后重新采样并实际点击商品管理成功；搜索「贝雷帽」从 431 项筛为 9 项，再清除搜索返回原草稿。草稿仍为第 3578 版、431 商品 / 656 图片。后续原生菜单验收结束后必须明确取消菜单，并验证普通侧栏鼠标点击确实切页；若菜单状态不明，正常退出重启后再交付，不能只凭 AX 读取或按钮直接调用判定完成。

证据：`/private/tmp/pink-stuck-sample.txt`、`/private/tmp/pink-recovered-sample.txt` 及安装记录的 `followupRecovery` 字段。
