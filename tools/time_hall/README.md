# 梦裙时光馆·分批入馆

`content_batches.json` 是内容批次的 source of truth。批次只能通过对应 importer
增量合并进 `ItemManager/Resources/TimeHall/catalog.json`，不允许用旧 schema
覆盖整个馆藏。

## 批次顺序

1. `catalogue-2026-summer`：2026 Summer 完整目录（已入馆）
2. `commerce-current-outlet`：当前商品与 OUTLET 快照（已入馆）
3. `coordinate-current`：官方搭配关系（已入馆）
4. `feature-craft`：印花专题与制作工艺（已入馆）
5. `news-timeline`：发售、联名与限定事件（已入馆）
6. `history-evidence`：品牌历史补证（已入馆）

## Catalogue 批次

先做只读解析：

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"
python3 tools/time_hall/import_catalogue_batch.py \
  --batch catalogue-2026-summer \
  --dry-run
```

确认数量后入馆：

```bash
python3 tools/time_hall/import_catalogue_batch.py \
  --batch catalogue-2026-summer
```

Importer 会：

- 解析官方 Catalogue 页面、商品名、含税价格、BUY 链接与品番。
- 同名商品按目录季节去重，保留所有出现页和造型图。
- 目录页图压缩至最大 `1200px` 宽后写入 Bundle。
- 只替换本批次拥有的 Catalogue 与商品，保留其他批次。
- 通过原子替换写入 `catalog.json`，不留半批次数据。

## 当前商品与 OUTLET 批次

先完整解析商品列表与详情，但不写文件：

```bash
python3 tools/time_hall/import_commerce_batch.py \
  --batch-id commerce-current-outlet \
  --dry-run
```

确认数量后入馆：

```bash
python3 tools/time_hall/import_commerce_batch.py \
  --batch-id commerce-current-outlet
```

Importer 会：

- 仅采集 `brand_label_codes=10` 的 PINK HOUSE 当前商品与 OUTLET。
- 以品番去重，保存采集日、当前/OUTLET 来源、原价/折扣价与库存状态。
- 从详情页保存分类、颜色、尺寸、材质、产地、官方介绍与完整图片 URL。
- 每件商品物化一张封面和一张详情图，压缩至最大 `900px` 宽后写入 Bundle。
- 生成独立 `commerceSnapshots` / `commerceItems`，不伪装成 Catalogue 展品。
- 只替换本批次拥有的快照与商品，并通过原子替换写入 `catalog.json`。

## 四个品牌官网商品

```bash
python3 tools/time_hall/import_curated_commerce.py --dry-run
python3 tools/time_hall/import_curated_commerce.py
/usr/bin/python3 tools/time_hall/translate_catalog_descriptions.py
```

翻译脚本保留官方日文原文，并生成随 App 语言切换的中文商品名与商品介绍。

已有商品元数据、只需补齐或续传本地封面时：

```bash
python3 tools/time_hall/import_curated_commerce.py --images-only
```

采集边界均为官网目前仍公开可枚举的在售、售罄或预约商品页：Angelic Pretty
逐页读取官方 Product List；BABY（含 ALICE and the PIRATES）与 Juliette et
Justine 读取各自官方商城全商品；Wunderwelt 只读取 FLEUR 官方授权新品集合，
不混入 USED 二手总库。官网已经删除或从未公开索引的旧商品无法据实补造。

品牌资料依据分别为 [Angelic Pretty 官网与 2026 Spring Collection](https://angelicpretty.com/Page/collection2026spring.aspx)、
[BABY 官方品牌页](https://www.babyssb.co.jp/brand/)、
[Juliette et Justine 官方介绍](https://juliette-et-justine.com/zh-cn/pages/about) 与
[Wunderwelt FLEUR 官方介绍](https://libre.wunderwelt.jp/zh/9183/)。导入器保留商品页、
原图 URL、采集日、价格和库存状态；每件商品的首张官方图压缩到最大 600px 后写入
App Bundle，已存在的封面会跳过，详情页其余图片仍按需读取官方 HTTPS 地址。
中文正文由 macOS 已下载的 Apple 日文/简体中文翻译语言包生成；官网原文未变化时，
重新采集会保留已有中文正文。

## Coordinate 批次

```bash
python3 tools/time_hall/import_coordinate_batch.py --dry-run
python3 tools/time_hall/import_coordinate_batch.py
```

Importer 会解析官方 9 页、150 套造型，保存整套造型图、搭配说明、页面日期、
品番与单品名。能与当前商品快照按品番精确匹配的关系写入
`linkedCommerceItemIDs`；没有品番或已经下架的单品只保留文字记录，不做模糊绑定。

## Feature 与制作工艺批次

```bash
python3 tools/time_hall/import_story_batch.py --dry-run
python3 tools/time_hall/import_story_batch.py
```

Importer 会解析官方 Feature 的 4 页、35 篇专题详情，并合并 Melrose 的 1 篇
PINK HOUSE 手捺染工艺长档案。每篇保存发布日期（官网有标注时）、官方正文、
关联品番、本地封面和完整官方图片 URL；数据写入独立 `stories`，不伪装成商品。

## News V3 批次

正式 V3 News 入馆命令：

```bash
python3 tools/time_hall/import_news_batch.py --dry-run
python3 tools/time_hall/import_news_batch.py
```

Importer 会解析 61 页、721 篇 News 详情，保存官方日期、正文、品番、封面与
完整图片 URL。官网栏目统一标为 INFORMATION；馆内仅根据明确的活动、发售、
联名、限定、展会与促销词汇增加事件分类，原始正文不改写。

## 品牌历史补证

```bash
python3 tools/time_hall/import_history_batch.py --dry-run
python3 tools/time_hall/import_history_batch.py
```

从 Melrose 官方沿革提取与 PINK HOUSE 直接相关的 6 条证据原文，并关联到
1972、1982、1983、1985、2004、2011 年的馆内编年史。

## News 旧脚本

`scrape_pinkhouse_news.py` 仍是历史 V2 解析器，它会把 News 文章当作裙子。
默认已禁止写入；正式 News 导入只使用 V3 事件实体，不得再生成
`collections` / `dresses` 结构。

## 图片去重

所有批次导入完成后运行：

```bash
python3 tools/time_hall/deduplicate_images.py --visual --apply
python3 tools/time_hall/optimize_images.py --apply
```

去重脚本优先用 SHA-256 合并字节完全相同的图片；`--visual`
还会用差异哈希和 RGB 均方根差双重检查，合并编码不同但画面一致的官方图，
改写 `catalog.json` 为共享引用，并删除未被图鉴引用的旧图。阈值保守，不合并
仅仅相似的商品或搭配图。

压缩脚本只改写长边超过 `1600px` 且能节省至少 5% 的 JPG。改写后长边不再超标，
因此重复运行不会反复重压；原本已高效的图会保留原文件。商品、News 和搭配图已是
900–1200px，不会被改写。
