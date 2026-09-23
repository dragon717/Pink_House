#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
时光馆 / 仲夏物语 → 店家商品库（ShopCatalog）迁移工具
**第三版收口版**（口径文档：docs/时光馆上新_第三版收口迁移与流程_Agent执行审查.md）

与旧版的差别（对应方案 R03–R07，旧行为标注为「旧：」）：

  R03 catalogue 漏项
      旧：画册 item 的 productCode 只要在 commerceItems 里出现过就被跳过，
          而 scope=catalogue 随后又跳过整个 commerceItems —— 同码商品两边都丢。
      新：跳过条件只看「本轮实际迁入了什么」。catalogue 模式不包含在售清单，
          因此画册成员一律保留；full 模式才按实际迁入的同码记录去重。

  R04 ID 重放漂移
      旧：unique_id() 冲突时加 -2/-3，next_id() 用全局顺序号 →
          重跑 / 扩大范围 / 改变输入顺序都会换 ID 或产生重复实体。
      新：目标 ID 由「命名空间 + 来源类型 + 来源稳定 ID」确定性推导
          （见 migration_identity.py），并持久化到 migration-map.json。
          同一来源重复执行 = no-op 或更新，绝不改名再新增。

  R05 价格分档 / 尺码表未真正迁入
      旧：只迁一个现货标量；sizeCharts 初始化后从未获得内容。
      新：迁移结构化尺码表（midsummer-style-chart.json + item.sizeChartImages）
          及其原图；定金 / 尾款 / 分档区间全部登记，缺价不伪造。

  R06 Midsummer 款式与真实 SKU
      旧：只取顶层 colors/sizes 与 sku.color/sku.size，商品分类一律「其他」。
      新：解释 specGroups → skus[].options 的真实组合；
          kind=set 的系列容器按 style 选项拆成 OP / JSK 等多个商品。
          来源没有声明的组合不做笛卡尔积补造。

  R07 未知价格伪造为 0
      旧：price 为 None 时写 price=0 的 SaleEvent（「未知」变成「免费」）。
      新：未知价格登记到 pendingPrices，**不创建 0 元销售事件**；
          业务日期（launchedOn）与抓取日期（priceCapturedOn / observedAt）分开记录。

输入：
  · ItemManager/Resources/TimeHall/catalog*.json        画册编年史种子
  · ItemManager/Resources/TimeHall/timehall-brand-meta.json
  · ItemManager/Resources/Midsummer/midsummer-series.json
  · ItemManager/Resources/Midsummer/midsummer-style-chart.json  结构化尺码表

输出（默认 output/timehall_v3_migration/<run-id>/）：
  · inventory.json        来源盘点（§7.1）
  · migration-map.json    来源 → 目标映射（§7.3，跨运行幂等）
  · candidate.json        ShopCatalog 候选包（供人工复核后并入，本工具不改种子）
  · validation.json       结构 / 外键 / 币种 / 图片 / 表格校验
  · diff.json             与既有种子逐项差异（复用 / 新增 / 更新 / 跳过 / 冲突 / 待补）
  · rollback.json         回滚信息（§10.2）
  · migration-report.json 汇总报告（§9.2 必填项）

用法：
  python3 tools/timehall_migration/migrate_timehall_to_shop_catalog.py --repo . --scope catalogue
  python3 tools/timehall_migration/migrate_timehall_to_shop_catalog.py --repo . --scope full
"""

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from migration_identity import (  # noqa: E402
    RULE_VERSION,
    IdentityMap,
    child_target_id,
    entity_target_id,
    shop_target_id,
    slug,
    stable_hash,
)

# ShopCatalog canonical categories（与 ShopCatalogStore.canonicalCategoryOrder 一致）
CANONICAL_CATEGORIES = ["JSK", "OP", "SK", "Blouse", "KC", "小物", "鞋", "包", "其他"]

# 币种（§7.5：金额必须带币种，日元不得按人民币入库，来源不明 = UNKNOWN）
JPY = "JPY"
CNY = "CNY"
UNKNOWN_CURRENCY = "UNKNOWN"

# 尺码表里常见的颜色词（用于从款式选项名里剥离颜色，派生 designName）
COLOR_TOKENS = [
    "粉色", "藍綠色", "蓝绿色", "奶白色", "生成色", "白色", "黑色", "红色", "蓝色",
    "绿色", "紫色", "黄色", "米色", "杏色", "藏青", "酒红", "浅色", "深色",
]

NAMESPACE_TIMEHALL = "timehall"
NAMESPACE_MIDSUMMER = "midsummer"


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def dump_json(path, data):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)


def now_stamp():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def parse_date(text):
    """业务日期 → ISO 日期字符串（无法解析返回 None）。"""
    if not text or not isinstance(text, str):
        return None
    m = re.match(r"\s*(\d{4})[-/](\d{2})[-/](\d{2})", text)
    if not m:
        return None
    return "{}-{}-{}T00:00:00Z".format(m.group(1), m.group(2), m.group(3))


def parse_year(text):
    if not text:
        return None
    if isinstance(text, int):
        return text
    m = re.match(r"\s*(\d{4})", str(text))
    return int(m.group(1)) if m else None


def num(value):
    """金额归一：None / 空串 / 非数字 → None（**绝不**归一成 0，见 R07）。"""
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        cleaned = value.replace(",", "").replace("¥", "").replace("￥", "").strip()
        if not cleaned:
            return None
        try:
            return float(cleaned) if "." in cleaned else int(cleaned)
        except ValueError:
            return None
    return None


# --------------------------------------------------------------------------
# 分类映射（沿用旧口径，保证既有产物 ID / 分类不漂移）
# --------------------------------------------------------------------------

def map_category(item):
    """kind/categoryZH/category → ShopCatalog 规范分类。"""
    texts = []
    for key in ("category", "categoryZH", "kind", "name", "nameZH"):
        v = item.get(key)
        if isinstance(v, str) and v.strip():
            texts.append(v.strip().lower())
        for v2 in (item.get("stylesZH") or []) + (item.get("styles") or []):
            if isinstance(v2, str):
                texts.append(v2.lower())
    joined = " ".join(texts)
    for token, label in (("jsk", "JSK"), ("op", "OP"), ("blouse", "Blouse"), ("kc", "KC")):
        if re.search(r"\b{}\b".format(token), joined):
            return label
    if "半身裙" in joined:
        return "SK"
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
    kind = item.get("kind")
    if kind == "dress":
        return "JSK"
    if kind == "clothing":
        return "Blouse"
    if kind == "accessory":
        return "小物"
    return "其他"


def source_key_for(record, file_tag):
    """来源稳定键：productCode > id > **内容寻址**。

    第三坑：来源既无 productCode 也无 id 时，旧口径（以及简单的 `or` 兜底）
    会把它们全部坍缩成同一个目标 ID（实测 `th-unknown` 吞掉了多条真实商品）。
    这里退化到内容寻址（文件名 + 名称 + 分类），保证「无 ID ≠ 同一条」。
    """
    code = record.get("productCode")
    if code:
        return str(code)
    rid = record.get("id")
    if rid:
        return str(rid)
    name = record.get("nameZH") or record.get("name") or ""
    return "anon-{}".format(stable_hash(
        "{}|{}|{}".format(file_tag, name, record.get("category") or ""), 16))


def strip_color_tokens(text):
    """从款式选项名里剥离颜色词，得到可复用的 designName。"""
    out = (text or "").strip()
    # 去掉来源里常见的「现 / 预售」前缀
    out = re.sub(r"^(现|预售|现货)\s*", "", out)
    for token in COLOR_TOKENS:
        out = out.replace(token, "")
    return re.sub(r"\s+", "", out).strip("-· ") or (text or "").strip()


# --------------------------------------------------------------------------
# 盘点（§7.1：先盘点四类输入，不只扫描 Bundle）
# --------------------------------------------------------------------------

class Inventory:

    def __init__(self, repo):
        self.repo = repo
        self.sources = []

    def add(self, source_id, kind, path, present, note=None, entities=None,
            resources=None, checksum=None, version=None, collection=None):
        self.sources.append({
            "sourceID": source_id,
            "kind": kind,
            "path": os.path.relpath(path, self.repo) if path and path.startswith(self.repo) else path,
            "present": present,
            # 未读取到的数据写「未读取 / 未纳入本轮」，**不写 0**（§7.1）
            "status": "已纳入" if present else "未读取 / 未纳入本轮",
            "collection": collection or ("已读取" if present else "未读取"),
            "version": version,
            "entityCount": entities,
            "resourceCount": resources,
            "checksum": checksum,
            "note": note,
        })

    @staticmethod
    def checksum(path):
        if not path or not os.path.exists(path):
            return None
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return "sha256:" + h.hexdigest()[:16]

    def missing(self):
        return [s for s in self.sources if not s["present"]]


# --------------------------------------------------------------------------
# 迁移主体
# --------------------------------------------------------------------------

class Migrator:

    def __init__(self, existing, identity, scope="catalogue"):
        self.existing = existing or {}
        self.identity = identity
        self.scope = scope
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
            "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "ruleVersion": RULE_VERSION,
            "scope": scope,
            "skipped": [],
            "warnings": [],
            # R07：缺价登记（**不**再写成 0 元事件）
            "pendingPrices": [],
            # R05：价格分档登记（真实来源区间，可追溯）
            "priceTiers": [],
            "unknownCurrency": [],
            "missingSizeCharts": [],
            "brokenImages": [],
            "brandMetaUnmatched": [],
            "splitContainers": [],
            "reusedShops": [],
            "counts": {},
        }
        # 本轮实际产出的商品身份键（R03 去重只按这个集合判定）
        self._produced_product_keys = set()

    # ---- 基础登记 --------------------------------------------------------
    def warn(self, text):
        if text not in self.report["warnings"]:
            self.report["warnings"].append(text)

    def find_shop_by_name(self, name):
        lowered = (name or "").strip().lower()
        if not lowered:
            return None
        for s in self.existing.get("shops", []):
            if (s.get("name") or "").strip().lower() == lowered:
                return s
            if any((a or "").strip().lower() == lowered for a in s.get("aliases") or []):
                return s
        return None

    def add_shop(self, namespace, merchant_id, name, aliases):
        existing = self.find_shop_by_name(name)
        if existing:
            shop_id = existing["id"]
            self.report["reusedShops"].append(
                {"namespace": namespace, "merchant": merchant_id,
                 "shopID": shop_id, "name": name, "reason": "既有店家同名/别名命中"})
            self.identity.resolve(
                namespace, "shop", merchant_id, "shops", shop_id,
                rule="shop-by-name", source_context={"name": name}, result="reused")
            return shop_id
        candidate = shop_target_id(namespace, merchant_id)
        shop_id = self.identity.resolve(
            namespace, "shop", merchant_id, "shops", candidate,
            rule="shop-by-merchant", source_context={"name": name})
        if any(s["id"] == shop_id for s in self.out["shops"]):
            return shop_id
        self.out["shops"].append({"id": shop_id, "name": name, "aliases": aliases})
        return shop_id

    def add_series(self, namespace, source_id, shop_id, name, year, season,
                   cover, rule="series-by-source"):
        candidate = entity_target_id(namespace, source_id)
        series_id = self.identity.resolve(
            namespace, "series", source_id, "series", candidate, rule=rule,
            source_context={"shopID": shop_id})
        for s in self.out["series"]:
            if s["id"] == series_id:
                return series_id
        self.out["series"].append({
            "id": series_id, "shopID": shop_id, "name": name,
            "year": year, "season": season, "cover": cover, "description": None,
        })
        return series_id

    def add_product(self, namespace, source_id, shop_id, series_id, name,
                    category, images, design_name=None, rule="product-by-source",
                    detail=None):
        candidate = entity_target_id(namespace, source_id)
        product_id = self.identity.resolve(
            namespace, "product", source_id, "products", candidate, rule=rule,
            source_context={"shopID": shop_id, "seriesID": series_id}, detail=detail)
        for p in self.out["products"]:
            if p["id"] == product_id:
                # 重放：只更新可补资料，绝不新建第二条
                if design_name and not p.get("designName"):
                    p["designName"] = design_name
                for img in images or []:
                    if img not in p["images"]:
                        p["images"].append(img)
                return product_id
        self.out["products"].append({
            "id": product_id, "shopID": shop_id, "seriesID": series_id,
            "name": name, "category": category, "images": images or [],
            "description": None, "designName": design_name,
        })
        return product_id

    def add_variant(self, namespace, product_id, color, size, image=None,
                    combo_source="declared"):
        """规格：ID 由「父商品 + 颜色 + 尺码」内容寻址，重放不漂移。"""
        candidate = child_target_id(namespace, product_id, "var", color, size)
        if any(v["id"] == candidate for v in self.out["variants"]):
            return
        row = {"id": candidate, "productID": product_id, "color": color, "size": size}
        if image:
            asset_id = self.add_asset(namespace, image, "productImage",
                                      context="variant-{}".format(product_id))
            row["imageAssetID"] = asset_id
        self.out["variants"].append(row)

    def add_asset(self, namespace, reference, asset_type, context=""):
        if not isinstance(reference, str) or not reference.strip():
            return None
        ref = reference.strip()
        candidate = child_target_id(namespace, context or asset_type, "asset", ref, asset_type)
        for a in self.out["assets"]:
            if a["id"] == candidate:
                return a["id"]
        self.out["assets"].append({
            "id": candidate, "type": asset_type,
            "thumbnailURL": None, "previewURL": None,
            "originalURL": ref, "width": None, "height": None,
        })
        return candidate

    # ---- 销售事件（R05 / R07） ------------------------------------------
    def add_sale_event(self, namespace, product_id, source_key, kind, price,
                       currency, deposit=None, balance=None, start_at=None,
                       end_at=None, tier_min=None, tier_max=None,
                       batch_label=None, observed_at=None, rule="event-by-source"):
        """写入一条销售事件。

        R07：price 为 None / 非正 → **不写事件**，登记到 pendingPrices。
             「未知」不等于「免费」：源数据里 `priceJPY: 0` 实测表示「未采集到」，
             写成 0 元销售事件会让商品页显示「免费」，属于伪造事实。
        R05：真实分档区间写入 priceTierMin / priceTierMax，不伪造单一标量。
        """
        if price is None or (isinstance(price, (int, float)) and price <= 0):
            self.report["pendingPrices"].append({
                "productID": product_id,
                "sourceKey": source_key,
                "kind": kind,
                "reason": "来源未提供有效价格（空值或 0，源数据中 0 表示未采集），"
                          "允许资料待补；未创建销售事件（未知 ≠ 免费）",
                "observedAt": observed_at,
            })
            return None
        if currency == UNKNOWN_CURRENCY:
            self.report["unknownCurrency"].append(
                {"productID": product_id, "kind": kind, "price": price})

        event_key = "{}|{}|{}".format(source_key, kind, price)
        candidate = child_target_id(namespace, product_id, "ev", kind, price, deposit,
                                    balance, start_at, end_at)
        self.identity.resolve(namespace, "event", event_key, "saleEvents", candidate,
                              rule=rule, source_context={"productID": product_id})
        if any(e["id"] == candidate for e in self.out["saleEvents"]):
            return candidate  # 重放：幂等，不追加第二条

        event = {
            "id": candidate,
            "productID": product_id,
            "type": kind,
            "price": price,
            "deposit": deposit,
            "balance": balance,
            "startAt": start_at,
            "endAt": end_at,
            "currency": currency,
        }
        if tier_min is not None or tier_max is not None:
            event["priceTierMin"] = tier_min
            event["priceTierMax"] = tier_max
            self.report["priceTiers"].append({
                "productID": product_id, "kind": kind,
                "tierMin": tier_min, "tierMax": tier_max, "currency": currency,
                "source": source_key,
            })
        if batch_label:
            event["batchLabel"] = batch_label
        # 抓取日期是采集元数据，**不是**业务日期（R07）：单独存，不参与档期判定
        if observed_at:
            event["observedAt"] = observed_at
        self.out["saleEvents"].append(event)
        return candidate


# --------------------------------------------------------------------------
# TimeHall
# --------------------------------------------------------------------------

def _brand_meta_index(meta_path):
    """merchantID → brand 元数据；同时对 URL 形态的 source 建一份宽松索引。"""
    if not os.path.exists(meta_path):
        return {}, {}
    data = load_json(meta_path)
    by_id, by_slug = {}, {}
    for b in data.get("brands", []):
        merchant = b.get("merchantID")
        if merchant:
            by_id[merchant] = b
            by_slug[re.sub(r"[^a-z0-9]", "", (merchant or "").lower())] = b
    return by_id, by_slug


def _match_brand_meta(source_url, by_id, by_slug):
    """source 是官网 URL、brand-meta 的键是 merchantID：按规范化 slug 双向包含匹配。"""
    if not source_url:
        return None
    if source_url in by_id:
        return by_id[source_url]
    key = re.sub(r"[^a-z0-9]", "", source_url.lower())
    for slug_key, meta in by_slug.items():
        if not slug_key:
            continue
        if slug_key in key or (len(slug_key) >= 8 and key in slug_key):
            return meta
    return None


def migrate_timehall_catalog(m, path, meta, inventory, scope="catalogue"):
    data = load_json(path)
    merchant_id = data.get("source") or os.path.basename(path)
    file_name = os.path.basename(path)

    meta_by_id, meta_by_slug = meta
    brand = _match_brand_meta(merchant_id, meta_by_id, meta_by_slug)
    if brand is None:
        m.report["brandMetaUnmatched"].append(
            {"file": file_name, "source": merchant_id,
             "reason": "品牌元数据未命中，店家名回退到 item.brand（ID 仍按 source 推导，不漂移）"})

    items = data.get("items") or []
    brand_name = None
    if brand:
        brand_name = brand.get("displayName")
    if not brand_name:
        for it in items:
            if it.get("brand"):
                brand_name = it["brand"]
                break
    brand_name = brand_name or merchant_id or file_name
    aliases = [brand.get("displayNameEN")] if brand and brand.get("displayNameEN") else []

    shop_id = m.add_shop(NAMESPACE_TIMEHALL, merchant_id, brand_name, aliases)

    # 同一文件内的 brand 与文件级店家名不一致时只报告，不擅自改归属
    # （改归属会重写既有产物 shopID，属于 ID 漂移，需人工确认后单独执行）
    distinct = sorted({it.get("brand") for it in items if it.get("brand")})
    others = [b for b in distinct if b.strip().lower() != brand_name.strip().lower()]
    if others:
        m.warn("{}：{} 个条目的 brand 与文件级店家「{}」不一致（{}…），"
               "按现状归属并在报告中登记，未自动改归属"
               .format(file_name, len(others), brand_name, others[:3]))

    inventory.add(
        "timehall:" + file_name, "画册编年史种子", path, True,
        version=data.get("version"), collection="Bundle 静态资源",
        entities=len(items), resources=sum(
            1 for it in items for k in ("coverImage",) if it.get(k)),
        checksum=Inventory.checksum(path))

    # ---- 系列：catalogues + archiveCatalogues（§7.2 两者都是 CatalogSeries） ----
    catalogue_series = {}
    for key in ("catalogues", "archiveCatalogues"):
        for cat in data.get(key) or []:
            cover = None
            if cat.get("coverImage"):
                cover = m.add_asset(NAMESPACE_TIMEHALL, cat["coverImage"], "seriesCover",
                                    context="series-{}".format(cat.get("id")))
            year = cat.get("year") or parse_year(cat.get("seasonLabel"))
            season = cat.get("seasonLabelZH") or cat.get("seasonLabel") or cat.get("season")
            sid = m.add_series(
                NAMESPACE_TIMEHALL, cat.get("id"), shop_id,
                cat.get("titleZH") or cat.get("title") or "未命名系列",
                year, season, cover,
                rule="series-from-{}".format(key))
            catalogue_series[cat.get("id")] = sid
            catalogue_series[cat.get("officialID")] = sid

    misc_series_id = [None]

    def ensure_misc_series():
        if misc_series_id[0]:
            return misc_series_id[0]
        # 「未归属」合成系列：年份未知（**不用当前年份冒充历史年份**，§5.2 步骤 2）
        sid = m.add_series(
            NAMESPACE_TIMEHALL, "{}::misc".format(slug(merchant_id)), shop_id,
            "{} 未归属系列".format(brand_name), None, None, None,
            rule="series-misc")
        misc_series_id[0] = sid
        return sid

    # ---- 商品 A：画册展品 ----
    # R03：去重只看「本轮实际迁入了什么」。catalogue 模式不包含 commerceItems，
    # 因此这里**不**因为 commerceItems 里有同码就丢弃画册成员。
    commerce_items = data.get("commerceItems") or []
    commerce_keys_in_scope = set()
    if scope == "full":
        for ci in commerce_items:
            commerce_keys_in_scope.add(source_key_for(ci, file_name))

    for item in items:
        code = item.get("productCode")
        key = source_key_for(item, file_name)
        if scope == "full" and key in commerce_keys_in_scope and code:
            # T04/T05：画册条目与在售清单同码 → **商品实体合并**（不重复建商品），
            # 但画册这条自己的价格事实必须保留：它的销售事件 ID 在 catalogue 阶段
            # 已经产出，用户引用可能已经指向它。只因为换了个 scope 就让它消失，
            # 等于「catalogue 产物合入后再跑 full 会丢记录」。
            # 因此这里只跳过商品建档，事件仍按画册来源照常写入同一目标商品。
            # 目标商品 ID：优先查历史映射（可能来自 catalogue 阶段的另一上下文），
            # 查不到就用同一把 ID 生成规则推导——两者必须一致，绝不能退回原始
            # source key，否则会写出悬空外键（validate-only 无映射时尤其容易踩到）。
            merged_product_id = (m.identity.existing_target_any_context(
                NAMESPACE_TIMEHALL, "product", key)
                or entity_target_id(NAMESPACE_TIMEHALL, key))
            m.report["skipped"].append({
                "reason": "full 模式下同 productCode 已在在售清单中迁入（商品按来源身份合并，"
                          "画册价格事实仍保留为独立销售事件）",
                "itemID": item.get("id"), "productCode": code, "file": file_name,
                "mergedInto": merged_product_id})
            m.identity.mark(NAMESPACE_TIMEHALL, "product", key, "merged",
                            detail="同码已由 commerceItems 建档，商品合并、事件保留",
                            source_context={"shopID": shop_id})
            price = num(item.get("priceJPY"))
            m.add_sale_event(
                NAMESPACE_TIMEHALL, merged_product_id or key, "item:{}".format(key),
                "stock", price, JPY,
                start_at=None,  # 画册只有 observedAt（抓取日期），不是开售日期
                observed_at=item.get("observedAt"),
                rule="event-from-priceJPY(merged)")
            continue
        image_ids = []
        for ref in ([item.get("coverImage")] if item.get("coverImage") else []) + \
                   (item.get("gallery") or []):
            aid = m.add_asset(NAMESPACE_TIMEHALL, ref, "productImage",
                              context="product-{}".format(key))
            if aid:
                image_ids.append(aid)
        series_id = catalogue_series.get(item.get("catalogueID")) or ensure_misc_series()
        name = (item.get("nameZH") or item.get("name") or "未命名商品").strip()
        product_id = m.add_product(
            NAMESPACE_TIMEHALL, key, shop_id, series_id, name,
            map_category(item), image_ids,
            design_name=strip_color_tokens(name))
        m._produced_product_keys.add(key)

        # 规格：只有来源声明的轴才展开；画册展品只给 stylesZH（无尺码轴）
        for style in (item.get("stylesZH") or item.get("styles") or []):
            m.add_variant(NAMESPACE_TIMEHALL, product_id, style, None,
                          combo_source="declared")
        if not (item.get("stylesZH") or item.get("styles")):
            m.add_variant(NAMESPACE_TIMEHALL, product_id, None, None,
                          combo_source="unspecified")

        # 价格：priceJPY → 币种 JPY；缺价登记不写事件（R07）
        price = num(item.get("priceJPY"))
        m.add_sale_event(
            NAMESPACE_TIMEHALL, product_id, "item:{}".format(key), "stock", price, JPY,
            start_at=None,  # 画册只有 observedAt（抓取日期），不是开售日期
            observed_at=item.get("observedAt"),
            rule="event-from-priceJPY")

    # ---- 商品 B：在售清单（仅 full） ----
    if scope != "full":
        if commerce_items:
            m.report["skipped"].append({
                "reason": "scope=catalogue：本轮不包含全量在售清单（{} 条），"
                          "画册成员已全部保留，不会因去重漏项".format(len(commerce_items)),
                "merchantID": merchant_id, "count": len(commerce_items),
                "file": file_name})
        return

    for ci in commerce_items:
        key = source_key_for(ci, file_name)
        image_ids = []
        for ref in ([ci.get("coverImage")] if ci.get("coverImage") else []) + \
                   ([ci.get("detailImage")] if ci.get("detailImage") else []):
            aid = m.add_asset(NAMESPACE_TIMEHALL, ref, "productImage",
                              context="product-{}".format(key))
            if aid:
                image_ids.append(aid)
        name = (ci.get("nameZH") or ci.get("name") or "未命名商品").strip()
        product_id = m.add_product(
            NAMESPACE_TIMEHALL, key, shop_id, ensure_misc_series(), name,
            map_category(ci), image_ids, design_name=strip_color_tokens(name))
        m._produced_product_keys.add(key)

        colors = [c for c in (ci.get("colors") or []) if isinstance(c, str) and c.strip()]
        sizes = [s for s in (ci.get("sizes") or []) if isinstance(s, str) and s.strip()]
        if colors or sizes:
            for c in (colors or [None]):
                for s in (sizes or [None]):
                    m.add_variant(NAMESPACE_TIMEHALL, product_id, c, s,
                                  combo_source="declared-axes")
        else:
            m.add_variant(NAMESPACE_TIMEHALL, product_id, None, None,
                          combo_source="unspecified")

        # 在售：salePriceJPY 优先，否则 regularPriceJPY；两者都缺 → 待补
        sale_price = num(ci.get("salePriceJPY"))
        regular_price = num(ci.get("regularPriceJPY"))
        if sale_price is not None and regular_price is not None and sale_price != regular_price:
            # 真实分档：挂牌价 / 促销价构成区间，两者都保留（R05）
            m.add_sale_event(
                NAMESPACE_TIMEHALL, product_id, "ci:{}".format(key), "stock",
                sale_price, JPY, tier_min=min(sale_price, regular_price),
                tier_max=max(sale_price, regular_price),
                observed_at=ci.get("observedAt"), rule="event-from-commerce-tier")
        else:
            m.add_sale_event(
                NAMESPACE_TIMEHALL, product_id, "ci:{}".format(key), "stock",
                sale_price if sale_price is not None else regular_price, JPY,
                observed_at=ci.get("observedAt"), rule="event-from-commerce")


# --------------------------------------------------------------------------
# Midsummer（R06：specGroups / skus.options / set 容器拆分）
# --------------------------------------------------------------------------

def _style_group(item):
    """找出「款式」维度：role=variant 或 id=style 的 specGroup。"""
    for group in item.get("specGroups") or []:
        gid = (group.get("id") or "").lower()
        role = (group.get("role") or "").lower()
        if gid == "style" or role == "variant":
            if group.get("options"):
                return group
    return None


def _options_index(item):
    """specGroup id → {option id: option}（用于把 skus.options 还原成真实值）。"""
    index = {}
    for group in item.get("specGroups") or []:
        gid = group.get("id")
        index[gid] = {}
        for opt in group.get("options") or []:
            index[gid][opt.get("id")] = opt
    return index


def _size_group_values(item):
    for group in item.get("specGroups") or []:
        if (group.get("id") or "").lower() == "size" or (group.get("role") or "").lower() == "size":
            return [(o.get("name") or o.get("id")) for o in group.get("options") or []]
    return None


def migrate_midsummer(m, series_path, chart_path, inventory):
    data = load_json(series_path)
    brand_id = data.get("brandID") or "midsummer-tale"
    shop_id = m.add_shop(
        NAMESPACE_MIDSUMMER, brand_id, data.get("brandName") or "仲夏物语",
        [data.get("brandNameEN")] if data.get("brandNameEN") else [])

    inventory.add(
        "midsummer:series", "品牌系列源数据", series_path, True,
        collection="Bundle 静态资源", entities=len(data.get("series") or []),
        checksum=Inventory.checksum(series_path))

    # 结构化尺码表：categories[].charts[]（headers + rows + imageName）
    # 按来源 URL 归组，只归属真正属于该来源的条目（防跨系列错挂）
    chart_bundle = {"all": [], "byURL": {}}
    if chart_path and os.path.exists(chart_path):
        chart_data = load_json(chart_path)
        source_urls = [(s.get("url") or "").strip() for s in chart_data.get("sources") or []]
        source_urls = [u for u in source_urls if u]
        for cat in chart_data.get("categories") or []:
            for ch in cat.get("charts") or []:
                entry = {
                    "categoryID": cat.get("id"),
                    "categoryName": cat.get("name"),
                    "title": ch.get("title"),
                    "headers": ch.get("headers") or [],
                    "rows": ch.get("rows") or [],
                    "imageName": ch.get("imageName"),
                }
                chart_bundle["all"].append(entry)
                for url in source_urls:
                    chart_bundle["byURL"].setdefault(url, []).append(entry)
        inventory.add(
            "midsummer:style-chart", "结构化尺码表", chart_path, True,
            collection="Bundle 静态资源", entities=len(chart_bundle["all"]),
            checksum=Inventory.checksum(chart_path),
            note="categories[].charts[] → CatalogSizeChart（headers/rows/原图）；"
                 "按 sources[].url 归属，仅限对应商品页条目")
    else:
        inventory.add("midsummer:style-chart", "结构化尺码表", chart_path, False,
                      note="文件不存在，本轮未纳入；尺码表结构化内容将缺失")

    for series in data.get("series") or []:
        series_id = m.add_series(
            NAMESPACE_MIDSUMMER, series.get("id"), shop_id,
            series.get("name") or "未命名系列",
            series.get("year") or parse_year(series.get("launchedOn")),
            None,
            m.add_asset(NAMESPACE_MIDSUMMER, series.get("coverImage"), "seriesCover",
                        context="series-{}".format(series.get("id")))
            if series.get("coverImage") else None,
            rule="series-from-midsummer")

        # 业务日期 = launchedOn；抓取日期 = priceCapturedOn（两者分开，R07）
        business_date = parse_date(series.get("launchedOn"))
        captured_on = parse_date(series.get("priceCapturedOn"))
        stage = series.get("stage")

        for item in series.get("items") or []:
            _migrate_midsummer_item(
                m, shop_id, series_id, series, item, chart_bundle,
                business_date, captured_on, stage)


def _migrate_midsummer_item(m, shop_id, series_id, series, item, chart_bundle,
                            business_date, captured_on, stage):
    charts = _charts_for_item(item, chart_bundle)
    options_index = _options_index(item)
    style_group = _style_group(item)
    skus = [s for s in (item.get("skus") or []) if isinstance(s, dict)]
    item_name = (item.get("name") or "").strip()

    # 系列级定金分档（R05：真实来源区间，登记到报告，不据此伪造单品事件）
    deposit_min, deposit_max = num(series.get("depositMin")), num(series.get("depositMax"))
    if deposit_min is not None or deposit_max is not None:
        m.report["priceTiers"].append({
            "seriesID": series_id, "kind": "deposit",
            "tierMin": deposit_min, "tierMax": deposit_max, "currency": CNY,
            "source": "series.depositMin/depositMax（系列级定金区间，非单品事实）",
        })

    # ---- 容器判定（R06：kind=set 且存在款式维度 → 按款式拆成多个商品） ----
    is_container = (item.get("kind") == "set") and style_group is not None \
        and len(style_group.get("options") or []) > 1
    style_options = (style_group.get("options") or []) if (style_group and is_container) else [None]

    for option in style_options:
        if option is None:
            source_key = item.get("id")
            display = item_name or series.get("name") or "未命名商品"
            category = map_category(item)
            design_name = strip_color_tokens(display)
            style_label = None
        else:
            source_key = "{}::{}".format(item.get("id"), option.get("id"))
            opt_name = (option.get("name") or option.get("id") or "").strip()
            display = opt_name if item_name and item_name in opt_name \
                else "{} {}".format(item_name, opt_name).strip()
            # 款式决定品类：OP / JSK 不是普通颜色规格
            category = map_category({"name": opt_name, "nameZH": opt_name, "kind": item.get("kind")})
            design_name = strip_color_tokens(opt_name)
            style_label = opt_name

        # 商品图：款式图优先，其次条目主图
        image_refs = []
        if option is not None and option.get("image"):
            image_refs.append(option["image"])
        elif item.get("coverImage"):
            image_refs.append(item["coverImage"])
        for extra in (item.get("galleryImageNames") or []):
            if option is not None and option.get("image"):
                break
            image_refs.append(extra)
        image_ids = []
        for ref in image_refs:
            aid = m.add_asset(NAMESPACE_MIDSUMMER, ref, "productImage",
                              context="product-{}".format(source_key))
            if aid and aid not in image_ids:
                image_ids.append(aid)

        product_id = m.add_product(
            NAMESPACE_MIDSUMMER, source_key, shop_id, series_id, display,
            category, image_ids, design_name=design_name,
            rule="product-from-style-option" if option is not None else "product-from-item",
            detail=("由系列容器 {} 按款式拆分".format(item.get("id"))
                    if option is not None else None))

        if option is not None:
            m.report["splitContainers"].append({
                "sourceItemID": item.get("id"),
                "styleOptionID": option.get("id"),
                "targetProductID": product_id,
                "category": category,
            })

        # ---- 规格：真实 SKU 优先（R06：不为不存在的组合做笛卡尔积） ----
        sku_count = 0
        for sku in skus:
            opts = sku.get("options") or {}
            if option is not None and opts.get("style") != option.get("id"):
                continue
            color_id = opts.get("color")
            size_id = opts.get("size")
            color = None
            size = None
            if color_id and color_id in options_index.get("color", {}):
                color = options_index["color"][color_id].get("name") or color_id
            elif color_id:
                color = color_id
            if size_id and size_id in options_index.get("size", {}):
                size = options_index["size"][size_id].get("name") or size_id
            elif size_id:
                size = size_id
            image = sku.get("image") or (option or {}).get("image")
            m.add_variant(NAMESPACE_MIDSUMMER, product_id, color, size, image=image,
                          combo_source="sku")
            sku_count += 1

        if sku_count == 0:
            # 无 SKU：只用来源显式声明的轴，并标记为「来源声明轴」而非真实组合
            colors = [c for c in (item.get("colors") or []) if isinstance(c, str) and c.strip()]
            sizes = [s for s in (item.get("sizes") or []) if isinstance(s, str) and s.strip()]
            if not sizes:
                sizes = [v for v in (_size_group_values(item) or []) if v]
            if colors or sizes:
                for c in (colors or [None]):
                    for s in (sizes or [None]):
                        m.add_variant(NAMESPACE_MIDSUMMER, product_id, c, s,
                                      combo_source="declared-axes")
            else:
                m.add_variant(NAMESPACE_MIDSUMMER, product_id, None, None,
                              combo_source="unspecified")
            m.warn("{}：无 SKU 数据，规格按来源声明的颜色/尺码轴展开（非真实组合清单）"
                   .format(product_id))

        # ---- 尺码表（R05：结构化内容 + 原图，两者独立缺失都要报告） ----
        _attach_size_chart(m, product_id, item, charts,
                           _style_keys(option, style_label), display)

        # ---- 价格（R07：未知不写事件；定金/尾款只有真实值才对账） ----
        price = num(item.get("price"))
        deposit = num(item.get("deposit"))
        balance = num(item.get("balance"))
        sku_prices = sorted({
            num(s.get("price")) for s in skus
            if num(s.get("price")) is not None
            and (option is None or (s.get("options") or {}).get("style") == option.get("id"))
        }) if skus else []
        tier_min = tier_max = None
        if len(sku_prices) > 1:
            tier_min, tier_max = min(sku_prices), max(sku_prices)
        if price is None and sku_prices:
            # SKU 挂牌价是来源给出的**真实价格**（商品页逐项价），不是推断。
            # 多档时取最低档为保守代表值，区间一并入库，不伪造单一标量。
            price = sku_prices[0]

        # 业务类型：定金 > 阶段 > 价格性质；都判不出就登记待补，不硬塞在售
        if deposit is not None:
            kind = "reservation"
        elif stage == "inStock":
            kind = "stock"
        elif stage in ("deposit", "balance"):
            kind = "reservation"
        elif item.get("priceKind") in ("shop", "reference"):
            kind = "stock"
        else:
            kind = None

        if kind is None:
            m.report["pendingPrices"].append({
                "productID": product_id,
                "sourceKey": "item:{}".format(source_key),
                "kind": "unknown",
                "reason": "阶段「{}」与价格性质不足以判定销售类型；"
                          "未创建销售事件（来源未声明则不得推断为在售）".format(stage or "未标注"),
                "observedAt": captured_on,
            })
            return

        if kind == "reservation":
            total = price
            if total is None and balance is not None and deposit is not None:
                total = deposit + balance
            if balance is None and total is not None and deposit is not None:
                balance = total - deposit
            m.add_sale_event(
                NAMESPACE_MIDSUMMER, product_id, "item:{}".format(source_key),
                "reservation", total, CNY, deposit=deposit, balance=balance,
                start_at=business_date, tier_min=tier_min, tier_max=tier_max,
                observed_at=captured_on, rule="event-from-deposit")
        else:
            m.add_sale_event(
                NAMESPACE_MIDSUMMER, product_id, "item:{}".format(source_key),
                "stock", price, CNY, start_at=business_date,
                tier_min=tier_min, tier_max=tier_max,
                batch_label=("参考价" if item.get("priceKind") == "reference" else None),
                observed_at=captured_on, rule="event-from-stage")


def _normalize_style(text):
    """款式名归一：去序号 / 空格 / 大小写，用于尺码表精确配对。

    「② 定位花 JSK」与「定位花JSK」与「现 定位花jsk 粉色」（剥离颜色后）
    必须落到同一把钥匙；同时不能让「JSK」模糊命中「定位花 JSK」——
    早期实现用子串模糊匹配，把樱花小羊的尺码表挂到了小熊博物馆的 JSK 上。
    """
    out = re.sub(r"^[①-⑳\d]+", "", (text or "").strip())
    return re.sub(r"[\s・·]+", "", out).lower()


def _charts_for_item(item, chart_bundle):
    """结构化尺码表按来源 URL 精确归属。

    midsummer-style-chart.json 只覆盖特定淘宝商品页（sources[].url）。
    不属于该来源的条目**不参与**匹配，避免跨系列错挂尺码表。
    """
    if not chart_bundle:
        return []
    # 顺序敏感：itemURL（商品页）优先于 sourceURL（图鉴页）。
    # 用集合迭代会让「同一条目两次迁移拿到不同尺码表」，破坏幂等。
    for url in ((item.get("itemURL") or "").strip(),
                (item.get("sourceURL") or "").strip()):
        if url and url in chart_bundle.get("byURL", {}):
            return chart_bundle["byURL"][url]
    return []


def _style_keys(option, style_label):
    """尺码表配对的候选钥匙（按可信度排序）：选项 id > 剥离颜色后的选项名。

    同一个款式在来源里有三种写法：option.id（`op`）、option.name
    （`切替 OP`）、带颜色的 option.name（`现 sk 粉色`）。
    只有把它们都归一后比对，才能既配对上又不与「定位花JSK / JSK」互相误命中。
    """
    keys = []
    if option is not None:
        oid = option.get("id")
        if oid:
            keys.append(oid)
    if style_label:
        keys.append(strip_color_tokens(style_label))
    return keys


def _attach_size_chart(m, product_id, item, charts, style_keys, display):
    """结构化尺码表 + 原图（可独立缺失，缺失必须报告，§7.6）。

    配对口径（先精确后兜底）：
      1. 用 `sizeChartImages[].style` 与款式候选钥匙归一后**相等**配对，取该款原图；
      2. 再用同一把钥匙在结构化表里配对 headers / rows；
      3. 只有当条目本身没有任何款式维度（整条 = 一个商品）时才允许取第一张。
    """
    entries = [e for e in (item.get("sizeChartImages") or []) if isinstance(e, dict)]
    normalized_keys = [_normalize_style(k) for k in (style_keys or []) if k]

    matched_entry = None
    for key in normalized_keys:
        for entry in entries:
            if key and _normalize_style(entry.get("style")) == key:
                matched_entry = entry
                break
        if matched_entry is not None:
            break
    if matched_entry is None and not normalized_keys and entries:
        # 整条条目就是一个商品（无款式维度）→ 只有一张表，取它
        matched_entry = entries[0]

    selected = None
    if charts and matched_entry is not None:
        want = _normalize_style(matched_entry.get("style"))
        for ch in charts:
            if _normalize_style(ch.get("categoryName")) == want:
                selected = ch
                break

    image_name = matched_entry.get("imageName") if matched_entry else None
    has_structured = bool(selected and selected.get("headers") and selected.get("rows"))

    if not has_structured and not image_name:
        m.report["missingSizeCharts"].append({
            "productID": product_id,
            "reason": "来源未提供尺码表（既无结构化内容也无原图）",
        })
        return
    if not has_structured:
        m.report["missingSizeCharts"].append({
            "productID": product_id,
            "reason": "只有尺码表原图，缺结构化内容（详情页需给出明确提示，不能按完整表呈现）",
        })
    if has_structured and not image_name:
        m.report["missingSizeCharts"].append({
            "productID": product_id,
            "reason": "有结构化尺码表但缺原图",
        })

    source_image = None
    if image_name:
        source_image = m.add_asset(NAMESPACE_MIDSUMMER, image_name, "sizeChartImage",
                                   context="chart-{}".format(product_id))

    chart_id = child_target_id(NAMESPACE_MIDSUMMER, product_id, "chart")
    if any(c["id"] == chart_id for c in m.out["sizeCharts"]):
        return
    columns = list(selected.get("headers") or []) if selected else []
    rows = []
    if selected:
        for row in selected.get("rows") or []:
            if not row:
                continue
            label = row[0] if isinstance(row[0], str) else str(row[0])
            values = [None if v is None else str(v) for v in row[1:]]
            rows.append({"label": label, "values": values})
    m.out["sizeCharts"].append({
        "id": chart_id, "productID": product_id,
        "unit": "cm", "columns": columns, "rows": rows,
        "sourceImage": source_image,
    })


# --------------------------------------------------------------------------
# 校验（§7.5 / §7.6）
# --------------------------------------------------------------------------

def validate_output(out, existing=None):
    """结构 + 外键 + 币种 + 图片 + 表格校验。"""
    errors = []
    warnings = []
    merged_shops = list((existing or {}).get("shops", [])) + out["shops"]
    shop_ids = {s["id"] for s in merged_shops}
    series_ids = {s["id"] for s in out["series"]} | {s["id"] for s in (existing or {}).get("series", [])}
    product_ids = {p["id"] for p in out["products"]}

    required = {
        "shops": ["id", "name", "aliases"],
        "series": ["id", "shopID", "name"],
        "products": ["id", "shopID", "seriesID", "name", "category", "images"],
        "variants": ["id", "productID"],
        "sizeCharts": ["id", "productID"],
        "saleEvents": ["id", "productID", "type", "price"],
        "assets": ["id", "type", "originalURL"],
    }
    for entity, keys in required.items():
        for e in out.get(entity, []):
            for k in keys:
                if k not in e:
                    errors.append("{} 缺字段 {}: {}".format(entity, k, e.get("id")))

    for s in out["series"]:
        if s["shopID"] not in shop_ids:
            errors.append("series {} 悬空 shopID {}".format(s["id"], s["shopID"]))
    for p in out["products"]:
        if p["shopID"] not in shop_ids:
            errors.append("product {} 悬空 shopID {}".format(p["id"], p["shopID"]))
        if p["seriesID"] not in series_ids:
            errors.append("product {} 悬空 seriesID {}".format(p["id"], p["seriesID"]))
    for v in out["variants"]:
        if v["productID"] not in product_ids:
            errors.append("variant {} 悬空 productID {}".format(v["id"], v["productID"]))
    for c in out["sizeCharts"]:
        if c["productID"] not in product_ids:
            errors.append("sizeChart {} 悬空 productID {}".format(c["id"], c["productID"]))
    for e in out["saleEvents"]:
        if e["productID"] not in product_ids:
            errors.append("saleEvent {} 悬空 productID {}".format(e["id"], e["productID"]))
        if e["type"] not in ("reservation", "stock", "rerelease"):
            errors.append("saleEvent {} 非法 type {}".format(e["id"], e["type"]))
        # R02/R07：金额必须带币种，且不允许 0 元「未知价」事件
        if not e.get("currency"):
            errors.append("saleEvent {} 缺币种（日元不得按人民币入库）".format(e["id"]))
        elif e["currency"] not in (JPY, CNY, UNKNOWN_CURRENCY):
            errors.append("saleEvent {} 非法币种 {}".format(e["id"], e["currency"]))
        if e.get("currency") == UNKNOWN_CURRENCY:
            warnings.append("saleEvent {} 币种待确认".format(e["id"]))
        if e.get("price") == 0:
            errors.append("saleEvent {} 价格为 0（未知价格不得写成免费销售事件）".format(e["id"]))
        if e.get("deposit") is not None and e.get("balance") is not None \
                and e.get("price") is not None:
            try:
                if float(e["deposit"]) + float(e["balance"]) != float(e["price"]):
                    warnings.append(
                        "saleEvent {} 定金 + 尾款 ≠ 价格（{} + {} ≠ {}）".format(
                            e["id"], e["deposit"], e["balance"], e["price"]))
            except (TypeError, ValueError):
                pass
    for a in out["assets"]:
        if a["type"] not in ("productImage", "sizeChartImage", "seriesCover", "shopCover"):
            errors.append("asset {} 非法 type {}".format(a["id"], a["type"]))
        if not a.get("originalURL"):
            errors.append("asset {} 缺 originalURL（原图必须保留）".format(a["id"]))

    for entity in ("shops", "series", "products", "variants", "sizeCharts", "saleEvents", "assets"):
        ids = [e["id"] for e in out.get(entity, [])]
        if len(ids) != len(set(ids)):
            dupes = sorted({i for i in ids if ids.count(i) > 1})
            errors.append("{} 存在重复 id：{}".format(entity, dupes[:5]))
    return errors, warnings


def build_diff(out, existing, identity):
    """与既有种子的逐项差异（§9.2：复用 / 新增 / 更新 / 跳过 / 冲突 / 待补）。"""
    existing_ids = {}
    for key in ("shops", "series", "products", "variants", "sizeCharts", "saleEvents", "assets"):
        existing_ids[key] = {e.get("id") for e in (existing or {}).get(key, [])}
    diff = {}
    for key in ("shops", "series", "products", "variants", "sizeCharts", "saleEvents", "assets"):
        new_ids = [e["id"] for e in out.get(key, [])]
        diff[key] = {
            "candidate": len(new_ids),
            "reused": len([i for i in new_ids if i in existing_ids[key]]),
            "added": len([i for i in new_ids if i not in existing_ids[key]]),
            "addedIDs": sorted(i for i in new_ids if i not in existing_ids[key])[:50],
        }
    diff["identityResults"] = identity.totals()
    diff["conflicts"] = identity.conflicts
    return diff


def build_inventory(repo, inventory, out, identity):
    inventory.sources.append({
        "sourceID": "user-private-state",
        "kind": "用户私有状态（treasured 集合 / 迁移标记 / 心愿尾款 / 衣橱引用）",
        "path": None,
        "present": False,
        "status": "未读取 / 未纳入本轮",
        "collection": "未读取",
        "note": "本机安全迁移，不塞入公共 Catalog 导出包（§7.1）",
    })
    inventory.sources.append({
        "sourceID": "cloud-public",
        "kind": "旧公共云端数据（CloudKit）",
        "path": None,
        "present": False,
        "status": "未读取 / 未纳入本轮",
        "collection": "未读取",
        "note": "只有取得真实导出 / 读取报告才能计为已迁移；"
                "读取 Bundle 不证明云端存量已覆盖（§7.1）",
    })
    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "ruleVersion": RULE_VERSION,
        "sources": inventory.sources,
        "candidateTotals": {k: len(v) for k, v in out.items() if isinstance(v, list)},
        "identityTotals": identity.totals(),
    }


def build_rollback(run_id, out, existing, diff, inventory):
    """回滚信息（§10.2）：切换前保留旧公共快照与本次新增实体清单。"""
    return {
        "runID": run_id,
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "candidateTotals": {k: len(v) for k, v in out.items() if isinstance(v, list)},
        "newEntityIDs": {k: v["addedIDs"] for k, v in diff.items()
                         if isinstance(v, dict) and "addedIDs" in v},
        "reusedEntityIDs": {k: v["reused"] for k, v in diff.items()
                            if isinstance(v, dict) and "reused" in v},
        "steps": [
            "候选包未经人工复核不得并入种子 / 覆盖层",
            "回滚公共档案：切回校验通过的旧公共快照，并记录本次新增 / 更新实体与版本",
            "回滚私人数据：本工具不触碰用户私有状态，无需回滚",
            "图片资源：确认无旧 / 新公共档案和个人记录引用后才清理",
            "云端源数据：本轮不删除",
        ],
        "untouchedSources": [s["sourceID"] for s in inventory.missing()],
    }


# --------------------------------------------------------------------------
# 入口
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="TimeHall/Midsummer → ShopCatalog 迁移（第三版收口）")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)))), help="仓库根目录")
    ap.add_argument("--scope", choices=["catalogue", "full"], default="catalogue",
                    help="catalogue=画册年鉴；full=含全量在售清单（§7.4）")
    ap.add_argument("--out-dir", default=None, help="产物目录（默认 output/timehall_v3_migration/<run-id>）")
    ap.add_argument("--run-id", default=None)
    ap.add_argument("--map-path", default=None,
                    help="迁移映射表路径（跨运行复用；默认在产物目录内）")
    ap.add_argument("--validate-only", action="store_true", help="只跑自检与统计，不写产物")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    th_dir = os.path.join(repo, "ItemManager", "Resources", "TimeHall")
    ms_json = os.path.join(repo, "ItemManager", "Resources", "Midsummer", "midsummer-series.json")
    ms_chart = os.path.join(repo, "ItemManager", "Resources", "Midsummer", "midsummer-style-chart.json")
    seed_path = os.path.join(repo, "ItemManager", "Resources", "ShopCatalog", "shop-catalog.json")

    run_id = args.run_id or now_stamp()
    out_dir = args.out_dir or os.path.join(repo, "output", "timehall_v3_migration", run_id)
    map_path = args.map_path or os.path.join(out_dir, "migration-map.json")

    existing = load_json(seed_path) if os.path.exists(seed_path) else {}
    inventory = Inventory(repo)
    inventory.add("shopcatalog:seed", "现有 ShopCatalog 种子", seed_path,
                  os.path.exists(seed_path),
                  collection="Bundle 静态资源",
                  entities=sum(len(v) for v in existing.values() if isinstance(v, list)),
                  checksum=Inventory.checksum(seed_path),
                  note="差异比对基线")
    inventory.add("timehall:brand-meta", "品牌元数据",
                  os.path.join(th_dir, "timehall-brand-meta.json"),
                  os.path.exists(os.path.join(th_dir, "timehall-brand-meta.json")),
                  collection="Bundle 静态资源",
                  checksum=Inventory.checksum(os.path.join(th_dir, "timehall-brand-meta.json")))

    identity = IdentityMap(map_path)
    meta = _brand_meta_index(os.path.join(th_dir, "timehall-brand-meta.json"))
    m = Migrator(existing, identity, scope=args.scope)

    for fname in sorted(os.listdir(th_dir)):
        if fname.startswith("catalog") and fname.endswith(".json"):
            migrate_timehall_catalog(m, os.path.join(th_dir, fname), meta, inventory,
                                     scope=args.scope)

    if os.path.exists(ms_json):
        migrate_midsummer(m, ms_json, ms_chart, inventory)
    else:
        inventory.add("midsummer:series", "品牌系列源数据", ms_json, False,
                      note="文件不存在，本轮未纳入")

    errors, warnings = validate_output(m.out, existing)
    diff = build_diff(m.out, existing, identity)
    m.report["validationErrors"] = errors
    m.report["validationWarnings"] = warnings
    m.report["totals"] = {k: len(v) for k, v in m.out.items() if isinstance(v, list)}
    m.report["diff"] = diff
    m.report["identityConflicts"] = identity.conflicts
    m.report["counts"] = {
        "skipped": len(m.report["skipped"]),
        "pendingPrices": len(m.report["pendingPrices"]),
        "priceTiers": len(m.report["priceTiers"]),
        "missingSizeCharts": len(m.report["missingSizeCharts"]),
        "splitContainers": len(m.report["splitContainers"]),
        "unknownCurrency": len(m.report["unknownCurrency"]),
    }

    print(json.dumps(m.report["totals"], ensure_ascii=False))
    print("身份映射：{}".format(json.dumps(identity.totals(), ensure_ascii=False)))
    print("冲突：{} 条".format(len(identity.conflicts)))

    if args.validate_only:
        if errors:
            print("❌ 结构自检失败 {} 项".format(len(errors)), file=sys.stderr)
            for e in errors[:20]:
                print("  -", e, file=sys.stderr)
            sys.exit(1)
        print("✅ 结构自检通过（validate-only，未写产物）")
        return

    dump_json(os.path.join(out_dir, "inventory.json"), build_inventory(repo, inventory, m.out, identity))
    dump_json(os.path.join(out_dir, "candidate.json"), m.out)
    dump_json(os.path.join(out_dir, "validation.json"),
              {"errors": errors, "warnings": warnings,
               "errorCount": len(errors), "warningCount": len(warnings)})
    dump_json(os.path.join(out_dir, "diff.json"), diff)
    dump_json(os.path.join(out_dir, "migration-report.json"), m.report)
    dump_json(os.path.join(out_dir, "rollback.json"),
              build_rollback(run_id, m.out, existing, diff, inventory))
    # 映射表写两处：--map-path（跨运行复用链）+ 本次产物目录（留档可审计）
    identity.save(map_path)
    if os.path.abspath(map_path) != os.path.abspath(os.path.join(out_dir, "migration-map.json")):
        identity.save(os.path.join(out_dir, "migration-map.json"))

    print("产物目录：{}".format(out_dir))
    if errors:
        print("❌ 结构自检失败 {} 项".format(len(errors)), file=sys.stderr)
        for e in errors[:20]:
            print("  -", e, file=sys.stderr)
        sys.exit(1)
    print("✅ 结构自检通过")


if __name__ == "__main__":
    main()
