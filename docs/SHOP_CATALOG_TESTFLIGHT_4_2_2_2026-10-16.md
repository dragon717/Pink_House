# TestFlight 团次修复包 4.2（2）（2026-10-16）

> **用户已暂停TestFlight上传。** 直连分发尝试另返回“Account credentials have expired”，未上传成功；原系统代理已恢复。后续还完成了[入橱同页选择批次的界面调整](SHOP_CATALOG_INLINE_BATCH_PICKER_2026-10-16.md)，新本地归档另行保留，未继续上传。只有用户明确恢复分发才继续；下文是暂停前的准备与排障记录。

## 原因与数据口径

用户真机确认 Xcode 开发安装版已显示「先行团 / 非圣诞先行团」后，反馈测试版仍无团次。Xcode Organizer 中最新已上传归档为 2026-10-15 19:32 的 4.2（1），上传时间20:04，早于10月16日的购买查询修复。此证据证明旧上传包不含修复，不等同于当前所有测试用户均已安装该包。

2026-10-16 11:32（Asia/Shanghai）独立只读拉取 Production：seq16，根摘要 `975d4e3d401ce6246f55a18dbafe3c069105a6136cecab6d65f989825d619d57`。系列 `series-ops-19AAE8DD` 已包含两团、稳定ID及「一个月」结束描述。测试版需要包含新代码的安装包；不重复发布该系列或更改线上数据。

本次归档包含 [已发布团次消费修复](SHOP_CATALOG_PUBLISHED_BATCH_CONSUMPTION_2026-10-16.md)，该修复104项回归通过，开发版真机由用户确认已显示两团。归档基于当前本机工作区；没有重置其他既有改动，没有提交或推送。

## 构建

Xcode27.0（27A266a），显式指定 DEVELOPER_DIR，不修改全局 Xcode 选择。仅命令行覆盖版本，使主 App 和 Widget 均为4.2（2），不改写工程已有版本字段。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild archive \
  -project ItemManager.xcodeproj -scheme ItemManager -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -archivePath '/Users/sangyu/Library/Developer/Xcode/Archives/2026-10-16/ItemManager 4.2-2 Catalog Fix.xcarchive' \
  -jobs 3 CURRENT_PROJECT_VERSION=2 MARKETING_VERSION=4.2
```

证据目录：`/private/tmp/pink-house-testflight-batches-20261016/`，包含归档日志、Production回读及独立提取的团次核对结果。

## 当前发布状态

Release归档 **ARCHIVE SUCCEEDED**（退出0）。`archive-verification.json`：主App及Widget均4.2（2），签名团队833FJ74GS2，CloudKit环境Production，深层严格签名校验通过，无XCTest插件。归档仍为开发签名，需由后续分发导出重新签名，不能直接当作App Store分发IPA。

App Store Connect分发导出已执行两次，均退出70（EXPORT FAILED）（`method=app-store-connect`、`destination=export`、自动签名、Production、固定build2），命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -exportArchive \
  -archivePath '/Users/sangyu/Library/Developer/Xcode/Archives/2026-10-16/ItemManager 4.2-2 Catalog Fix.xcarchive' \
  -exportPath /private/tmp/pink-house-testflight-batches-20261016/exported-app-store \
  -exportOptionsPlist /private/tmp/pink-house-testflight-batches-20261016/ExportOptions.plist \
  -allowProvisioningUpdates
```

分发失败发生在登录及获取签名阶段：`NSURLErrorDomain -1200`，TLS连接失败；本机没有有效的Apple Distribution私钥作为离线回退。未将该错误断定为密码过期，没有重置账号或签名资料。

只读网络诊断：系统HTTP / HTTPS / SOCKS代理均启用，指向本机同一端口。直接使用默认curl连接Apple开发者服务返回HTTP200、证书验证0；App Store Connect返回302、证书验证0。给同一开发者URL显式套用当前系统HTTP代理后，curl退出35（SSL_ERROR_SYSCALL），HTTP000。与Xcode请求的lo0路径及TLS错误一致，支持“当前代理路径失败”结论；不推断Apple全局服务故障。

已请求用户选择：允许分发期间临时关闭系统代理、上传4.2（2）并恢复，或由用户自行调整网络。此操作会影响整台Mac的联网方式，因此等待用户授权后再更改。**当前未修改系统代理，未关闭证书校验。**

最终状态：Release归档完成；App Store Connect分发导出尚未完成；没有上传Apple，也未确认TestFlight可用。完整结果为证据目录内`release-status.json`。网络恢复后复用同一归档继续分发，无需重新编译；上传成功后仍需检查Apple处理与测试组可用状态。

`git diff --check`通过。104项测试及开发安装版真机确认来自所链接的前序修复验证；本轮没有把它们记为TestFlight真机验收。
