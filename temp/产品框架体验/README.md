# 产品框架体验 Harness

本 harness 用于把“底部自定义导航、等轴手帐房间、萌宠手机、裙子股市情报站”收束成可持续扩展的产品框架。目标不是一次做完所有酷点子，而是先建立统一入口与真实验收流程。

## 文件结构

```text
temp/产品框架体验/
├── README.md
├── MANIFEST.yaml
├── EXEC_PLAN.md
├── ACCEPT_PLAN.md
└── _artifacts/
    ├── runs/<ts>/      # Codex 自测截图、静态检查记录
    └── accept/<ts>/    # 验收截图、RESULT.md
```

## 范围取舍

本期先做框架：

- P0：统一功能入口模型 `Feature Registry`
- P1：底部导航最右侧支持用户自定义
- P2：House 等轴手帐房间 MVP，只做固定入口与视觉壳
- P3：萌宠手机 MVP，只做手机壳、原生入口网格与聊天入口
- P4：裙子股市外链情报站，先做手动链接观察，不做全网爬虫

本期不做：

- 完整装修系统、多房间、真 3D 房间
- 完整 HTML 小程序平台和外链音乐播放器
- 全量裙子股市爬虫生态
- Live2D 全产品化
- 全页面一次性主题化

## 交付闭环

每轮必须产生：

- 代码或文档变更的 git commit
- `temp/产品框架体验/_artifacts/runs/<ts>/RESULT.md`
- 真实产品流程截图，优先使用模拟器；如按项目约束未运行 iOS 构建，必须在 RESULT 中写清楚
- 验收通过后再归档 `accept/<ts>/RESULT.md`

## 美术素材原则

等轴房间、萌宠手机、主题贴纸如果需要新增美术素材，使用 image2 / imagegen 生成透明 PNG 或背景图。禁止用透明 placeholder 冒充正式素材；如果素材缺失，优先走程序化 fallback 或把素材列入 `MANIFEST.yaml` 的 backlog。
