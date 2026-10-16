# DIY搭配入口调整（2026-10-15）

后续截图反馈的返回操作已调整：DIY 左上角返回箭头现在直接回到来源页面；“加入其他手帐”独立为书页按钮，不再通过返回前的确认弹窗执行。最新实现与补充点验见 [收纳柜入口避让与 DIY 搭配返回](STORAGE_ENTRY_AND_DIY_BACK_2026-10-15.md)，下方早期验收中的书页管理弹窗仅为历史记录。

## 功能名称与位置

原「魔法贴纸」改为「DIY搭配」，继续使用现有衣物抠图、画布拼搭、缩放旋转和加入手帐功能。

- 主要入口：衣橱顶部统计卡片的功能区，顺序为「今日穿搭色 / DIY搭配 / 穿搭手帐 / 详细统计」。沿用现有卡片高度和主题配色。
- 补充入口：衣橱右上角「更多」菜单中的「DIY搭配」。统计卡片收起时仍能找到；正式系统菜单与引导菜单调用同一打开动作。
- 已有自定义底部导航、House 注册项、魔法任务、萌宠推荐按钮及流程标题同步使用新名称；不增加底部导航槽位。
- 解锁检查沿用既有规则。未解锁点击进入魔法任务；已解锁打开画布，返回来源记录为衣橱。
- 功能体验引导说明改为从衣橱进入，并继续监听真实画布打开事件推进。

## 数据兼容

功能 ID `magicSticker`、路由及解锁 ID `ootdDefaultBook`、通知名和默认手帐资料保持原有存储语义。「默认手帐」与「少女魔法贴」仍是旧画布的查找依据，不因展示改名创建另一份画布。

DIY 入口给编辑器传入独立的展示标题「DIY搭配」；普通手帐编辑器仍显示各自书页名称，不改写用户内容。旧常用菜单的 `FavoriteMenuItem.ootd.rawValue` 保留，展示名称单独映射。

## 验证

本机 Xcode 27.0（27A266a），单独建立 iOS 26.3 的 `Codex DIY Outfit QA` 模拟器，UDID `F64FFA05-1AA0-4C8F-9920-F18A772486CB`。不使用用户现有模拟器的数据作为夹具。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3
```

日志与验收截图：`/tmp/pink-house-diy-outfit-20261015/`。构建、安装、新进程及真实界面验收结果在下方补充。


### 结果

| 检查 | 结果 |
| --- | --- |
| 首次构建、补充翻译后的增量构建 | **BUILD SUCCEEDED**；日志 `ios-build.log`、`ios-final-build.log` |
| 编译产物名称与翻译 | 二进制包含「DIY搭配」；中英文 `Localizable.strings` 分别为「DIY搭配」「DIY Outfits」 |
| 安装与新进程 | **PASS**；bundle id `bugod2.ItemManager`，首次 PID 32045，已解锁夹具重新启动 PID 32315 |
| 衣橱统计卡片 | **PASS**；四个入口完整显示，DIY 位于穿搭色与手帐之间 |
| 未解锁点击 | **PASS**；进入魔法任务，名称为「DIY搭配」，条件仍为收集 3 件衣物 |
| 已解锁点击及返回 | **PASS**；进入原默认画布、标题显示「DIY搭配」，保留默认手帐后返回衣橱 |
| 收起统计后的更多菜单 | **PASS**；仍有「DIY搭配」，点击正常进入同一画布 |

安装及新进程命令（均针对本轮新建的独立 QA 模拟器）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install \
  F64FFA05-1AA0-4C8F-9920-F18A772486CB \
  /tmp/pink-house-reservation-batches-ios/Build/Products/Debug-iphonesimulator/ItemManager.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl terminate \
  F64FFA05-1AA0-4C8F-9920-F18A772486CB bugod2.ItemManager
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch \
  F64FFA05-1AA0-4C8F-9920-F18A772486CB bugod2.ItemManager -AppleLanguages '(zh-Hans)'
```

UI 使用本机 Xcode 的 Device Hub 打开精确匹配的 QA 设备，以 Computer Use 检查画面、点击真实入口和返回；没有读取其它手机或 iPad 的内容。验收图为 `wardrobe-entry.png`、`locked-task.png`、`more-menu.png`、`diy-canvas.png`。

首次启动夹具仅设置欢迎页已看过、当天打卡已处理，以避开无关开屏流程。已解锁分支另在此独立模拟器的偏好中注入 DIY 功能解锁状态，未把此项当作真实收集衣物 / 解锁奖励业务验收。

边界：本轮覆盖 iPhone 17 Pro、iOS 26.3.1、默认浅色主题的名称、入口、访问检查和返回；未覆盖真机、iPad、其它主题及完整抠图/画布编辑流程，也未重复跑无关业务测试。验收后关闭本轮新建的 QA 模拟器，保留设备及截图供复核。
