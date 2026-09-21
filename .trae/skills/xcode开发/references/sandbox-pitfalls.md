# 三个沙箱坑

读取时机：**xcodebuild 报了看不懂的错时先读这一页**，再判断是不是自己代码的问题。

本机在受限沙箱里跑 `xcodebuild` 会连撞三个坑，**都不是代码问题**。

## 坑 1：SwiftPM 清单编译

```
sandbox-exec: sandbox_apply: Operation not permitted
xcodebuild: error: Could not resolve package dependencies: Invalid manifest (...)
```

Xcode 用 `sandbox-exec` 跑 SwiftPM manifest，沙箱里不允许。
绕过：`-IDEPackageSupportDisableManifestSandbox=YES`

## 坑 2：宏插件服务被沙箱杀掉（**最容易误判为代码错误**）

```
error: external macro implementation type 'SwiftDataMacros.PersistentModelMacro'
could not be found for macro 'Model()';
'/Applications/Xcode.app/.../swift-plugin-server' produced malformed response
```

`swift-frontend` 默认用沙箱拉起 `swift-plugin-server`，沙箱里拉不起来 → 服务进程被杀 → "malformed response"。

**症状特征**：报错集中出现在所有 SwiftData `@Model` / `@Relationship` 文件
（`Brand.swift`、`Clothing.swift`、`Tag.swift`），**与当前改动无关**。

诊断：直接运行插件服务，它应该是"读 stdin，EOF 后 0 退出"的正常进程：

```bash
( /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/swift-plugin-server & \
  PID=$!; sleep 3; kill -0 $PID 2>/dev/null && echo 存活 && kill $PID || echo "退出" )
```

绕过：`OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'`
**关掉坑 2，才会看到真正的编译错误。**

## 坑 3：用户脚本阶段被 sandbox-exec 拦截

Swift 全部编译通过之后，还可能卡在脚本阶段：

```
/usr/bin/sandbox-exec -D SCRIPT_INPUT_FILE_0=... Script-XXXX.sh
sandbox-exec: sandbox_apply: Operation not permitted
Command PhaseScriptExecution failed with a nonzero exit code
... failed: PhaseScriptExecution Remove Duplicate Resources (...)
```

`ENABLE_USER_SCRIPT_SANDBOXING` 默认为 YES，xcodebuild 用 `sandbox-exec` 包脚本。
绕过：`ENABLE_USER_SCRIPT_SANDBOXING=NO`

## 总判据

**如果日志里没有任何 `error:`，只有 `PhaseScriptExecution ... failed`，
说明代码已经编译通过，失败纯粹是脚本沙箱。别误报成代码错误。**

更一般的判据：**报错的文件是否在本次 `git status` 里**。不在 → 环境问题，不要改代码。
