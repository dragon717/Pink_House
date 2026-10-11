# 店家目录安全同步与丢失商品恢复（2026-10-11）

## 问题与证据

- Mac 日志 `20261011-131110-pull-catalog-B9261BCE.log` 实际成功读取 Production seq 9，但店家、系列、商品全部为零。这不是网络拉取失败。
- Production 的包有两条销售记录，其中 `ev-ops-AE338C37-stock-e4a680ac832cfa60` 指向缺失且未下架的 `prod-ops-74790EED`。
- iPad TestFlight 草稿 `AE338C37-2A5B-422E-8249-898BFC049930` 保留「1304 / pad / 粉色op」、面料「赛博面料」、现货价 888 CNY、原商品 ID 与本机图片。用户确认补录后点击过「以线上为准对齐本机」。
- 旧对齐函数移除线上没有的本机实体，只留下销售记录；旧校验在父集合为空时跳过关联检查，导致损坏空目录仍显示发布成功。

## 当前流程

运营录入或编辑 → 本机入库 → 点击「同步更新并上传」。入口自动完成：

1. 用普通读取路径拉发布头、根清单、目录包，验证协议和摘要。仅准确确认发布头不存在才视为空库；网络失败停止且保留本机内容。
2. 以同环境的上次编辑基线做三方合并。保留两端独有实体与本机新增、修改；远端没有某商品不代表删除。明确删除记录级联生效，销售历史保留。
3. 有同字段冲突时显示选择。选择仅对当时的本机内容与远端摘要有效，任一侧变化必须重新核对。
4. 覆盖层只保存本机相对远端的新增与修改；远端相同实体不保存副本，避免挡住后续线上更新。基线保存远端原文而非未上传的合并结果，版本与正文原子保存。
5. 没有修改直接完成同步；有修改上传内容寻址的缺失图片、不可变目录包，再核对基线并条件切换发布头。保留其他分片、撤回信息与根清单附加元数据。
6. 普通读取路径回读正文与图片，成功后显示已发布。明确下架商品的销售历史保留在本机和旧不可变包，公共包只带能关联商品的事件，兼容当前 TestFlight 的旧读取器。上传任务带店家、系列、商品名称。

公共协议采用整包快照，上传前将本机增量叠加到最新远端；不会上传清空后的本机目录。

「店家上新」支持下拉刷新，包括空列表与加载失败状态。批次添加单品继承当前整批归属，包含尚未保存的输入；不覆盖已有单品的单独归属。

## 删除的旧代码

移除 iOS 查看差异/对齐 UI 与状态、Store 删除式对齐/自证函数、独立暂存图片入口和单独失败项重试分支（重试统一重新同步）、Mac 未使用的旧对齐/预览函数、共享包 aligned/align/localOnlyRemainder/isAligned 及旧删除式测试。随后删除共享包整套旧对齐报告及 Mac 无调用的采用告知；Mac 合并统计直接复用现有 ChangeSetCalculator，不留只由旧测试调用的接口。

## 恢复与验证

恢复入口要求保留草稿有回执、商品确实缺失且未明确下架。复用原商品 ID 与确定性销售记录 ID；有销售记录不再被误判为商品实体已存在。

离线导出测试 `ShopCatalogPublishRecoveryTests/testExportRecoveredCatalogForExplicitOfflineFixture` 仅在显式给出隔离输入/输出路径和草稿 ID 时执行，不访问云端、不写真实 iPad 资料。

正式工具 `tools/time_hall/publication/recover_published_product.py` 先冻结恢复产物与原发布头，再复校验、核对版本、通过现有条件发布器发布，并独立回读目录与图片。恢复范围限定为原商品一件及关联实体；原实体、销售历史与删除记录不允许改变。诊断与发布证据在 `output/catalog-sync-diagnosis-20261011/`。

构建、针对性回归与恢复发布的最终结果见下方执行记录。新入口、下拉刷新与批次继承需要包含本次代码的下一版 TestFlight；现有 TestFlight 不会因本地源码修改自动更新。

SDK 27 构建在 iOS 26.3 模拟器的同步测试中暴露主 actor 对象析构回部署崩溃（`swift_task_deinitOnExecutorMainActorBackDeploy`）。无收尾业务的目录 Store、上传 Store 与 Publisher 明确采用 `nonisolated deinit`，避免释放对象时进入此路径。首次失败结果保留在诊断目录，修复后重新验证。

## 最终执行记录

### 实际恢复与交叉读取

- 2026-10-11 14:44 左右，受控条件发布将 Production seq 9 推进到 seq 10；未修改 Development。
- 原商品 ID `prod-ops-74790EED`；店家 `1304`、系列按草稿保留 `pad`、商品 `粉色op`、款式 `op`、面料 `赛博面料`、现货 888 CNY。草稿原分类为「其他」，未擅自改分类。
- 新根清单 SHA-256：`36c3ebac7e7f7097c12f4f50c8a48c1c2e1a302215918681c20196de5a2e5526`。
- 公共包 SHA-256：`e47545e88a0ea9dc677d33ef71689f902be24723dbfbf5fe4133a25282d481dd`。
- 原图 SHA-256：`5b56e7211afe0d52959ce50d27123a6accca62dcc2464fc8e50880106953ab8c`，回读原图字节与 iPad 原文件一致。
- 只恢复一件商品和所需关联实体；已删除旧商品未复活，原三组下架记录保持不变。原两条销售历史完整保留于 `production-recovery-verified/recovered-full-catalog.json` 和旧不可变包；公共包保留此商品的一条原现货记录，兼容旧 TestFlight。
- 恢复前新版 Mac 桥接器明确拒绝 seq 9 的悬空销售记录，退出 3，未生成可导入基线；恢复后独立 `pull-catalog` 退出 0，返回 confirmed seq 10、店家 1 / 系列 1 / 商品 1、规格 / 图片 / 款式档案各 1。
- 冻结审计、条件发布回执与独立云端回读结果：`output/catalog-sync-diagnosis-20261011/production-recovery-verified/{audit,publish-receipt,verified}.json`。恢复准备第一次被既有 Python 门禁拦截（缺 checkedThrough），已补齐恢复工具和原生发布器，使用新目录重新冻结后发布；失败记录保留。

恢复命令（准备不写云端；仅本次指定商品）：

```sh
tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/recover_published_product.py --environment production --output output/catalog-sync-diagnosis-20261011/production-recovery-verified --catalog output/catalog-sync-diagnosis-20261011/recovered-catalog.json --drafts output/catalog-sync-diagnosis-20261011/ipad/shop-catalog-drafts.json --draft-id AE338C37-2A5B-422E-8249-898BFC049930 --images output/catalog-sync-diagnosis-20261011/ipad
tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/recover_published_product.py --environment production --output output/catalog-sync-diagnosis-20261011/production-recovery-verified --apply
tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/ops_publish_bridge.py --mode pull-catalog --request output/catalog-sync-diagnosis-20261011/independent-pull-after-request.json --quiet
```

### 构建与回归

环境：Xcode 27.0 (`27A266a`)，显式 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`；iPhone 17 Pro / iOS 26.3，UDID `826F5E71-D2BC-4E76-A8C5-4251C526A5D4`。不改全局 xcode-select。

| 验证 | 最终结果 | 日志 / 结果 |
|---|---|---|
| ItemManager Debug build-for-testing（清理后） | 退出 0 | `ios26-cleanup-build.log` |
| iOS 目录相关 9 组测试 | 96 项，0 失败 | `catalog-sync-tests-final.log` / `.xcresult` |
| SharedCatalog（删旧报告与测试后） | 202 项，0 失败 | `shared-catalog-cleanup.log` |
| PinkHouseOpsCore（删无调用采用接口后） | 84 项，0 失败 | `mac-core-cleanup.log` |
| PinkHouseOps Debug macOS build（清理后） | 退出 0 | `mac-cleanup-final-build.log` |
| Python 安全同步回归 | 19 项，0 失败 | `python-regression.log` |
| 恢复范围守卫 | 6 项通过：正常恢复允许；改价、改面料、改图、明确下架、无关新增均拒绝 | 本地范围核验 |
| 源码/文案残留与差分格式 | 旧删除式接口/入口检索无结果，diff --check 通过 | 本次最终检索 |

构建命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme ItemManager -configuration Debug -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' -derivedDataPath build/DDSeries -clonedSourcePackagesDirPath build/SourcePackages -jobs 2 OTHER_SWIFT_FLAGS='$(inherited) -j2' -quiet build-for-testing
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme PinkHouseOps -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DDOps -clonedSourcePackagesDirPath build/SourcePackages -jobs 2 -quiet build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SharedCatalog -j 2
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PinkHouseOps -j 2
tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/selftest_ops_sync.py
```

原生回归使用生成的 xctestrun 副本，仅对单测目标指定离线草稿输入、独立输出和草稿 ID；随后 `test-without-building -parallel-testing-enabled NO`，只选 CloudSync、BatchAttribution、PublishRecovery、OpsPublisher、OpsMediaStaging、UploadJob、OpsPublishScope、AssetMediaKey、Gzip。完整命令保存在测试日志首行。未启用 Stage C/D 真实写云测试。

初次运行存在对象析构崩溃，修复后第二次仅剩测试共享单例草稿缓存污染；测试 setup 重新加载隔离空目录后，最后 96 项全部通过。原失败日志与 xcresult 保留，未将失败测试隐藏或跳过。最终构建后重新安装并启动同一模拟器 App（进程 3398），首屏可正常渲染；模拟器没有可启动的 Simulator GUI，未据此宣称下拉手势已做 UI 验收。

### 设备与交付边界

iPad 当前安装的 TestFlight 未被覆盖安装。恢复发布后首次启动尝试被系统以锁屏拒绝，最初只读控制文件为 seq 9。用户随后解锁打开「店家上新」并确认拉到商品；2026-10-11 17:44（北京时间）的只读控制状态为 seq 10。复制其缓存包并核对 SHA-256，与 Production / Mac 独立回读的包完全一致；1304 / pad / 粉色op、赛博面料、888 CNY、原商品 ID 均在真机缓存中。用户也确认 iPhone 已拉到；该 iPhone 结论来自用户反馈，未宣称独立读过它的缓存。证据：`output/catalog-sync-diagnosis-20261011/ipad/{sync-control-confirmed,device-confirmation}.json` 与 `confirmed-seq10-pack.json.gz`。此时 iPad 尚无对应远端图片缓存文件，因此不将此次目录核验表述为图片渲染验收；服务器原图回读验证已通过。

线上数据恢复和 Mac / iPad 读取已闭环。手势刷新、新同步入口、上传名称与批次继承仍需要下一版 TestFlight。本次未分发新 TestFlight、未覆盖任何真实设备的运营草稿。功能验收后，按用户要求单独提交本次修复，未推送 Git。
