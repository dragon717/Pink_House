# 自定义收纳柜图片图标（2026-10-14）

## 用户操作

新增或编辑自己的柜子时，保留八个内置图标，并增加「自定义图标 → 从照片选择」。用户选图后进入现有 `ImageCropView`，通过缩放 / 拖动调整正方形内容，圆形轮廓预览最终图标。裁剪完成只更新编辑草稿；点击柜子「保存」后，抽屉与侧边栏同步显示同一张图片。未选择图片时仅显示照片加号占位。

编辑时可以更换图片、重用当前图片或选择内置图标。取消照片选择、裁剪或整个编辑，不写入图片和设置；裁剪页交互式关闭也会清空本次照片选择，允许再次选择同一张照片。图片加载 / 裁剪期间禁止保存。载入失败显示可重试的错误，缺失图标文件回退到原内置插画。

图标仅改变展示。使用图片时保留原内置图标对应的柜体层高、柜子 ID、名称和物品归属；没有新增默认柜子或示例库存。主题渐变底座、选中边框、可读文字与背景继续使用原统一主题。

## 保存与兼容

`WardrobeStorageCustomCabinet` 增加可选的 `iconImageFile`；既有 `wardrobe.storage.custom-cabinets.v1` key 与内置图标 rawValue 不变，旧 JSON 缺少新字段时按 nil 解码。UserDefaults 只保存文件名，图片由 `WardrobeStorageIconStore` 保存到本机 Application Support 的 `WardrobeStorage/Icons/`，不进入衣物照片目录、SwiftData 或 CloudKit。

选图预处理使用 ImageIO 的方向修正缩略图，最大 1024 像素；保存生成 256 × 256、保留透明度的 PNG（上限 512 KiB），以新 UUID 文件名原子写入。先成功写图，再更新柜子设置；失败保留原设置与图片。成功更换 / 恢复内置图标后，只清理不再被其他柜子引用的旧衍生图。文件访问仅接受 UUID.png 文件名，拒绝其他路径。小图使用 64 项 / 16 MiB 有界内存缓存。原照片保持不变。

自定义柜子与图片继续只在本机保存，本轮未增加跨设备同步或备份导入功能。

## 构建与测试

Xcode 27.0 / 27A266a，scheme ItemManager，iPhone 18 Pro / iOS 27.0，bundle `bugod2.ItemManager`。

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=600 \
LOG=/private/tmp/pink-house-storage-custom-icons-final-build-20261014.log \
tools/xcode/stable_cli_build_and_run.sh
```

初次构建 57 秒通过；新增依赖的默认参数曾引入 MainActor 警告，已改为在隔离的初始化函数内取得 shared。最终构建 54 秒，build / install / launch 返回 0；terminate 返回 3（无旧进程），已启动 PID 47776。最终日志没有新增的 WardrobeStorage 隔离警告。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -jobs 5 -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/WardrobeStorageCustomIconTests \
  -only-testing:ItemManagerTests/WardrobeStorageSettingsTests \
  -resultBundlePath /private/tmp/pink-house-storage-custom-icons-20261014.xcresult \
  -quiet test
```

**16/16 PASS，0 失败 / 0 跳过**：8 项新图标测试及原 8 项自定义收纳设置测试。覆盖旧 JSON、持久化后重新读取、改名 / 修改物品保留图片和柜体类型、替换图片与恢复内置图标、仅清理旧衍生图、非法图片 / 名称及写盘失败保留原设置、方向修正、缩小实际像素、透明角点、缺图 / 非法路径兜底、日夜模式自定义图标渲染，以及既有物品分区与 JSK 整套保护。

最后仅优化空图片的照片加号占位，随后重新构建并核对实际页面。测试全部使用隔离 UserDefaults 与本次创建的临时文件，不写入用户柜子 / 照片；生成的简单色块仅用于测试图标渲染。机器摘要与从 XCTest attachment 导出的日夜图位于 `docs/design/wardrobe-storage/validation/custom-icons/`，渲染图已读取像素预览。

## 实际页面与边界

完成同一目标的编译、安装、重启后，通过 Device Hub Computer Use 从首页「更多 → 我的收纳柜 → 添加柜子」核对：名称与图标文字可读，八个内置选项保留，自定义照片加号和「从照片选择」入口完整可见，空名保存禁用。点击入口成功打开系统照片选择器，取消后回到原编辑页，仍为未选择图片的状态；再取消整个编辑，回到只有原四个默认柜子的抽屉，未新建柜子。实际页面截图为 `validation/custom-icons/editor-simulator.png`。

系统照片选择器停留在加载页，本轮未通过真实照片库完成选图 / 拖动裁剪 / 保存的全流程验收；图片处理、保存与重新读取由原生测试验证，裁剪复用现有头像等功能使用的组件。未覆盖真机、iPad、大字号、极低内存或完整数据回归。Device Hub 偶发 AXError.cannotComplete，重新连接后以实际页面为准，没有把点击尝试计为成功。既有 MainActor / Sendable、扩展版本与资源脚本警告仍在。
