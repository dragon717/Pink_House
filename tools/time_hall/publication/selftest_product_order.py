#!/usr/bin/env python3
"""Offline regression: operator order survives the real public catalog pack builder."""
import argparse
import gzip
import json
import tempfile
import unittest
from pathlib import Path

from build_release import build_shop_catalog_pack, collect_shop_catalog_media


class ProductOrderTests(unittest.TestCase):
    def catalog(self):
        return {
            "version": 1,
            "shops": [{"id": "shop", "name": "店家"}],
            "series": [{"id": "series", "shopID": "shop", "name": "系列"}],
            "products": [
                {"id": "second", "shopID": "shop", "seriesID": "series", "name": "同名款式",
                 "category": "OP", "images": ["image"], "displayOrder": 1},
                {"id": "first", "shopID": "shop", "seriesID": "series", "name": "同名款式",
                 "category": "OP", "images": ["image"], "displayOrder": 0},
            ],
            "assets": [{"id": "image", "type": "productImage", "originalURL": "local:image.png"}],
        }

    def pack(self, doc):
        _, compressed, _ = build_shop_catalog_pack(
            {"brandID": "shaonv-xinyuan"}, doc,
            argparse.Namespace(coverage_mode="partial", checked_through=None))
        return json.loads(gzip.decompress(compressed))["shopCatalog"]

    def test_published_array_matches_order_for_legacy_clients(self):
        published = self.pack(self.catalog())
        self.assertEqual([p["id"] for p in published["products"]], ["first", "second"])
        self.assertEqual([p["id"] for p in sorted(published["products"], key=lambda p: p["displayOrder"])], ["first", "second"])

    def test_archive_filter_does_not_renumber_remaining_products(self):
        doc = self.catalog()
        doc["products"][1]["archivedAt"] = "2026-10-17T00:00:00Z"
        self.assertEqual([(p["id"], p["displayOrder"]) for p in self.pack(doc)["products"]], [("second", 1)])

    def test_image_rewrite_keeps_order_and_stable_image_bindings(self):
        with tempfile.TemporaryDirectory() as scratch:
            directory = Path(scratch)
            (directory / "image.png").write_bytes(b"publication media fixture")
            rewritten, _, _ = collect_shop_catalog_media(self.catalog(), directory)
            published = self.pack(rewritten)
        self.assertEqual([p["displayOrder"] for p in published["products"]], [0, 1])
        self.assertTrue(published["assets"][0]["originalURL"].startswith("thmedia:"))
        self.assertEqual(published["products"][0]["images"], ["image"])

    def test_screenshot_styles_do_not_interleave_in_legacy_array_reader(self):
        doc = self.catalog()
        names = ["正腰JSK", "正腰JSK+胸针（一对）", "正腰JSK+项链",
                 "正腰JSK+项链+胸针（一对）", "正腰JSK+眼罩发带",
                 "正腰JSK+胸针（一对）+眼罩发带", "纯色JSK", "纯色JSK+项链"]
        # 现场发布数组正腰后插入纯色；模拟不认识 displayOrder 的已分发旧客户端。
        doc["products"] = [dict(id=str(i), shopID="shop", seriesID="series", name=names[i],
                                category="JSK", displayOrder=i) for i in [0, 6, 7, 1, 2, 3, 4, 5]]
        self.assertEqual([p["name"] for p in self.pack(doc)["products"]][:6], names[:6])

    def test_ranked_series_keep_other_series_slots_and_unranked_order(self):
        doc = self.catalog()
        doc["series"] += [dict(id="other", shopID="shop", name="另一系列")]
        doc["products"].insert(1, dict(id="legacy-jsk", shopID="shop", seriesID="other", name="旧JSK", category="JSK"))
        doc["products"].append(dict(id="legacy-op", shopID="shop", seriesID="other", name="旧OP", category="OP"))
        before = {p["id"]: p for p in doc["products"]}
        published = self.pack(doc)
        self.assertEqual([p["id"] for p in published["products"]], ["first", "legacy-jsk", "second", "legacy-op"])
        self.assertEqual({p["id"]: p for p in published["products"]}, before)
        self.assertEqual(self.pack(published), published)


if __name__ == "__main__":
    unittest.main()
