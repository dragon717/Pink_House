# 全球扩区发布 Gate 与提交记录

> P0/P1 通过后方可 Submit；本文件记录扩区决策与 build 对照  
> 更新：2026-07-03

---

## 1. Gate 定义

### P0 — 阻断（任一未过 = 禁止扩区）

| # | 条件 | 证据 | Pass |
|---|------|------|------|
| P0.1 | Paid Apps Agreement Active | ASC screenshot | ☐ |
| P0.2 | 六 IAP 全球 Availability = App | ASC diff | ☐ |
| P0.3 | Privacy URL 全球 200 | curl en/privacy | ☐ |
| P0.4 | App Privacy / Age / Export 已更新 | Phase 4 checklist | ☐ |
| P0.5 | US Sandbox 至少 2 档 IAP 购买成功 | sandbox-iap-result | ☐ |

### P1 — 限制（P0 全过但 P1 未全过 = 可缩区发布，不建议一次性全球）

| # | 条件 | Pass |
|---|------|------|
| P1.1 | en metadata + 截图完成 | ☐ |
| P1.2 | zh-Hant metadata + 截图完成 | ☐ |
| P1.3 | IAP 各语言 Display Name/Description 已粘贴 | ☐ |
| P1.4 | Review Notes 已粘贴 | ☐ |
| P1.5 | KR/VN Legal 签字或明确排除这两国 | ☐ |
| P1.6 | en 系统语言下 P0 页面无大块中文混语（知悉 ~1220 硬编码风险） | ☐ |

### P2 — 可接受债务

| # | 条件 | 登记 |
|---|------|------|
| P2.1 | ja/ko/fr/de/es/pt-BR App 内翻译不全 | fallback en，后续版本 |
| P2.2 | Widget 中文 | 后续版本 |
| P2.3 | 非核心页混语 | STRING_AUDIT backlog |

---

## 2. 提交策略

### 选项 A — 仅扩 Availability（无 binary 变更）

- 适用：metadata/IAP 区域已在 ASC 配好，当前 approved build 不变  
- ASC：Pricing and Availability → Save  
- 风险：App 内语言可能与新区 metadata 不一致  

### 选项 B — 新版本 + 全球扩区（推荐）

| 字段 | 值 |
|------|-----|
| Marketing Version | 2.8.x |
| Build | 递增 CURRENT_PROJECT_VERSION |
| 变更说明 | Global availability, localization, IAP metadata |
| What's New | 见 [app-store-metadata/en/metadata.md](./app-store-metadata/en/metadata.md) |

---

## 3. 提交记录模板

```markdown
## Submission — YYYY-MM-DD

| 字段 | 值 |
|------|-----|
| ASC Version | |
| Build | |
| Submission ID | |
| Regions | All except [exclusions] |
| Metadata languages | en, zh-Hant, ja, ko, fr, de, es, pt-BR |
| Binary languages shipped | en, zh-Hans, zh-Hant (+ partial others) |
| Review Notes version | APP_REVIEW_NOTES_GLOBAL.md 2026-07-03 |
| Sandbox evidence | runs/YYYY-MM-DD/sandbox-iap-result.md |

### Excluded storefronts (if any)
- KR: Wait_Legal — reason:
- VN: Wait_Legal — reason:

### Outcome
- [ ] Waiting for Review
- [ ] In Review
- [ ] Approved
- [ ] Rejected — reason:
```

---

## 4. 扩区后监控（首 72 小时）

| # | 监控项 |
|---|--------|
| 4.1 | App Analytics 新 storefront 下载 |
| 4.2 | IAP 收入按 storefront 分布 |
| 4.3 | 审核反馈 / 用户评论（语言、IAP、VIP 误解） |
| 4.4 | Support 邮箱 huangsangmuniao@126.com |

---

## 5. 当前决策（2026-07-03）

| 项 | 决策 |
|----|------|
| 目标 | 除 CN 外 **全部** ASC 可选地区 |
| KR / VN | **Wait_Legal** — 建议法务 clearance 前在 Gate 表排除或暂缓勾选 |
| 推荐提交 | **选项 B** — 2.8.x + en/zh-Hant metadata + IAP 全球 |
| P0 状态 | 文档与英文协议已备；**ASC 操作与 Sandbox 待人工执行** |

---

## 6. 关联 checklist

- [APP_STORE_CONNECT_CHECKLIST.md](./APP_STORE_CONNECT_CHECKLIST.md)
- [APP_AVAILABILITY_EXPAND.md](./APP_AVAILABILITY_EXPAND.md)
- [SANDBOX_GLOBAL_IAP_ACCEPTANCE.md](./SANDBOX_GLOBAL_IAP_ACCEPTANCE.md)
