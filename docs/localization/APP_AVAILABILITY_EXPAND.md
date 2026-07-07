# App 全球可用性扩区操作指南

> 对应 checklist Phase 1；中国大陆已 Live，本指南用于 **开放其余全部地区**  
> 更新时间：2026-07-03

## 目标状态

| 对象 | CN | 全球其余 |
|------|-----|----------|
| App | ✅ 已上线 | ☐ 待勾选 |
| 6 × IAP Consumable | ✅ | ☐ 与 App 同步 |
| 6 × Offer Code | ✅（含 CHN） | ☐ 扩至全部 storefront |

## ASC 操作步骤

### Step 1 — 导出当前配置（扩区前存档）

1. App Store Connect → **Apps** → Pink House  
2. **Pricing and Availability** → 截图或记录当前已选地区  
3. 每个 IAP → **Availability** → 截图当前国家列表  

### Step 2 — 扩展 App 可用性

1. **Pricing and Availability** → **Manage Availability**  
2. **保留** 中国大陆勾选  
3. 点击 **Select All**（或逐洲勾选除已禁售地区外全部）  
4. **Save**  
5. 确认 **Distribution** = 标准 App Store 分发  

### Step 3 — 同步六个 IAP

对每个 Product ID（见 [iap-localizations.md](./app-store-metadata/iap-localizations.md)）：

1. In-App Purchases → 选择商品  
2. **Availability** → 与 App **完全相同** 的国家列表  
3. **Price Schedule** → 确认 Base Country 与 Tier 已设（CNY 锚价已存在则从 CN 扩展即可）  
4. Save  

**验证**：随机抽 3 个 IAP，Availability 国家数 = App Availability 国家数。

### Step 4 — 同步六个 Offer Code

对每个 `gift_*_meow_v1`：

1. IAP → Offers → 编辑 Free Offer  
2. **Countries or Regions** → 从仅 CHN 改为 **与 App 一致**  
3. Save  

### Step 5 — 交叉 diff 清单

| # | 检查 | Pass |
|---|------|------|
| 5.1 | App 可用国家 ⊇ IAP 可用国家（应相等） | ☐ |
| 5.2 | Offer 可用国家 ⊇ IAP 可用国家（若启用 Offer） | ☐ |
| 5.3 | 无「App 全球 / IAP 仅 CN」不一致 | ☐ |
| 5.4 | 已更新 [LOCALE_MATRIX.md](./LOCALE_MATRIX.md) last_checked | ☐ |

## 无需新二进制的情况

若 **仅扩可用性、metadata、IAP 区域** 且无 binary 变更：

- 可在 ASC 对 **当前已批准版本** 扩展 availability（Apple 允许部分 metadata/availability 无需新版本）  
- 若同时提交新 localization 截图或 binary 语言包，需 **新版本** 提审  

> 以 ASC 当前 UI 提示为准；若有 doubt，准备 2.8.x build 一并提交。

## 禁选地区

跟随 Apple 列表：**不要** 手动勾选 Apple 已移除的 storefront（如部分制裁地区）。见 [LOCALE_MATRIX.md](./LOCALE_MATRIX.md) 俄罗斯条目。

## 扩区后 smoke test

见 [SANDBOX_GLOBAL_IAP_ACCEPTANCE.md](./SANDBOX_GLOBAL_IAP_ACCEPTANCE.md) — 至少 US storefront Sandbox 购买一档 IAP。
