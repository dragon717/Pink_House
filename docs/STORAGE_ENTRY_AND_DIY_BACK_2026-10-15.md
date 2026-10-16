# 收纳柜入口避让与 DIY 搭配返回（2026-10-15）

## 改动

- 衣橱右侧收纳柜入口改为 32 × 52 pt 的小图标，去掉常驻的两行文字；保留无障碍名称、提示、点击和左滑入口，以及“更多 → 我的收纳柜”。
- 从覆盖卡片的浮层改为衣橱内容右侧的 `safeAreaInset`，预留 32 pt 独立区域。卡片按可用宽度布局，入口不再盖住卡片图片、名称或金额；系统底部 TabView 保持原有布局。
- 抽屉打开时隐藏入口，保留这块布局空间，避免打开 / 关闭抽屉时卡片宽度跳变。编辑、搜索和心愿尾款页面沿用原有入口显示条件。
- DIY 搭配在自身导航栏左上角提供返回箭头，无障碍名称为“返回”。点击直接返回进入前的衣橱、心愿尾款或 House 页面；House 不可用时返回衣橱。
- 原先返回前的书页管理弹窗移除。“加入其他手帐”保留为独立书页按钮，存在其它手帐时显示；普通手帐编辑器的返回操作不变。

## 构建

Xcode 27.0（27A266a），iPhoneSimulator 27.0 SDK；验收目标为 iPhone 17 Pro / iOS 26.3.1（23D8133），独立 QA 模拟器 `Codex DIY Outfit QA`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3
```

构建日志与截图：`/tmp/pink-house-storage-diy-navigation-20261015/`。

## 验收结果

| 检查 | 结果 |
| --- | --- |
| 初次构建、保留抽屉打开期间的边距后的最终构建 | **BUILD SUCCEEDED**，退出 0；`build.log`、`build-final.log` |
| 精确目标安装、新进程启动 | **PASS**；`bugod2.ItemManager`，首次 PID 45033，主题夹具重启 PID 46611 |
| 默认主题三列卡片 | **PASS**；入口与右侧卡片之间留有间距；点击入口旁最右侧第一行卡片的金额区域，正常打开“性能压测裙装 #9”详情 |
| 收纳柜按钮 | **PASS**；点击小图标打开原抽屉，关闭返回后卡片宽度、三列布局保持一致 |
| 天空音乐会主题三列 | **PASS**；卡片图片、名称、价格和主题边框均未被小入口遮盖 |
| 左滑入口 | **PASS**；从小入口向左拖动打开原抽屉，关闭后回到主题衣橱 |
| 从统计卡片打开 DIY | **PASS**；左上角返回箭头一次点击回到衣橱，未出现书页管理确认弹窗 |
| 从更多菜单打开 DIY | **PASS**；天空音乐会主题下正常进入画布，左上角一次点击回到衣橱 |

安装与启动命令：

```bash
xcrun simctl install F64FFA05-1AA0-4C8F-9920-F18A772486CB \
  /tmp/pink-house-reservation-batches-ios/Build/Products/Debug-iphonesimulator/ItemManager.app
xcrun simctl terminate F64FFA05-1AA0-4C8F-9920-F18A772486CB bugod2.ItemManager
xcrun simctl launch F64FFA05-1AA0-4C8F-9920-F18A772486CB bugod2.ItemManager \
  -AppleLanguages '(zh-Hans)' -UserPreference_ViewLayout '三列'
```

安装时已无旧进程，`terminate` 返回“found nothing to terminate”；随后新进程启动成功。电脑控制仅检查 Device Hub 中与构建 UDID 对应的 `Codex DIY Outfit QA`。

独立 QA 夹具：通过已有 DEBUG 性能种子入口追加 11 条测试衣物，连同之前一条测试数据形成多行三列；没有读写真机或生产衣物。主题检查前备份此 QA 应用的偏好，再只在该 QA 容器设置天空音乐会主题拥有 / 启用状态及三列布局，不以此验证主题购买流程。未动主题注册、素材和持久化格式。

截图：

- [默认主题三列](/tmp/pink-house-storage-diy-navigation-20261015/default-grid3.png)
- [天空音乐会主题三列](/tmp/pink-house-storage-diy-navigation-20261015/sky-concert-grid3.png)
- [收纳柜抽屉](/tmp/pink-house-storage-diy-navigation-20261015/storage-drawer.png)
- [DIY 返回按钮](/tmp/pink-house-storage-diy-navigation-20261015/diy-back-button.png)

已有 Swift 6 actor 隔离 warning（例如 `DraftPersistencePipeline` 的日志调用）及资源脚本构建备注，没有阻断本次构建。

## 边界

本轮为入口布局和导航调整，不修改衣物、手帐存档格式、主题 slot 或鱼币逻辑。通过实际界面点验验证三列卡片与入口不重叠、收纳柜仍可进入、DIY 一次点击直接返回，没有为样式尺寸添加实现镜像单元测试。未覆盖真机、iPad、其它系统版本、心愿尾款 / House 来源的运行时返回、其它网格列数，以及书页实际移动保存分支。普通手帐编辑器沿用原有导航。
