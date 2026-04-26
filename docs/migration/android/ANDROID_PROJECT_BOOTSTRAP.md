# Android 工程初始化记录

更新时间：2026-04-20

## 本次创建内容

- 在仓库根目录新增 `android/` 原生 Android 工程骨架。
- 使用单模块 `:app`，Gradle Kotlin DSL + Version Catalog 管理依赖。
- 初始化 Kotlin、Jetpack Compose、Material 3、Navigation Compose、Room、DataStore、Timber。
- 建立入口 `MainActivity`、`PinkHouseApplication`、Compose Theme、底部导航和六个主 feature 占位页。
- 建立 `core`、`data/local`、`domain/model`、`feature/*` 基础包结构。
- 添加 Android README，覆盖 macOS 开发、debug 构建、release APK/AAB 和本地签名配置。

## 本地验证状态

当前机器缺少 Java Runtime、`gradle` 命令和 `ANDROID_HOME`，因此未执行 Gradle Sync 或 Android 构建。工程按标准 Android Studio 项目结构手写，后续需在安装 Android Studio/JDK 17/SDK 35 后由 Android Studio 完成 Sync 和构建验证。

## 设计约束

- 不修改 iOS 工程文件。
- 不修改 `harmony_next/`。
- 不提交 keystore、签名密码或本地 `keystore.properties`。
- 暂不引入 Google Play Services/Firebase，保持国内安卓和 HarmonyOS 3/4 APK 兼容。
