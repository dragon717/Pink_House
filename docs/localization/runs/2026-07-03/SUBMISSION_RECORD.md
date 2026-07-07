# 全球扩区提交记录

> 模板 — 提交时在 GLOBAL_SUBMISSION_GATE 流程中填写  
> 关联：[GLOBAL_SUBMISSION_GATE.md](../GLOBAL_SUBMISSION_GATE.md)

## Submission — （待填日期）

| 字段 | 值 |
|------|-----|
| ASC Version | 2.8.x |
| Build | |
| Submission ID | |
| Regions | All ASC selectable（CN 已 Live；KR/VN 见 LOCALE_MATRIX） |
| Metadata languages | en, zh-Hans, zh-Hant, ja, ko, fr, de, es, pt-BR |
| Review Notes | APP_REVIEW_NOTES_GLOBAL.md 2026-07-03 |
| Privacy URL (en) | https://sangsang.online/en/privacy/ |
| Support URL (en) | https://sangsang.online/en/contact/ |

### Pre-submit Gate

| Gate | Pass |
|------|------|
| P0.1 Paid Apps Agreement | ☐ |
| P0.2 IAP global availability | ☐ |
| P0.3 Privacy URL 200 | ☐ |
| P0.4 Privacy/Age/Export | ☐ |
| P0.5 US Sandbox IAP | ☐ |
| P1.1 en metadata + screenshots | ☐ |
| P1.2 zh-Hant metadata + screenshots | ☐ |

### Excluded storefronts (if any)

| Storefront | Reason |
|------------|--------|
| KR | Wait_Legal — GRAC 待法务 |
| VN | Wait_Legal — 游戏许可待法务 |

### Outcome

- [ ] Waiting for Review
- [ ] In Review
- [ ] Approved — live date:
- [ ] Rejected — reason:

### Storefront ↔ Build 对照（批准后填写）

| Storefront | First visible build | Notes |
|------------|---------------------|-------|
| US | | |
| JP | | |
| TW | | |
| DE | | |

---

## 文档交付清单（2026-07-03 已完成）

- [x] APP_STORE_CONNECT_CHECKLIST.md  
- [x] APP_AVAILABILITY_EXPAND.md  
- [x] LOCALE_MATRIX.md  
- [x] GLOSSARY.md  
- [x] app-store-metadata/（9 语 + IAP）  
- [x] APP_REVIEW_NOTES_GLOBAL.md  
- [x] APP_PRIVACY_AGE_EXPORT_QUESTIONNAIRE.md  
- [x] SANDBOX_GLOBAL_IAP_ACCEPTANCE.md  
- [x] GLOBAL_SUBMISSION_GATE.md  
- [x] ops/legal-site/en/*  
- [x] translation-gate0/（InfoPlist 模板 + P0 audit）  
- [x] SCREENSHOT_CAPTURE_GUIDE.md  

**待人工在 ASC / 真机执行**：勾选 availability、Sandbox 购买、上传截图、Submit。
