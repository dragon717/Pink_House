# 运营颜色图片连续填充（2026-10-16）

## 行为

「批量填充颜色图片」左侧点击图片即填充右侧当前勾选的颜色，移除每张图下方的「分配图片」按钮。填充成功后，按右侧颜色排列自动勾选后一个颜色；即使下一颜色已有图片，也允许连续更换。

- 默认选中打开入口指定的颜色，未指定时选中首个颜色。
- 单色配图完成后只选中下一颜色，并滚动到该颜色；无需再次手动勾选。
- 多选仍支持共用图片；本次勾选全部填好后，推进到最后一个已勾选颜色的后一项。
- 到列表末尾停止自动推进并清空勾选，提示点击「确定」保存。不会自动回到首色，也不自动提交窗口。
- 没有勾选颜色时，填充按钮不可用；图片读取失败时不推进颜色选择。
- 图片上不叠加预览图标；点击图片下方的文件名打开大图，右侧已配图片仍可点击预览。预览不填充、不推进选择。此为同日用户要求去除遮挡后的现行布局。
- 图片分配仍保存在窗口工作副本，点击「确定」通过原有稳定 ID 保存入口写回；取消保留原已保存配图。上传历史继续独立保留。

实现入口：`PinkHouseOps/Views/OpsColorImagesSheet.swift`。通用图片预览组件与其他运营上传入口不变。

## 构建、回归与验证边界

本机 Xcode 27.0（27A266a），工作区 `/Users/sangyu/develop/Pink_House`。以下命令通过：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
```

构建结果 `TEST BUILD SUCCEEDED`；65 项运营存储回归通过、0 失败，包括颜色图片保存、上传历史复用及草稿持久化。正常运行构建将 `build-for-testing` 改为 `build -configuration Debug`，结果 `BUILD SUCCEEDED`。`git diff --check` 通过。

用临时 `ColorFillQA.app` 承载实际 `OpsColorImagesSheet`，使用内存 SwiftData、三张不同原图和蓝 / 粉 / 白三色，没有读取真实运营数据库或发送云端请求。电脑控制实测：

1. 初次版本通过放大镜打开蓝图预览，关闭后勾选和分配数不变；下述后续调整已将入口移到文件名。
2. 初始蓝色与粉色已有错配图片；依次单击蓝图、粉图、白图，自动选择顺序为蓝 → 粉 → 白 → 无勾选。右侧图片随点击立即填入。
3. 确定后逐一核对稳定颜色 ID 对应的图片 ID，三色各自正确；S / M / L 尺码选择保留。证据 `ui-after-sequential.json`。
4. 重新打开，将蓝色临时改为粉图后取消，界面及已保存数据仍为原先正确的三色配图。
5. 同时勾选蓝色和粉色，单击白图，两个颜色一起填充，自动选中白色；确定后核对三色共用同一原图，尺码保留。证据 `ui-after-multiple.json`。

自动滚动使用 `ScrollViewReader` 随选择变更定位；本次实际点验为三色窗口，未宣称完成超长颜色列表的逐项验收。

## 日常工具生效

真实运营窗口显示已保存、无待确认配图后，退出旧窗口并通过 Xcode Stop 结束仍被调试器持有的旧进程，再更新日常应用。新旧签名均通过严格验证，四项 entitlements 相同。

新版已安装并启动于：

`/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/Build/Products/Debug/PinkHouseOps.app`

旧应用保留为同目录 `.codex-color-fill-20261016-165755/PinkHouseOps.previous.app`，未复制、清空或迁移应用数据目录。实际进入 S3 打开批量配图，确认显示「点击图片填充选中颜色」和独立「查看原图」入口；未操作真实配图，取消后仍为草稿第 1,419 版，5 店家、14 系列、273 商品、449 图片。

本次证据目录：`/private/tmp/pink-house-color-fill-20261016/`，包含构建日志、65 项回归日志、临时验收源文件、图片 ID 核对结果、签名与安装记录。TestFlight 上传继续暂停。

## 后续去除图片遮挡（同日）

用户确认右上角图标挡住图片后，移除 `ZStack` 中的放大镜覆盖层，直接显示可填充的缩略图；文件名作为下方独立的预览入口，未增加额外按钮行。提示同步改为「点击图片下方的文件名查看大图」。

本次执行上述正常运行构建（`build -configuration Debug`），结果 `BUILD SUCCEEDED`，`git diff --check` 通过。仅调整视图布局与提示，未新增测试或重复运行存储回归。隔离 `ColorPreviewQA.app` 使用真实配图组件，截图确认三张缩略图没有覆盖图标；实际点击文件名打开正确大图，关闭后仍选中蓝色、分配数不变；再点击蓝图成功填充并自动选中粉色。取消临时配图后退出，未修改真实颜色绑定。

新版已更新到上述日常工具路径并启动。新旧应用严格签名校验通过，权限相同；旧应用保留在 `.codex-preview-placement-20261016-175842/PinkHouseOps.previous.app`。此次证据目录为 `/private/tmp/pink-house-color-preview-placement-20261016/`，包含 `build.log`、验收夹具、`ui-verification.json`、签名与安装记录。
