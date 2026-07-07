# LOCALE_MATRIX — Pink_House 全球 storefront 四轨矩阵

> 每条 storefront 记录四条轨道：可用性 / Metadata / Binary / 合规  
> `last_checked` 格式：YYYY-MM-DD  
> 更新时间：2026-07-03

## 图例

| availability_decision | 含义 |
|---------------------|------|
| Available | 计划开放 |
| Wait_Legal | 待法务确认 |
| Blocked | 暂不开放 |
| Live_CN | 已在中国大陆上线 |

| risk_level | 含义 |
|------------|------|
| Low | 标准 ASC 配置即可 |
| Medium | 需本地化 metadata + 隐私 |
| High | 需地区许可或分级 |
| Blocked | 不建议开放直至 clearance |

---

## 全球默认策略（2026-07-03）

| 字段 | 值 |
|------|-----|
| launch_wave | Global（除已 Live 的 CN） |
| availability_decision | Available（待 ASC 勾选） |
| metadata_languages | en + zh-Hant + ja + ko + fr + de + es + pt-BR |
| binary_languages | en, zh-Hans, zh-Hant（Gate-0）；ja/ko/fr/de/es/pt-BR 部分（fallback en） |
| iap_availability | 与 App 一致（六档 consumable） |
| owner | Product / iOS / Legal / Finance |

**执行动作**：ASC → Pricing and Availability → 保留 CN → Select All 其余地区 → 六个 IAP Availability 同步 → 六个 Offer 扩区。详见 [APP_STORE_CONNECT_CHECKLIST.md](./APP_STORE_CONNECT_CHECKLIST.md) Phase 1–3。

---

## 地区专项法务结论（需 Legal 签字）

> 以下基于公开监管框架与 App 特性（衣橱 + 虚拟宠物 + 虚拟货币 IAP + AI 聊天 + UGC 衣橱/手帐）的**初步研判**，不构成法律意见；正式扩区前建议当地律师确认。

### 欧盟 / 英国（EU/UK）

| 字段 | 结论 |
|------|------|
| risk_level | Medium |
| availability_decision | Available |
| 监管要点 | GDPR（数据处理、删除权）、DSA（ trader 信息若适用）、数字商品消费者保护 |
| 无代码动作 | Privacy 英文版上线；Support URL 可达；Contact 邮箱响应；ASC Privacy 标签与 manifest 一致 |
| owner | Legal |
| last_checked | 2026-07-03 |
| 签字 | ☐ Legal |

### 韩国（KR）

| 字段 | 结论 |
|------|------|
| risk_level | **High** |
| availability_decision | **Wait_Legal** |
| 监管要点 | GRAC 游戏物分级；含虚拟宠物养成 + 虚拟货币可能被归类为「游戏」 |
| 无代码动作 | 1) 确认 App Store 年龄问卷分类；2) 咨询是否需 GRAC 评级或可按「生活/工具」归类；3) 韩文 metadata + 客服 |
| owner | Legal |
| last_checked | 2026-07-03 |
| 签字 | ☐ Legal |
| **建议** | 法务 clearance 前可在 ASC 暂不排除 KR，但 **P0 Gate 将 KR 标为 Wait_Legal** |

### 越南（VN）

| 字段 | 结论 |
|------|------|
| risk_level | **High** |
| availability_decision | **Wait_Legal** |
| 监管要点 | 在线游戏发行许可（虚拟宠物 + IAP 养成要素） |
| 无代码动作 | 咨询当地 partner 是否需要许可；准备越南语 metadata 或 en fallback |
| owner | Legal |
| last_checked | 2026-07-03 |
| 签字 | ☐ Legal |

### 日本（JP）

| 字段 | 结论 |
|------|------|
| risk_level | Medium |
| availability_decision | Available |
| 监管要点 | 特定商取引法、景表法（赠送比例 / 首充双倍表述与 IAP 描述一致） |
| 无代码动作 | ja metadata；IAP 描述不写误导性「抽奖」；Support 日文或英文 |
| owner | Legal / Localization |
| last_checked | 2026-07-03 |

### 巴西（BR）

| 字段 | 结论 |
|------|------|
| risk_level | Medium |
| availability_decision | Available |
| 监管要点 | 消费者保护法、虚拟商品披露 |
| 无代码动作 | pt-BR metadata；Contact 可达 |
| last_checked | 2026-07-03 |

### 台湾（TW）

| 字段 | 结论 |
|------|------|
| risk_level | Low–Medium |
| availability_decision | Available |
| 监管要点 | 消费争议、繁中商品页 |
| 无代码动作 | zh-Hant metadata + 截图 |
| last_checked | 2026-07-03 |

### 香港 / 澳门（HK / MO）

| 字段 | 结论 |
|------|------|
| risk_level | Low |
| availability_decision | Available |
| 无代码动作 | zh-Hant metadata |
| last_checked | 2026-07-03 |

### 美国 / 加拿大 / 澳新（US / CA / AU / NZ）

| 字段 | 结论 |
|------|------|
| risk_level | Low |
| availability_decision | Available |
| 无代码动作 | en metadata；U.S. Tax Form；COPPA 未成年人条款在 Privacy 中 |
| last_checked | 2026-07-03 |

### 俄罗斯及制裁相关地区

| 字段 | 结论 |
|------|------|
| risk_level | Blocked（以 Apple 列表为准） |
| availability_decision | 跟随 ASC 当前可选列表；Apple 已禁售地区勿勾选 |
| last_checked | 2026-07-03 |

### 中国大陆（CN）— 已上线

| 字段 | 结论 |
|------|------|
| availability_decision | **Live_CN** |
| metadata_languages | zh-Hans |
| 备注 | ICP：沪ICP备2026008696号-1A；勿在海外 metadata 强制展示 |
| last_checked | 2026-07-03 |

---

## 四轨状态汇总表（扩区前快照）

| Track | CN | Global（待扩） | 阻塞项 |
|-------|-----|----------------|--------|
| App 可用性 | Live | ☐ ASC 待勾选 | Phase 1 checklist |
| Metadata | zh-Hans 已有 | ☐ en/zh-Hant/ja/ko/… | app-store-metadata/ |
| Binary | 三语 ~56% | ☐ Gate-0 翻译 | translation-gate0/ |
| IAP | 六档 CN 已配 | ☐ 全球 Availability | iap-localizations.md |
| 合规 | ICP | ☐ KR/VN Wait_Legal | 上表 |
| 协议网站 | 中文 | ☐ en 已备稿 | ops/legal-site/en/ |

---

## 变更日志

| 日期 | 变更 | 作者 |
|------|------|------|
| 2026-07-03 | 初版；KR/VN 标 Wait_Legal | Agent |
