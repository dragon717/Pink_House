#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""商店目录发布前处理自测（纯逻辑，不联网）：
   · `strip_archived_shop_catalog`：归档条目连带剔除，且剔除后不得留下悬空引用
   · 未归档内容一个不动；墓碑保留

用法：
    python3 selftest_shop_catalog.py
"""
from __future__ import annotations

import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protocol import (  # noqa: E402
    COVERAGE_COMPLETE,
    strip_archived_shop_catalog,
    validate_shop_catalog,
)

BRAND = "shaonv-xinyuan"

failures = []


def check(label, condition, detail=""):
    if condition:
        print("  ✓ {}".format(label))
    else:
        print("  ✗ {} {}".format(label, detail))
        failures.append(label)


def make_catalog():
    return {
        "version": 1,
        "shops": [
            {"id": "shop-live", "name": "在售店家", "logo": "asset-live-logo"},
            {"id": "shop-arch", "name": "归档店家", "archivedAt": "2026-09-01T00:00:00Z",
             "logo": "asset-arch-logo"},
        ],
        "series": [
            {"id": "series-live", "shopID": "shop-live", "name": "在售系列"},
            {"id": "series-arch", "shopID": "shop-arch", "name": "归档店家的系列"},
            {"id": "series-arch-self", "shopID": "shop-live", "name": "自己归档的系列",
             "archivedAt": "2026-09-02T00:00:00Z"},
        ],
        "products": [
            {"id": "prod-live", "shopID": "shop-live", "seriesID": "series-live",
             "name": "在售商品", "category": "JSK", "images": ["asset-live-img"]},
            {"id": "prod-arch", "shopID": "shop-live", "seriesID": "series-live",
             "name": "归档商品", "category": "JSK", "images": ["asset-arch-img"],
             "archivedAt": "2026-09-03T00:00:00Z"},
            {"id": "prod-arch-series", "shopID": "shop-live", "seriesID": "series-arch-self",
             "name": "归档系列下的商品", "category": "OP", "images": []},
        ],
        "variants": [
            {"id": "var-live", "productID": "prod-live", "color": "粉", "imageAssetID": "asset-live-img"},
            {"id": "var-arch", "productID": "prod-arch", "color": "蓝"},
        ],
        "sizeCharts": [
            {"id": "chart-live", "productID": "prod-live", "sourceImage": "asset-arch-chart"},
            {"id": "chart-arch", "productID": "prod-arch", "sourceImage": "asset-arch-chart"},
        ],
        "saleEvents": [
            {"id": "ev-live", "productID": "prod-live", "type": "reservation", "price": 328},
            {"id": "ev-arch", "productID": "prod-arch", "type": "reservation", "price": 299},
        ],
        "assets": [
            {"id": "asset-live-logo", "type": "shopCover", "originalURL": "local:a.jpg"},
            {"id": "asset-live-img", "type": "productImage", "originalURL": "local:b.jpg"},
            {"id": "asset-arch-logo", "type": "shopCover", "originalURL": "local:c.jpg"},
            {"id": "asset-arch-img", "type": "productImage", "originalURL": "local:d.jpg"},
            {"id": "asset-arch-chart", "type": "sizeChartImage", "originalURL": "local:e.jpg"},
            {"id": "asset-orphan", "type": "productImage", "originalURL": "local:f.jpg"},
        ],
        "styleProfiles": [
            {"id": "profile-live", "seriesID": "series-live", "category": "JSK", "designName": "在售款"},
            {"id": "profile-arch", "seriesID": "series-arch-self", "category": "OP", "designName": "归档款"},
        ],
        "removedShopIDs": ["shop-gone"],
        "removedSeriesIDs": [],
        "removedProductIDs": [],
    }


print("=== strip_archived_shop_catalog ===")

# 1) 未归档时一个不动（含孤儿图片也必须原样留着）
clean_source = make_catalog()
clean_source["shops"] = [clean_source["shops"][0]]
clean_source["series"] = [clean_source["series"][0]]
clean_source["products"] = [clean_source["products"][0]]
clean_source["variants"] = [clean_source["variants"][0]]
clean_source["sizeCharts"] = [clean_source["sizeCharts"][0]]
clean_source["saleEvents"] = [clean_source["saleEvents"][0]]
clean_source["styleProfiles"] = [clean_source["styleProfiles"][0]]
unchanged, clean_report = strip_archived_shop_catalog(copy.deepcopy(clean_source))
check("未归档目录：一条都不剔除", all(value == 0 for value in clean_report.values()),
      str(clean_report))
check("未归档目录：内容逐字段等价",
      all(unchanged[field] == clean_source[field]
          for field in ("shops", "series", "products", "variants",
                        "sizeCharts", "saleEvents", "styleProfiles", "assets")))

# 2) 归档连带剔除
doc = make_catalog()
cleaned, report = strip_archived_shop_catalog(copy.deepcopy(doc))

check("归档店家被剔除", [s["id"] for s in cleaned["shops"]] == ["shop-live"],
      str([s["id"] for s in cleaned["shops"]]))
check("归档店家的系列连坐剔除",
      [s["id"] for s in cleaned["series"]] == ["series-live"],
      str([s["id"] for s in cleaned["series"]]))
check("自归档系列连坐剔除（其下商品也不留）",
      [p["id"] for p in cleaned["products"]] == ["prod-live"],
      str([p["id"] for p in cleaned["products"]]))
check("归档商品的规格连坐剔除",
      [v["id"] for v in cleaned["variants"]] == ["var-live"])
check("归档商品的尺码表连坐剔除",
      [c["id"] for c in cleaned["sizeCharts"]] == ["chart-live"])
check("归档商品的销售事件连坐剔除",
      [e["id"] for e in cleaned["saleEvents"]] == ["ev-live"])
check("归档系列的款式档案连坐剔除",
      [p["id"] for p in cleaned["styleProfiles"]] == ["profile-live"])
check("剔除数量如实上报（products 少了 2 条）", report["products"] == 2, str(report))

asset_ids = {a["id"] for a in cleaned["assets"]}
check("只被归档实体引用的图片被剔除",
      "asset-arch-logo" not in asset_ids and "asset-arch-img" not in asset_ids,
      str(sorted(asset_ids)))
check("仍被在售实体引用的图片保留", "asset-live-img" in asset_ids and "asset-live-logo" in asset_ids,
      str(sorted(asset_ids)))
check("未被任何实体引用的孤儿图片保持原样（不误删）", "asset-orphan" in asset_ids,
      str(sorted(asset_ids)))
check("墓碑保留（归档与强制删除是两件事）", cleaned["removedShopIDs"] == ["shop-gone"])

# 3) 剔除结果必须过得了客户端同一口径的结构校验
issues = validate_shop_catalog(cleaned, BRAND, COVERAGE_COMPLETE)
check("剔除后无悬空引用（客户端结构校验通过）", not issues, str(issues))

# 4) 反向用例：不连带剔除会被校验拒绝 —— 说明这段裁剪不是可省的
partial = copy.deepcopy(doc)
partial["products"] = [p for p in partial["products"] if p["id"] != "prod-arch"]
partial["variants"] = [v for v in partial["variants"] if v["productID"] != "prod-arch"]
issues_partial = validate_shop_catalog(partial, BRAND, COVERAGE_COMPLETE)
check("反向：只删商品不删尺码表/事件 → 校验必须报悬空引用", bool(issues_partial),
      "期望有 issue，实际 {}".format(issues_partial))

# 5) 裁剪不得掩盖发布端的数据错误：商品指向**本来就不存在**的系列（与归档无关）
broken = copy.deepcopy(doc)
broken["products"].append(
    {"id": "prod-broken", "shopID": "shop-live", "seriesID": "series-missing",
     "name": "指向不存在系列的商品", "category": "JSK"}
)
kept, _ = strip_archived_shop_catalog(broken)
check("非归档的悬空引用不被裁剪抹平（坏数据要留下来报错，不能静默消失）",
      any(p["id"] == "prod-broken" for p in kept["products"]),
      str([p["id"] for p in kept["products"]]))
check("…且会被结构校验如实报出", bool(validate_shop_catalog(kept, BRAND, COVERAGE_COMPLETE)))

print()
if failures:
    print("❌ {} 项未通过：{}".format(len(failures), "、".join(failures)))
    sys.exit(1)
print("✅ 商店目录归档裁剪自测全部通过")
