# Mac 云端同步 174 张缺图：交接恢复（2026-10-08）

## 现场证据

用户提供 `/Users/sangyu/Desktop/许愿池/云端同步问题-174.txt`。该次运行已下载 development 的 releaseSeq 5 并保存合并结果，上传在发送请求前因本机缺图受阻。

本次只读检查 Downloads 中的 `2026-09-28-00-58-shop-catalog-bundle` 和对应 tar：目录引用了 450 个不同的本地图片文件，包内有 276 个；缺失的 174 个文件名与附件逐一相同。桌面、Downloads 和仓库资源目录中未找到这些原文件。用户确认原图仍在手机上。

这是旧交接包没有带齐原图造成的现场数据缺口。当前线上目录只有 4 个图片资源；按线上 `thmedia:` 下载无法凭本地随机文件名重建这批原图。不能清空引用或换成占位图来放行。

## 修复后的使用方式

1. 在保留原图的手机上使用最新 iOS App 的「导出整包（含图片）」，把新包传到 Mac，再解压。
2. 打开新构建的 Mac 运营工具，在「设置 → 数据修复 → 补齐缺失图片…」选择新包的解压目录或 `images` 文件夹。
3. 查看补入数和剩余缺图数。全部补齐后再次运行「云端更新」。

补图入口只补当前草稿引用但 staging 中不存在的原文件名；不导入包内 JSON、不替换当前编辑、不推进发布或合并基线、不覆盖已有图片。支持整包根目录、`images` 文件夹及只套一层的解压目录。

每张图片先过共享媒体字节门禁，再写临时文件并移动到正式路径。读写失败不会留下被误认为已补齐的文件；部分成功保留，失败和找不到的文件单独计数。拒绝路径越界的文件名及逃逸到所选目录之外的符号链接。

iOS 的整包导出统一使用 `ShopCatalogExportArchive.completeHandoffEntries`，遍历商品资源、店家图、系列封面/价格表和尺码表原图，去重打包。任一本地引用缺文件时停止导出并显示缺图数量和文件名，避免交出可被误认为完整的包。

## 验证

环境：`/Applications/Xcode.app`，Xcode 27.0（27A266a）。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/SharedCatalog --scratch-path /tmp/pink-image-repair-shared --disable-sandbox
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/PinkHouseOps --scratch-path /tmp/pink-image-repair-ops --disable-sandbox
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/PinkHouseOps --scratch-path /tmp/pink-image-repair-ops \
  --disable-sandbox --filter OpsLocalImageRepairTests
python3 tools/ops_ui/check_markdown_callsites.py
git diff --check
```

SharedCatalog 207 项通过，PinkHouseOpsCore 85 项通过；最终临时文件落盘调整后，6 项补图测试再次通过。新增回归覆盖非商品图完整交接、缺图停止导出、保留原文件名/字节、只收所需图片、已有图片不覆盖、重复补图、套层目录、坏图部分成功、路径越界，以及旧包缺 174 张时仍如实报告。

构建命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ItemManager.xcodeproj -target PinkHouseOps -configuration Debug -sdk macosx -jobs 5 \
  SYMROOT=/Users/sangyu/develop/Pink_House/build/image-repair-products \
  OBJROOT=/Users/sangyu/develop/Pink_House/build/image-repair-objects build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ItemManager.xcodeproj -scheme ItemManager -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /Users/sangyu/develop/Pink_House/build/DerivedDataImageRepair \
  -jobs 5 CODE_SIGNING_ALLOWED=NO build
```

两条构建命令均通过（`BUILD SUCCEEDED`）；Mac 最终补图落盘调整后也已增量构建通过。Mac 产物为 `build/image-repair-products/Debug/PinkHouseOps.app`，iOS 模拟器产物为 `build/DerivedDataImageRepair/Build/Products/Debug-iphonesimulator/ItemManager.app`。日志：`/tmp/pink-image-repair-mac-build.log`、`/tmp/pink-image-repair-ios-build.log`。

Markdown 渲染门禁为 31 个文件、0 违规，差异空白检查通过。构建仍有工程既有的 API 弃用、并发隔离、架构选择及 AppIntents 元数据警告；未在此次补图任务中调整这些无关代码。

验证边界：没有运行 GUI 或模拟器界面验收，没有安装到用户手机、访问手机上的原图、修改现有用户草稿或执行真实 CloudKit 发布。附件指向的应用容器日志被 macOS 以 `Operation not permitted` 拒绝读取。代码与离线测试通过不代表现场 174 张原图已经补回或上传成功。

## 2026-10-09 后续现场核对

当前 Mac 已保存 revision 457：452 个本地引用文件全部存在，0 缺图；其中 450 个与本轮从手机复制的原图 SHA-256 完全一致。已保存完整目录及图片副本，没有覆盖用户编辑或执行云端写入。本轮没有往真实 staging 补写图片，旧包缺 174 张属于此前历史现场。详见 [真实业务发布准备](BUSINESS_PUBLICATION_PREPARATION_2026-10-09.md)。
