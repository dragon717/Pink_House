# 4.4 商店截图更新记录

## 代码与环境

Duo 双栏详情和系统竖向导航的提交为 `1de6d242816ace6f6d9b3f48b3a0bc1cb9533885`，已推送到 GitHub 的 `codex/duo-adaptive-navigation` 分支，并通过 `git ls-remote` 核对。工作区已有的图标、内购和多语言修改仍单独保留，不能把此提交描述为全部发布改动已入库。

本轮使用 `$HOME/Applications/Xcode-27.1.app`，SDK 为 iPhoneSimulator 27.1。Duo 运行 iOS 27.1，其余专用截图设备运行 iOS 26.3。全部原生页面来自当前工作区构建，示例内容为四件离线衣物。

```sh
export DEVELOPER_DIR="$HOME/Applications/Xcode-27.1.app/Contents/Developer"
dd="$HOME/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh"
xcodebuild -scheme ItemManager -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$dd" -jobs 2 -quiet ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerUITests/StoreScreenshotUITests/testCaptureCurrentFeatures \
  -resultBundlePath "$RESULT_BUNDLE" test
```

Duo 外屏使用 `testCaptureDuoOuterStates`，单独补拍简中使用 `testCaptureSimplifiedStorePage`。退出码、测试结果和附件保存在 `output/app-store-4.4/proof/recapture-271/`。UI 测试通过只证明采集流程成功；图片载入、权限弹窗、目标页和转场仍需逐张检查。iPhone 12 的简中衣橱使用预设不允许定位后的单独原生截图，避免系统弹窗遮挡。

| 验证 | 结果 |
|---|---|
| iPad 详情列采集 `ipad13-detail` | PASS，退出码 0 |
| iPhone 17 Pro 采集 | PASS，退出码 0 |
| iPhone 12 / Pro Max 预热后采集 | PASS，退出码 0；首轮异常页面已单独替换 |
| Pro Max 简中页面补拍 | PASS，退出码 0，三张均通过视觉复查 |
| Duo 三语外屏衣橱和详情 | PASS，退出码 0，六张均通过视觉复查 |
| 截图测试启动弹层处理调整后的 `build-for-testing` | PASS，退出码 0；此测试辅助逻辑只重编译，未再执行采集 |
| Python 工具语法、实际图包解码及 SHA-256 暂存清单 | PASS，共 43 张 |

最后一项构建使用上述相同 destination 和编译参数，将 `test` 替换为 `build-for-testing`，日志为 `screenshot-harness-build.log`。已知资源同名警告、SDK build-version 解析警告仍存在，没有作为编译失败处理。

## 素材范围

主设备为 iPhone 12、17 Pro、17 Pro Max 和 13 英寸 iPad，每台设备有简中、繁中、英文的衣橱、尾款和统计三张。iPad 的衣橱和尾款均选择了示例衣物，右侧显示实际详情。

Duo 外屏三种语言共六张已完成，分别展示衣橱及衣物详情。简中展开图复用同一版适配代码已验收的 `output/duo-adaptation/proof/open-detail.png`，重新配上官方外框及双栏说明。英文、繁中展开图仍待在 Device Hub 切换展开姿态后补拍；旧版两张兼容模式图已移出上传目录，不与本轮素材混用。

目前图包共 43 张：四种主要设备 36 张、Duo 外屏 6 张、简中展开图 1 张。所有成图使用官方外框、完整设备分辨率、RGB、sRGB、无透明通道。最终数量和逐文件校验值以发布目录里的 `screenshots.json`、`上传尺寸核验.md` 和上传暂存目录 `manifest.json` 为准。图包校验不代表线上已经保存。

## Safari 后台状态

本轮已通过 Safari 重新登录 App Store Connect，目标为 App `6758352161` 的 iOS 4.4「准备提交」版本。

| 语言与槽位 | 本轮操作 | 尚待复核 |
|---|---|---|
| 简中 · 灵动岛中屏 iPhone | 三张新图已上传，读回数量为 3 | 顺序目前为 01、03、02，须调整为 01、02、03 |
| 简中 · 13 英寸 iPad | 三张新图已在文件选择器提交上传 | 尚未读回最终数量和顺序 |
| 其余设备和语言 | 尚未完成替换 | 上传、保存并逐槽读回 |

Safari 与用户的云端硬盘操作发生切换冲突，因此已询问何时可以连续操作电脑。在收到可操作时间前，继续处理本地素材，不把上述状态记作「全部上传完成」。英文和繁中使用原生截图，其他六种商店语言按既定主语言继承方案处理，不能称为九种语言的原生截图。

4.4 尚未选择最终构建；旧的 4.4 (3) 来自 SDK 27.0，不包含本轮 Duo 适配。用户后续上传的最终包需使用 Xcode 27.1 或更新版本归档。本轮未点击提交审核，也未验证真机、真实支付或系统多任务窗口。运行日志中的 AI 服务余额不足会触发已有本地日签回退，与本次截图页面无关。
