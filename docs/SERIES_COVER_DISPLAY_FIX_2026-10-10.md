# 系列封面两端展示根因修复（2026-10-10）

用户反馈：运营端「店家与系列」列表没有显示已上传的系列封面，少女心愿 App 中也不显示。

## 根因与修改

1. Mac `OpsCatalogEditorView.seriesRow` 只绘制系列名称、状态和商品数量，没有图片视图。现在增加 44 点封面缩略图，保留原选择、筛选和编辑菜单。
2. Mac 上新保存的 `CatalogSeries.cover` 是 `CatalogAsset.id`。发布端会改写资源表里的本机路径为 THMedia 地址，保留该资源 ID，这是合法协议。App 的系列卡把这个 ID 直接传给图片视图；旧图片视图直接按 Bundle/local/HTTP/thmedia 地址解析，没有查询资源表，因而找不到图片。
3. 新增共享 `ShopCatalogImageSource`，先解析资源 ID，再保留 original/preview/thumbnail 引用与 canonical mediaKey；直接文件名、Bundle、local、HTTP 和旧 thmedia 引用继续兼容。空原图也可使用 preview/thumbnail 或 canonical 媒体键。
4. App 统一图片视图观察目录 Store，以解析后的图片来源作为加载标识。同一个资源 ID 更换图片或媒体键时重新加载，并隔离旧下载结果及旧失败状态，避免自动刷新目录后仍显示旧封面。
5. Mac 列表、上新封面预览及系列配置封面预览使用相同的资源解析入口；已下载的 THMedia 字节可在本机 staging 中显示。

没有更改目录字段、草稿存储格式、封面归属、发售阶段或发布协议；既有有效封面引用无需重新填写。

## 验证

共享包：

```sh
swift test --package-path Packages/SharedCatalog
```

结果：220 项通过，0 失败。日志 `/tmp/pink-house-series-cover-shared-tests.log`。
新增覆盖资源 ID、直接引用、空地址 canonical 媒体、兼容 fallback、多地址去重，以及同 ID 图片变化后的加载标识变化。

Mac：

```sh
xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pink-house-ops-save-logo-build build-for-testing
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-ops-save-logo-build \
  --snapshot-dir /tmp/pink-house-series-cover-after
```

结果：`TEST BUILD SUCCEEDED`，44 项回归通过。日志 `/tmp/pink-house-series-cover-mac-build.log`、`/tmp/pink-house-series-cover-mac-tests.log`。
新增验证：上传封面 → 提交系列 → 删除原始输入文件 → 重开草稿 → 封面仍可解码 → 交接整包包含对应图像字节与资源 ID；直接引用、已下载 THMedia、预览兜底及 canonical-only 图片可读取。

已检查原生 SwiftUI 截图 `/tmp/pink-house-series-cover-after/series-list-with-cover.png`：系列卡左侧显示临时上传的粉色图片，与店家图片一致，不再只有文字。

App（本机 Xcode 27.0，iPhone 17 Pro / iOS 26.3）：

```sh
xcodebuild -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /tmp/pink-house-auto-refresh-build -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ShopCatalogCoverImageTests \
  -only-testing:ItemManagerTests/ShopCatalogChartPresentationTests test
```

结果：`TEST SUCCEEDED`，21 项通过，0 失败（3 项封面测试、18 项既有图表展示测试）。日志 `/tmp/pink-house-series-cover-ios-tests.log`。
结果包 `/tmp/pink-house-auto-refresh-build/Logs/Test/Test-ItemManager-2026.10.10_22-35-47-+0800.xcresult`。
封面测试使用真实 `ShopCatalogAssetImage` 和 `ImageRenderer` 渲染上传红图，校验输出像素为红色而非灰色占位；同时验证安装新目录后同一封面 ID 解析到新媒体键，以及 canonical-only / Bundle 旧格式兼容。

验证边界：使用临时 Mac 数据库和模拟器测试图片，没有读取或修改用户运营沙盒、没有真实云端发布及真机 THMedia 下载验收。用户当前运行的 Mac App 和真机 App 未替换，新行为需要对应的新编译版本。截图是临时数据的原生界面，不是用户当前线上目录。
