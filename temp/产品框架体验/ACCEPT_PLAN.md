# ACCEPT_PLAN — 产品框架体验

## 0. 启动协议

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
FEATURE_DIR="$PROJ/temp/产品框架体验"
ARTIFACT_ROOT="$FEATURE_DIR/_artifacts"
```

验收前确认：

```bash
cd "$PROJ"
git log -1 --oneline
git status --short
```

## 1. P0/P1 静态验收

```bash
cd "$PROJ"
git diff --check HEAD~1
rg -n "AppFeatureRegistry|BottomDockSettingsManager|bottomDockSelectedFeature" ItemManager
rg -n "底部导航" ItemManager/Views temp/产品框架体验
rg -n "House 长按|长按 House|常用菜单|smallWorldQuickMenuOpened" ItemManager/Views ItemManager/Services
```

期望：

- 有统一功能入口模型。
- 有底部导航布局设置管理器。
- `MainTabView` 4 个底栏槽位读取底部导航布局。
- `FavoriteMenuSettingsView` 只展示底部导航配置，不再展示 House 长按菜单配置。
- `MainTabView` 不再挂载 House 长按快捷菜单 overlay。
- 未改 `ThemeSkinSlot.rawValue`、SwiftData schema、IAP 商品、UserDefaults 旧 key。

## 2. P0/P1 真实流程验收

截图目录：

```bash
DIR="$ARTIFACT_ROOT/accept/$(date +%Y%m%d-%H%M)"
mkdir -p "$DIR"
```

验收路径：

1. 启动 app，确认底部默认顺序是“衣橱 / House / 我 / 萌宠对话”。
2. 进入“我 → 底部导航”。
3. 在“底部导航”任意位置选择“心愿尾款”（若来财已解锁，也可额外选择来财做增强截图）。
4. 回首页，确认对应底栏位置变为“心愿尾款”，且 House / 我仍保留。
5. 点击“心愿尾款”，确认进入衣橱页的心愿尾款 Tab。
6. 回“底部导航”，确认页面只提供 4 个底部位置配置；候选项保留「萌宠对话」，不展示「萌宠」主页入口。
7. 长按当前 House 所在底栏位置，确认不会弹出原长按快捷菜单。

截图建议：

- `A_default_pet_chat_tab.png`
- `B_bottom_dock_settings.png`
- `C_select_deposit_dock.png`
- `D_deposit_tab_visible.png`
- `E_deposit_opened.png`
- `F_house_long_press_retired.png`

## 3. RESULT.md 模板

```markdown
# 验收结果 — 产品框架体验 <YYYY-mm-dd HH:MM>
状态：PASS / PARTIAL / FAIL
COMMIT: <git rev-parse HEAD>

## 静态检查
- git diff --check HEAD~1：PASS / FAIL
- Feature Registry：PASS / FAIL
- 底部导航布局设置：PASS / FAIL

## 真实流程截图
| 步骤 | 状态 | 截图 | 备注 |
|---|---|---|---|
| A 默认萌宠对话 | | A_default_pet_chat_tab.png | |
| B 底部导航设置 | | B_bottom_dock_settings.png | |
| C 选择心愿尾款 | | C_select_deposit_dock.png | |
| D 底栏变为心愿尾款 | | D_deposit_tab_visible.png | |
| E 打开心愿尾款 | | E_deposit_opened.png | |
| F House 长按无菜单 | | F_house_long_press_retired.png | |

## 不通过项
- 无 / <列出问题>
```

## 4. 判定

- P0/P1 全通过：PASS，可进入 P2 等轴手帐房间 MVP。
- 底部入口可用但仍出现长按菜单：PARTIAL，先修下线残留。
- 无法导航或设置不持久：FAIL，回退修复。
