# Pink_House 本地化术语表（Glossary）

> 翻译与 App Store metadata 统一口径  
> 更新时间：2026-07-03

## 品牌与产品

| zh-Hans | en | zh-Hant | ja | ko | 备注 |
|---------|-----|---------|-----|-----|------|
| 少女心愿 | Pink House | 少女心願 | Pink House | Pink House | App 显示名；ASC Name 可本地化 |
| 少女心愿衣橱 | Pink House Wardrobe | 少女心願衣櫥 | — | — | Widget 名 |

## 虚拟货币与 IAP

| zh-Hans | en | zh-Hant | ja | ko | 备注 |
|---------|-----|---------|-----|-----|------|
| 喵币 | Meow Coins | 喵幣 | ニャンコイン | 냥코인 | 官方译名；勿用 "recharge/充值" |
| 购买 / 获取 | Purchase / Get | 購買 / 取得 | 購入 | 구매 | 避免「充值」 |
| 首充双倍 | First purchase double | 首購雙倍 | 初回2倍 | 첫 구매 2배 | 每档位独立 |
| 赠送 | Bonus | 贈送 | ボーナス | 보너스 | +10%/15%/25%/35% |
| 虚拟物品 | Virtual items | 虛擬物品 | 仮想アイテム | 가상 아이템 | 不可退款 |
| 不可退款 | Non-refundable | 不可退款 | 返金不可 | 환불 불가 | IAP/VIP 页必现 |

## IAP 档位包装名（App 内营销，非 ASC 必填）

| Product ID | zh-Hans | en |
|------------|---------|-----|
| meowcoin_60 | 喵币小钱包 | Meow Coin Mini Wallet |
| meowcoin_120 | 喵币零食袋 | Meow Coin Snack Bag |
| meowcoin_300 | 喵币鼓鼓袋 | Meow Coin Plump Bag |
| meowcoin_500 | 喵币小宝箱 | Meow Coin Treasure Box |
| mcoin_1280 | 喵币大宝箱 | Meow Coin Grand Chest |
| mcoin_3280 | 喵币藏宝库入场券 | Meow Coin Vault Pass |

## VIP 与会员

| zh-Hans | en | 禁止译法 |
|---------|-----|----------|
| VIP 会员 | VIP membership | Subscription, Auto-renew |
| 喵币兑换型权益 | Meow Coin exchange benefit | Monthly subscription |
| 非自动续费 | Not auto-renewing | Recurring billing |
| 手动兑换 | Manual exchange | Subscribe now |

## 主题与商店

| zh-Hans | en |
|---------|-----|
| 主题皮肤 | Theme skin |
| 天空音乐会 | Sky Concert |
| 天鹅入梦 | Swan Dream |

## 核心功能 Tab

| zh-Hans | en | zh-Hant |
|---------|-----|---------|
| 衣橱 | Wardrobe | 衣櫥 |
| 财富 | Wealth | 財富 |
| 手帐 | Diary | 手帳 |
| 我 | Me | 我 |
| 喵币商店 | Meow Coin Store | 喵幣商店 |

## 权限（InfoPlist）

| Key | en 参考 |
|-----|---------|
| NSCameraUsageDescription | Pink House needs camera access to take clothing photos and perform 3D scans. |
| NSPhotoLibraryUsageDescription | Pink House needs photo library access to choose clothing photos. |
| NSMicrophoneUsageDescription | Pink House needs microphone access for pet voice interactions and recording features. |
| NSSpeechRecognitionUsageDescription | Pink House uses speech recognition for pet voice interactions and commands. |
| NSLocationWhenInUseUsageDescription | Pink House uses your location for location-based outfit recommendations. |
| NSMotionUsageDescription | Pink House uses motion data for the 3D parallax background effect. |
| NSWorldSensingUsageDescription | Pink House uses world sensing to perform 3D object scans. |

## 法律文档标题

| zh-Hans | en |
|---------|-----|
| 隐私政策 | Privacy Policy |
| 用户协议 | Terms of Service |
| 会员协议 | VIP Agreement |
| 联系我们 | Contact Us |

## 翻译禁区

1. 不翻译：用户输入的衣物名、品牌、标签、宠物昵称、手帐标题  
2. 不机械翻译：AI prompt、宠物口癖（单独风格指南）  
3. 不用：充值、订阅（指 VIP）、赌博、抽奖（除非确有 gacha 机制）
