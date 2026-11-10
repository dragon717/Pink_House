# 衣橱筛选优化 TestFlight 发布记录

日期：2026-11-10（Asia/Shanghai）。

后续用户要求纳入全部功能，已生成 [4.4（5）全量候选](TESTFLIGHT_FULL_RELEASE_2026-11-11.md)。本记录的 4.4（4）保留为历史产物，不再用于后续上传。

## 当前状态

- GitHub：已提交并推送至 `codex/duo-adaptive-navigation`。
- 功能提交：`b9b7724f0028cd8051b6a8f8fe11f35bd0c4ff81`。
- 发布源码：`3fa0141349076c124e0fa7f6a4612560467ff884`，补交了已验证依赖的 `Package.resolved`。
- 归档：4.4（4）成功，主 App / Widget 版本一致，深层严格签名核验通过，主 App CloudKit 为 Production，无 XCTest 插件。
- App Store 分发导出：退出 70，尚未生成可分发 IPA。
- 上传：未执行；本次版本尚不能通过 TestFlight 安装。

## 范围与清理

发布收纳柜同步筛选、店家优先排序、品牌/标签索引与数据快照复用。移除重复的品牌/标签匹配、只返回常量的选项包装与无用参数，精简相关注释。保留用户其他未提交的本地功能改动。

从提交 `3fa01413` 创建独立干净工作区 `/tmp/PinkHouseTestFlight20261110` 归档。没有将其他未提交的图标、内购或多语言调整带入本包；没有合并或强推主分支。

独立工作区运行 `python3 tools/performance/benchmark_wardrobe_filter.py`：8 项校验通过；1 万件 / 100 品牌的热筛选 P50 0.245ms、P95 0.396ms，5 万件 / 100 品牌的 P50 1.735ms、P95 2.514ms。仅为合成数据上的筛选计算，不代表真机完整界面响应时间。前序测试目标编译记录见 [性能说明](wardrobe/FILTER_PERFORMANCE.md)；本次没有声称 XCTest 或真机界面验收通过。

## 归档

Xcode 27.1（27A9275）；仅命令行覆盖版本和构建号，不改变其他未提交工程配置。

```sh
cd /tmp/PinkHouseTestFlight20261110
DEVELOPER_DIR=/Users/sangyu/Applications/Xcode-27.1.app/Contents/Developer \
xcodebuild -project ItemManager.xcodeproj -scheme ItemManager -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/PinkHouseTestFlightDerived20261110 \
  -clonedSourcePackagesDirPath /tmp/PinkHouseWardrobeBuild/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -archivePath /Users/sangyu/develop/Pink_House/output/TestFlight/2026-11-10-filter-release/ItemManager-4.4-4.xcarchive \
  -jobs 2 -allowProvisioningUpdates \
  MARKETING_VERSION=4.4 CURRENT_PROJECT_VERSION=4 DEVELOPMENT_TEAM=833FJ74GS2 archive
```

结果：`ARCHIVE SUCCEEDED`，退出 0。归档主 App 可执行文件 SHA-256：`0e3a0ceaad6908dfc57b68e3364c0ead0267bd0c8cc197b783f3b63636ed93f5`。归档当前仍是开发签名（`get-task-allow=true`），不能直接作为 TestFlight 分发包。

首次新工作区自动解析依赖时未找到远端 `Package.swift`；补交既有锁文件，并复用 SHA `44a40daf54bcb8db2695f4af618107e72c472b36` 的已验证 checkout 后解决，没有升级第三方依赖。

## 分发阻塞与恢复

`xcodebuild -exportArchive -allowProvisioningUpdates` 使用 `method=app-store-connect`、自动签名、Production、`destination=export` 导出失败，具体错误为：

- Xcode 无法载入 Apple 账号凭据：`missing Xcode-Username` / `No Accounts`。
- 没有团队 `833FJ74GS2` 的可用 Distribution 私钥。
- 随后尝试打开发布用 Xcode，电脑控制明确返回 Mac 已锁定且无法自动解锁。

需要用户解锁 Mac，在 Xcode 27.1 的 Apple Accounts 恢复账号登录，然后复用现有归档继续导出。无需重编译、无需重置账号或系统代理。分发导出成功后需核验分发签名、实际构建号和 Production 环境，再上传并确认 Apple 处理及测试组可用状态。

证据根目录：`output/TestFlight/2026-11-10-filter-release/`。包含 `archive-final.log`、`archive-verification.json`、`ExportOptions.plist`、`UploadOptions.plist`、`export.log`、`release-status.json`。此目录被 Git 忽略，签名资料和分发日志未上传 GitHub。
