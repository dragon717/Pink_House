# 手机入橱看不到已发布团次：旧运营副本覆盖（2026-10-16）

## 现场证据

用户截图：Mac“小狗仪仗队”已配置“先行团 / 非圣诞先行团”，手机“红色托胸贴布绣Jsk → 加入少女衣橱”却直接进入确认页，没有购买批次。

已通过 Xcode 的受支持 `devicectl` 通道，只读核对当前连接 iPhone16 Pro（iOS26.5）中 `bugod2.ItemManager` 的目录控制、公开缓存包和运营覆盖层。应用是开发安装，4.2（1）。

- 真机已安装 Development **23**，最近检查为 `2026-10-16T03:02:33Z`。不能归因为“没有下拉刷新”。
- 公开缓存 gzip 包的 SHA-256 为 `7ded64b60df37282c1296d09af5c2ed1047040975b5ce0e94176913a595f06c2`，与手机控制文件及此前服务器独立回读完全一致。
- 包中 `series-ops-19AAE8DD.reservationBatches` 有两团，名称、稳定ID及“一个月”结束描述齐全。
- 本机 `shop-catalog-override.json` 中同一系列保留旧整份副本，`reservationBatches` 缺失，只有合写的旧尾款文字。本机还有图片、价格表等编辑，不能直接删覆盖层。
- 商品 `prod-ops-C921A336` 确实引用此系列。根因是 Store 的 `base → remote → overlay` 按整实体覆盖；手机即使已同步23，入橱读取 `store.series` 仍得到没有团次的旧副本。

上述资料和最小结论在 `/private/tmp/pink-house-phone-batch-entry-20261016/`：`diagnosis.json`、`phone-sync-control.json`、`phone-installed-pack.json.gz`、`phone-catalog-overlay.json`。未修改手机目录文件，未读取衣橱数据库。尝试读取运营发布基线时文件不存在；修复不依赖未知基线。

此前云端两环境回读正确，但未覆盖手机本机层叠加；因此不能把“云端已发布”当成“手机入橱已看到团次”。本记录补充并取代此前对该手机原因尚未确定的边界描述。

## 修复口径

新增 `ShopCatalogStore.seriesForPurchase(id:)`，用户购买档期统一读取已安装的公开系列：发售阶段、预约起止、尾款类型 / 原文 / 起止和预约团次。不会回写本机覆盖层。

- 本机编辑查询 `series(id:)` 保持原规则；系列名、封面、描述、价格表等本机编辑保留。
- 已有公开系列时，公开档期的空值也生效，不能用旧副本恢复已撤销团次或旧尾款日。
- 没有公开系列的纯本机内容继续使用原查询，不要求联网才可使用。
- 墓碑和归档仍先于购买查询，已下架系列不会从公开层绕过删除保护。
- 多选 / 单选入橱页、草稿生成、最终落库校验、团次ID保存与后续尾款校准均使用同一购买读取入口，避免只修界面、保存时仍用旧副本。
- 系列选购页把自己的 Store 传入入橱页，测试和实际入口使用同一份来源，不偷偷改用全局实例。

没有重复发布两端公共目录，没有清空覆盖层、替换用户衣物或修改金额。

## 验证入口

- `ShopCatalogCloudSyncTests`：旧副本缺少团次但公开系列有两团；保留本机字段及覆盖层原始字节；线上更名 / 移除团次；纯本机回退；墓碑和归档。
- `ShopCatalogWardrobeBalanceSyncTests`：复现本机无团次；未选公开团次时草稿和落库都拒绝；选择后正确保存ID及尾款窗口；公开时长更新后校准原记录。
- `ShopCatalogPurchaseBatchSelectionTests.testActualMergeEntryRendersPublishedGroupsOverStaleLocalSeries`：实际 `ShopCatalogWardrobeMergeView`（与截图入口相同）注入有旧副本的 Store，渲染两团选择页；单纯选择不产生衣物。

Xcode27.0（27A266a），全部命令显式使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，不改变全局选择。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogCloudSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogPurchaseBatchSelectionTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeBalanceSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -resultBundlePath /private/tmp/pink-house-phone-batch-entry-20261016/PhoneBatchEntry.xcresult
```

**104项通过，0失败，TEST SUCCEEDED**：公开同步42、购买批次10、尾款同步18、既有入橱记账34。包含本次新增5项；截图由结果包导出至 `screenshots/`。完整入橱入口截图 `AC15FB48-1104-43E2-8E85-3D3062B3FDA5.png` 已目视核对，显示“小狗仪仗队”、两团、各自开始 / 结束日期，未选择时继续按钮不可用。

同目标普通模拟器构建通过（上述命令改用 `build`，移除测试筛选、测试并行与结果包），日志 `simulator-normal-build.log`。已安装到同一目标并重启 `bugod2.ItemManager`。

真机构建使用同一项目 / scheme / 包缓存，`build -configuration Debug -destination 'platform=iOS,id=00008140-000C289E1862201C' -derivedDataPath /private/tmp/pink-house-phone-batch-entry-device -jobs 3`；日志 `phone-build.log`。不修改版本、签名团队或 CloudKit 环境。

真机普通构建 **BUILD SUCCEEDED**，严格签名核验通过，团队仍为833FJ74GS2，get-task-allow为true，描述文件包含目标手机。Debug沿用仓库原本未显式设置CloudKit环境键的权限文件，没有改为Production；最初校验脚本错误地要求该键必须显式为Development，随后核对源权限文件、签名及描述文件后修正，结果记于 `phone-build-verification.json`。

`devicectl device install app` **成功**，安装回执 `phone-install.json`，新应用安装标识 `20D4F3CE-0430-4423-A787-F534D546B122`。首次普通启动成功，PID2325，回执 `phone-launch.json`。安装后再次只读复制运营覆盖层，原始字节与安装前完全相同（SHA-256 `8bfd3f7a8f7da6796c96674134773bd133acd5aa02b96387e97ff3c2ac3c920b`），没有为绕过问题改手机JSON。

后续运行时核对尚未完成：LLDB未取得可检查的运行实例，后续启动明确被手机系统以 **Locked / 设备未解锁** 拒绝（`phone-launch-console.log`）。已请用户解锁并打开App后继续核对；未将首次launch回执写成完整业务验收。

用户确认解锁并打开后，`devicectl` 已只读确认运行中新进程PID2351，应用路径是新安装标识 `20D4F3CE-0430-4423-A787-F534D546B122`（`phone-processes-unlocked.json`）。LLDB后续因进程未处于可检查状态 / 再次锁屏未取得团次值，没有把失败的表达式当作读取成功。修复已经安装，最后页面核对已请用户从“小狗仪仗队”重新加入，确认是否先显示两团。

**真机页面确认完成：用户重新执行“小狗仪仗队 → 选择商品 → 加入衣橱”后，明确反馈“已显示两个团次”。** 该结论来自用户现场确认；实际入口的独立渲染与落库 / 同步逻辑另有上述104项测试支持。未把团次出现视为用户已完成最终入橱或提醒实际送达。

Device Hub 另实际返回：iOS26.5不支持该Mac的屏幕共享（需要iOS27）；不把模拟器截图、安装成功或目录回读写成真机点击入橱已验收。本轮未上传TestFlight / App Store，未执行真实用户衣物入库或发奖励。
