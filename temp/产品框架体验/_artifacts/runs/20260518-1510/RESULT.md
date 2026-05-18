# 自测结果 — 产品框架体验 2026-05-18 15:10

状态：PARTIAL
COMMIT: 见本轮最终 `git log -1 --oneline`

## 本轮范围

- 建立 `temp/产品框架体验/` harness。
- 新增 `AppFeatureRegistry` 与 `BottomDockSettingsManager`。
- `MainTabView` 底部最右侧入口改为用户可配置，默认仍为“萌宠对话”。
- “我”页入口从“常用菜单”升级为“常用入口”。
- `FavoriteMenuSettingsView` 顶部增加“底部快捷入口”，下方保留 House 长按菜单配置。
- 同步魔法贴纸引导文案里的“常用入口”命名。

## 静态检查

- `git diff --check`：PASS
- `rg -n "AppFeatureRegistry|BottomDockSettingsManager|bottomDockSelectedFeature|常用入口|底部快捷入口" ItemManager temp/产品框架体验`：PASS

## 构建与截图

- iOS 构建：未跑。原因：项目 `AGENTS.md` 明确要求 iOS 开发默认不使用 `xcodebuild`，由用户自行编译并反馈错误。
- 真实产品流程截图：未截图。原因：本轮未安装新构建到模拟器。
- image2 素材：未使用。本轮 P0/P1 不需要新增美术素材；P2 等轴手帐房间和 P3 萌宠手机如进入实现，会按 `MANIFEST.yaml` 的素材 backlog 使用 image2。

## 待验收流程

1. 启动 app，确认底部最右侧默认是“萌宠对话”。
2. 进入“我 → 常用入口”。
3. 在“底部快捷入口”选择“心愿尾款”。
4. 回首页，确认底部最右侧变为“心愿尾款”。
5. 点击底部“心愿尾款”，确认进入衣橱页的心愿尾款 Tab。
6. 回“常用入口”，确认 House 长按菜单配置仍存在。
7. 长按 House，确认原常用菜单仍可打开。
