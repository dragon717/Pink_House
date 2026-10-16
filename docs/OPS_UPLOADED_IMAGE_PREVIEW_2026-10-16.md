# 运营已上传图片点击预览（2026-10-16）

## 行为

已有图片点击缩略图直接打开应用内大图，支持适应窗口、放大至400%、横纵滚动及关闭。没有图片时仍点击占位框上传；已有图片的更换、价格表追加和颜色重新配图使用独立文字按钮。预览按点击时的路径和NSImage一起传入sheet，避免空路径首帧。

已接入Logo、系列封面、向导尺码表及价格表、颜色图片、商品图片绑定列表和表图详情。右侧已配图片的预览与颜色选择分开。缺失或未下载的本机图片不假装已加载；已有路径读取失败时显示明确错误。

同日用户后续调整：批量配图的上传历史改为点击图片直接填充，并自动选中下一颜色，去掉「分配图片」按钮。为避免遮挡图片，移除右上角放大镜，查看大图改为点击图片下方的文件名。该窗口的现行交互及验收见 [颜色图片连续填充](OPS_COLOR_IMAGE_SEQUENTIAL_FILL_2026-10-16.md)。下文预览点验保留为此前版本的历史记录。

共用组件位于`PinkHouseOps/Views/OpsFormSupport.swift`。不修改图片文件、图片身份、颜色绑定存储或发布链路。

## 构建与回归

Xcode27.0（27A266a），scheme PinkHouseOps，目标macOS arm64。

```sh
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

构建 **TEST BUILD SUCCEEDED**。现有运营Workspace回归 **65项通过，0失败**，覆盖存储、图片导入、草稿及已有编辑路径；没有为简单预览新增镜像实现的单元测试。

正常构建把上面的`build-for-testing`替换为`build -configuration Debug`，**BUILD SUCCEEDED**。`git diff --check`通过。日志根`/private/tmp/pink-house-ops-image-preview-20261016/`：`build.log`、`regressions.log`、`normal-build.log`。

## 本机安装与实际点验

原工具草稿显示已保存。正常退出请求后，Xcode仍持有旧PID65914；通过Xcode Stop结束旧调试会话，再更新日常应用路径。新旧应用深层严格签名验证通过，全部签名权限相同。旧应用移至备份目录保留，没有删除；安装路径与备份见日志目录`installation.json`，签名比对见`signing-verification.json`。应用数据目录未复制、清空或改写。

用Computer Use打开新进程后，实际完成：

1. 点击已有Logo进入大图，没有打开文件选择器。图片首帧可见，缩放由100%变为130%，点适应窗口及关闭返回。
2. 独立点「更换图片」打开文件选择器，取消后原Logo保留，草稿版号不变。
3. 在系列资料点击已关联价格表，正确显示HEIC长图全貌，关闭返回。没有点删除或新增图片。
4. 打开颜色批量配图窗口，点击上传历史中的JPEG图片，嵌套预览正常显示完整尺码表。关闭后颜色选择保持原状，没有「已分配」操作反馈；取消整个配图窗口，不保存任何配图更改。
5. 返回原S1页，草稿版号、店家 / 系列 / 商品 / 图片数量与点验前一致。

本次实际点验覆盖Logo、价格表、上传历史及嵌套配图预览，共用入口的其他接入由构建与代码核对覆盖；未把它们记为逐一点击全部入口。未执行新增上传、修改绑定、云端发布或TestFlight上传。TestFlight继续遵循用户此前的暂停指令。
