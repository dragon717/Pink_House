# EXEC_PLAN — 产品框架体验

## 0. 启动协议

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
FEATURE_ID="product_framework_experience"
FEATURE_DIR="$PROJ/temp/产品框架体验"
ARTIFACT_ROOT="$FEATURE_DIR/_artifacts"
```

执行前必须确认：

```bash
cd "$PROJ"
git status --short
```

若存在无关改动，只修改并 stage 本专项文件；不要执行 `git add .`。

## 1. 必读上下文

1. `ItemManager/Views/MainTabView.swift`
2. `ItemManager/Utilities/TabNavigationManager.swift`
3. `ItemManager/Models/AppFeatureRegistry.swift`
4. `ItemManager/Views/FavoriteMenuSettingsView.swift`
5. `ItemManager/Views/SmallWorldMenuOverlay.swift`（仅保留 House 底栏 fallback frame 兼容工具）
6. `ItemManager/Models/SmallWorldDestination.swift`
7. `ItemManager/Services/FeatureUnlockManager.swift`
8. `ItemManager/Views/MeView.swift`
9. `temp/产品框架体验/MANIFEST.yaml`

## 2. 框架原则

- 功能先进入统一 `Feature Registry`，再决定是否展示在底栏、House 房间、萌宠手机或搜索/AI。
- 底部 4 个位置都可调整，默认顺序为：衣橱、House、我、萌宠对话。
- House 和我作为安全入口必须保留，但可以换位置；选择重复入口时做槽位互换。
- House 长按快捷菜单下线；高频入口收敛到底部导航或 House 房间内可见入口，旧新手引导不得再依赖长按菜单配置。
- P2/P3 如需新美术，用 image2 生成正式素材，不使用透明占位。

## 3. 实施顺序

### P0 — Feature Registry

- 新增功能入口模型，字段包含：稳定 id、标题、副标题、SF Symbol、颜色、路由、解锁项、展示容器。
- 路由覆盖：主 Tab、衣橱二级 Tab、House 子目的地。
- 在 `TabNavigationManager` 中增加按 feature id 导航的方法。

### P1 — 自定义底部导航

- 新增底部导航布局设置管理器，持久化 key 使用新 key，不复用常用菜单历史，并兼容旧最右侧快捷入口 key。
- `MainTabView` 4 个底栏槽位都改为读取用户选择。
- `FavoriteMenuSettingsView` 只保留“底部导航”设置区，不再暴露 House 长按菜单配置。
- `MeView` 入口文案改为“底部导航”。
- `SmallWorldMenuOverlay.swift` 不再挂载长按触发区，仅保留 `buildFallbackFrame` 供新手引导定位 House 底栏。

### P2 — 等轴手帐房间 MVP

- 等 P0/P1 稳定后执行。
- 只做固定布局和热区，不做拖拽装修。
- 若需要背景图，先生成 image2 素材并入库。

### P3 — 萌宠手机 MVP

- 等 P0/P1 稳定后执行。
- 只做手机壳和原生入口网格。
- HTML/音乐外链先保留为安全占位。

## 4. 自测

```bash
cd "$PROJ"
git diff --check
rg -n "bottomDockSelectedFeature|AppFeatureRegistry|底部导航" ItemManager temp/产品框架体验
rg -n "House 长按|长按 House|常用菜单|smallWorldQuickMenuOpened" ItemManager/Views ItemManager/Services
```

iOS 构建按项目约束默认不跑；如用户明确要求真实流程截图，先记录 AGENTS 约束，再由用户编译或授权后安装模拟器截图。

## 5. 交付记录

每轮自测写入：

```text
temp/产品框架体验/_artifacts/runs/<YYYYmmdd-HHMM>/RESULT.md
```

内容必须包含：

- commit hash
- 修改文件
- 自测命令
- 是否跑构建/模拟器
- 截图清单或未截图原因
