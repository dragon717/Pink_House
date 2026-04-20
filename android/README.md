# Pink House Android

少女心愿 Android 原生工程骨架。当前阶段按 `docs/migration/android/PRD.md` 初始化，目标是给后续 Android MVP 开发提供可继续扩展的 Kotlin + Jetpack Compose 基础项目。

## 技术栈

- Kotlin + Gradle Kotlin DSL
- Jetpack Compose + Material 3
- Navigation Compose
- Room
- DataStore Preferences
- Timber
- Min SDK 26, Target SDK 34, Compile SDK 35
- 不接入 Google Play Services / Firebase，保持国内安卓渠道与 HarmonyOS 3/4 APK 兼容优先

## 目录结构

```text
android/
  settings.gradle.kts
  build.gradle.kts
  gradle/libs.versions.toml
  app/
    build.gradle.kts
    src/main/
      AndroidManifest.xml
      java/com/pinkhouse/android/
        MainActivity.kt
        PinkHouseApplication.kt
        core/
          datastore/
          navigation/
          ui/
        data/local/
        domain/model/
        feature/
          wardrobe/
          pet/
          smallworld/
          wealth/
          vip/
          settings/
```

## macOS 开发环境

1. 安装 Android Studio。
2. 安装 JDK 17。Android Studio 自带 JBR 通常也可用于 Gradle。
3. 在 Android Studio 中打开本目录：`/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/android`。
4. 安装 Android SDK Platform 35、Android SDK Build-Tools、Android SDK Platform-Tools。
5. 首次打开后让 Android Studio 执行 Gradle Sync。

当前仓库没有提交 Gradle Wrapper，因为本机没有 Java/Gradle 环境，无法安全生成 wrapper。装好环境后可在 `android/` 下生成：

```bash
gradle wrapper --gradle-version 8.10.2 --distribution-type bin
```

生成后再使用 `./gradlew` 执行下面命令。

## Debug 构建

```bash
cd "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/android"
./gradlew :app:assembleDebug
```

Debug 包输出位置：

```text
android/app/build/outputs/apk/debug/
```

## Release APK / AAB

未配置签名时可先产出未签名 release 产物用于本地验证：

```bash
./gradlew :app:assembleRelease
./gradlew :app:bundleRelease
```

Release APK / AAB 输出位置：

```text
android/app/build/outputs/apk/release/
android/app/build/outputs/bundle/release/
```

## 本地签名配置

不要提交 keystore、密码或 `keystore.properties`。它们已在 `android/.gitignore` 中排除。

本地生成 keystore 示例：

```bash
keytool -genkeypair \
  -v \
  -keystore pink_house_release.jks \
  -alias pink_house \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

在 `android/keystore.properties` 中填写本地配置：

```properties
storeFile=pink_house_release.jks
storePassword=your_store_password
keyAlias=pink_house
keyPassword=your_key_password
```

配置后再执行：

```bash
./gradlew :app:assembleRelease
./gradlew :app:bundleRelease
```

## 当前 App 壳

- `MainActivity` 使用 Compose 启动 `PinkHouseApp`。
- `PinkHouseTheme` 提供 Material 3 浅色/深色基础配色。
- 底部导航包含 `Wardrobe`、`Pet`、`World`、`Wealth`、`VIP`、`Settings` 六个占位入口。
- `PinkHouseDatabase` 已建立 Room v1 数据库和 `wardrobe_item` 最小表。
- `UserPreferencesDataStore` 已预留主题、衣橱视图模式、音效、震动、语言设置。

## 后续开发注意

- 按 PRD，Android 版不接 AI、不接云同步、不依赖 GMS。
- 国内渠道合规需要补隐私政策/用户协议弹窗、个人信息收集清单、通知权限解释。
- Weather 需求在 PRD 中存在“需要粗略定位”和“权限不申请位置”的冲突，正式实现前需要产品侧确认策略。
- Room schema 输出目录为 `app/schemas/`，后续数据库变更要提交 schema 并补 migration。
