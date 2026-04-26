# Android Migration · Notice Center 通知中心

## BATCH-M4-03A NoticeCenterRoute UI 入口 + 已读/确认交互

**背景**

- iOS 母本：`ItemManager/Views/Notice/NoticeView.swift`、`NoticePopupView.swift` 与 `Models/Notice.swift`。
- iOS 公告卡包含媒体区域、严重级别 badge、标题、摘要、正文、发布时间，以及 `requiresAck` / `isPinned` / `channel` 等状态。
- Android 本批先做 House 内通知中心 UI 与会话内交互；不接 CloudKit，不改 Room schema，不做系统通知权限。

**改动范围**

- `feature/notice/NoticeCenterRoute.kt`（新建）
  - 新增 `通知中心` 首屏：顶部统计 `未读 / 需确认 / 全部`。
  - 新增 `全部 / 未读 / 需确认` 分段筛选。
  - 新增 Notice 卡片：媒体占位区、`INFO / IMPORTANT / CRITICAL`、`收件箱 / 横幅 / 弹窗`、`ACK`、置顶图标、标题、摘要、发布时间。
  - 支持会话内 `标记已读` 与 `我已知晓`，点卡片会展开正文并标记已读。
  - 当前使用本地样例公告，后续 schema 批再换成 `local_notification` 查询。
- `feature/smallworld/SmallWorldRoute.kt`
  - House 菜单新增 `通知中心` 目的地。
  - `SmallWorldDestination.NoticeCenter` 接入 `NoticeCenterRoute()`。
  - 已复刻独立页继续隐藏通用占位卡，保持 UI 纯净。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：本批业务文件无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中；`git diff --check` 通过。
- Android Emulator 装机验证：
  - `House → 菜单 → 通知中心` 可见 `通知中心`、`未读`、`需确认`、`全部` 与公告卡 `梦裙日历已接入`。
  - 切到 `需确认` 可见 `UI 还原度优化进行中`、`CRITICAL`、`ACK` 与 `我已知晓`。
- 截图记录：
  - `/tmp/pinkhouse_m4_03a_notice_home.png`
  - `/tmp/pinkhouse_m4_03a_notice_ack.png`

**后续待办**

- `BATCH-M4-03B`：单独 Room schema 批，新增 `local_notification` 表与 v4 migration。
- `BATCH-M4-03C`：NoticeCenterRoute 改读本地表，并持久化已读 / ACK 状态。
- 弹窗治理：后续如做自动弹窗，必须按每日入口治理规则限制自动展示频率。


## BATCH-UX-COPY-01A 用户侧文案清理（通知中心 / House）

**触发原因**

- 用户指出：用户能看到的界面不能出现迁移进度、内部实现、后续批次等开发侧内容，也不需要置顶标识。

**改动范围**

- `NoticeCenterRoute.kt`
  - 移除所有样例公告，当前无真实公告数据时只展示用户侧空状态：`暂无公告`、`有新消息时会显示在这里`。
  - 移除置顶图标展示，不再出现 `PIN`/置顶语义。
  - 将严重级别从英文 `INFO / IMPORTANT / CRITICAL` 改为中文 `普通 / 重要 / 紧急`；确认状态显示 `需确认 / 已确认`。
- `SmallWorldRoute.kt`
  - 清理 House 菜单和未完成页里的开发侧文案，替换成用户侧说明，例如 `功能准备中`、`从这里进入小世界、日历、通知和更多工具`。
  - 小世界主图说明不再出现“已接入 / 下一批 / 复刻”等内部词。

**验证结果**

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug` 通过。
- 红线 grep：本批业务文件无 `0xFF...`、`.sp`、`Modifier.blur`、`Firebase`、`dynamicColor` 命中；`git diff --check` 通过。
- 装机检查：通知中心页面不再出现 `Android`、`后续`、`复刻`、`已接入`、`schema`、`local_notification`、`置顶`、`梦裙日历已接入`、`UI 还原度` 等开发侧可见文案。
