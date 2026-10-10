# 系列上新款式复制（2026-10-10）

需求：S3 左侧款式条目提供复制选项，所有填写内容保持原样，然后在副本上修改。

## 行为

- 每个左侧款式卡片右侧增加复制图标（悬停说明「复制款式（保留全部填写内容）」）；右键菜单同样有「复制款式」。
- 副本插在原款式下一行，并选中副本进入右侧编辑区。保留类型、款式名称、区分尺码开关、尺码单位/列/行/原图、预约价/定金/尾款/现货价原文、币种、颜色顺序/名称/图片与可售尺码。
- 名称不追加「副本」后缀；不重新解析不完整输入，不重算已填写尾款。图片引用复用已上传素材，不额外上传图像字节。
- 新款式与每个颜色生成独立身份，清空对应的已提交商品 ID 和上次提交结果；因此副本提交为新商品，不会更新原款式的商品、价格、规格。
- 编辑器以款式身份隔离状态，切到副本时不会因旧编辑器的身份或颜色数量变化而自动补满原来未勾选的尺码。
- 复制通过 `duplicateSeriesTypeEntry(id:)` 编排，原条目及副本一起保存到当前向导草稿 JSON 后才更新内存列表。保存失败恢复原 JSON、保留原输入，不插入未保存的副本。不触发商品提交或云端发布。

## 验证

```sh
xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pink-house-ops-save-logo-build build-for-testing
python3 tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /tmp/pink-house-ops-save-logo-build \
  --snapshot-dir /tmp/pink-house-style-copy-after
```

结果：`TEST BUILD SUCCEEDED`；48 项实际 App 离线 XCTest 通过，0 失败。
日志：`/tmp/pink-house-style-copy-build.log`、`/tmp/pink-house-style-copy-tests.log`。

新增 4 项测试覆盖：全字段原文保持、重开后的持久化、独立款式/颜色身份；副本编辑不改原款式；已提交款式复制后再次提交产生独立商品；保存失败完整保留原 JSON 与输入；无效文本也能复制、重复复制无身份碰撞、未知条目不改数据。

初次测试的两个完整草稿比较因既有 ISO8601 日期只保存到秒而出现默认日期亚秒误差，测试按原有 JSON 编码精度比较完整恢复结果；生产日期存储格式没有改变。

已查看原生 SwiftUI 截图 `/tmp/pink-house-style-copy-after/style-copy-option.png`：复制图标清晰可见，复制后出现两条同名 OP 款式，原来的尺码文本保持。截图使用临时数据库，并通过服务调用产生副本；没有对用户真实草稿点击复制。

验证边界：没有真实云端发布，也未替换或重启用户正在运行的运营 App。新入口需要运行本次编译版本。
