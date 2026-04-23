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
        data/repository/
        domain/model/
        domain/repository/
        domain/usecase/
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
- 底部导航已对齐 iOS 为 `衣橱`、`House`、`我`、`萌宠对话` 四个入口。
- `PinkHouseDatabase` 已升级到 Room v3，`wardrobe_item` 支持图片、标签、小物、心愿尾款、软删除、回收站和详情编辑所需字段。
- `UserPreferencesDataStore` 已预留主题、衣橱视图模式、音效、震动、语言设置。

## 衣橱 MVP 状态

当前衣橱页已经从占位页推进到本地 Room 驱动的衣橱闭环雏形：

- `WardrobeItemEntity` 与 `WardrobeItem` 已通过 mapper 转换，价格以 cents 存储、日期以 epoch day 存储、状态以枚举名存储。
- `WardrobeItemDao` 支持观察未删除衣物、详情读取、回收站读取、插入、批量插入、更新、软删除、恢复和彻底删除。
- `WardrobeRepository` / `RoomWardrobeRepository` 已建立，业务入口通过 `GetWardrobeItems`、`AddSampleWardrobeItems` usecase 暴露。
- 暂未引入 Hilt；`PinkHouseApplication` 持有简单 `AppContainer`，再传入 `PinkHouseApp` 和 `WardrobeRoute`。
- `WardrobeRoute` 支持少女衣橱/心愿尾款切换、排序、筛选、布局切换、详情、编辑、手动创建、批量导入、批量软删除、回收站和本地尾款提醒设置。
- 原项目开屏、Logo、猫咪探头、宠物头像、小世界/VIP/喵金币等资产已迁入 Android 资源目录，并由 `PinkHouseAssets` 统一引用。

首次 Android Studio Sync 后重点关注：

- Room KSP 是否生成 `app/schemas/` 下的 v1 schema，若生成需要纳入版本管理。
- `collectAsStateWithLifecycle`、Material 3 Compose API 与当前 BOM 版本是否匹配。
- 示例数据按钮当前每次点击都会追加一组测试衣物，后续接真实新增页时需要替换为表单或去重策略。
- 当前搜索只按衣物名称模糊匹配，后续再扩展分类、品牌、颜色、标签和筛选。

## 后续开发注意

- 按 PRD，Android 版不接 AI、不接云同步、不依赖 GMS。
- 国内渠道合规需要补隐私政策/用户协议弹窗、个人信息收集清单、通知权限解释。
- Weather 需求在 PRD 中存在“需要粗略定位”和“权限不申请位置”的冲突，正式实现前需要产品侧确认策略。
- Room schema 输出目录为 `app/schemas/`，后续数据库变更要提交 schema 并补 migration。
- 视觉/交互复刻要求使用 Computer Use 对照 iOS Simulator 与 Android Studio 模拟器，不能只凭代码完成验收。
