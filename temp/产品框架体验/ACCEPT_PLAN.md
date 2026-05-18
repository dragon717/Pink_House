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
rg -n "常用入口|底部快捷入口" ItemManager/Views temp/产品框架体验
```

期望：

- 有统一功能入口模型。
- 有底部快捷入口设置管理器。
- `MainTabView` 读取底部快捷入口。
- `FavoriteMenuSettingsView` 同时保留 House 长按菜单配置。
- 未改 `ThemeSkinSlot.rawValue`、SwiftData schema、IAP 商品、UserDefaults 旧 key。

## 2. P0/P1 真实流程验收

截图目录：

```bash
DIR="$ARTIFACT_ROOT/accept/$(date +%Y%m%d-%H%M)"
mkdir -p "$DIR"
```

验收路径：

1. 启动 app，确认底部最右侧默认是“萌宠对话”。
2. 进入“我 → 常用入口”。
3. 在“底部快捷入口”选择“心愿尾款”（若来财已解锁，也可额外选择来财做增强截图）。
4. 回首页，确认底部最右侧变为“心愿尾款”。
5. 点击“心愿尾款”，确认进入衣橱页的心愿尾款 Tab。
6. 回“常用入口”，确认 House 长按菜单配置仍存在。
7. 长按 House，确认原常用菜单仍可打开。

截图建议：

- `A_default_pet_chat_tab.png`
- `B_common_entry_settings.png`
- `C_select_deposit_dock.png`
- `D_deposit_tab_visible.png`
- `E_deposit_opened.png`
- `F_house_favorite_menu.png`

## 3. RESULT.md 模板

```markdown
# 验收结果 — 产品框架体验 <YYYY-mm-dd HH:MM>
状态：PASS / PARTIAL / FAIL
COMMIT: <git rev-parse HEAD>

## 静态检查
- git diff --check HEAD~1：PASS / FAIL
- Feature Registry：PASS / FAIL
- 底部快捷入口设置：PASS / FAIL

## 真实流程截图
| 步骤 | 状态 | 截图 | 备注 |
|---|---|---|---|
| A 默认萌宠对话 | | A_default_pet_chat_tab.png | |
| B 常用入口设置 | | B_common_entry_settings.png | |
| C 选择心愿尾款 | | C_select_deposit_dock.png | |
| D 底栏变为心愿尾款 | | D_deposit_tab_visible.png | |
| E 打开心愿尾款 | | E_deposit_opened.png | |
| F House 常用菜单 | | F_house_favorite_menu.png | |

## 不通过项
- 无 / <列出问题>
```

## 4. 判定

- P0/P1 全通过：PASS，可进入 P2 等轴手帐房间 MVP。
- 底部入口可用但长按菜单异常：PARTIAL，先修兼容。
- 无法导航或设置不持久：FAIL，回退修复。
