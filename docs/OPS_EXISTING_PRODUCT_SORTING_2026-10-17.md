# 已提交商品排序入口（2026-10-17）

## 使用方式

「少女心愿运营 → 店家与系列 → 选择店家和系列 → 商品栏『调整排序…』」。

左侧调整类型先后，右侧调整该类型内的商品。两侧都支持原生拖动及上下箭头。点击「保存并同步」后保存顺序，自动更新开发环境和用户环境中已上架商品；无需回到系列录入向导或重新提交整份系列。取消只放弃本次排序。

排序面板读取整个系列的未归档商品，不随主页面搜索结果缩小保存范围。按稳定商品 ID 定位，商品图片、价格、名称与规格不改；已归档商品和其他系列不参与改序。面板打开后商品列表、分类或顺序发生变化时拒绝旧快照保存，提示重新打开。

## 实现边界

- `OpsProductOrderSheet` 提供类型与商品两列工作副本。只有服务保存成功才关闭，失败保留当前调整。
- `saveProductDisplayOrder` 校验草稿身份、完整商品集合与原排序快照，写入已有 `displayOrder`。落盘失败恢复原目录、版本与同步意图。
- `OpsSeriesConfigUpdate.productOrder` 冻结商品 ID → 顺序映射；与团次/封面/价格表的保存合并时保留最近排序，复用原有分环境发布、回读确认与未知结果查询。
- 对目标环境中已有、未下架且归属相符的商品，只修改排序字段。2026-10-17 后续实机核对发现另一环境可能漏发商品，现增加已确认公共快照：补齐其他环境已发布的相关商品与必要资料，并逐 ID 核对排序；本机未发布的新草稿不因排序上线，下架内容不自动恢复，同 ID 商品换系列时明确阻断。详见 [排序同步漏项根因修复](OPS_PRODUCT_ORDER_SYNC_ROOT_FIX_2026-10-17.md)。
- 「店家与系列」商品列表使用与 App 相同的 `CatalogProductOrdering`，保存后直接显示新顺序。

## 验证

Xcode 27.0（27A266a），所有命令显式 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

```sh
swift test --package-path Packages/PinkHouseOps \
  --filter 'OpsSeriesConfigUpdateTests|OpsCatalogMergeBaselineTests|OpsCatalogEditSyncTests'
xcodebuild build-for-testing -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
SPM_CACHE=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  tools/xcode/build_mac_release.sh
```

105 项通过、0 失败：工作区 79，运营核心 26。覆盖表单已清空后的现有商品重排、类型和款式同时变序、重开恢复、图片/价格/规格不变、磁盘失败回滚、过期或不完整 ID 列表拒绝、自动排队、跨环境范围限定、合并后保留排序以及排序确认后的真实并发变化合并。测试使用内存库与替代发布闭包，不写真实线上数据。

Release 构建通过，严格签名和新旧 entitlement 比较通过，旧 App 保留备份，已安装并重新启动 `/Applications/少女心愿运营.app`。安装记录：`/private/tmp/pink-house-postpublish-order-mac-install-20261017.json`。

实际电脑控制确认「店家与系列」新增入口，并打开「小狗仪仗队」的真实排序面板：左列 8 种类型，右列显示已提交 JSK 商品及箭头，保存/取消按钮完整可见。运行中的用户随后关闭了面板；本轮没有点保存或改变实际商品顺序。更新前后草稿均为第 3564 版、4 店家、14 系列、431 商品、617 图片。保存与同步由隔离工作区/核心测试验证；不以真实发布作为测试。

日志：`/private/tmp/pink-house-postpublish-order-{final-core-tests,workspace-tests,mac-final-build,mac-release}-20261017.log`，`git diff --check` 通过。

本次只更新 Mac；少女心愿 App 已在上一轮接入此排序字段。TestFlight 上传继续暂停。
