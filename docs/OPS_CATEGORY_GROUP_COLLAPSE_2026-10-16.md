# 运营类型录入分组折叠（2026-10-16）

## 使用行为

「系列上新 → S3 类型录入」左侧款式按 OP、JSK 等类型分组。点击类型标题或箭头收起、展开整组；标题持续显示该类型和款式数量。完成一个类型后，可收起该组继续录入下一类型。

- 分组顺序采用草稿里类型首次出现的顺序，组内保留原有款式顺序；展示分组不改写草稿排列。
- 收起当前正在编辑的类型时，自动选择其他已展开类型的首条款式；全部收起时提示展开类型继续编辑。
- 折叠状态通过 `SceneStorage` 按草稿、店家和系列隔离，返回上一步再进入时保留；不写入商品资料、不改变上传状态。
- 新增同类款式会自动展开所属类型并选中新款式。
- 组内款式继续支持拖拽排序、复制和按独立 ID 删除。拖拽限于同类型，避免落点与分组显示顺序产生歧义。删除及保存规则见 `SHOP_CATALOG_STYLE_ORDER_AND_DELETE_2026-10-16.md`。

实现入口：`PinkHouseOps/Views/OpsSeriesWizardTypeEditor.swift`。

## 构建与回归

本机 Xcode 27.0（27A266a）。以下命令通过：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  tools/testing/run_ops_catalog_editor_regressions.py \
  --derived-data /private/tmp/pink-house-reservation-batches-ops
```

`OpsCatalogEditorPersistenceTests`：65 项通过、0 失败，包含排序、独立删除、复制、草稿保存及失败回退的既有回归。测试使用隔离工作区，未改动真实运营数据。该测试集不自动验证折叠界面；折叠交互通过下述电脑控制检查。

正常运行构建将上述 `build-for-testing` 改为 `build -configuration Debug`，结果为 `BUILD SUCCEEDED`。证据目录：`/private/tmp/pink-house-ops-category-collapse-20261016/`，包含 `build.log`、`regressions.log`、`normal-build.log`、`signing-verification.json`、`installation.json` 和 `ui-verification.json`。

## 本机界面验收及安装

签名严格校验通过，四项 entitlements 与更新前相同。新版已更新并启动于日常运营工具路径：

`/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/Build/Products/Debug/PinkHouseOps.app`

旧应用保留在同目录下 `.codex-category-collapse-20261016-144430/PinkHouseOps.previous.app`，未替换或迁移用户数据目录。

电脑控制在真实窗口的「仲夏物语 → 双子星」执行只读展示交互：

1. 初始显示 OP 36 款、JSK 16 款，右侧编辑 OP「娃娃领OP」。
2. 点击 OP 标题后变为「展开OP，36款」，36 条 OP 行隐藏，右侧自动转为 JSK「正腰JSK」，其尺码、黄色/粉色配色及 399/79/320 元价格完整显示。
3. 再收起 JSK，显示「类型已收起。展开左侧 OP、JSK 等类型后，选择款式继续编辑。」
4. 重新展开 JSK，款式与编辑内容恢复。
5. 返回 S2 后再进入 S3，OP 保持收起、JSK 保持展开，继续编辑 JSK。截图确认分组标题、款数和所选款式正确显示。
6. 草稿始终为第 1,419 版；5 店家、14 系列、273 商品、449 图片保持不变。未执行实际草稿删除、拖拽、上传或发布。

此次仅更新 Mac 运营工具，不涉及手机安装或 TestFlight 上传。用户暂停 TestFlight 的指令继续生效。
