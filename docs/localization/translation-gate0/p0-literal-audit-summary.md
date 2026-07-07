# P0 硬编码审计摘要 — Gate-0

> 生成：`tools/localization/audit_swift_literals.py`  
> 范围：IAP / VIP / Settings / Notification 相关  
> 日期：2026-07-03  
> 明细 CSV：[p0-literal-audit.csv](./p0-literal-audit.csv)

## 统计

| 指标 | 数量 |
|------|------|
| 扫描文件 | 26 |
| 含中文行 | 488 |
| **candidate（待本地化）** | **158** |
| localized（已 .appLocalized 等） | 295 |
| low-priority（日志/注释） | 35 |

## 高优先级 candidate 模块

| 文件 | candidate 约数 | 说明 |
|------|----------------|------|
| `IAPError.swift` | ~20 | 购买错误全文 — **P0 必译** |
| `IAPServerManager.swift` | 少量 | 余额不足等 |
| `MeowCoinStoreView.swift` | 若干 | 商店 UI |
| `VIPCenterView.swift` | 若干 | VIP 文案 |
| `SystemSettingsView.swift` | 若干 | 设置/语言 |

## Gate-0 行动

1. 将 CSV 中 `classification=candidate` 行交给翻译（或后续改 `.appLocalized`）  
2. 优先 `IAPError.swift` 全套错误信息 en 译文  
3. 与 String Catalog 缺失 ~20 key 一并处理  

## 重新生成

```bash
python3 tools/localization/audit_swift_literals.py \
  ItemManager/Views/IAP ItemManager/Views/VIP \
  ItemManager/Views/Settings/Refactored \
  ItemManager/Services/IAP ItemManager/Services/VIP \
  ItemManager/Services/NotificationManager.swift \
  --csv docs/localization/translation-gate0/p0-literal-audit.csv
```
