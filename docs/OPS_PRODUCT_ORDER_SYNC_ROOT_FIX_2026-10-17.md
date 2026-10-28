# 店家与系列排序同步漏项修复（2026-10-17）

> 用户后续截图证明已发布旧客户端仍按原商品数组显示，编号正确并不足以完成验收。后续根因与兼容修复见 [现有 TestFlight 商品数组排序修复](SHOP_CATALOG_LEGACY_ARRAY_ORDER_ROOT_FIX_2026-10-17.md)。该数据修复不依赖恢复 TestFlight 上传。

## 现场与根因

用户反馈在「店家与系列」更新排序后，App 仍未显示新排序。正常诊断导出 `/private/tmp/pink-house-order-sync-before-20261017.json` 显示草稿第 3568 版：双子星 145 件商品、许愿池 13 件商品均已有明确排序；Production 第 23 版的对应商品排序与本机完全一致。Development 第 24 版中双子星仅有 1 件、其余 144 件缺失，许愿池 13 件全部缺失。用户此前明确手机为 Xcode 安装的 Debug 开发版。

用户随后明确本次异常为「仲夏物语 → 双子星」。需要区分设备：此前通过 Xcode 安装开发版的是「💕凤」；本轮重新连接并获授权配对的是「吃胖了想鼠」，用户最终确认它运行 TestFlight 测试版。前述开发环境缺商品是已证实的运营同步缺陷，不能据此认定当前 TestFlight 手机的全部原因已排除。

排序旧逻辑 `OpsSeriesConfigUpdate.applying` 只遍历远端现有商品；缺失商品或系列直接跳过。完成核验又复用同样的 applying 比较，因此整批商品缺失时仍可能得出“无需修改 / 已完成”，不能证明 App 可以取得全部已保存顺序。另外 `saveProductDisplayOrder` 在本机排序未变时直接返回，导致“再次保存”无法补核对之前漏发的排序。

## 修复

- 排序保存冻结 `publishedOrderCatalog`，来源仅为各环境已确认发布的公共快照，保留真实源商品、图片、规格、尺码表与销售记录；本机未发布的名称、图片和价格不会混入。
- 复用已验证的缺失商品关联补齐器，仅补本次排序涉及且其他环境已发布的商品及必要引用。目标环境已有商品只修改排序，不覆盖它的图片、价格或说明。下架标记阻断自动恢复。
- `verifyProductOrders` 明确逐 ID 检查已发布商品是否存在、归属与顺序是否正确。旧任务缺少发布快照时，也不能忽略排序映射中的缺失商品。仅有发布号、回执或部分已有商品的正确顺序不能显示 100%。
- 排序快照随合并保存、失败恢复与冻结任务继续保留；与团次保存合并时不能丢失已发布商品范围。
- 排序未变时再次点击保存仍建立新的双环境核验任务，不增加无意义的编辑版本。
- 新可空迁移标记与已保存排序补核对任务原子持久化；升级后检查旧版已保存排序，避免用户重新拖动。只采用已保存内容，保留当前工作副本和编辑版本。
- 同步阶段保留真实图片上传张数，不把上传张数当作整个任务的完成比例；两个环境逐项回读通过后才显示 100%。

## 验证与交付

Xcode 27.0 / 27A266a；所有构建显式使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
swift test --package-path Packages/PinkHouseOps \
  --filter 'OpsSeriesConfigUpdateTests|OpsCatalogEditorUpdateTests|OpsCatalogEditSyncTests|OpsCatalogMergeBaselineTests|OpsDataSyncProgressTests'
xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
SPM_CACHE=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  MAX_JOBS=2 tools/xcode/build_mac_release.sh
```

最终核心 47 项、工作区 97 项全部通过，包含实际双环境流水线里的缺商品/缺系列补齐、成功回执但读回旧顺序拒绝完成、同一冻结任务查询续传、未发布本机商品隔离、目标价格保留、下架保护、同排序重新保存及带日期快照的持久化恢复。全部测试使用隔离工作区与替代桥接闭包。Debug `build-for-testing`、Release 正式构建及 `git diff --check` 通过。

已正常退出并安装 `/Applications/少女心愿运营.app`，完整签名严格验证、新旧 entitlement 完全一致，最终 CDHash `9285d6e86a0709259757cf3a319d8403bd58ad00`。安装与备份记录 `/private/tmp/pink-house-sort-root-install-20261017.json`。新进程恢复草稿第 3568 版、4 店家 / 14 系列 / 431 商品 / 617 图片，自动开始旧排序补核对任务并完成：Development 第 25 版、Production 第 23 版、进度 100%。最终工具更新重启后仍恢复同一版本与 100% 确认结果，没有重复启动补核对任务。

通过正常保存面板导出 `/private/tmp/pink-house-sort-root-after-20261017.json`，逐件核对双子星 145 件、许愿池 13 件：两个环境均没有缺失 ID，全部 `displayOrder` 与运营已保存排序一致。双子星前几项为娃娃领 OP、娃娃领 OP+胸针（一对）、娃娃领 OP+项链、娃娃领 OP+胸针（一对）+项链，类型与款式顺序沿用共享规则。Development 补齐 157 件已发布商品后为 436 件，保留它原有独有商品；Production 保持 431 件，业务目录与补核对前逐字段完全相同。本机目录与操作前导出快照也逐字段完全相同，编辑版本保持 3568。

验证明细 `/private/tmp/pink-house-sort-root-verification-20261017.json`。Development 根摘要 `ebfe438e1c46096b6df196feb74780c541b663128d79eeac43e45ee712d483d0`；Production 根摘要 `fc0bbc41fb93ae7a2941891d64723795f648574f7e239e5255d87340a5e3d4d3`。

用户随后反馈刷新后仍不一致，并明确是同类型内的款式先后。已授权配对并核对当前设备「吃胖了想鼠」：iPhone Air，iOS 27.2 beta / 24B5110a，开发者模式关闭。用户确认此机为 TestFlight 测试版；实际安装版本号尚未读取，Xcode 27.0 的 DDI 在该系统上个性化失败，Device Hub 也显示不可用，因此没有宣称已目视该机排序或安装新版。此前含排序实现的开发版安装在另一台手机，TestFlight 上传仍受用户暂停指令约束。

继续排查还复现了客户端只比较发布序号、未比较内容摘要的缓存缺陷，已修复并通过 48 项 iOS 测试。客户端修复与本地新归档记录见 [TestFlight 排序客户端修复](SHOP_CATALOG_TESTFLIGHT_ORDER_CLIENT_FIX_2026-10-17.md)。发布数据已核对正确与测试手机已更新是两个独立验收条件；后者仍需在恢复 TestFlight 上传并安装新构建后确认。
