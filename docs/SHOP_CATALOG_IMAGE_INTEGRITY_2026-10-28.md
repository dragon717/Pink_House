# 时光馆图片全量检查与入橱根因修复（2026-10-28）

## 结论与范围

BB 帽的图没有丢失。`product-6a211b65` 的粉、黄、蓝三色明确绑定同一张合照，旧入橱代码却把任何绑定其它颜色的图片排除，连所选颜色自己的绑定也一起排除了，空选图结果再被误报成下载失败。

两个环境各有 7 件商品、16 种配色选择受此问题影响：BB帽、眼罩发带，以及 5 件段段 JSK 组合商品。修复作用于共用规则，未更换或删除商品照片。

| 目标 | 发布号 | 商品 | 资源记录 | 唯一云图片 | 图片引用 | 商品及配色选图 | 缺失 / 摘要错误 / 解码失败 / 空选图 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Production | 24 | 431 | 617 | 770 | 3,739 | 981 | 全部 0 |
| Development | 26 | 436 | 587 | 740 | 3,629 | 988 | 全部 0 |

逐张检查了下载可用性、SHA-256、类型与大小、ImageIO 完整性及所有帧的实际像素解码。覆盖原图、预览图、缩略图、店铺图、系列图、价格表、尺码表，以及商品和规格引用；不同环境的计数分别计算，不能相加称为全局去重图片数。

Bundle 商店目录为空；`Resources/ShopCatalog/images/` 另有 10 个历史文件，共用同一份图片字节，完整解码通过。它们没有在当前 Bundle 目录中注册为商品。

检查期间只读公共库。Production 下载曾遇到 HTTP 503，保留已成功文件并重试剩余 426 张，最终 770 张全部完成。结束时回读发布头与开始快照一致：

- Production：`eb5b46787e886cc92d7a5c8c4f2c4735b39345b9a94250a51de6440674d2c301`。
- Development：`39fde747df1dab441b0be8871acc2421b85a3502d610bdd6952c5dc646044f96`。

逐图片记录保存在 [Production](validation/time_hall_images_2026-10-28/production.json) 与 [Development](validation/time_hall_images_2026-10-28/development.json)。未发布新的云端目录，也未上传 App；客户端修复须随新版 App 分发后生效。

## 防止复发的实现

1. `ShopCatalogProductImages` 统一选图：所选配色的明确绑定优先，共享合照保留；仅绑定其它配色的图片仍排除。按 canonical 媒体键去重，兼容不同资源 ID 指向相同图片。
2. `ShopCatalogImageSource.mediaKeys` 统一候选顺序：canonical 原图、其它原图引用、预览图、缩略图。展示、保存相册和入橱均能尝试其它云端候选，避免 THMedia 候选被当作不可解析 URL 跳过。
3. 下载前后均核对缓存：首次使用校验摘要及解码，坏缓存移除后重下；已验证且文件大小和修改时间未变的缓存复用。校验失败的下载不进入缓存。
4. iOS 上传暂存与 Mac 发布前检查使用同一份 `rejectionReason`，实际解码，不再仅凭扩展名、文件存在或格式头放行。
5. Swift 与 Python 发布链路都遍历商品、规格中的直接 local/thmedia 引用，上传并改写直接引用，同时保留资源 ID。Python 门禁额外拦截缺失的明确资源 ID，避免漏检商品与规格字段。
6. 选图配置为空与真正下载失败使用不同报错；任一必要图片保存失败仍回滚整次入橱，不能保存空图或半批记录，不能提前发成功反馈或奖励。

网络暂时中断仍可能发生：界面保留明确重试入口，并按业务事务回滚。上述全量检查针对发布快照及图片完整性，不包含逐张人工判断商品照片是否拍摄正确、颜色标注是否准确。

## 可重复检查入口

只读使用既有 `ops_publish_bridge.py --mode pull-catalog` 获取目标环境目录，再用 `--mode fetch-media` 下载目录全部 `thmedia:` 摘要与 `assets.mediaKey`。请求文件格式见桥接器文件头；对网络失败仅重试 manifest 的 `pending`，保留已下载文件。不要把远端记录存在或 HEAD 请求成功当作实际解码通过。

下载完整后执行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift run --package-path Packages/SharedCatalog CatalogImageAudit \
  /absolute/path/shop-catalog.json /absolute/path/media /absolute/path/image-audit.json
```

审计器与客户端共用选图、来源解析和字节校验。成功退出码为 0；缺图、坏图、空选图、未核对的非受控图片引用返回 1；输入或执行错误返回 2。它只读输入，并输出含每张图片摘要、尺寸、字节数、失败原因的 JSON。缺图反例已核验返回 1。

## 构建与回归记录

本机 Xcode 27.0（27A266a），显式使用 `/Applications/Xcode.app/Contents/Developer`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SharedCatalog
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PinkHouseOps
tools/time_hall/publication/.venv/bin/python -m unittest discover -s tools/time_hall/publication -p 'selftest_image_references.py'
tools/time_hall/publication/.venv/bin/python -m unittest discover -s tools/time_hall/publication -p 'selftest_ops_sync.py'
tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/selftest_shop_catalog.py
```

结果：SharedCatalog 257 项通过，PinkHouseOpsCore 147 项通过；Python 新增图片字段 2 项、运营同步 21 项通过，商店发布自测通过。

iOS 最新代码验证命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests \
  -only-testing:ItemManagerTests/ShopCatalogCloudSyncTests \
  -only-testing:ItemManagerTests/ShopCatalogOpsMediaStagingTests test
```

结果：iPhone 17 Pro / iOS 26.3.1，**71 项通过**。覆盖三色共享 BB 帽持久化、其它颜色排除、原图缺失回退、坏缓存重下、错摘要和截断图片拒收、上传阻断及事务回滚。

Mac 构建：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme PinkHouseOps -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/pink-house-image-ops-build \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

结果：**BUILD SUCCEEDED**，未验证签名或实际云端发布。

额外扩大回归时，`ShopCatalogWardrobeIndividualAdditionTests/testRenderMenuAndSinglePageConfirmationContainingAllProducts` 在 iOS 26.3.1 的 UIHosting 截图测试宿主发生 SIGSEGV；单独复跑仍失败。首次扩大测试共 64 项通过、1 项崩溃，不能记为全量测试通过。此项视觉验收单独记录，不以图片单元测试通过替代。

同一截图用例又在 iPhone 18 Pro / iOS 27.0（`FA7332BE-B29E-4879-A139-C68A24314DB1`）执行 `test-without-building`，仍出现宿主异常退出并重启；未将其记为视觉验收通过。截图测试崩溃的根因尚未确定，不能据此断定仅为模拟器问题。
