# App Store Connect 全球扩区 Checklist

> 用途：在 ASC 后台逐项勾选，配合 [LOCALE_MATRIX.md](./LOCALE_MATRIX.md) 记录 `last_checked`。  
> App ID：`6758352161` | Bundle ID：`bugod2.ItemManager` | 当前 Marketing Version：`2.8`  
> 更新时间：2026-07-03

---

## Phase 0 — 账号与协议（全球收款前提）

路径：**Agreements, Tax, and Banking**

| # | 项 | 状态 | 备注 |
|---|-----|------|------|
| 0.1 | Paid Apps Agreement = **Active** | ☐ | 大陆已上线通常已签；扩区前再确认 |
| 0.2 | Banking 收款账户有效 | ☐ | 支持多币种结算 |
| 0.3 | U.S. Tax Form（W-8BEN / W-8BEN-E）已提交 | ☐ | 非美开发者必做 |
| 0.4 | VAT/GST（欧盟、澳新等）状态已确认 | ☐ | ASC Tax 模块 |
| 0.5 | 联系人、法律实体信息最新 | ☐ | 与协议网站主体一致 |

**阻塞规则**：任一项未完成 → IAP 无法在新增 storefront 销售。

---

## Phase 1 — App 可用性（除大陆外全区）

路径：**Pricing and Availability → Manage Availability**

| # | 项 | 状态 | 备注 |
|---|-----|------|------|
| 1.1 | 中国大陆保持已选 | ☐ | 勿误取消 |
| 1.2 | 勾选 **其余全部** 国家/地区 | ☐ | 或以 Apple 当前列表「Select All」 |
| 1.3 | 分发类型 = 正式版（非 Pre-Order） | ☐ | |
| 1.4 | 记录扩区日期到 LOCALE_MATRIX | ☐ | `last_checked: YYYY-MM-DD` |

路径：**App Information → Availability**

| # | 项 | 状态 |
|---|-----|------|
| 1.5 | 导出当前 availability CSV 存档 | ☐ |
| 1.6 | 确认无「Removed from Sale」误操作 | ☐ |

---

## Phase 2 — 六档 IAP 全球配置

路径：**Apps → Pink House → In-App Purchases**

对每个 consumable 重复下表（Product ID 见 [IAP 元数据模板](./app-store-metadata/iap-localizations.md)）：

| Product ID | CNY 锚价 | Tier 建议 |
|------------|---------|-----------|
| `com.pinkhouse.app.meowcoin_60` | ¥6 | Tier 1 附近 |
| `com.pinkhouse.app.meowcoin_120` | ¥12 | |
| `com.pinkhouse.app.meowcoin_300` | ¥30 | |
| `com.pinkhouse.app.meowcoin_500` | ¥50 | |
| `com.pinkhouse.app.mcoin_1280` | ¥128 | |
| `com.pinkhouse.app.mcoin_3280` | ¥328 | |

### 每个 IAP 勾选项

| # | 项 | 状态 |
|---|-----|------|
| 2.1 | Type = **Consumable** | ☐ ×6 |
| 2.2 | Status = Ready to Submit / Approved | ☐ ×6 |
| 2.3 | **Availability** = 与 App 完全一致（全球） | ☐ ×6 |
| 2.4 | **Price Schedule** 已设且全球 storefront 生效 | ☐ ×6 |
| 2.5 | 各 metadata 语言 Display Name + Description | ☐ 见 iap-localizations.md |
| 2.6 | **Review Screenshot**（App 内购买/使用喵币场景） | ☐ ×6 |
| 2.7 | 与代码 `IAPProduct.swift` Product ID 一致 | ☐ |

**常见失误**：App 已全球，IAP 仍仅 CN → 海外用户看不到购买项。

---

## Phase 3 — Offer Code 全球可用性

路径：每个 IAP → **Offers** → Free Offer（`gift_*_meow_v1`）

| # | 项 | 状态 |
|---|-----|------|
| 3.1 | 6 个 Offer ID 与 [商业化开发书](../商业化开发书.md) 一致 | ☐ |
| 3.2 | 用户资格三项全选 | ☐ |
| 3.3 | **国家/地区** 从 CHN 扩展到全部目标 storefront | ☐ |
| 3.4 | Sandbox Codes 已生成（测试用） | ☐ |
| 3.5 | 生产 Custom / One-Time Codes（按需） | ☐ |

Redeem URL 模板：`https://apps.apple.com/redeem?ctx=offercodes&id=6758352161&code=CODE`

---

## Phase 4 — App Privacy / Age / Export

详见 [APP_PRIVACY_AGE_EXPORT_QUESTIONNAIRE.md](./APP_PRIVACY_AGE_EXPORT_QUESTIONNAIRE.md)

| # | 项 | 状态 |
|---|-----|------|
| 4.1 | App Privacy 与 `PrivacyInfo.xcprivacy` 一致 | ☐ |
| 4.2 | Age Rating 全球问卷已重填（虚拟货币、AI 聊天、UGC） | ☐ |
| 4.3 | Export Compliance 与 `ITSAppUsesNonExemptEncryption=false` 一致 | ☐ |
| 4.4 | Privacy Policy URL = `https://sangsang.online/en/privacy/`（或主站 privacy） | ☐ |
| 4.5 | Support URL = `https://sangsang.online/en/contact/` | ☐ |

---

## Phase 5 — Metadata 与截图

| # | 项 | 状态 | 源稿 |
|---|-----|------|------|
| 5.1 | en 全套 metadata + 截图 | ☐ | [app-store-metadata/en/](./app-store-metadata/en/) |
| 5.2 | zh-Hant 全套 | ☐ | [app-store-metadata/zh-Hant/](./app-store-metadata/zh-Hant/) |
| 5.3 | ja / ko | ☐ | 各语言目录 |
| 5.4 | fr / de / es / pt-BR | ☐ | 各语言目录 |
| 5.5 | 截图 UI 语言与 metadata 语言一致 | ☐ | |

---

## Phase 6 — Review Information

| # | 项 | 状态 |
|---|-----|------|
| 6.1 | Notes 粘贴 [APP_REVIEW_NOTES_GLOBAL.md](./APP_REVIEW_NOTES_GLOBAL.md) | ☐ |
| 6.2 | Demo 账号（若需） | ☐ |
| 6.3 | 联系人电话 / 邮箱 | ☐ |

---

## Phase 7 — 提交前交叉验证

| # | 验证 | 命令/方法 |
|---|------|-----------|
| 7.1 | IAP 可用国家 = App 可用国家 | ASC 导出对比 |
| 7.2 | 美/日/德 Sandbox 六档购买 | [SANDBOX_GLOBAL_IAP_ACCEPTANCE.md](./SANDBOX_GLOBAL_IAP_ACCEPTANCE.md) |
| 7.3 | Privacy URL 全球 200 OK | `curl -fsSIL https://sangsang.online/en/privacy/` |
| 7.4 | P0/P1 Gate | [GLOBAL_SUBMISSION_GATE.md](./GLOBAL_SUBMISSION_GATE.md) |

---

## 完成签字

| 角色 | 姓名 | 日期 | 签字 |
|------|------|------|------|
| Product | | | |
| iOS | | | |
| Finance | | | |
| Legal | | | |
