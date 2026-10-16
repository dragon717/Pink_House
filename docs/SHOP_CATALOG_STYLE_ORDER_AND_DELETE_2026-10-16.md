# 目录运营款式拖拽排序与逐条删除（2026-10-16）

## 范围与行为

对应用户截图中「系列上新 → 系列内多类型录入」左列的款式条目。

同日追加：左列已按 OP、JSK 等类型分组，支持整组收起与展开，拖拽在同一类型内调整款式顺序。折叠规则与界面验收见 [运营类型录入分组折叠](OPS_CATEGORY_GROUP_COLLAPSE_2026-10-16.md)。

- 每条款式显示拖拽标记、复制按钮与删除按钮；也可通过右键菜单删除指定款式。
- 拖动条目经过其他款式时实时调整顺序，并保存到整份系列向导草稿；重开后沿用已保存的顺序。结束或取消拖动时保留当前已调整的排列。
- 拖动来源限定当前应用进程及当前草稿，其他窗口或外部文件不能当作款式排序。
- 删除确认明确展示款式名称；仅按该行的独立 ID 定位并移除一次。同名、同类型、共用图片或复制产生的其他条目均保留。已写入目录的商品不随向导条目一起删除。
- 类型勾选区取消勾选时，优先定位该类型下当前选中的款式。该类型存在多条且未选中其中一条时，不再默认删除第一条，提示先选择具体款式。
- 草稿恢复及数组编辑时修复空白或重复的条目 ID，保留每一行的全部输入与原顺序。有效 ID 不变，修复结果随草稿保存。
- 排序、删除与复制共用保存入口：先保存草稿，再更新界面；落盘失败时保留原条目和原顺序，显示失败原因。损坏隔离草稿仍拒绝写入。

实现入口：`OpsSeriesWizardTypeEditor.swift`、`OpsSeriesEntryDraft.swift`、`OpsWorkspace+SeriesEntry.swift`。

## 自动验证

本机 Xcode 27.0（27A266a），使用 `/Applications/Xcode.app/Contents/Developer`。以下命令通过：

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

`OpsCatalogEditorPersistenceTests`：**64 项通过，0 失败**。新增 6 项覆盖同名同类型与共用图片的独立删除、上下移动及重开恢复、多行和非法落点、删除或排序保存失败回退、旧重复标识恢复、损坏隔离草稿拒绝写入。既有复制、发布与同步回归仍通过。

正常运行构建使用上述 `xcodebuild` 命令，将 `build-for-testing` 改为 `build -configuration Debug`。结果、签名核验与安装记录保存在 `/private/tmp/pink-house-style-order-delete-20261016/`，正常构建日志为 `mac-normal-build.log`。

## 界面验证

通过独立 `StyleEntryQA.app` 使用真实 `OpsSeriesWizardTypeEntriesView` 和内存 SwiftData 容器，未打开用户存储，也不发送网络请求。电脑控制实际验证：

1. 将末尾「娃娃领 OP+胸针」拖至首位，界面显示新排列且右侧仍为该款式原有的 559 元及粉色配色；`ui-after-move-to-front.json` 确认顺序为 `brooch, plain, ribbon-a, ribbon-b`。
2. 继续向下拖动调整排列，四条输入均保留。
3. 排序后点击第二条「娃娃领 OP+发带」自身的删除按钮并确认。仅 `ribbon-b` 消失，保留 `ribbon-a, plain, brooch`，金额仍分别为 529、499、559；证据为 `ui-after-single-delete.json`。

测试使用临时条目，未执行真实运营草稿删除或云端目录变更。

## 日常应用生效

新版更新到日常启动路径：`/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/Build/Products/Debug/PinkHouseOps.app`。签名与权限比对通过后替换，旧应用保留为同目录的备份，具体路径见日志目录内 `mac-install.json`。

保留正在运行的运营窗口及录入进程，重开工具后使用新版。此次仅修改 Mac 运营工具，不要求重新发布目录。
