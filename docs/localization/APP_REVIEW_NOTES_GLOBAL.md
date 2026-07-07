# App Review Notes — Global Expansion

> 粘贴至 App Store Connect → App Review Information → Notes  
> 版本：2.8 | App ID：6758352161 | 更新：2026-07-03

---

## Copy-paste block (English)

```
Pink House (少女心愿) is a wardrobe organization and virtual pet nurturing app.

MONETIZATION — IMPORTANT FOR REVIEW:
• We sell "Meow Coins" through 6 Consumable In-App Purchases only.
• VIP membership, theme skins, and pet shop items are purchased INSIDE the app using Meow Coins — they are NOT separate IAP products.
• VIP is NOT an auto-renewable subscription. Users manually exchange Meow Coins for VIP duration (e.g., 1 month). When VIP expires, nothing renews automatically.
• First purchase of each coin tier grants double base coins (per tier, tracked independently). Repeat purchases include tier bonus percentages (10%–35%).
• Virtual items cannot be refunded or converted to real currency.

HOW TO TEST IAP:
1. Open app → tab "Me" (我) → Meow Coin Store (喵币商店)
2. Purchase any consumable tier (Sandbox account)
3. Optional: Me → VIP Center → exchange coins for VIP duration
4. Optional: Theme store → purchase a theme skin with Meow Coins

OFFER CODES (if testing):
• Use Sandbox Offer Codes bound to each consumable tier (gift_*_meow_v1)
• Redemption grants base coins only — no first-purchase double, no bonus percent

PERMISSIONS — WHY WE REQUEST THEM:
• Camera / Photo Library: add clothing photos, OOTD, 3D object capture
• Microphone / Speech Recognition: pet voice interaction features
• Location (when in use): location-based outfit suggestions
• Motion: 3D parallax background effect
• World Sensing: 3D scanning feature

DATA & PRIVACY:
• Privacy Policy: https://sangsang.online/en/privacy/
• Support / Contact: https://sangsang.online/en/contact/
• Email: huangsangmuniao@126.com
• We use iCloud (CloudKit) for user data sync. Photos and user-generated content are collected for app functionality only (see Privacy Manifest).
• Sign in with Apple is supported. No separate registration required.

AI FEATURES:
• Optional AI styling suggestions and pet chat may call third-party AI APIs. Described in Privacy Policy. We do NOT use data for tracking (NSPrivacyTracking = false).

ACCOUNT:
• [If demo account required, fill in below]
• Demo Apple ID: _______________
• Password: _______________
• Steps: _______________

CHINA MAINLAND:
• App is already live on China mainland storefront. This submission expands availability to additional regions with the same IAP product IDs and VIP model.

CONTACT FOR REVIEW:
• huangsangmuniao@126.com
• Phone: +86-17387657156 (if needed)
```

---

## 中文补充（供内部审核沟通）

- VIP 为喵币兑换型，非订阅；审核话术与 [过审开发书](../过审开发书.md) 一致  
- 文案使用「购买」「获取」，避免「充值」  
- ICP 备案号仅大陆 App 内展示，海外无需在 Review Notes 重复  

---

## VIP 英文话术（可嵌入 Description / 回复审核）

```
Our application's "VIP" feature is designed as a flexible, on-demand service. Users purchase Meow Coins via IAP and decide when to exchange them for specific service durations based on their needs. Since this is not a recurring monthly commitment but a one-time service activation triggered by the user, the Consumable IAP model (Meow Coins) provides the most transparent and user-controlled experience.
```

---

## 权限 → 功能入口对照（审核追问用）

| Permission | User-facing entry |
|------------|-------------------|
| Camera | Wardrobe → add clothing photo; 3D capture |
| Photo Library | Wardrobe, OOTD, export save |
| Microphone | Pet chat / voice features |
| Speech Recognition | Pet voice commands |
| Location | Outfit recommendation (when enabled) |
| Motion | Home / theme parallax background |
| World Sensing | Object Capture scanner |

---

## ATS 说明（若被问及 NSAllowsArbitraryLoads）

```
The app may connect to multiple HTTPS endpoints for AI services and content delivery. We are evaluating narrowing ATS exceptions in a future update. All user-facing legal and support pages are served over HTTPS.
```

---

## Checklist before submit

- [ ] Demo account filled or marked N/A (Sign in with Apple only)
- [ ] Privacy URL returns 200 globally
- [ ] Six IAP products Ready + global availability
- [ ] Screenshots match metadata language
- [ ] Notes pasted without unfilled placeholders (or clearly marked N/A)
