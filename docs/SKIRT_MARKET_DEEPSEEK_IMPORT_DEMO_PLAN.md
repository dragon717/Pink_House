# 裙装股市 DeepSeek 商品解析 Demo

## 目标

在现有“裙装股市”页做一个轻量 demo：用户从右上角菜单进入，选择“链接模式”或“关键词模式”，把淘宝、闲鱼、小红书、微店的链接/分享文案/搜索结果粘贴进来，由 DeepSeek V4 抽取商品信息和价格时间线，用户确认后写入裙装股市 GRDB。

## 调研结论

- v1 不做网页爬虫、代理、验证码、用户 Cookie、WebView 自动化、Share Extension。
- 淘宝有官方 TOP/TBK 接口，但 AppSecret 不能放 iOS 端，后续应走后端签名。
- 闲鱼和小红书面向普通公开搜索的官方能力不稳定或不开放，v1 只支持用户粘贴文本。
- iOS 端优先用系统能力：`PasteButton` 做显式粘贴，`NSDataDetector` 抽链接；关键词模式不跳转外部网站。
- DeepSeek 只负责结构化分析，不假装联网，不猜价格和日期。

## 输入输出契约

输入给 DeepSeek：

```json
{
  "mode": "link|keyword",
  "platform_hint": "taobao|xianyu|xiaohongshu|weidian|unknown",
  "source_url": "string|null",
  "keyword": "string|null",
  "captured_at": "ISO-8601",
  "raw_text": "用户粘贴文本",
  "local_parse": {
    "platform_hint": "string",
    "source_url": "string|null",
    "title": "string|null",
    "price": 0.0
  }
}
```

DeepSeek 只允许返回 JSON：

```json
{
  "items": [
    {
      "title": "string",
      "brand": "string|null",
      "series": "string|null",
      "category": "jsk|op|sk|blouse|accessory|bag|shoes|other",
      "color": "string|null",
      "size": "string|null",
      "condition": "string|null",
      "is_lolita_related": true,
      "sale_intent": "sell|buy|deposit|final_payment|reservation|unknown",
      "confidence": 0.0,
      "missing_fields": ["string"],
      "price_events": [
        {
          "kind": "current|original|deposit|balance",
          "amount": 0.0,
          "currency": "CNY",
          "observed_at": "ISO-8601",
          "applies_at": "ISO-8601|null",
          "note": "string|null"
        }
      ]
    }
  ]
}
```

## 实现口径

- 入口：`DressStockMarketView` 右上角 `Menu`，包含“粘贴链接/文本”和“关键词模式”。
- 链接模式：用户粘贴分享文案；本地先抽 URL、平台、粗标题、粗价格。
- 关键词模式：用户输入关键词，或把商品/搜索结果文本粘贴进本页，由 DeepSeek 直接分析并生成可确认草稿。
- DeepSeek 服务：`SkirtMarketDeepSeekImportService` 读取 `DS_API_KEY`，调用 `deepseek-v4-flash`，启用 JSON output。
- 保存：先展示确认页，用户可改标题、价格、原价、定金、尾款、定金日期、尾款日期。
- 数据：`lolita_items` 增加解析字段，`lolita_price_events` 保存每个价格的观察时间和适用时间。

## 验收

- 淘宝、闲鱼、小红书分享文案能本地抽出 URL、平台和粗价格。
- 缺 `DS_API_KEY` 或 DeepSeek 失败时，仍生成本地草稿并提示错误。
- DeepSeek 返回多个商品时，确认页可选择其中一个保存。
- 保存后 `lolita_items` 写入当前字段，`lolita_price_events` 至少写入当前价事件；原价、定金、尾款有值时分别写事件。
- 重复初始化 GRDB 不报错，旧库能补齐新增列和事件表。
- 构建命令：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet build`。
