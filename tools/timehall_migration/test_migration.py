#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
迁移工具自测：合成最小 fixture，验证映射规则与结构自检（方案 Phase 3 验收）。

运行：python3 tools/timehall_migration/test_migration.py
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import migrate_timehall_to_shop_catalog as mig  # noqa: E402


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


class MigrationTests(unittest.TestCase):

    def setUp(self):
        self.existing = make_existing()
        self.m = mig.Migrator(self.existing)
        self.reg = mig.IDRegistry(self.existing)

    def test_shop_dedup_by_name_reuses_existing_id(self):
        """同名店家应复用既有 id（§29 防重复），不新建。"""
        meta = {"alice-girl": {"merchantID": "alice-girl", "displayName": "Alice Girl"}}
        data = {
            "source": "alice-girl",
            "catalogues": [],
            "items": [],
            "commerceItems": [],
        }
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "catalog.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f)
            mig.migrate_timehall_catalog(self.m, path, meta, self.reg)
        self.assertEqual(len(self.m.out["shops"]), 0, "同名店家不应新建")
        self.assertEqual(self.m.report["reusedShops"][0]["shopID"], "shop-alice-girl")

    def test_item_maps_to_product_with_code_priority(self):
        """productCode 优先作 id 种子；价格生成 stock SaleEvent；品类映射。"""
        meta = {}
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
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "catalog.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f)
            mig.migrate_timehall_catalog(self.m, path, meta, self.reg)
        product = self.m.out["products"][0]
        self.assertEqual(product["id"], "th-P001", "productCode 应优先作 id 种子")
        self.assertEqual(product["category"], "JSK")
        self.assertEqual(product["seriesID"], "th-cat-1")
        event = self.m.out["saleEvents"][0]
        self.assertEqual(event["type"], "stock")
        self.assertEqual(event["price"], 24800)
        self.assertEqual(event["startAt"], "2024-03-01T00:00:00Z")
        self.assertEqual(len(self.m.out["assets"]), 3, "系列封面1 + 商品图2")

    def test_item_with_live_product_code_is_skipped(self):
        """已有在售条目的画册展品应跳过（按 productCode 合并，不产生重复商品）。"""
        data = {
            "source": "x",
            "catalogues": [],
            "items": [{"id": "item-1", "productCode": "P1", "category": "JSK",
                       "name": "A", "nameZH": "A", "priceJPY": 100,
                       "observedAt": None, "catalogueID": None}],
            "commerceItems": [{"id": "c-1", "productCode": "P1", "category": "JSK",
                               "name": "A", "nameZH": "A", "regularPriceJPY": 120,
                               "salePriceJPY": None, "observedAt": None,
                               "colors": ["粉"], "sizes": ["M"]}],
        }
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "catalog.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f)
            mig.migrate_timehall_catalog(self.m, path, {}, self.reg, scope="full")
        self.assertEqual(len(self.m.out["products"]), 1, "同名商品只保留在售条目")
        self.assertEqual(self.m.out["products"][0]["id"], "th-P1")
        self.assertTrue(any(s["reason"].startswith("item 已有在售商品")
                            for s in self.m.report["skipped"]))

    def test_midsummer_deposit_maps_to_reservation(self):
        """仲夏物语：有定金 → reservation（定金/尾款），无价 → 记 unknownPrices 且 price=0。"""
        data = {
            "brandID": "midsummer-tale", "brandName": "仲夏物语", "brandNameEN": "Midsummer Tale",
            "series": [
                {"id": "s-1", "name": "小熊博物馆", "launchedOn": "2026-02-09",
                 "items": [
                     {"id": "i-1", "name": "小熊博物馆 JSK", "price": 468,
                      "deposit": 168, "balance": 300,
                      "colors": ["粉"], "sizes": ["S", "M"],
                      "coverImage": None, "skus": []},
                     {"id": "i-2", "name": "未定价套装", "price": None,
                      "deposit": None, "balance": None,
                      "colors": [], "sizes": [], "coverImage": None, "skus": []},
                 ]},
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "midsummer.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f)
            mig.migrate_midsummer(self.m, path, self.reg)
        events = self.m.out["saleEvents"]
        self.assertEqual(events[0]["type"], "reservation")
        self.assertEqual(events[0]["deposit"], 168)
        self.assertEqual(events[0]["balance"], 300)
        self.assertEqual(events[1]["price"], 0)
        self.assertEqual(len(self.m.report["unknownPrices"]), 1)
        # 变体：i-1 = colors × sizes 叉乘（1×2）；i-2 无规格 → 1 条「未区分」变体
        self.assertEqual(len(self.m.out["variants"]), 3)

    def test_reference_integrity_and_unique_ids(self):
        """悬空引用 / 重复 id 必须被结构自检拦截。"""
        self.m.out["shops"].append({"id": "shop-a", "name": "A", "aliases": []})
        self.m.out["series"].append({"id": "s-a", "shopID": "shop-missing", "name": "S",
                                     "year": None, "season": None, "cover": None,
                                     "description": None})
        self.m.out["products"].append({"id": "p-a", "shopID": "shop-a", "seriesID": "s-a",
                                       "name": "P", "category": "其他", "images": [],
                                       "description": None})
        self.m.out["saleEvents"].append({"id": "e-a", "productID": "p-missing",
                                         "type": "stock", "price": 1, "deposit": None,
                                         "balance": None, "startAt": None, "endAt": None})
        errors = mig.validate_output(self.m.out)
        self.assertTrue(any("悬空 shopID" in e for e in errors))
        self.assertTrue(any("悬空 productID" in e for e in errors))

    def test_bad_type_rejected(self):
        self.m.out["shops"].append({"id": "shop-a", "name": "A", "aliases": []})
        self.m.out["saleEvents"].append({"id": "e1", "productID": "x", "type": "flash",
                                         "price": 1, "deposit": None, "balance": None,
                                         "startAt": None, "endAt": None})
        errors = mig.validate_output(self.m.out)
        self.assertTrue(any("非法 type" in e for e in errors))


if __name__ == "__main__":
    unittest.main(verbosity=2)
