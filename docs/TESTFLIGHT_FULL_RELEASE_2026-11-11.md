# 4.4（5）全量功能 TestFlight 发布记录

日期：2026-11-11（Asia/Shanghai）。取代 [4.4（4）的局部范围候选](TESTFLIGHT_WARDROBE_FILTER_2026-11-10.md)。两个候选均未上传 Apple。

## 范围与 GitHub

用户明确要求包含工作区现有全部功能改动。本轮提交并推送 `f2e1a9ac635417a75d31bb09b749242a013b7cb5`，分支 `codex/duo-adaptive-navigation`：

- 主 App 与 Widget 多语言、名称及权限文案、衣橱快捷入口文案、尾款日期排版。
- 春光主图标、经典及 VIP 可切换图标、空衣橱插画、背景细节。
- 喵币同笔交易共用到账任务、余额/首购/回执一起保存、中断后只补齐状态及流水、购买历史防重。
- 前序收纳柜同步筛选、店家优先排序、筛选索引和相关死代码清理；本轮继续精简新增内购和本地化注释。
- 本地 StoreKit 配置、专用测试 scheme、商店资料工具与既有验证记录。

主 App、Widget 的工程版本统一为 4.4（5）。个人 `.workbuddy/memory/2026-10-31.md` 未加入功能提交；没有强推、合并主分支或改变线上商店地区、价格及 App Store 审核状态。

## 验证

- 主 App 3,746 个本地化键、Widget 16 个键均可解析且无重复 JSON 键；新增图标、图片和本地 StoreKit JSON 校验通过。
- `git diff --check`、工程和权限字符串 plist 语法检查通过。
- 当前代码的 StoreKit 测试目标编译完成，但模拟器启动后未进入测试执行，停止本次运行；不记为测试通过。历史 4.4（3）的本地 StoreKit 2/2 记录见 [既有验证报告](localization/runs/2026-11-03/RESULT.md)，不冒充本次新跑的结果。
- Release 归档成功（`ARCHIVE SUCCEEDED`，退出 0）。主 App 与 Widget 均为 4.4（5），九语 `Localizable.strings` 与 `InfoPlist.strings` 齐全。
- 主图标为 `SpringWardrobe`，五个备用图标齐全；深层严格签名校验通过，团队为 `833FJ74GS2`，主 App CloudKit 为 Production。
- 归档不含 `.xctest` 和 `.storekit` 文件。未完成真机界面、TestFlight 实购或 TestFlight 安装验收。

## 构建与产物

源码工作区为干净的 `/tmp/PinkHouseTestFlight20261110`，固定在上述提交。Xcode 27.1（27A9275），不改全局 Xcode 选择。

```sh
cd /tmp/PinkHouseTestFlight20261110
DEVELOPER_DIR=/Users/sangyu/Applications/Xcode-27.1.app/Contents/Developer \
xcodebuild -project ItemManager.xcodeproj -scheme ItemManager -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/PinkHouseTestFlightDerived20261110 \
  -clonedSourcePackagesDirPath /tmp/PinkHouseWardrobeBuild/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -archivePath /Users/sangyu/develop/Pink_House/output/TestFlight/2026-11-11-full-release/ItemManager-4.4-5.xcarchive \
  -jobs 2 -allowProvisioningUpdates archive
```

主 App 可执行文件 SHA-256：`7a4e874bd1cd9c7735bb1a3596f30781fd3d15c2c5b50ed237bad53c54da424c`。

本地产物根：`output/TestFlight/2026-11-11-full-release/`，含 `archive.log`、`archive-verification.json`、分发选项、`export.log` 与 `release-status.json`。分发日志和签名资料未上传 GitHub。

## 尚待完成的分发

用户确认解锁后，打开正确路径的 Xcode 27.1，实际看到首次启动组件选择；跳过额外模拟器下载后，Apple Accounts 列表为空，已打开账号登录窗口交给用户完成。此前 Xcode 27.0 中缓存的账号条目不能作为 27.1 已登录的证据。两个 Xcode 版本的命令行签名预检均返回 `No Accounts`。

新 4.4（5）归档再次分发导出返回退出码 70：`No Accounts`，没有团队对应的 `iOS Distribution` 私钥。目前归档仍是开发签名（`get-task-allow=true`）；没有生成 App Store 分发 IPA，没有执行上传，测试用户尚不能安装本候选。

下一步：在已打开的 Xcode 27.1 登录窗口完成账号验证，随后复用本归档导出，核验分发签名/实际构建号，上传并确认 Apple 处理及测试组可用性。无需重新编译；不要上传旧 4.4（4）候选。
