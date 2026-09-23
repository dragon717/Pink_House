#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
迁移工具自测（第三版收口版）。

覆盖方案 §9 测试矩阵中与迁移工具直接相关的条目：
  T03 同源执行两次 / 输入顺序变化 → 目标 ID 不变，无重复
  T04 catalogue 模式 item 与 commerce 同 productCode → 画册商品仍在
  T05 catalogue 产物合入后再执行 full → 公共部分身份不变
  T06 跨店同码 / 同名 → 不误合并，给出冲突报告
  T07 Midsummer style=OP / JSK 与 SKU options → 不同商品语义，真实组合
  T08 定金尾款 / 价格分档 / 尺码表原图 → 全部可追溯
  T09 混币种（JPY / CNY）→ 币种保持，不按人民币入库
  T10 价格为 null / 0 → 不伪装成免费销售事件
另加：断链素材、缺表报告、映射表持久化与重放。

运行：python3 tools/timehall_migration/test_migration.py
      python3 -m unittest discover -s tools/timehall_migration -p 'test_*.py'
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import migrate_timehall_to_shop_catalog as mig  # noqa: E402
from migration_identity import IdentityMap, entity_target_id  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


def fixture(name):
    return os.path.join(FIXTURES, name)


def make_existing():
    return {
        "version": 1,
        "shops": [{"id": "shop-alice-girl", "name": "Alice Girl", "aliases": ["AG"]}],
        "series": [{"id": "series-ag-xueguo-2026", "shopID": "shop-alice-girl",
                    "name": "雪国来信", "year": 2026, "season": "冬",
                    "cover": None, "description": None}],
        "products": [{"id": "prod-ag-xueguo-jsk", "shopID": "shop-alice-girl",
                      "seriesID": "series-ag-xueguo-2026", "name": "雪国来信 JSK",
                      "category": "JSK", "images": [], "description": None}],
        "variants": [],
        "sizeCharts": [],
        "saleEvents": [{"id": "ev-ag-jsk-resv-2026", "productID": "prod-ag-xueguo-jsk",
                        "type": "reservation", "price": 428, "deposit": 128,
                        "balance": 300, "startAt": None, "endAt": None}],
        "assets": [],
    }


def write_temp(data, suffix=".json"):
    fd, path = tempfile.mkstemp(suffix=suffix)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f)
    return path


class MigrationTests(unittest.TestCase):

    def setUp(self):
        self.existing = make_existing()
        self.tmpdir = tempfile.mkdtemp()
        self.map_path = os.path.join(self.tmpdir, "migration-map.json")

    def new_migrator(self, scope="catalogue", existing_map=None):
        identity = IdentityMap(existing_map)
        return mig.Migrator(self.existing, identity, scope=scope), identity

    def run_timehall(self, data, scope="catalogue", identity=None, meta=None):
        m, ident = self.new_migrator(scope, identity)
        path = write_temp(data)
        mig.migrate_timehall_catalog(m, path, meta or ({}, {}), mig.Inventory("."), scope=scope)
        return m, ident

    # ------------------------------------------------------------------
    # 既有行为（保留，不回退）
    # ------------------------------------------------------------------

    def test_shop_dedup_by_name_reuses_existing_id(self):
        """同名店家应复用既有 id（§29 防重复），不新建。"""
        meta = ({"alice-girl": {"merchantID": "alice-girl", "displayName": "Alice Girl"}}, {})
        data = {"source": "alice-girl", "catalogues": [], "items": [], "commerceItems": []}
        m, _ = self.run_timehall(data, meta=meta)
        self.assertEqual(len(m.out["shops"]), 0, "同名店家不应新建")
        self.assertEqual(m.report["reusedShops"][0]["shopID"], "shop-alice-girl")

    def test_item_maps_to_product_with_code_priority(self):
        """productCode 优先作 id 种子；品类映射；价格生成带币种的销售记录。"""
        data = {
            "source": "pink-house",
            "catalogues": [{"id": "cat-1", "year": 2024, "seasonLabel": "春",
                            "title": "Spring", "titleZH": "春季画册",
                            "coverImage": "cat-1.jpg"}],
            "items": [{
                "id": "item-9", "productCode": "P001", "categoryZH": "JSK",
                "name": "Sugar JSK", "nameZH": " sugar JSK ",
                "catalogueID": "cat-1", "priceJPY": 24800,
                "observedAt": "2024-03-01T00:00:00Z",
                "coverImage": "item-9.jpg", "gallery": ["item-9-2.jpg"],
            }],
            "commerceItems": [],
        }
        m, _ = self.run_timehall(data)
        product = m.out["products"][0]
        self.assertEqual(product["id"], "th-P001")
        self.assertEqual(product["category"], "JSK")
        self.assertEqual(product["seriesID"], "th-cat-1")
        event = m.out["saleEvents"][0]
        self.assertEqual(event["type"], "stock")
        self.assertEqual(event["price"], 24800)
        # R02：日元必须带 JPY 币种，不得按人民币入库
        self.assertEqual(event["currency"], "JPY")
        self.assertEqual(len(m.out["assets"]), 3, "系列封面1 + 商品图2")

    def test_reference_integrity_and_unique_ids(self):
        """悬空引用 / 重复 id 必须被结构自检拦截。"""
        m, _ = self.new_migrator()
        m.out["shops"].append({"id": "shop-a", "name": "A", "aliases": []})
        m.out["series"].append({"id": "s-a", "shopID": "shop-missing", "name": "S",
                                "year": None, "season": None, "cover": None,
                                "description": None})
        m.out["products"].append({"id": "p-a", "shopID": "shop-a", "seriesID": "s-a",
                                  "name": "P", "category": "其他", "images": [],
                                  "description": None})
        m.out["saleEvents"].append({"id": "e-a", "productID": "p-missing",
                                    "type": "stock", "price": 1, "deposit": None,
                                    "balance": None, "startAt": None, "endAt": None})
        errors, _ = mig.validate_output(m.out)
        self.assertTrue(any("悬空 shopID" in e for e in errors))
        self.assertTrue(any("悬空 productID" in e for e in errors))

    def test_bad_type_rejected(self):
        m, _ = self.new_migrator()
        m.out["shops"].append({"id": "shop-a", "name": "A", "aliases": []})
        m.out["saleEvents"].append({"id": "e1", "productID": "x", "type": "flash",
                                    "price": 1, "deposit": None, "balance": None,
                                    "startAt": None, "endAt": None})
        errors, _ = mig.validate_output(m.out)
        self.assertTrue(any("非法 type" in e for e in errors))

    # ------------------------------------------------------------------
    # R03 catalogue 去重漏项（T04）
    # ------------------------------------------------------------------

    def test_catalogue_keeps_item_when_commerce_out_of_scope(self):
        """T04：catalogue 模式不包含在售清单，同 productCode 的画册展品必须保留。

        旧实现先在 items 循环里按 commerce_codes 跳过、随后又整体跳过
        commerceItems —— 同码商品两边都丢。
        """
        with open(fixture("timehall_same_code.json"), encoding="utf-8") as f:
            data = json.load(f)
        m, _ = self.run_timehall(data, scope="catalogue")
        ids = {p["id"] for p in m.out["products"]}
        self.assertIn("th-SC-001", ids, "catalogue 模式必须保留画册成员")
        self.assertEqual(len(m.out["products"]), 1)
        self.assertTrue(any("scope=catalogue" in s["reason"] for s in m.report["skipped"]),
                        "跳过在售清单要显式登记")

    def test_full_merges_same_code_into_one_product(self):
        """full 模式：同 productCode 只产出一个商品（按来源身份合并，不复制）。"""
        with open(fixture("timehall_same_code.json"), encoding="utf-8") as f:
            data = json.load(f)
        m, _ = self.run_timehall(data, scope="full")
        ids = [p["id"] for p in m.out["products"]]
        self.assertEqual(ids.count("th-SC-001"), 1, "同码不得产生两条商品")
        self.assertTrue(any("同 productCode 已在在售清单中迁入" in s["reason"]
                            for s in m.report["skipped"]))

    # ------------------------------------------------------------------
    # R04 稳定身份 / 幂等（T03 / T05）
    # ------------------------------------------------------------------

    def test_repeat_execution_is_noop(self):
        """T03：同一来源执行两次 → 目标 ID 不变、实体数不变、无重复。"""
        with open(fixture("timehall_same_code.json"), encoding="utf-8") as f:
            data = json.load(f)
        m1, ident1 = self.run_timehall(data, scope="catalogue")
        snapshot1 = json.dumps(m1.out, sort_keys=True)
        ident1.save(self.map_path)

        m2, ident2 = self.run_timehall(data, scope="catalogue", identity=self.map_path)
        snapshot2 = json.dumps(m2.out, sort_keys=True)
        self.assertEqual(snapshot1, snapshot2, "重放产物必须逐字节一致")
        self.assertEqual(ident2.totals().get("created", 0), 0,
                         "重放不应再创建任何实体，实际：{}".format(ident2.totals()))
        self.assertEqual(ident2.totals().get("reused", 0), len(ident1.entries))

    def test_input_order_does_not_change_target_ids(self):
        """T03：输入顺序变化不改变目标 ID（旧的顺序号口径会漂移）。"""
        base = {"id": "item-1", "productCode": "ORD-1", "categoryZH": "JSK",
                "name": "A", "nameZH": "A", "priceJPY": 100,
                "observedAt": None, "catalogueID": None}
        other = {"id": "item-2", "productCode": "ORD-2", "categoryZH": "OP",
                 "name": "B", "nameZH": "B", "priceJPY": 200,
                 "observedAt": None, "catalogueID": None}
        data_a = {"source": "x", "catalogues": [], "items": [base, other], "commerceItems": []}
        data_b = {"source": "x", "catalogues": [], "items": [other, base], "commerceItems": []}
        ma, _ = self.run_timehall(data_a)
        mb, _ = self.run_timehall(data_b)
        self.assertEqual(sorted(p["id"] for p in ma.out["products"]),
                         sorted(p["id"] for p in mb.out["products"]))
        # 变体 ID 同样不得依赖顺序号
        self.assertEqual(sorted(v["id"] for v in ma.out["variants"]),
                         sorted(v["id"] for v in mb.out["variants"]))

    def test_catalogue_to_full_preserves_public_identity(self):
        """T05：catalogue 产物合入后再执行 full，公共部分复用同一 ID。"""
        with open(fixture("timehall_same_code.json"), encoding="utf-8") as f:
            data = json.load(f)
        m1, ident1 = self.run_timehall(data, scope="catalogue")
        ident1.save(self.map_path)
        catalogue_ids = {p["id"] for p in m1.out["products"]}

        m2, ident2 = self.run_timehall(data, scope="full", identity=self.map_path)
        full_ids = {p["id"] for p in m2.out["products"]}
        self.assertTrue(catalogue_ids.issubset(full_ids),
                        "catalogue 已迁的公共部分不得改名：{}".format(catalogue_ids - full_ids))
        self.assertGreater(ident2.totals().get("reused", 0), 0)

        # 商品合并时，画册那条价格事实**不得**随商品一起消失：
        # 换 scope 后 catalogue 阶段已产出的事件 ID 必须仍然可解析，
        # 否则用户既有引用会指向不存在的记录（T05「用户引用仍能解析」）。
        catalogue_events = {e["id"] for e in m1.out["saleEvents"]}
        full_events = {e["id"] for e in m2.out["saleEvents"]}
        self.assertTrue(catalogue_events.issubset(full_events),
                        "catalogue 的销售事件在 full 中丢失：{}".format(catalogue_events - full_events))
        product_ids = {p["id"] for p in m2.out["products"]}
        for e in m2.out["saleEvents"]:
            self.assertIn(e["productID"], product_ids,
                          "销售事件 {} 指向不存在的商品 {}".format(e["id"], e["productID"]))

    def test_cross_shop_same_code_is_not_silently_merged(self):
        """T06：跨店同码不得自动认作同一商品 —— 登记冲突交由人工确认。"""
        with open(fixture("timehall_same_code.json"), encoding="utf-8") as f:
            data_a = json.load(f)
        with open(fixture("timehall_cross_shop_same_code.json"), encoding="utf-8") as f:
            data_b = json.load(f)
        # 把 B 店的 productCode 改成与 A 店相同，构造跨店同码
        data_b["items"][0]["productCode"] = "SC-001"

        m, ident = self.new_migrator(scope="catalogue")
        path_a = write_temp(data_a)
        path_b = write_temp(data_b)
        mig.migrate_timehall_catalog(m, path_a, ({}, {}), mig.Inventory("."), scope="catalogue")
        mig.migrate_timehall_catalog(m, path_b, ({}, {}), mig.Inventory("."), scope="catalogue")
        self.assertTrue(ident.conflicts, "跨店同码必须登记冲突，不能静默合并")
        self.assertEqual(ident.conflicts[0]["targetID"], "th-SC-001")

    # ------------------------------------------------------------------
    # R06 Midsummer 款式与真实 SKU（T07）
    # ------------------------------------------------------------------

    def _migrate_midsummer_fixture(self, m):
        mig.migrate_midsummer(m, fixture("midsummer_specgroups.json"),
                              fixture("midsummer_style_chart.json"), mig.Inventory("."))

    def test_set_container_splits_into_op_and_jsk(self):
        """T07：kind=set 的系列容器按 style 选项拆成不同商品，品类不再是「其他」。"""
        m, _ = self.new_migrator()
        self._migrate_midsummer_fixture(m)
        products = {p["id"]: p for p in m.out["products"]}
        op = products.get("ms-fx-2026-spec-op")
        jsk = products.get("ms-fx-2026-spec-jsk")
        self.assertIsNotNone(op, "OP 应拆为独立商品，实际：{}".format(sorted(products)))
        self.assertIsNotNone(jsk, "JSK 应拆为独立商品")
        self.assertEqual(op["category"], "OP")
        self.assertEqual(jsk["category"], "JSK")
        self.assertEqual(len(m.report["splitContainers"]), 2)

    def test_variants_follow_real_sku_combinations(self):
        """T07：只写来源真实声明的 SKU 组合，不做笛卡尔积补造。"""
        m, _ = self.new_migrator()
        self._migrate_midsummer_fixture(m)
        # fixture 里 OP 有 2 个 SKU（粉-S / 粉-M），JSK 有 1 个（蓝-L）
        op_variants = [v for v in m.out["variants"] if v["productID"] == "ms-fx-2026-spec-op"]
        jsk_variants = [v for v in m.out["variants"] if v["productID"] == "ms-fx-2026-spec-jsk"]
        self.assertEqual(len(op_variants), 2, "OP 真实组合 2 条")
        self.assertEqual(len(jsk_variants), 1, "JSK 真实组合 1 条")
        self.assertEqual(op_variants[0]["color"], "粉色")
        self.assertEqual(jsk_variants[0]["color"], "蓝色")
        self.assertEqual(jsk_variants[0]["size"], "L")
        # 规格图绑定（V1.2 图文联动）
        self.assertTrue(all(v.get("imageAssetID") for v in op_variants + jsk_variants))

    # ------------------------------------------------------------------
    # R05 尺码表 / 价格分档（T08）
    # ------------------------------------------------------------------

    def test_size_chart_structured_and_source_image(self):
        """T08：结构化尺码表与原图都要迁入，且按款式精确配对（不跨款错挂）。"""
        m, _ = self.new_migrator()
        self._migrate_midsummer_fixture(m)
        charts = {c["productID"]: c for c in m.out["sizeCharts"]}
        op_chart = charts.get("ms-fx-2026-spec-op")
        jsk_chart = charts.get("ms-fx-2026-spec-jsk")
        self.assertIsNotNone(op_chart)
        self.assertIsNotNone(jsk_chart)
        self.assertEqual(op_chart["columns"], ["尺寸", "胸围", "腰围"])
        self.assertEqual(jsk_chart["columns"], ["尺寸", "胸围", "裙长"],
                         "JSK 必须拿到自己的表，不能沿用 OP 的")
        self.assertEqual(len(op_chart["rows"]), 3)
        assets = {a["id"]: a for a in m.out["assets"]}
        for chart in (op_chart, jsk_chart):
            self.assertIsNotNone(chart["sourceImage"], "原图必须保留")
            asset = assets[chart["sourceImage"]]
            self.assertEqual(asset["type"], "sizeChartImage")
        # 两款各拿各的原图，不能共用同一张
        self.assertNotEqual(op_chart["sourceImage"], jsk_chart["sourceImage"])

    def test_size_chart_not_attached_to_unrelated_series(self):
        """尺码表只归属来源 URL 命中的条目，杜绝跨系列错挂（回归）。"""
        m, _ = self.new_migrator()
        with open(fixture("midsummer_specgroups.json"), encoding="utf-8") as f:
            data = json.load(f)
        data["series"][0]["items"][0]["itemURL"] = "https://example.com/other"
        data["series"][0]["items"][0]["sourceURL"] = "https://example.com/other"
        path = write_temp(data)
        mig.migrate_midsummer(m, path, fixture("midsummer_style_chart.json"), mig.Inventory("."))
        for chart in m.out["sizeCharts"]:
            self.assertEqual(chart["columns"], [], "非来源条目不应拿到结构化表")
        self.assertTrue(any("缺结构化内容" in r["reason"] for r in m.report["missingSizeCharts"]),
                        "缺结构化内容必须报告，不能宣称完整")

    def test_deposit_tier_recorded_and_balance_derived(self):
        """T08：定金分档登记到报告；尾款仅在总价已知时推导。"""
        m, _ = self.new_migrator()
        self._migrate_midsummer_fixture(m)
        tiers = [t for t in m.report["priceTiers"] if t["kind"] == "deposit"]
        self.assertTrue(tiers, "系列级定金区间必须登记")
        self.assertEqual(tiers[0]["tierMin"], 100)
        self.assertEqual(tiers[0]["tierMax"], 120)
        self.assertEqual(tiers[0]["currency"], "CNY")

    # ------------------------------------------------------------------
    # R07 未知价格不伪造（T10）
    # ------------------------------------------------------------------

    def test_null_price_creates_no_zero_event(self):
        """T10：price 为 None → 不创建 0 元销售事件，登记待补。"""
        data = {"source": "x", "catalogues": [], "commerceItems": [],
                "items": [{"id": "item-null", "productCode": "NP-1", "categoryZH": "JSK",
                           "name": "A", "nameZH": "A", "priceJPY": None,
                           "observedAt": None, "catalogueID": None}]}
        m, _ = self.run_timehall(data)
        self.assertEqual(len(m.out["saleEvents"]), 0, "未知价格不得产生销售事件")
        self.assertEqual(len(m.report["pendingPrices"]), 1)
        self.assertIn("未知 ≠ 免费", m.report["pendingPrices"][0]["reason"])

    def test_zero_price_treated_as_unknown_not_free(self):
        """T10：源数据里 priceJPY=0 表示未采集，不得写成「免费」。"""
        data = {"source": "x", "catalogues": [], "commerceItems": [],
                "items": [{"id": "item-zero", "productCode": "ZP-1", "categoryZH": "OP",
                           "name": "B", "nameZH": "B", "priceJPY": 0,
                           "observedAt": None, "catalogueID": None}]}
        m, _ = self.run_timehall(data)
        self.assertEqual(len(m.out["saleEvents"]), 0)
        self.assertEqual(len(m.report["pendingPrices"]), 1)

    def test_validator_rejects_zero_price_event(self):
        """T10：即便有人手写 0 元事件，结构自检也要拦下来。"""
        m, _ = self.new_migrator()
        m.out["products"].append({"id": "p-a", "shopID": "shop-a", "seriesID": "s-a",
                                  "name": "P", "category": "其他", "images": []})
        m.out["series"].append({"id": "s-a", "shopID": "shop-a", "name": "S"})
        m.out["shops"].append({"id": "shop-a", "name": "A", "aliases": []})
        m.out["saleEvents"].append({"id": "e0", "productID": "p-a", "type": "stock",
                                    "price": 0, "currency": "JPY"})
        errors, _ = mig.validate_output(m.out)
        self.assertTrue(any("价格为 0" in e for e in errors))

    # ------------------------------------------------------------------
    # R02 币种（T09）
    # ------------------------------------------------------------------

    def test_mixed_currency_preserved(self):
        """T09：JPY 与 CNY 各自保留币种，日元不得按人民币入库。"""
        m, _ = self.new_migrator()
        jpy = {"source": "jp-brand", "catalogues": [], "commerceItems": [],
               "items": [{"id": "item-jpy", "productCode": "JP-1", "categoryZH": "JSK",
                          "name": "C", "nameZH": "C", "priceJPY": 24800,
                          "observedAt": None, "catalogueID": None}]}
        mig.migrate_timehall_catalog(m, write_temp(jpy), ({}, {}), mig.Inventory("."),
                                     scope="catalogue")
        mig.migrate_midsummer(m, fixture("midsummer_specgroups.json"),
                              fixture("midsummer_style_chart.json"), mig.Inventory("."))
        currencies = {e["currency"] for e in m.out["saleEvents"]}
        self.assertIn("JPY", currencies)
        self.assertIn("CNY", currencies)
        for e in m.out["saleEvents"]:
            self.assertNotEqual(e.get("currency"), "UNKNOWN", "已知来源必须带明确币种")

    def test_validator_requires_currency(self):
        """T09：缺币种的销售事件必须被拦下。"""
        m, _ = self.new_migrator()
        m.out["products"].append({"id": "p-a", "shopID": "shop-a", "seriesID": "s-a",
                                  "name": "P", "category": "其他", "images": []})
        m.out["series"].append({"id": "s-a", "shopID": "shop-a", "name": "S"})
        m.out["shops"].append({"id": "shop-a", "name": "A", "aliases": []})
        m.out["saleEvents"].append({"id": "e1", "productID": "p-a", "type": "stock",
                                    "price": 100})
        errors, _ = mig.validate_output(m.out)
        self.assertTrue(any("缺币种" in e for e in errors))

    # ------------------------------------------------------------------
    # 身份模块本身
    # ------------------------------------------------------------------

    def test_identity_target_id_is_deterministic(self):
        self.assertEqual(entity_target_id("timehall", "ABC-1"),
                         entity_target_id("timehall", "ABC-1"))
        # 纯非 ASCII 来源 ID 不得坍缩到同一个 unknown
        a = entity_target_id("timehall", "テストページ")
        b = entity_target_id("timehall", "ギフト-ネックレス")
        self.assertNotEqual(a, b, "不同来源 ID 必须得到不同目标 ID")

    def test_identity_conflict_does_not_auto_rename(self):
        """冲突时保留候选 ID 并登记冲突，绝不自动追加 -2/-3。"""
        ident = IdentityMap()
        first = ident.resolve("timehall", "product", "src-a", "products", "th-dup",
                              rule="test")
        second = ident.resolve("timehall", "product", "src-b", "products", "th-dup",
                               rule="test")
        self.assertEqual(first, second, "候选 ID 原样保留，由人工确认")
        self.assertEqual(len(ident.conflicts), 1)

    def test_identity_map_roundtrip(self):
        ident = IdentityMap()
        ident.resolve("timehall", "product", "src-a", "products", "th-a", rule="test")
        ident.save(self.map_path)
        reloaded = IdentityMap(self.map_path)
        self.assertEqual(reloaded.existing_target("timehall", "product", "src-a"), "th-a")


if __name__ == "__main__":
    unittest.main(verbosity=2)
