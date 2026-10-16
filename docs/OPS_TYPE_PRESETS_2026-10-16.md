# 运营添加类型固定选项（2026-10-16）

系列上新 S3 的固定类型按用户最新要求显示：**OP、JSK、SK、开衫、衬衫、内搭、围裙/罩裙、斗篷、小物、包、其他**。同日补充 SK 后，用户要求去掉 SK 下方单独的「罩裙」选项，再补充「小物」与「包」到「其他」前面；「围裙/罩裙」和自定义入口保留。

自定义类型输入及添加入口继续保留。此次仅改变 `OpsSeriesEntryCategory.known` 的预设列表，并同步空页面示例文案；类型持久化仍为自由字符串，不迁移、重命名或删除旧草稿中的类型。KC 等历史类型仍可通过款式列表编辑，通过「添加条目」继续添加同类款式。

## 构建与界面验证

本机 Xcode 27.0（27A266a），执行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -configuration Debug \
  -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ops \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2
```

结果 **BUILD SUCCEEDED**，`git diff --check` 通过。仅调整固定选项及提示，没有为常量列表新增单元测试或重跑无关存储回归。

临时 `TypePresetsQA.app` 使用真实 `OpsSeriesWizardTypeEntriesView`、内存 SwiftData 和 OP / 旧 SK 两条款式。电脑控制实测：

1. 九个选项按指定顺序显示，自定义输入与添加入口可见；1000 × 680 窗口内可正常操作。
2. 旧 SK 款式仍可选中并编辑，其原名、299 元价格和蓝色配色保留。
3. 输入自定义「头饰」并添加成功，新增独立条目。
4. 勾选「围裙/罩裙」创建正确类型，不影响原有 OP / SK 条目的 ID、价格或配色。

证据目录 `/private/tmp/pink-house-type-presets-20261016/`：`build.log`、临时验收源文件、`ui-state.json`、`ui-verification.json`。所有新增、选择均为临时数据，没有操作真实运营草稿。

## 本机更新状态

用户随后明确选择「现在更新并重启」。已保存当前草稿并正常退出旧进程，将签名核验通过的新版更新到日常应用路径：

`/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/Build/Products/Debug/PinkHouseOps.app`

旧应用保留在同目录 `.codex-type-presets-20261016-191022/PinkHouseOps.previous.app`，新旧签名严格校验通过、四项 entitlements 一致。没有复制、清空或迁移运营数据目录。

重启后实际进入 S3，截图确认九项固定选项按指定顺序显示，自定义类型入口仍在。草稿仍为第 1,440 版，5 店家、14 系列、273 商品、511 图片均与重启前相同；已有 OP / JSK / 开衫 / 衬衫 / 围裙/罩裙的记录保持原样。本次未新增、删除或改写真实款式。

安装路径、备份与签名记录见证据目录 `installation.json`、`signing-verification.json`，实际窗口核对见 `ui-verification.json`。

TestFlight 上传继续暂停。

## 同日补齐 SK

用户补充遗漏的 SK 后，仅在预设列表的 JSK 后插入 SK。执行上文相同正常构建命令，结果 `BUILD SUCCEEDED`；`git diff --check` 通过，未新增或重复运行常量列表测试。

新版已签名核验、安装到同一日常路径并重启，旧应用保留在 `.codex-type-presets-sk-20261016-191658/PinkHouseOps.previous.app`。实际进入 S3 后，原生界面读取确认 OP、JSK、SK、罩裙、开衫、衬衫、内搭、围裙/罩裙、斗篷、其他十项按顺序显示，自定义输入仍在。未勾选或添加真实 SK 款式，草稿第 1,440 版及 5 店家、14 系列、273 商品、511 图片保持不变。

此次构建、签名、安装和界面记录位于 `/private/tmp/pink-house-type-presets-sk-20261016/`。

## 同日移除单独的罩裙选项

用户随后要求去掉 SK 下方单独的「罩裙」，仅从 `known` 固定列表移除此项，保留「围裙/罩裙」及自定义入口。执行上文相同正常构建命令，结果 `BUILD SUCCEEDED`；`git diff --check` 通过。本次未新增或重复运行常量列表测试。

新版已严格校验签名、更新并重启，旧应用保留在 `.codex-no-overskirt-20261016-192201/PinkHouseOps.previous.app`。实际进入 S3，原生界面确认固定项依次为 OP、JSK、SK、开衫、衬衫、内搭、围裙/罩裙、斗篷、其他，没有单独「罩裙」，自定义输入仍在。未新增、删除真实款式，草稿第 1,440 版和 5 店家、14 系列、273 商品、511 图片保持不变。

本次构建、签名、安装和界面记录位于 `/private/tmp/pink-house-type-presets-no-overskirt-20261016/`。

## 同日补充小物和包

根据用户补充，在「其他」前新增「小物」「包」两个固定选项。执行上文相同正常构建命令，结果 `BUILD SUCCEEDED`；`git diff --check` 通过。本次仅修改预设列表，未新增单元测试或重复执行存储回归。

签名核验通过后已更新同一日常应用路径并重启，旧应用保留在 `.codex-accessories-bag-20261016-205505/PinkHouseOps.previous.app`。实际进入 S3 后，重新连接原生窗口读取确认十一项固定类型顺序正确，「小物」「包」均显示，自定义输入仍在，单独「罩裙」没有恢复。未操作真实类型勾选、添加或删除；草稿仍为第 1,444 版，5 店家、14 系列、273 商品、574 图片保持原样。

本次构建、签名、安装和界面记录位于 `/private/tmp/pink-house-type-presets-accessories-bag-20261016/`。
