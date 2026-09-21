# xcodebuild 命令

读取时机：要跑构建或测试时。**优先用 `scripts/build.sh`**，它已经封装好三个沙箱开关；
下面列出等价的手工命令，用于需要改参数或排错时。

## 三个沙箱开关必须一起给

在受限沙箱里跑 xcodebuild，这三个开关缺一不可。少了它们，失败会以**看起来像代码错误**的形式出现。

```bash
FLAGS=(
  -IDEPackageSupportDisableManifestSandbox=YES   # 坑 1：SwiftPM manifest 编译
  -skipPackagePluginValidation
  -skipMacroValidation
  ENABLE_USER_SCRIPT_SANDBOXING=NO               # 坑 3：用户脚本阶段
  'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox'  # 坑 2：宏插件服务
)
```

## 1) 只编译主 target（最快，验证自己的代码能否编译）

```bash
scripts/build.sh app
```

等价于：

```bash
xcodebuild -project ItemManager.xcodeproj -target ItemManager \
  -sdk iphonesimulator -configuration Debug \
  "${FLAGS[@]}" \
  SYMROOT="$PWD/build/sym" OBJROOT="$PWD/build/obj" \
  build > /tmp/xcb_app.log 2>&1; echo "退出码=$?"
```

- `-target` 时**不能**配 `-derivedDataPath`（会报 `-scheme ... is required`），改用 `SYMROOT` / `OBJROOT`。
- `OBJROOT` 固定住可复用增量编译：首次约 6 分钟，之后几十秒。

## 2) build-for-testing（验证新增测试文件能编译）

```bash
scripts/build.sh testing -d "iPhone 18 Pro"
```

注意：`build-for-testing` 只证明**能编译**，不等于测试通过。

## 3) 跑测试

```bash
scripts/build.sh test -o ItemManagerTests/TimeHallPublicationProtocolTests
scripts/build.sh test -o ItemManagerUITests/MyFlowUITests -r /tmp/ph_ui.xcresult
```

`-only-testing` **必须用斜杠语法** `Target/ClassName`；点语法会被本 scheme 报
`isn't a member of the specified test plan or scheme` 直接拒跑（约 4 秒退出）。

## 怎么 grep 才不误报

源码里存在 `error: error` 这类文本，裸 `grep "error:"` 会捞出一堆 `#ActorIsolatedCall` 片段。
只匹配**行首带路径的编译器诊断行**：

```bash
grep -nE "^/Users/.*:( error| fatal error| error:)" /tmp/xcb_app.log
grep -E "\*\* (TEST )?BUILD (SUCCEEDED|FAILED) \*\*" /tmp/xcb_app.log
```

## 常见排错

| 现象 | 处理 |
|---|---|
| `-derivedDataPath` 报 `flag -scheme ... is required` | 改用 `SYMROOT`/`OBJROOT`，或换成 `-scheme` |
| `Model()` / `Relationship()` 宏找不到 | `-Xfrontend -disable-sandbox`（坑 2） |
| SwiftPM manifest invalid | `-IDEPackageSupportDisableManifestSandbox=YES`（坑 1） |
| `PhaseScriptExecution ... failed` 但日志里没有 `error:` | `ENABLE_USER_SCRIPT_SANDBOXING=NO`（坑 3）；代码其实已编译通过 |
| 卡在 `Resolve Package Graph` 很久 | 正常，首次要 fetch；`Package.resolved` 在 `ItemManager.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` |
| `Mach error -308 - (ipc/mig) server died` | 模拟器基础设施抖动，**不是代码错误**；原命令重试。若伴随 `PruneExplicitPrecompiledModules` + 全量重编，单次可能拉到 20-30 分钟 |
| `xcodebuild test` 卡很久但用例秒级完成 | 先 `tail` 日志确认卡在编译/模拟器启动；单测墙钟时间主要由模拟器启动决定 |
| `sandbox_apply: Operation not permitted` 反复出现 | 该命令需要绕过沙箱执行 |

## 全量单测有既有失败时

`ItemManagerTests` 全量跑时 `PetChatGuidanceEngineTests` 存在**与改动无关的既有失败**。

1. 先 `git status --porcelain` 确认报错文件**不在**自己的改动范围里；
2. 再用 `-only-testing:` 精确跑本轮相关测试类，拿干净的 `TEST SUCCEEDED`；
3. 结论里如实写「既有失败，与本次改动无关」。
