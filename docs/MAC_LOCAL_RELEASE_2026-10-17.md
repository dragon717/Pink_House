# 少女心愿运营：本地 Release 版（2026-10-17）

用户要求 Mac 运营工具以独立 app 在本机日常运行，名称为「少女心愿运营」。本次使用 Release 构建并安装到 `/Applications/少女心愿运营.app`。

## 构建与产物

本机为 Apple Silicon，Xcode `/Applications/Xcode.app`，27.0（27A266a）。应用最低系统版本沿用 macOS 26.2。本次只生成本机 arm64 架构。

正式入口：`tools/xcode/build_mac_release.sh`。在仓库根目录执行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SPM_CACHE=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
tools/xcode/build_mac_release.sh
```

`SPM_CACHE` 可省略；指定时复用已解析的 Xcode 包缓存并禁止自动更新。脚本固定使用 `PinkHouseOps` scheme、`Release`、当前机器架构和 `ONLY_ACTIVE_ARCH=YES`，默认两路编译。它仅构建及打包，不安装或上传。再次打包时将旧 app/zip 移入输出目录的 `.previous.*` 备份，再放入新产物，避免合并签名包。

默认输出位于仓库的 `build/mac-release/`，已被 Git 忽略：

- `少女心愿运营.app`：可以直接双击的应用包。
- `少女心愿运营.zip`：保留 macOS 元数据的压缩包。
- `DerivedData/`：独立的 Release 构建缓存及 dSYM。
- `build.log`：最近一次构建日志。
- `verification.json`：本次安装、签名、压缩包及数据恢复核对记录。

## 名称与签名

`PinkHouseOps/Info.plist` 明确提供中文 `CFBundleName` 和 `CFBundleDisplayName`，窗口标题同步修改。使用显式 plist，避免自动生成的 `CFBundleName` 继续显示内部 product 名称；plist 从同步文件夹的资源成员中排除。

bundle ID 仍为 `bugod2.ItemManager.Ops`，内部 product、模块和可执行文件仍为 `PinkHouseOps`，现有测试宿主及脚本路径可继续使用。

使用现有 Apple Development 证书签名以供本机使用。Release 设置 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`，实际签名不包含 `com.apple.security.get-task-allow`。应用沙盒、用户选择文件读写和网络客户端三项权限保留；Debug 仍使用原有调试权限。

应用启动及原生界面独立于 Xcode。运营发布继续沿用原有仓库授权、Python 虚拟环境及凭证配置；本次未将这套既有发布工具迁入 app，也未执行真实云端发布。

## 实际验证

1. 上述脚本实际执行通过，底层 `xcodebuild build -scheme PinkHouseOps -configuration Release -destination 'platform=macOS,arch=arm64' ... ONLY_ACTIVE_ARCH=YES` 返回 `BUILD SUCCEEDED`。编译命令确认 `-O -whole-module-optimization`。
2. 构建包、复制后的应用、安装包及 zip 解压后的应用均通过 `codesign --verify --deep --strict`。实际 entitlement 只有上述三项，未包含调试附加权限；包内没有 `.debug.dylib`。
3. `otool -L` 确认可执行文件只链接系统库/系统 Swift 运行库，无 DerivedData 或 Debug 产物路径依赖。
4. 旧 Debug 版已保存草稿并正常退出，原应用包保留；将 Release 包复制到 `/Applications/少女心愿运营.app` 后独立启动，实际进程来自该路径且父进程为 launchd。
5. 电脑控制确认主窗口、标题栏和应用菜单均为「少女心愿运营」。草稿仍为「2026-09-26 上新」第 3414 版、已保存，4 店家、13 系列、418 商品、585 图片与切换前一致。设置中 Development / Production 均显示已配置，原 Production 选择保留。
6. `bash -n tools/xcode/build_mac_release.sh`、plist 语法及 `git diff --check` 通过。

验证边界：本次只涉及名称、Release 打包和本机安装启动；未重新执行 iOS 或全量业务回归，未做性能基准测试，也未通过上传真实数据验证发布功能。
