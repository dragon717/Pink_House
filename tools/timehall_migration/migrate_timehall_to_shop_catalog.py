#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
时光馆 → 店家商品库（ShopCatalog）一次性迁移工具（重构方案 Phase 3，§5.6）

输入：
  · ItemManager/Resources/TimeHall/catalog*.json   画册编年史种子（catalogues/items/commerceItems）
  · ItemManager/Resources/TimeHall/timehall-brand-meta.json  品牌元数据（merchantID → 展示名）
  · ItemManager/Resources/Midsummer/midsummer-series.json    仲夏物语系列（含价格/规格）

输出：
  · --out     ShopCatalog 结构 JSON（version 1，七实体数组），供人工复核后并入
              Bundle 种子或运营覆盖层；本工具不直接改任何种子文件
  · --report  迁移报告（实体计数、价格未知清单、疑似重名、无法迁移项）

硬约束（方案 §9）：
  · id 稳定：迁移实体 id = "th-" + 原始稳定来源 id（productCode 优先于 item id）
  · SaleEvent 只追加：本工具只产出新事件，不读取也不改写既有事件
  · 只迁不删：原始种子文件不动；CloudKit 公共库数据不动
  · 叙事实体（stories/coordinates/events/historyEntries/timelineYears）不迁移

用法：
  python3 tools/timehall_migration/migrate_timehall_to_shop_catalog.py \
      --repo /Users/sangyu/develop/Pink_House \
      --out output/timehall_migration/shop-catalog-migrated.json \
      --report output/timehall_migration/migration-report.json
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime

# ShopCatalog canonical categories（与 ShopCatalogStore.canonicalCategoryOrder 一致）
CANONICAL_CATEGORIES = ["JSK", "OP", "SK", "Blouse", "KC", "小物", "鞋", "包", "其他"]


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def dump_json(path, data):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)


def parse_date(text):
    """observedAt / publishedOn → ISO 日期（无法解析时返回 None）。"""
    if not text or not isinstance(text, str):
        return None
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", text)
    if not m:
        return None
    return f"{m.group(1)}-{m.group(2)}-{m.group(3)}T00:00:00Z"


def map_category(item):
    """kind/categoryZH/category → ShopCatalog 规范分类。

    源数据的 categoryZH 是自由中文（「OP 连衣裙」「半身裙」「衬衫」…），
    按显式 token → 中文映射 → kind 兜底三级判定；未知归「其他」。
    """
    texts = []
    for key in ("category", "categoryZH", "kind", "name", "nameZH"):
        v = item.get(key)
        if isinstance(v, str) and v.strip():
            texts.append(v.strip().lower())
        for v2 in (item.get("stylesZH") or []) + (item.get("styles") or []):
            if isinstance(v2, str):
                texts.append(v2.lower())
    joined = " ".join(texts)
    # 1) 显式规范 token（词边界匹配，避免 "Shop"/"Droplet" 误命中 "op"）
    for token, label in (("jsk", "JSK"), ("op", "OP"), ("blouse", "Blouse"), ("kc", "KC")):
        if re.search(rf"\b{token}\b", joined):
            return label
    if "半身裙" in joined:
        return "SK"
    # 2) 中文映射（顺序敏感：先判断语义更窄的）
    zh_rules = [
        (("吊带裙", "背带裙", "连衣裙", "裙装"), "JSK"),
        (("半身裙",), "SK"),
        (("衬衫", "上衣", "开衫", "背心"), "Blouse"),
        (("鞋",), "鞋"),
        (("包",), "包"),
        (("kc",), "KC"),
        (("胸花", "袜子", "小物", "头饰", "发饰", "配件"), "小物"),
    ]
    for keys, cat in zh_rules:
        if any(k in joined for k in keys):
            return cat
    # 3) kind 兜底
    kind = item.get("kind")
    if kind == "dress":
        return "JSK"
    if kind == "clothing":
        return "Blouse"
    if kind == "accessory":
        return "小物"
    return "其他"


def sanitize_shop_id(merchant_id):
    """merchantID 可能是官网 URL → 清洗成简短 slug（id 是稳定标识，只求可读）。"""
    raw = merchant_id or "unknown"
    raw = re.sub(r"^https?://", "", raw.lower())
    raw = re.sub(r"^www\.", "", raw)
    slug = re.sub(r"[^a-z0-9]+", "-", raw).strip("-")
    return (slug or "unknown")[:60]


class Migrator:
    def __init__(self, existing_catalog):
        self.existing = existing_catalog
        self.out = {
            "version": 1,
            "shops": [],
            "series": [],
            "products": [],
            "variants": [],
            "sizeCharts": [],
            "saleEvents": [],
            "assets": [],
        }
        self.report = {
            "generatedAt": datetime.now().isoformat(timespec="seconds"),
            "shops": 0,
            "series": 0,
            "products": 0,
            "variants": 0,
            "saleEvents": 0,
            "assets": 0,
            "skipped": [],
            "warnings": [],
            "unknownPrices": [],
        }
        self._seq = 0

    # ---- id 工具 -------------------------------------------------------------
    def existing_ids(self, key):
        return {e.get("id") for e in self.existing.get(key, [])}

    def existing_shop_names(self):
        names = set()
        for s in self.existing.get("shops", []):
            names.add((s.get("name") or "").lower())
            names.update((a or "").lower() for a in s.get("aliases", []))
        return names

    def next_id(self, prefix):
        self._seq += 1
        return f"{prefix}-{self._seq:05d}"

    def unique_id(self, candidate, taken):
        """候选 id 冲突时追加 -2/-3…，保证 id 全局唯一（id 是唯一稳定标识）。"""
        if candidate not in taken:
            taken.add(candidate)
            return candidate
        n = 2
        while f"{candidate}-{n}" in taken:
            n += 1
        final = f"{candidate}-{n}"
        taken.add(final)
        return final

    # ---- 实体工厂 ------------------------------------------------------------
    def add_shop(self, shop_id, name, aliases, taken):
        if any(s["id"] == shop_id or s["name"] == name for s in self.out["shops"]):
            return next(s for s in self.out["shops"] if s["id"] == shop_id or s["name"] == name)
        shop = {"id": shop_id, "name": name, "aliases": aliases}
        self.out["shops"].append(shop)
        self.report["shops"] += 1
        return shop

    def add_series(self, series_id, shop_id, name, year, season, cover, taken):
        sid = self.unique_id(series_id, taken["series"])
        series = {"id": sid, "shopID": shop_id, "name": name,
                  "year": year, "season": season,
                  "cover": cover, "description": None}
        self.out["series"].append(series)
        self.report["series"] += 1
        return series

    def add_product(self, product_id, shop_id, series_id, name, category,
                    images, taken):
        pid = self.unique_id(product_id, taken["products"])
        product = {"id": pid, "shopID": shop_id, "seriesID": series_id,
                   "name": name, "category": category, "images": images,
                   "description": None}
        self.out["products"].append(product)
        self.report["products"] += 1
        return product

    def add_variants(self, product_id, colors, sizes):
        colors = [c for c in (colors or []) if isinstance(c, str) and c.strip()]
        sizes = [s for s in (sizes or []) if isinstance(s, str) and s.strip()]
        combos = [(c, s) for c in (colors or [None]) for s in (sizes or [None])]
        for c, s in combos:
            self.out["variants"].append({
                "id": self.next_id("var-th"),
                "productID": product_id,
                "color": c,
                "size": s,
            })
            self.report["variants"] += 1

    def add_sale_event(self, product_id, kind, price, deposit, balance, start_at):
        if price is None:
            self.report["unknownPrices"].append(
                {"productID": product_id, "kind": kind})
            price = 0
        event = {
            "id": self.next_id("ev-th"),
            "productID": product_id,
            "type": kind,
            "price": price,
            "deposit": deposit,
            "balance": balance,
            "startAt": parse_date(start_at),
            "endAt": None,
        }
        self.out["saleEvents"].append(event)
        self.report["saleEvents"] += 1

    def add_assets(self, references, asset_type, taken):
        ids = []
        for ref in references or []:
            if not isinstance(ref, str) or not ref.strip():
                continue
            aid = self.unique_id("asset-th-" + re.sub(r"[^A-Za-z0-9_.-]", "-", ref)[:60],
                                 taken["assets"])
            self.out["assets"].append({
                "id": aid, "type": asset_type,
                "thumbnailURL": None, "previewURL": None,
                "originalURL": ref, "width": None, "height": None,
            })
            ids.append(aid)
            self.report["assets"] += 1
        return ids


class IDRegistry:
    """taken-id 集合：跨品牌共享，防 id 冲突。"""

    def __init__(self, existing):
        self.taken = {
            "shops": {e.get("id") for e in existing.get("shops", [])},
            "series": {e.get("id") for e in existing.get("series", [])},
            "products": {e.get("id") for e in existing.get("products", [])},
            "variants": {e.get("id") for e in existing.get("variants", [])},
            "assets": {e.get("id") for e in existing.get("assets", [])},
        }


def migrate_timehall_catalog(m, path, meta_by_merchant, reg, scope="catalogue"):
    data = load_json(path)
    merchant_id = data.get("source") or ""
    # 品牌名：优先 brand-meta；否则用 item.brand / 文件名
    meta = meta_by_merchant.get(merchant_id) or {}
    brand_name = meta.get("displayName") or (
        (data.get("items") or [{}])[0].get("brand") or merchant_id or os.path.basename(path))
    aliases = [meta.get("displayNameEN")] if meta.get("displayNameEN") else []

    # 店家：已有同名（或别名命中）店家 → 复用既有 id（§29 防重复匹配）
    name_l = brand_name.lower()
    existing_hit = next(
        (s for s in self_shops(m.existing) if name_l in shop_name_keys(s)), None)
    if existing_hit:
        shop_id = existing_hit["id"]
        m.report.setdefault("reusedShops", []).append(
            {"merchant": merchant_id, "shopID": shop_id, "name": brand_name})
    else:
        shop = m.add_shop(
            m.unique_id("shop-th-" + sanitize_shop_id(merchant_id), reg.taken["shops"]),
            brand_name, aliases, reg.taken["shops"])
        shop_id = shop["id"]

    # 系列：catalogues → CatalogSeries（cover 一并入资产）
    catalogue_ids = set()
    for cat in data.get("catalogues") or []:
        cover_ids = m.add_assets([cat.get("coverImage")], "seriesCover", reg.taken)
        series = m.add_series(
            "th-" + str(cat.get("id")), shop_id, cat.get("titleZH") or cat.get("title") or "未命名系列",
            cat.get("year"), (cat.get("seasonLabel") or cat.get("season") or None),
            (cover_ids[0] if cover_ids else None), reg.taken)
        catalogue_ids.add(cat.get("id"))

    # 商品 A：画册展品 items（productCode 优先作为 id 种子）
    commerce_codes = {c.get("productCode") for c in data.get("commerceItems") or []
                      if c.get("productCode")}
    for item in data.get("items") or []:
        code = item.get("productCode")
        if code and code in commerce_codes:
            m.report["skipped"].append(
                {"reason": "item 已有在售商品条目（按 productCode 合并）",
                 "itemID": item.get("id"), "productCode": code})
            continue
        image_ids = m.add_assets(
            ([item.get("coverImage")] if item.get("coverImage") else [])
            + (item.get("gallery") or []), "productImage", reg.taken)
        product = m.add_product(
            "th-" + (code or item.get("id")), shop_id,
            "th-" + str(item.get("catalogueID")) if item.get("catalogueID") else None,
            item.get("nameZH") or item.get("name") or "未命名商品",
            map_category(item), image_ids, reg.taken)
        if product["seriesID"] is None:
            product["seriesID"] = ensure_misc_series(m, shop_id, reg)
        m.add_variants(product["id"], item.get("stylesZH") or item.get("styles"), None)
        if item.get("priceJPY"):
            m.add_sale_event(product["id"], "stock", item["priceJPY"], None, None,
                             item.get("observedAt"))

    # 商品 B：在售商品 commerceItems（挂在「当前在售」合成系列下）
    # scope=catalogue（默认）时跳过：全量在售清单体量大（数千商品），
    # 适合作为未来云端分发包（THDataPack）而非 Bundle 种子。
    if scope == "catalogue":
        skipped_live = len(data.get("commerceItems") or [])
        if skipped_live:
            m.report["skipped"].append({
                "reason": f"scope=catalogue：跳过全量在售清单 {skipped_live} 条（适合云端分发包）",
                "itemID": merchant_id, "productCode": None})
        return
    misc_series_id = None
    for ci in data.get("commerceItems") or []:
        if misc_series_id is None:
            misc_series_id = ensure_misc_series(m, shop_id, reg)
        # 资产只保留真实商品图；imageSourceURLs 是来源引用链接，不进资产
        image_ids = m.add_assets(
            ([ci.get("coverImage")] if ci.get("coverImage") else [])
            + ([ci.get("detailImage")] if ci.get("detailImage") else []),
            "productImage", reg.taken)
        product = m.add_product(
            "th-" + (ci.get("productCode") or ci.get("id")), shop_id, misc_series_id,
            ci.get("nameZH") or ci.get("name") or "未命名商品",
            map_category(ci), image_ids, reg.taken)
        m.add_variants(product["id"], ci.get("colors"), ci.get("sizes"))
        price = ci.get("salePriceJPY") if ci.get("salePriceJPY") else ci.get("regularPriceJPY")
        m.add_sale_event(product["id"], "stock", price, None, None, ci.get("observedAt"))


def self_shops(existing):
    return existing.get("shops", [])


def shop_name_keys(shop):
    keys = {(shop.get("name") or "").lower()}
    keys.update((a or "").lower() for a in shop.get("aliases", []))
    return keys


def ensure_misc_series(m, shop_id, reg):
    """「当前在售」合成系列：year 取当前年份，承载无系列归属的在售商品。"""
    for s in m.out["series"]:
        if s["shopID"] == shop_id and s.get("description") == "__misc_current__":
            return s["id"]
    year = datetime.now().year
    series = m.add_series(m.next_id(f"series-th-current-{year}"), shop_id,
                          f"{year} 在售", year, None, None, reg.taken)
    series["description"] = "__misc_current__"
    # 报告里不暴露内部标记
    return series["id"]


def migrate_midsummer(m, path, reg):
    data = load_json(path)
    shop = m.add_shop("shop-midsummer-tale", data.get("brandName") or "仲夏物语",
                      [data.get("brandNameEN")] if data.get("brandNameEN") else [],
                      reg.taken["shops"])
    if any(s.get("id") == "shop-midsummer-tale" for s in m.existing.get("shops", [])):
        m.report.setdefault("reusedShops", []).append(
            {"merchant": data.get("brandID"), "shopID": "shop-midsummer-tale",
             "name": shop["name"]})
    shop_id = shop["id"]
    for s in data.get("series") or []:
        cover_ids = m.add_assets([s.get("coverImage")] if s.get("coverImage") else [],
                                 "seriesCover", reg.taken)
        year = None
        if s.get("launchedOn"):
            mm = re.match(r"(\d{4})", str(s["launchedOn"]))
            year = int(mm.group(1)) if mm else s.get("year")
        series = m.add_series("th-" + str(s.get("id")), shop_id,
                              s.get("name") or "未命名系列", year, None,
                              (cover_ids[0] if cover_ids else None), reg.taken)
        for item in s.get("items") or []:
            image_ids = m.add_assets([item.get("coverImage")] if item.get("coverImage") else [],
                                     "productImage", reg.taken)
            product = m.add_product("th-" + str(item.get("id")), shop_id, series["id"],
                                    item.get("name") or "未命名商品", "其他",
                                    image_ids, reg.taken)
            # 规格：colors × sizes；sku 已有的话直接展开
            colors = item.get("colors") or []
            sizes = item.get("sizes") or []
            for sku in item.get("skus") or []:
                c = sku.get("color") if isinstance(sku, dict) else None
                sz = sku.get("size") if isinstance(sku, dict) else None
                if (c or sz) and (c not in colors if c else True):
                    if c and c not in colors:
                        colors.append(c)
                    if sz and sz not in sizes:
                        sizes.append(sz)
            m.add_variants(product["id"], colors, sizes)
            # 价格：deposit 有值 → 预约（定金/尾款），否则现货
            price, deposit, balance = item.get("price"), item.get("deposit"), item.get("balance")
            if deposit:
                m.add_sale_event(product["id"], "reservation", price, deposit, balance,
                                 s.get("launchedOn"))
            else:
                m.add_sale_event(product["id"], "stock", price, None, None,
                                 s.get("launchedOn"))


def validate_output(out, existing=None):
    """结构自检：与 ShopCatalogModels.swift 的 Codable 字段对齐。

    引用完整性按「既有种子 ∪ 迁移产物」判定：迁移允许复用既有店家
    （§29 防重复匹配），其产物实体指向既有 shop id 不算悬空。
    """
    errors = []
    merged = {"shops": list((existing or {}).get("shops", [])) + out["shops"]}
    required = {
        "shops": ["id", "name", "aliases"],
        "series": ["id", "shopID", "name"],
        "products": ["id", "shopID", "seriesID", "name", "category", "images"],
        "variants": ["id", "productID"],
        "saleEvents": ["id", "productID", "type", "price"],
        "assets": ["id", "type", "originalURL"],
    }
    shop_ids = {s["id"] for s in merged["shops"]}
    series_ids = {s["id"] for s in out["series"]}
    product_ids = {p["id"] for p in out["products"]}
    for entity, keys in required.items():
        for e in out.get(entity, []):
            for k in keys:
                if k not in e:
                    errors.append(f"{entity} 缺字段 {k}: {e.get('id')}")
    for s in out["series"]:
        if s["shopID"] not in shop_ids:
            errors.append(f"series {s['id']} 悬空 shopID {s['shopID']}")
    for p in out["products"]:
        if p["shopID"] not in shop_ids:
            errors.append(f"product {p['id']} 悬空 shopID {p['shopID']}")
        if p["seriesID"] not in series_ids:
            errors.append(f"product {p['id']} 悬空 seriesID {p['seriesID']}")
    for v in out["variants"]:
        if v["productID"] not in product_ids:
            errors.append(f"variant {v['id']} 悬空 productID {v['productID']}")
    for e in out["saleEvents"]:
        if e["productID"] not in product_ids:
            errors.append(f"saleEvent {e['id']} 悬空 productID {e['productID']}")
        if e["type"] not in ("reservation", "stock", "rerelease"):
            errors.append(f"saleEvent {e['id']} 非法 type {e['type']}")
    for a in out["assets"]:
        if a["type"] not in ("productImage", "sizeChartImage", "seriesCover", "shopCover"):
            errors.append(f"asset {a['id']} 非法 type {a['type']}")
    # id 唯一性（数据库 id 是唯一稳定标识）
    for entity in ("shops", "series", "products", "variants", "saleEvents", "assets"):
        ids = [e["id"] for e in out.get(entity, [])]
        if len(ids) != len(set(ids)):
            errors.append(f"{entity} 存在重复 id")
    return errors


def main():
    ap = argparse.ArgumentParser(description="TimeHall/Midsummer → ShopCatalog 迁移")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)))), help="仓库根目录")
    ap.add_argument("--out", default=None)
    ap.add_argument("--report", default=None)
    ap.add_argument("--scope", choices=["catalogue", "full"], default="catalogue",
                    help="catalogue=画册年鉴（Bundle 种子适用）；full=含全量在售清单（云端分发包适用）")
    ap.add_argument("--validate-only", action="store_true",
                    help="只跑自检与统计，不写文件")
    args = ap.parse_args()

    th_dir = os.path.join(args.repo, "ItemManager", "Resources", "TimeHall")
    ms_json = os.path.join(args.repo, "ItemManager", "Resources", "Midsummer",
                           "midsummer-series.json")
    existing = load_json(os.path.join(args.repo, "ItemManager", "Resources",
                                      "ShopCatalog", "shop-catalog.json"))

    meta_by_merchant = {}
    meta_path = os.path.join(th_dir, "timehall-brand-meta.json")
    if os.path.exists(meta_path):
        for b in load_json(meta_path).get("brands", []):
            meta_by_merchant[b.get("merchantID")] = b

    m = Migrator(existing)
    reg = IDRegistry(existing)

    for fname in sorted(os.listdir(th_dir)):
        if fname.startswith("catalog") and fname.endswith(".json"):
            migrate_timehall_catalog(m, os.path.join(th_dir, fname), meta_by_merchant,
                                     reg, scope=args.scope)

    if os.path.exists(ms_json):
        migrate_midsummer(m, ms_json, reg)

    # 收尾：合成系列内部标记不写入产物
    for s in m.out["series"]:
        if s.get("description") == "__misc_current__":
            s["description"] = None

    errors = validate_output(m.out, existing)
    m.report["validationErrors"] = errors
    m.report["totals"] = {k: len(v) for k, v in m.out.items() if isinstance(v, list)}

    if args.validate_only:
        pass
    else:
        if not args.out:
            args.out = os.path.join(args.repo, "output", "timehall_migration",
                                    "shop-catalog-migrated.json")
        dump_json(args.out, m.out)
        if not args.report:
            args.report = os.path.join(os.path.dirname(args.out), "migration-report.json")
        dump_json(args.report, m.report)
        print(f"产物：{args.out}")
        print(f"报告：{args.report}")

    print(json.dumps(m.report["totals"], ensure_ascii=False))
    if errors:
        print(f"❌ 结构自检失败 {len(errors)} 项", file=sys.stderr)
        for e in errors[:20]:
            print("  -", e, file=sys.stderr)
        sys.exit(1)
    print("✅ 结构自检通过")


if __name__ == "__main__":
    main()
