# TestFlight 商品排序客户端修复（2026-10-17）

> 用户继续提供截图后，已定位并修复发布商品数组未按编号重排的兼容遗漏，见 [现有 TestFlight 商品数组排序根因修复](SHOP_CATALOG_LEGACY_ARRAY_ORDER_ROOT_FIX_2026-10-17.md)。现有测试版可通过更新发布数据获得顺序，不需要先恢复 TestFlight 上传。本文的客户端缓存修复和本地归档仍保留，但不再把上传新包作为本次排序数据修复的前置条件。

## 现场边界

用户在运营「店家与系列」中保存仲夏物语 → 双子星的款式顺序，手机刷新后仍报告同类型内顺序不一致。运营同步修复后的实际导出显示 Development 25 与 Production 23 中全部 145 件双子星商品的 `displayOrder` 均与运营已保存值一致，缺失和错序均为 0；Production 的排序数据在此次补核对之前已正确。运营同步缺陷与实测记录见 [排序同步根因修复](OPS_PRODUCT_ORDER_SYNC_ROOT_FIX_2026-10-17.md)。

此前安装含排序实现的 Xcode 开发版的设备为「💕凤」。本轮用户连接、授权配对并确认异常的设备为「吃胖了想鼠」，运行 TestFlight 测试版。没有把另一台开发手机的安装结果作为这台测试手机已更新的证据。

`devicectl` 配对成功后读取设备详情：iPhone Air / iPhone18,4，iOS 27.2 beta / 24B5110a，开发者模式关闭。当前 Xcode 27.0 / 27A266a 在读取 App 列表时 DDI 个性化失败（CryptexKitHost.TatsuError 5），Device Hub 显示该设备不可用。尚未取得它实际安装的版本/构建号，也未目视手机排序。没有修改系统开发者模式或全局 Xcode 设置。

本地旧发布记录 `/private/tmp/pink-house-testflight-batches-20261016/release-status.json` 显示 4.2（2）仅归档成功，上传未获 Apple 接受；用户之后明确暂停 TestFlight 上传。此前的开发版安装不会自动更新 TestFlight 发行渠道。

## 客户端根因与修复

继续查刷新逻辑发现 `ShopCatalogCloudSyncService.syncOnce` 只比较 `installedReleaseSeq`。Development 与 Production 各自计数，可能出现序号相同、根清单与商品顺序不同的情况。即使用户强制刷新，已有远端层也会被判断为无需下载，仍保留旧的同类型顺序。

新增回归先在旧实现运行并失败：第二次收到相同序号、不同内容时，数据包下载次数仍为 1，商品顺序仍为 `[a, b]` 而非 `[b, a]`。这证明该缓存缺陷真实存在；由于未读取当前测试手机缓存，不能断言它就是该手机此次表现的唯一原因。

- `ShopCatalogSyncControl` 增加可空的 `installedRootIndexHash`，兼容已有控制文件；旧文件缺少字段时补做内容核验。
- 只有发布序号、根摘要同时一致，且内存已安装远端层时才复用不变状态。
- 缓存验证、下载并安装新包、空分区处理均保存实际安装根摘要；失败仍保留原有可用内容。
- 若旧缓存的数据包摘要仍正确，只核验根与包，不重复下载。未清空用户衣橱、草稿或业务缓存来规避问题。

## 验证

Xcode 27.0 / 27A266a；命令显式设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
xcodebuild test -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogCloudSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogProductOrderingTests \
  -resultBundlePath /private/tmp/pink-house-sort-client-cache-final-20261017.xcresult
```

最终 48 项全部通过。覆盖相同序号不同内容必须更新、旧控制文件无根摘要的兼容迁移、内容不变不重复下载、远端排序压过旧本机覆盖、真实系列菜单按运营顺序渲染。测试使用隔离存储与替代远端读取器；不等同于当前 TestFlight 真机安装与视觉验收。

日志：`/private/tmp/pink-house-sort-client-cache-final-20261017.log`；旧实现失败复现：`/private/tmp/pink-house-sort-client-cache-before-20261017.xcresult`。

## 本地归档与分发状态

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild archive \
  -project ItemManager.xcodeproj -scheme ItemManager -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -archivePath '/Users/sangyu/Library/Developer/Xcode/Archives/2026-10-17/ItemManager 4.2-3 Product Order Fix.xcarchive' \
  -jobs 3 CURRENT_PROJECT_VERSION=3 MARKETING_VERSION=4.2
```

Release 归档成功（退出 0，`ARCHIVE SUCCEEDED`）。主 App `bugod2.ItemManager` 与 Widget `bugod2.ItemManager.Widget` 均为 4.2（3）；团队 `833FJ74GS2`，CloudKit 环境为 Production，深层严格签名检查通过，不含 XCTest 插件。归档仍为开发签名（`get-task-allow=true`），后续 App Store Connect 分发导出需要重新签名，不能把当前归档直接当作分发 IPA。

主 App CDHash 为 `24168388a3b41e1de2f11657013b051bf77419dc`，可执行文件 SHA-256 为 `cb389a90b7d4cf18d0c205c915a7c96ec4302e89665ce4679a8c966af572ccaa`。构建日志 `/private/tmp/pink-house-sort-client-archive-20261017.log`；签名、版本、环境及关键源码摘要记录 `/private/tmp/pink-house-sort-client-release-20261017/archive-verification.json`；分发状态 `/private/tmp/pink-house-sort-client-release-20261017/release-status.json`。`git diff --check` 通过。保留既有工作区改动，没有提交、推送或覆盖手机安装。

4.2（3）替代此前未上传成功的 4.2（2）本地归档作为后续分发候选。TestFlight 上传继续暂停，没有执行分发导出、上传或修改系统代理。恢复必须取得用户明确授权；归档不代表 Apple 已接收、已处理或测试用户已安装。恢复分发后，需确认此构建在 TestFlight 可用，再由当前测试手机安装并复核双子星同类型内顺序。
