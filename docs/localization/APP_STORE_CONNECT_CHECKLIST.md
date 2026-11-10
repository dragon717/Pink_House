# App Store Connect 全球扩区 Checklist

> 用途：在 ASC 后台逐项勾选，配合 [LOCALE_MATRIX.md](./LOCALE_MATRIX.md) 记录 `last_checked`。  
> App ID：`6758352161` | Bundle ID：`bugod2.ItemManager`。当前候选版本与执行状态见[上架记录](./runs/2026-11-03/RESULT.md)。
> 2026-11-04 发布决定：**4.4（2）禁止正式提审**。4.4（3）本地 StoreKit 防重测试 2/2 通过，01:15:31（北京时间）上传成功，TestFlight 后台已列出构建 3，状态为「准备提交」。海外版本尚未提审，TestFlight 实购、生产购买及地区开放待后台完成。[核验记录](./runs/2026-11-03/RESULT.md)

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
| 1.1 | 中国大陆保持已选 | 已核 | 后台为 1/175 可供应，公开目录仅中国大陆有结果。 |
| 1.2 | 勾选全部可售国家和地区 | ☐ | 保留已有地区，先核对 ASC 提示和待补材料，逐区记录例外 |
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
| 2.1 | Type = **Consumable** | 六档均已核实。 |
| 2.2 | Status = Ready to Submit / Approved | 六个商品本身均为已批准。新增语言另有审核状态。 |
| 2.3 | **Availability** 与预计开放范围一致 | 主 App 为 1/175，六档内购均为相同的 133/175。未选的 42 个地区见[后台核验表](./runs/2026-11-03/RESULT.md#六档喵币的后台状态2026-11-04)。 |
| 2.4 | **Price Schedule** 已设且全球 storefront 生效 | 美国商店已拉取全部 6 档 USD 显示价，全球价格安排待后台核对。[拉取记录](../../output/app-store-4.4/proof/us-storekit-products.txt) |
| 2.5 | 各 metadata 语言 Display Name + Description | 54 组源稿已备，49 组已在后台回读。300 档仍有 5 语待解锁后录入。逐档审核状态见[逐档记录](./runs/2026-11-03/RESULT.md#六档喵币的后台状态2026-11-04)。 |
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

[九语商店填报包](../../output/app-store-4.4/少女心愿-4.4-九语商店资料.zip)已校验。4.4 九语商品页、名称和副标题已在后台保存并刷新回读。

| # | 项 | 状态 | 源稿 |
|---|-----|------|------|
| 5.1 | en 全套 metadata + 截图 | 文案已保存，含 Duo 的 14 张图已逐槽回读 | [app-store-metadata/en/](./app-store-metadata/en/) |
| 5.2 | zh-Hant 全套 | 文案已保存，含 Duo 的 14 张图已逐槽回读 | [app-store-metadata/zh-Hant/](./app-store-metadata/zh-Hant/) |
| 5.3 | ja / ko | 商品页已保存，iPad 槽已回读「使用现有素材」与三张图。六档内购见 2.5 | 各语言目录 |
| 5.4 | fr / de / es / pt-BR | 商品页已保存，iPad 槽已回读「使用现有素材」与三张图。六档内购见 2.5 | 各语言目录 |
| 5.5 | 截图 UI 语言与 metadata 语言一致 | 简中 15 张、繁中和英文各 14 张，均已上传并回读 | [43 张截图包](../../output/app-store-4.4/少女心愿-4.4-商店截图.zip) |

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
