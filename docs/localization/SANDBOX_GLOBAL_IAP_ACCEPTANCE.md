# 全球 Sandbox IAP 验收脚本

> 目标 storefront：**US（P0）**、**JP**、**DE（EU 代表）**  
> 环境：Sandbox Tester + 真机或 Simulator + 测试模式 **关闭**  
> 更新：2026-07-03

---

## 0. 前置条件

| # | 项 | Pass |
|---|-----|------|
| 0.1 | 六个 IAP 在 ASC Status = Ready/Approved | ☐ |
| 0.2 | IAP Availability 含测试 storefront | ☐ |
| 0.3 | Sandbox Tester 已创建（**非**大陆生产 Apple ID） | ☐ |
| 0.4 | 设备 Settings → App Store → Sandbox Account 已登录 | ☐ |
| 0.5 | App `IAPTestManager` 测试模式 = **关** | ☐ |

### 创建 Sandbox Tester 建议

| Storefront | 建议地区 | 用途 |
|------------|----------|------|
| US | United States | P0 全球默认 |
| JP | Japan | 日韩 + 价格 JPY |
| DE | Germany | 欧盟 + 价格 EUR |

---

## 1. Storefront 与价格显示

| # | 步骤 | 预期 | US | JP | DE |
|---|------|------|----|----|-----|
| 1.1 | 安装 App，打开喵币商店 | 显示 6 档商品 | ☐ | ☐ | ☐ |
| 1.2 | 价格格式 | `Product.displayPrice` 本地货币（$ / ¥ / €） | ☐ | ☐ | ☐ |
| 1.3 | 切换 Sandbox 账号地区后重启 App | 价格刷新 | ☐ | ☐ | ☐ |

---

## 2. 六档购买（每 storefront 至少测 2 档）

建议每区测：**meowcoin_60**（小档）+ **meowcoin_500**（热门档）

| Product ID | 基础喵币 | 首购预期 | 复购 bonus |
|------------|---------|----------|------------|
| meowcoin_60 | 60 | 120 | +6 (10%) |
| meowcoin_120 | 120 | 240 | +12 |
| meowcoin_300 | 300 | 600 | +30 |
| meowcoin_500 | 500 | 1000 | +75 (15%) |
| mcoin_1280 | 1280 | 2560 | +320 (25%) |
| mcoin_3280 | 3280 | 6560 | +1148 (35%) |

### 记录表（复制使用）

```
Storefront: ______  Date: ______  Build: 2.8 (___)  Tester: ______

| Tier | Purchase OK | Balance Δ | First-double OK | finish() OK |
|------|-------------|-----------|-----------------|-------------|
| 60   |             |           |                 |             |
| 500  |             |           |                 |             |
```

| # | 步骤 | 预期 | Pass |
|---|------|------|------|
| 2.1 | 购买 meowcoin_60 | Sandbox 弹窗 → Success | ☐ |
| 2.2 | 余额增加 | 首购 +120 或复购 +66 | ☐ |
| 2.3 | 再次购买同档 | 首充双倍不再触发；有 bonus | ☐ |
| 2.4 | `transaction.finish` | 无重复到账 | ☐ |

---

## 3. VIP 兑换（喵币消费，非 IAP）

| # | 步骤 | 预期 | Pass |
|---|------|------|------|
| 3.1 | 我 → VIP 中心 | 显示喵币兑换入口 | ☐ |
| 3.2 | 兑换 1 个月（66 喵币） | VIP 生效，余额 -66 | ☐ |
| 3.3 | 文案无「订阅/自动续费」 | | ☐ |

---

## 4. 主题皮肤（喵币消费）

| # | 步骤 | 预期 | Pass |
|---|------|------|------|
| 4.1 | 主题商店 → 购买皮肤 | 喵币扣减，皮肤 owned | ☐ |
| 4.2 | VIP 折扣价（若 VIP 有效） | 89 vs 99 | ☐ |

---

## 5. Offer Code（可选）

| # | 步骤 | 预期 | Pass |
|---|------|------|------|
| 5.1 | App Store 优惠码兑换页输入 Sandbox Code | | ☐ |
| 5.2 | 到账 = **基础喵币 only** | 无首充双倍 | ☐ |
| 5.3 | `firstPurchaseCompletedByProduct` 不变 | 首充资格仍可用 | ☐ |

---

## 6. 失败排查

| 现象 | 检查 |
|------|------|
| 商品列表空 | IAP ID 与 ASC 一致；Availability 含该 storefront |
| 价格不刷新 | 换 Sandbox 账号后杀进程重启；Storefront listener |
| 购买 pending | ASC 协议/税务；Sandbox 账号状态 |
| 到账失败 | `StoreManager.processTransaction` 日志；IAPDiagnosticStore 导出 |

---

## 7. 验收结论

| Storefront | 六档可购 | 首充双倍 | VIP/主题 | 签字 | 日期 |
|------------|---------|----------|----------|------|------|
| US | ☐ | ☐ | ☐ | | |
| JP | ☐ | ☐ | ☐ | | |
| DE | ☐ | ☐ | ☐ | | |

**Gate**：US 必须通过方可全球扩区（见 [GLOBAL_SUBMISSION_GATE.md](./GLOBAL_SUBMISSION_GATE.md)）。

---

## 8. 结果归档

将填写后的记录表保存至：

`docs/localization/runs/2026-07-03/sandbox-iap-result.md`

（截图索引可选，大图不入库）
