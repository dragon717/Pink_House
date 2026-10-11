# 运营发布后 App 自动刷新（2026-10-10，2026-10-11 更新策略）

用户需求：运营端修改并发布成功后，少女心愿 App 自动读取新目录、刷新页面，用户无需手动刷新。

原有实现只在进入店家浏览页时调用同步，而且已安装目录时 30 分钟内跳过检查；没有发布订阅，也没有全 App 的前台更新调度。

## 实现

- `ShopCatalogReleaseNotifications` 在 `iCloud.bugod2.ItemManager` 公共库维护 `shop-catalog-release-v1` 查询订阅，只监听 `THRelease`。发布器最后条件提交发布头，因此草稿编辑、上传素材不会提前触发目录生效。通知仅设置 `shouldSendContentAvailable`，不增加提示音、角标或用户可见弹窗。
- App 注册远程通知；只有本订阅的 CloudKit 查询通知进入商品同步，其他通知不会触发目录更新。APNs 裁剪了容器字段时，仍可用专用订阅 ID 识别。后台完成回调有 25 秒期限且只调用一次；目录安装仍走原有校验和原子落盘流程。
- 根页面使用 `.task(id: scenePhase)`。启动/回到前台检查，前台每 5 分钟检查一次，离开前台取消定时等待。这覆盖通知延迟、通知丢失、未登录 iCloud 而无法订阅等情况，且不依赖打开某个商品页面。
- 订阅失败不阻断公共库读取；至少间隔 5 分钟重试。iCloud 账户变化后重新确认订阅。
- 浏览页使用 `.task(id: isRoutePageActive && scenePhase == .active)`，每次切回时光馆或该页面回到前台都触发检查，覆盖系统 TabView 缓存页面的情况。页面进入和全局前台调度共用 1 分钟冷却，快速切页不重复请求；手动下拉和发布通知跳过冷却。并发调用等待同一任务，强制检查在同步中到达时合并为后续检查，避免已读到旧发布头的请求吞掉新发布。
- 发布头检查仅取元数据字段，不下载 `rootIndexAsset`。序号没变不下载目录包；序号变化但商店正文摘要相同，也复用已校验包并推进版本号。读取遵守 CloudKit `Retry-After`，失败继续保留已安装目录。
- 首次全局同步先加载 Bundle 基底和已保存的本机运营覆盖层，避免早于浏览页的远端安装短路页面懒加载、遮住未发布编辑。
- 安装新目录后由 `ShopCatalogStore.catalog` 的 `@Published` 通知现有店家、系列、商品列表/详情视图更新。

## 生效边界

需要安装包含本改动的 iOS App。运营发布环境和 App 读取环境必须一致：开发构建与正式分发环境各自使用对应的 CloudKit 数据库。

静默推送的执行由 iOS 调度，后台或用户强制结束 App 时不能承诺即时执行。网络可用且前台同步空闲时，每 5 分钟检查一次；进入店铺或回到前台会检查，1 分钟内已有检查则复用结果。同步中的后续更新排队检查，断网或服务端要求退避时会延迟。参见 [Apple 后台更新说明](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) 和 [CloudKit 查询订阅](https://developer.apple.com/documentation/cloudkit/ckquerysubscription)。

2026-10-11 用户要求自动刷新并授权选择策略，因此由原来的「前台强制每 30 秒轮询、页面 30 分钟冷却」改为「进入页面/回到前台检查，前台每 5 分钟兜底，共享 1 分钟冷却」。先恢复并显示缓存，再后台检查版本；新目录通过既有 Store 合并后自动更新列表。失败和空环境同样合并近期自动请求，但失败只记录本进程的尝试时间，不持久化成检查成功，也不清空原有内容。浏览页保持静默，不新增同步按钮或进度提示。

## 2026-10-10 验证记录

使用本机 Xcode 27.0（27A266a），没有修改全局工具链。

```sh
xcodebuild -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /tmp/pink-house-auto-refresh-build build-for-testing
```

初始测试构建通过，日志 `/tmp/pink-house-auto-refresh-build.log`。

最终代码的 iOS 26.3 回归 **36 项通过**，日志 `/tmp/pink-house-auto-refresh-ios26-final-tests.log`，结果包 `/tmp/pink-house-auto-refresh-build/Logs/Test/Test-ItemManager-2026.10.10_16-03-43-+0800.xcresult`。

```sh
xcodebuild -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /tmp/pink-house-auto-refresh-build -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogAutoRefreshTests \
  -only-testing:ItemManagerTests/ShopCatalogCloudSyncTests test
```

同一最终构建在 iOS 27.0 回归 **36 项通过**，日志 `/tmp/pink-house-auto-refresh-ios27-final-tests.log`，结果包 `/tmp/pink-house-auto-refresh-build/Logs/Test/Test-ItemManager-2026.10.10_16-06-18-+0800.xcresult`。

```sh
xcodebuild -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /tmp/pink-house-auto-refresh-build -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogAutoRefreshTests \
  -only-testing:ItemManagerTests/ShopCatalogCloudSyncTests test-without-building
```

回归覆盖前台立即/周期检查、取消及重新进入前台、订阅失败重试、账户变化、静默订阅配置、CloudKit 通知解析/筛选、元数据检查、服务端退避、发布通知在旧版本下载中到达时安装新版以及 Store 发布变化。

首次 iOS 26.3 回归发现模拟通知中订阅 ID 放在了错误层级，已按实际 CloudKit 解析改到 `ck.qry.sid`。另有四个既有同步 XCTest 在释放 `ShopCatalogStore` 夹具时崩溃，栈位于 `swift_task_deinitOnExecutorMainActorBackDeploy` / `TaskLocal::StopLookupScope`；这些测试改为 async XCTest，提供 Swift task 上下文。目录合并业务逻辑未改。

真机 APNs 投递和正式环境“Mac 发布 → iPhone 自动更新”尚未端到端验证；测试使用隔离缓存、替身发布头和模拟通知，不写真实运营目录。

## 浏览页面静默同步（2026-10-10 补充）

用户要求截图圈出的同步图标和「正在检查云端上新…」状态条不展示给用户。`ShopCatalogBrowseView` 移除右上角手动刷新/进度控件；`ShopCatalogListView` 移除整条同步状态提示（包含同步中、未发布、网络失败和重试按钮），也不再观察同步服务状态。页面仍观察 `ShopCatalogStore`，新目录安装后店家、系列和商品照常自动更新。启动、前台轮询、回到前台检查、静默发布通知和页面打开检查的服务逻辑未改；网络失败保留现有内容和内部诊断日志。目录本身无法加载的不可用页面仍保留。

运营上传区的两处说明同步改为「等待自动同步完成」，不再引导点击已移除的右上角刷新按钮。

本次验证命令：

```sh
xcodebuild -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /tmp/pink-house-auto-refresh-build build

git diff --check
```

结果：iOS 模拟器构建通过（`BUILD SUCCEEDED`），`git diff --check` 通过。构建仍有既有 Swift 6 并发兼容、UIKit 类型扩展和 App/扩展版本号警告，本次修改文件没有新增编译警告。

日志：`/tmp/pink-house-silent-catalog-build.log`。本次只改展示与文案，不新增镜像 UI 测试；自动刷新服务沿用上面的 36 项回归验证。本次未进行真机云端发布或模拟器画面验收，运行新版 iOS App 后展示改动生效。

## 2026-10-11 策略更新验证

本机 Xcode 27.0（27A266a）、iPhone 17 Pro / iOS 26.3 模拟器测试构建及 **47 项回归全部通过**，无失败；`git diff --check` 通过。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /private/tmp/pink-house-auto-refresh-build \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogAutoRefreshTests \
  -only-testing:ItemManagerTests/ShopCatalogCloudSyncTests test

git diff --check
```

最终日志：`/private/tmp/pink-house-shop-auto-refresh-20261011-cache-tests.log`；结果包：`/private/tmp/pink-house-auto-refresh-build/Logs/Test/Test-ItemManager-2026.10.11_22-37-18-+0800.xcresult`。

本次增加或调整的回归覆盖：页面/前台检查共享 1 分钟冷却；无需手动刷新即可安装下一版；失败保持原有状态并在冷却后重试；空环境不因快速切页连续请求，强制刷新仍立即检查；发布号变化但商店正文不变时复用缓存并推进版本。缓存复用仍进行新清单与包的完整校验，拒绝错误序号及分片版本；缓存文件损坏会重新下载修复。

测试使用隔离缓存、替身发布头及注入时钟，没有写真实运营数据。本次未做模拟器画面验收或真机“运营发布 → 自动更新”端到端验收。构建仍有既有 Swift 并发兼容及 App/扩展版本号警告。
