# App Privacy / Age Rating / Export Compliance 问卷对照

> ASC 路径：App Privacy、Age Rating、App Information → Export Compliance  
> 与仓库文件对齐：`PrivacyInfo.xcprivacy`、`Info.plist`  
> 更新：2026-07-03

---

## 1. App Privacy（隐私营养标签）

### 与 PrivacyInfo.xcprivacy 对齐

| Manifest | ASC 应选 |
|----------|----------|
| NSPrivacyTracking = **false** | Data Not Used for Tracking |
| Photos/Videos collected | Yes — App Functionality, Not Linked, Not Tracking |
| Other User Content collected | Yes — App Functionality, Not Linked, Not Tracking |
| File Timestamp API (C617.1) | Required Reason API — 在 App Privacy 问卷说明用途 |
| UserDefaults API (CA92.1) | Required Reason API |

### 建议在 ASC 额外声明（若问卷询问）

| 数据类型 | 用途 | Linked | Tracking |
|----------|------|--------|----------|
| Purchase History | App Functionality (IAP delivery) | No | No |
| User Content (wardrobe, diary) | App Functionality | No | No |
| Photos | App Functionality | No | No |
| iCloud sync | App Functionality | 按 Apple ID | No |

### CloudKit

- 在 Privacy Policy 英文版说明 iCloud 同步范围与删除方式  
- URL：`https://sangsang.online/en/privacy/`

---

## 2. Age Rating（全球问卷）

按当前 App 功能勾选（**扩区前重新填写全球问卷**）：

| 维度 | Pink_House 建议答案 | 理由 |
|------|---------------------|------|
| Cartoon/Fantasy Violence | None or Infrequent/Mild | 宠物互动无写实暴力 |
| Realistic Violence | None | |
| Profanity | None | |
| Mature/Suggestive Themes | None or Infrequent/Mild | 时尚/衣橱 |
| Horror | None | |
| Medical/Treatment | None | |
| Alcohol/Tobacco/Drugs | None | |
| Gambling | **None** | 喵币 IAP 非博彩；无 gacha 法规意义上的抽奖 |
| Unrestricted Web Access | No 或 Limited | 协议页 HTTPS |
| User Generated Content | **Yes** | 衣橱照片、手帐 — 需说明 moderation |
| Messaging/Chat | **Yes** | 宠物/AI 聊天 |
| In-App Purchases | **Yes** | 六档 consumable |

### 韩国 / 越南注意

若被归类为 Game，年龄分级可能不同 — 见 [LOCALE_MATRIX.md](./LOCALE_MATRIX.md) Wait_Legal 项。

---

## 3. Export Compliance（出口合规）

| 项 | 仓库值 | ASC 问卷 |
|----|--------|----------|
| Uses encryption | HTTPS, CloudKit | Yes |
| Exempt | `ITSAppUsesNonExemptEncryption` = **false** | App uses only standard Apple/OS encryption OR qualifies for exemption |
| Documentation | 通常无需额外 ERN | 与 plist 一致即可 |

**注意**：扩区时每个新版本仍要确认 Export 问题；答案应与 Info.plist 一致。

---

## 4. Privacy Policy URL 按语言

| Metadata 语言 | 建议 URL |
|---------------|----------|
| en 及无法语页面地区 | https://sangsang.online/en/privacy/ |
| zh-Hans | https://sangsang.online/privacy/ |
| zh-Hant | https://sangsang.online/privacy/（或未来 /zh-Hant/） |

## 5. Support URL

| 用途 | URL |
|------|-----|
| 全球默认 | https://sangsang.online/en/contact/ |
| 中文 | https://sangsang.online/contact/ |

---

## 6. 扩区前勾选

| # | 项 | Done |
|---|-----|------|
| 6.1 | App Privacy 已 Save | ☐ |
| 6.2 | Age Rating 全球问卷已 Submit | ☐ |
| 6.3 | Export Compliance 与 2.8 build 一致 | ☐ |
| 6.4 | Privacy URL curl 200 | ☐ |
| 6.5 | 与 [APP_STORE_CONNECT_CHECKLIST.md](./APP_STORE_CONNECT_CHECKLIST.md) Phase 4 同步 | ☐ |

```bash
curl -fsSIL https://sangsang.online/en/privacy/
curl -fsSIL https://sangsang.online/en/contact/
```
